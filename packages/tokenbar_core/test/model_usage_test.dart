import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

String _jwt(Map<String, Object?> claims) {
  String seg(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({'alg': 'HS256'})}.${seg(claims)}.sig';
}

CursorUsageEvent _ev(DateTime at, String model, {int tokens = 1, double? cents}) =>
    CursorUsageEvent(
      timestampMs: at.millisecondsSinceEpoch,
      model: model,
      tokens: tokens,
      chargedCents: cents,
    );

double _tokensOf(ModelUsageSeries series, String model) => [
  for (final b in series.buckets)
    for (final u in b.usage)
      if (u.model == model) u.tokens,
].fold(0.0, (a, b) => a + b);

double? _costOf(ModelUsageSeries series, String model) {
  double? total;
  for (final b in series.buckets) {
    for (final u in b.usage.where((u) => u.model == model)) {
      if (u.costUsd == null) return null;
      total = (total ?? 0) + u.costUsd!;
    }
  }
  return total;
}

int _requestsOf(ModelUsageSeries series, String model) => [
  for (final b in series.buckets)
    for (final u in b.usage)
      if (u.model == model) u.requests,
].fold(0, (a, b) => a + b);

List<String> _fixtureLines() =>
    File('test/fixtures/codex_session_synthetic.jsonl').readAsLinesSync();

List<CodexTokenDelta> _parse(Iterable<String> lines) {
  final parser = CodexSessionParser();
  return [
    for (final line in lines)
      if (parser.addLine(line) case final CodexTokenDelta d) d,
  ];
}

String _tokenCount(String at, {required List<int> last, required List<int> total, String? model}) {
  Map<String, Object?> usage(List<int> v) => {
    'input_tokens': v[0],
    'cached_input_tokens': v[1],
    'output_tokens': v[2],
  };
  return jsonEncode({
    'timestamp': at,
    'type': 'event_msg',
    'payload': {
      'type': 'token_count',
      'info': {'model': ?model, 'last_token_usage': usage(last), 'total_token_usage': usage(total)},
    },
  });
}

void main() {
  group('bucket rules', () {
    test('24 h and 36 h use hourly buckets, longer ranges use daily buckets', () {
      final to = DateTime(2026, 10, 24, 12);
      expect(
        modelUsageBucketWidth(to.subtract(const Duration(hours: 24)), to),
        const Duration(hours: 1),
      );
      expect(
        modelUsageBucketWidth(to.subtract(const Duration(hours: 36)), to),
        const Duration(hours: 1),
      );
      expect(
        modelUsageBucketWidth(to.subtract(const Duration(hours: 36, minutes: 1)), to),
        const Duration(days: 1),
      );
      expect(
        modelUsageBucketWidth(to.subtract(const Duration(days: 7)), to),
        const Duration(days: 1),
      );
      expect(
        modelUsageBucketWidth(to.subtract(const Duration(days: 30)), to),
        const Duration(days: 1),
      );
    });

    test('bucket starts are aligned to the local hour / local midnight', () {
      final t = DateTime(2026, 10, 24, 15, 47, 12);
      expect(modelUsageBucketStart(t, const Duration(hours: 1)), DateTime(2026, 10, 24, 15));
      expect(modelUsageBucketStart(t, const Duration(days: 1)), DateTime(2026, 10, 24));
      // UTC input is converted to local time first.
      final utc = DateTime.utc(2026, 10, 24, 15, 47);
      expect(
        modelUsageBucketStart(utc, const Duration(days: 1)),
        modelUsageBucketStart(utc.toLocal(), const Duration(days: 1)),
      );
    });

    test('aggregator drops out-of-range samples and hides partial costs', () {
      final from = DateTime(2026, 10, 24, 0);
      final to = DateTime(2026, 10, 24, 23);
      final agg = ModelUsageAggregator(from: from, to: to)
        ..add(DateTime(2026, 10, 23, 23, 59), 'a', tokens: 5, costUsd: 1)
        ..add(DateTime(2026, 10, 24, 10, 5), 'a', tokens: 10, costUsd: 0.5)
        ..add(DateTime(2026, 10, 24, 10, 6), 'a', tokens: 20, costUsd: null)
        ..add(DateTime(2026, 10, 24, 10, 7), 'b', tokens: 40, costUsd: 0.25)
        ..add(DateTime(2026, 10, 24, 11), 'b', tokens: 1, costUsd: 0.1)
        ..add(DateTime(2026, 10, 25, 1), 'b', tokens: 99, costUsd: 9);
      final series = agg.build(source: 'test');
      expect(series.source, 'test');
      expect(series.bucket, const Duration(hours: 1));
      expect(series.buckets.map((b) => b.start), [
        DateTime(2026, 10, 24, 10),
        DateTime(2026, 10, 24, 11),
      ]);
      final first = series.buckets.first.usage;
      expect(first.map((u) => u.model), ['b', 'a'], reason: 'largest tokens first');
      expect(first.firstWhere((u) => u.model == 'a').tokens, 30);
      expect(first.firstWhere((u) => u.model == 'a').costUsd, isNull);
      expect(first.firstWhere((u) => u.model == 'b').costUsd, closeTo(0.25, 1e-12));
      expect(series.models, ['b', 'a']);
    });
  });

  group('Cursor events → series', () {
    test('events are bucketed by hour × model with cost and request counts', () {
      final base = DateTime(2026, 10, 24, 9, 10);
      final events = [
        _ev(base, 'gpt-5', tokens: 100, cents: 4),
        _ev(base.add(const Duration(minutes: 20)), 'gpt-5', tokens: 50, cents: 6),
        _ev(base.add(const Duration(minutes: 5)), 'claude-4.5-sonnet', tokens: 10, cents: 1),
        _ev(base.add(const Duration(hours: 2)), 'gpt-5', tokens: 7, cents: 2),
        _ev(base.subtract(const Duration(days: 3)), 'gpt-5', tokens: 999, cents: 99),
      ];
      final series = buildCursorModelUsageSeries(
        events,
        from: DateTime(2026, 10, 23, 12),
        to: DateTime(2026, 10, 24, 12),
      );
      expect(series.source, 'cursor-events');
      expect(series.bucket, const Duration(hours: 1));
      expect(series.buckets.map((b) => b.start), [
        DateTime(2026, 10, 24, 9),
        DateTime(2026, 10, 24, 11),
      ]);
      final nine = series.buckets.first.usage;
      expect(nine.map((u) => u.model), ['gpt-5', 'claude-4.5-sonnet']);
      expect(nine.first.tokens, 150);
      expect(nine.first.requests, 2);
      expect(nine.first.costUsd, closeTo(0.10, 1e-12));
      expect(series.buckets.last.usage.single.costUsd, closeTo(0.02, 1e-12));
    });

    test('week ranges use local days; missing chargedCents → null cost; bad rows ignored', () {
      final day = DateTime(2026, 10, 22, 8);
      final series = buildCursorModelUsageSeries(
        [
          _ev(day, 'm', tokens: 3, cents: 10),
          _ev(day.add(const Duration(hours: 6)), 'm', tokens: 4),
          const CursorUsageEvent(timestampMs: null, model: 'm', tokens: 100),
          const CursorUsageEvent(timestampMs: 0, model: 'm', tokens: 100),
        ],
        from: DateTime(2026, 10, 17, 12),
        to: DateTime(2026, 10, 24, 12),
      );
      expect(series.bucket, const Duration(days: 1));
      final only = series.buckets.single;
      expect(only.start, DateTime(2026, 10, 22));
      expect(only.usage.single.tokens, 7);
      expect(only.usage.single.requests, 2);
      expect(only.usage.single.costUsd, isNull);
    });

    group('CursorProvider.fetchModelUsage', () {
      final token = _jwt({'sub': 'auth0|user_01ABC', 'exp': 1893456000});
      final account = AccountConfig(
        id: 'cursor-1',
        providerId: 'cursor',
        label: 'Cursor',
        sourceType: SourceType.apiKey,
        secret: token,
      );
      final now = DateTime.utc(2026, 10, 20, 12);
      final from = now.subtract(const Duration(days: 7));

      Map<String, Object?> page(int count, int total, DateTime at, {String model = 'gpt-5'}) => {
        'totalUsageEventsCount': total,
        'usageEventsDisplay': [
          for (var i = 0; i < count; i++)
            {
              'timestamp': '${at.millisecondsSinceEpoch + i}',
              'model': model,
              'tokenUsage': {
                'inputTokens': 1,
                'outputTokens': 1,
                'cacheWriteTokens': 0,
                'cacheReadTokens': 0,
              },
              'chargedCents': 1,
            },
        ],
      };

      test('posts [from, to] with the cookie and aggregates the rows', () async {
        final seen = <http.Request>[];
        final client = MockClient((r) async {
          seen.add(r);
          return http.Response(jsonEncode(page(3, 3, now.subtract(const Duration(hours: 5)))), 200);
        });
        final series = await CursorProvider().fetchModelUsage(
          account,
          FetchContext(client: client, clock: () => now),
          from: from,
          to: now,
        );
        expect(seen, hasLength(1));
        final req = seen.single;
        expect(req.url.path, '/api/dashboard/get-filtered-usage-events');
        expect(req.headers['Origin'], 'https://cursor.com');
        expect(req.headers['Cookie'], endsWith('WorkosCursorSessionToken=user_01ABC%3A%3A$token'));
        final body = jsonDecode(req.body) as Map<String, Object?>;
        expect(body['startDate'], '${from.millisecondsSinceEpoch}');
        expect(body['endDate'], '${now.millisecondsSinceEpoch}');
        expect(series, isNotNull);
        expect(series!.bucket, const Duration(days: 1));
        expect(_tokensOf(series, 'gpt-5'), 6);
        expect(_requestsOf(series, 'gpt-5'), 3);
        expect(_costOf(series, 'gpt-5'), closeTo(0.03, 1e-12));
      });

      test('reads at most 20 pages; an endless feed is unavailable, not partial', () async {
        var calls = 0;
        final client = MockClient((r) async {
          calls++;
          return http.Response(jsonEncode(page(1000, 999999, now)), 200);
        });
        final series = await CursorProvider().fetchModelUsage(
          account,
          FetchContext(client: client, clock: () => now),
          from: from,
          to: now,
        );
        expect(series, isNull);
        expect(calls, 20);
      });

      test('HTTP errors, bad cookies and an expired login return null', () async {
        final failing = MockClient((r) async => http.Response('nope', 500));
        expect(
          await CursorProvider().fetchModelUsage(
            account,
            FetchContext(client: failing, clock: () => now),
            from: from,
            to: now,
          ),
          isNull,
        );
        expect(
          await CursorProvider().fetchModelUsage(
            account.copyWith(secret: 'not-a-cookie'),
            FetchContext(client: failing, clock: () => now),
            from: from,
            to: now,
          ),
          isNull,
        );
        expect(
          await CursorProvider().fetchModelUsage(
            account,
            FetchContext(client: failing, clock: () => DateTime.utc(2035)),
            from: from,
            to: now,
          ),
          isNull,
        );
      });
    });
  });

  group('Codex session parser', () {
    test('synthetic session: per-request deltas, models, duplicates and stale lines', () {
      final deltas = _parse(_fixtureLines());
      expect(
        [for (final d in deltas) (d.model, d.input, d.cached, d.output, d.tokens)],
        [
          ('gpt-5.5', 1000, 400, 100, 1100),
          ('gpt-5.5', 2000, 1500, 50, 2050),
          ('gpt-5.4', 500, 100, 60, 560),
          ('custom-model-x', 100, 0, 10, 110),
        ],
      );
      expect(deltas.first.time, DateTime.utc(2026, 10, 23, 13, 5));
    });

    test('model: turn_context beats the record, blank clears, falls back to unknown', () {
      final deltas = _parse([
        jsonEncode({
          'type': 'turn_context',
          'payload': {'model': 'gpt-5-codex'},
        }),
        _tokenCount('2026-10-23T10:00:00Z', last: [10, 0, 1], total: [10, 0, 1], model: 'ignored'),
        jsonEncode({
          'type': 'turn_context',
          'payload': {'model': '  '},
        }),
        _tokenCount('2026-10-23T10:01:00Z', last: [20, 0, 2], total: [30, 0, 3]),
        jsonEncode({
          'type': 'turn_context',
          'payload': {
            'info': {'model_name': 'gpt-5.1'},
          },
        }),
        _tokenCount('2026-10-23T10:02:00Z', last: [5, 0, 1], total: [35, 0, 4]),
      ]);
      expect(deltas.map((d) => d.model), ['gpt-5-codex', 'unknown', 'gpt-5.1']);
    });

    test('a counter reset is not recounted as new usage', () {
      final deltas = _parse([
        _tokenCount('2026-10-23T10:00:00Z', last: [1000, 0, 100], total: [1000, 0, 100]),
        _tokenCount('2026-10-23T10:05:00Z', last: [100, 0, 10], total: [100, 0, 10]),
      ]);
      expect(deltas.map((d) => d.tokens), [1100]);
    });

    test('fork children do not report the inherited prefix', () {
      final deltas = _parse([
        jsonEncode({
          'type': 'session_meta',
          'payload': {
            'id': 'child',
            'forked_from_id': 'parent',
            'timestamp': '2026-10-23T12:00:00Z',
          },
        }),
        _tokenCount('2026-10-23T11:00:00Z', last: [1000, 0, 0], total: [1000, 0, 0]),
        _tokenCount('2026-10-23T12:05:00Z', last: [200, 0, 20], total: [1200, 0, 20]),
      ]);
      expect([for (final d in deltas) d.tokens], [220]);
    });

    test('lines without any marker are never decoded; garbage is ignored', () {
      final parser = CodexSessionParser();
      expect(parser.addLine('not json at all'), isNull);
      expect(parser.addLine('{"type":"token_count"'), isNull);
      expect(parser.addLine('[1,2,3] token_count turn_context'), isNull);
      expect(CodexSessionParser.isRelevantLine('{"type":"response_item"}'), isFalse);
    });
  });

  group('Codex pricing', () {
    test('known models are priced from the CodexBar table', () {
      // 600 uncached * 5e-6 + 400 cached * 5e-7 + 100 output * 3e-5
      expect(
        codexCostUsd('gpt-5.5', DateTime.utc(2026, 10, 23), input: 1000, cached: 400, output: 100),
        closeTo(0.0062, 1e-12),
      );
      expect(codexPriceFor('openai/gpt-5-codex-2025-09-15', DateTime.utc(2026)), isNotNull);
    });

    test('GPT-6.1 Terra and GPT-6.2 models use the CodexBar table', () {
      final at = DateTime.utc(2026, 11, 20);
      expect(codexPriceFor('gpt-6.1-terra', at)!.input, 1e-6);
      expect(codexPriceFor('gpt-6.2-astra', at)!.output, 4e-5);
      final sol = codexPriceFor('gpt-6.2-sol', at)!;
      expect(sol.cachedInput, 1e-7);
      // long-context request: the whole request is priced at the doubled input rate
      expect(
        codexCostUsd('gpt-6.2-sol', at, input: 300000, cached: 0, output: 0),
        closeTo(300000 * 4e-6, 1e-9),
      );
    });

    test('Sol keeps its old rates before the 2026-08-21 repricing; aliases resolve', () {
      expect(codexPriceFor('gpt-5.6-sol', DateTime.utc(2026, 8, 1))!.input, 5e-6);
      expect(codexPriceFor('gpt-5.6-sol', DateTime.utc(2026, 9, 1))!.input, 4e-6);
      expect(codexPriceFor('gpt-5.6', DateTime.utc(2026, 9, 1))!.input, 4e-6);
    });

    test('long-context requests double the input rate; unknown models have no price', () {
      final long = codexCostUsd(
        'gpt-5.5',
        DateTime.utc(2026, 10, 23),
        input: 300000,
        cached: 0,
        output: 0,
      );
      expect(long, closeTo(300000 * 1e-5, 1e-9));
      expect(codexPriceFor('custom-model-x', DateTime.utc(2026)), isNull);
      expect(codexPriceFor('unknown', DateTime.utc(2026)), isNull);
    });
  });

  group('Codex log scan', () {
    late Directory home;

    setUp(() => home = Directory.systemTemp.createTempSync('tokenbar_codex_'));
    tearDown(() => home.deleteSync(recursive: true));

    File write(String relative, List<String> lines, {DateTime? modified}) {
      final file =
          File(
              '${home.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('${lines.join('\n')}\n');
      if (modified != null) file.setLastModifiedSync(modified);
      return file;
    }

    final from = DateTime.utc(2026, 10, 23, 12);
    final to = DateTime.utc(2026, 10, 24, 12);

    test('missing log directories mean no data (null)', () async {
      expect(await loadCodexModelUsage('${home.path}/nope', from, to), isNull);
    });

    test('aggregates the synthetic session into model × bucket usage', () async {
      write(
        'sessions/2026/10/23/rollout-2026-10-23T21-00-00-aaa.jsonl',
        _fixtureLines(),
        modified: to,
      );
      final series = (await loadCodexModelUsage(home.path, from, to))!;
      expect(series.source, 'codex-logs');
      expect(series.bucket, const Duration(hours: 1));
      expect(series.models, ['gpt-5.5', 'gpt-5.4', 'custom-model-x']);
      expect(_tokensOf(series, 'gpt-5.5'), 3150);
      expect(_tokensOf(series, 'gpt-5.4'), 560);
      expect(_tokensOf(series, 'custom-model-x'), 110);
      expect(_requestsOf(series, 'gpt-5.5'), 2);
      // 0.0062 + 0.00475 (see codex_pricing); gpt-5.4: 400*2.5e-6 + 100*2.5e-7 + 60*1.5e-5
      expect(_costOf(series, 'gpt-5.5'), closeTo(0.01095, 1e-9));
      expect(_costOf(series, 'gpt-5.4'), closeTo(0.001925, 1e-9));
      expect(_costOf(series, 'custom-model-x'), isNull, reason: 'no price → no invented cost');
    });

    test('only events inside [from, to] are counted', () async {
      write('sessions/2026/10/23/rollout-x.jsonl', _fixtureLines(), modified: to);
      final series = (await loadCodexModelUsage(
        home.path,
        DateTime.utc(2026, 10, 23, 14),
        DateTime.utc(2026, 10, 23, 15),
      ))!;
      expect(series.models, ['gpt-5.4']);
      expect(_tokensOf(series, 'gpt-5.4'), 560);
    });

    test('files are filtered by modification time and date partitions', () async {
      final old = to.subtract(const Duration(days: 20));
      write('sessions/2026/10/23/rollout-fresh.jsonl', _fixtureLines(), modified: to);
      write('sessions/2026/10/23/rollout-stale.jsonl', _fixtureLines(), modified: old);
      write('sessions/2025/01/01/rollout-ancient.jsonl', _fixtureLines(), modified: to);
      write('sessions/2026/10/23/notes.txt', _fixtureLines(), modified: to);
      final files = (await listCodexSessionFiles(home.path, from, to))!;
      expect(files.map((p) => p.split(RegExp(r'[\\/]')).last), ['rollout-fresh.jsonl']);
    });

    test('archived sessions are included once; flat legacy files too', () async {
      write('sessions/2026/10/23/rollout-dup.jsonl', _fixtureLines(), modified: to);
      write('archived_sessions/rollout-dup.jsonl', _fixtureLines(), modified: to);
      write('archived_sessions/rollout-archived.jsonl', [
        _tokenCount('2026-10-23T20:00:00Z', last: [10, 0, 5], total: [10, 0, 5], model: 'gpt-5'),
      ], modified: to);
      write('sessions/rollout-flat.jsonl', [
        _tokenCount('2026-10-23T21:00:00Z', last: [1, 0, 1], total: [1, 0, 1], model: 'gpt-5-mini'),
      ], modified: to);
      final series = (await loadCodexModelUsage(home.path, from, to))!;
      expect(_tokensOf(series, 'gpt-5.5'), 3150, reason: 'duplicate file name counted once');
      expect(_tokensOf(series, 'gpt-5'), 15);
      expect(_tokensOf(series, 'gpt-5-mini'), 2);
    });

    test('symlinked day, archive and file entries are followed', () async {
      final elsewhere = Directory.systemTemp.createTempSync('tokenbar_codex_other_');
      addTearDown(() => elsewhere.deleteSync(recursive: true));
      File outside(String relative) => File('${elsewhere.path}${Platform.pathSeparator}$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync('${_fixtureLines().join('\n')}\n')
        ..setLastModifiedSync(to);
      final day = outside('day/rollout-day.jsonl').parent;
      final archive = outside('archive/rollout-archived.jsonl').parent;
      final single = outside('single/rollout-single.jsonl');
      final sep = Platform.pathSeparator;
      Directory('${home.path}${sep}sessions${sep}2026${sep}10').createSync(recursive: true);
      Directory('${home.path}${sep}sessions${sep}2026${sep}10${sep}22').createSync();
      try {
        Link('${home.path}${sep}sessions${sep}2026${sep}10${sep}23').createSync(day.path);
        Link('${home.path}${sep}archived_sessions').createSync(archive.path);
        Link('${home.path}${sep}sessions${sep}2026${sep}10${sep}22${sep}rollout-single.jsonl')
            .createSync(single.path);
      } on FileSystemException {
        markTestSkipped('symlinks cannot be created here (e.g. Windows without privilege)');
        return;
      }
      final files = (await listCodexSessionFiles(home.path, from, to))!;
      expect(files.map((p) => p.split(RegExp(r'[\\/]')).last).toSet(), {
        'rollout-day.jsonl',
        'rollout-archived.jsonl',
        'rollout-single.jsonl',
      });
    });

    test('compressed .jsonl.zst rollouts are skipped, not counted or crashed on', () async {
      write('sessions/2026/10/23/rollout-live.jsonl', _fixtureLines(), modified: to);
      write('archived_sessions/rollout-live.jsonl.zst', ['not json at all'], modified: to);
      write('sessions/2026/10/23/rollout-old.jsonl.zst', ['not json at all'], modified: to);
      final files = (await listCodexSessionFiles(home.path, from, to))!;
      expect(files.map((p) => p.split(RegExp(r'[\\/]')).last), ['rollout-live.jsonl']);
      final series = (await loadCodexModelUsage(home.path, from, to))!;
      expect(_tokensOf(series, 'gpt-5.5'), 3150, reason: 'no double counting');
    });

    test('provider uses the account home directory and returns null without logs', () async {
      write('sessions/2026/10/23/rollout-x.jsonl', _fixtureLines(), modified: to);
      final provider = CodexProvider();
      final ctx = FetchContext(clock: () => to);
      final series = await provider.fetchModelUsage(
        AccountConfig(id: 'c1', providerId: 'codex', label: 'Codex', homeDir: home.path),
        ctx,
        from: from,
        to: to,
      );
      expect(series, isNotNull);
      expect(series!.models, contains('gpt-5.5'));
      expect(
        await provider.fetchModelUsage(
          AccountConfig(
            id: 'c2',
            providerId: 'codex',
            label: 'Codex',
            homeDir: '${home.path}/missing',
          ),
          ctx,
          from: from,
          to: to,
        ),
        isNull,
      );
    });

    test('other providers keep the default (no per-model data)', () async {
      final provider = ProviderRegistry.instance.byId('claude')!;
      expect(
        await provider.fetchModelUsage(
          AccountConfig(id: 'x', providerId: 'claude', label: 'Claude'),
          FetchContext(),
          from: from,
          to: to,
        ),
        isNull,
      );
    });
  });
}
