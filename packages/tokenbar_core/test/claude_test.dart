import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

Map<String, Object?> _credentialsJson({
  required int expiresAtMs,
  List<String> scopes = const ['user:inference', 'user:profile'],
}) => {
  'claudeAiOauth': {
    'accessToken': 'sk-ant-oat01-access',
    'refreshToken': 'sk-ant-ort01-refresh',
    'expiresAt': expiresAtMs,
    'scopes': scopes,
    'subscriptionType': 'max',
    'rateLimitTier': 'default_claude_max_20x',
  },
  'mcpOAuth': {'keep': 'me'},
};

void main() {
  test('parses oauth/usage windows and extra usage (cents)', () {
    final json = jsonDecode(
      File('test/fixtures/claude_oauth_usage.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final parsed = parseClaudeOAuthUsage(json);
    expect(parsed.windows.map((w) => w.id), ['session', 'weekly', 'weekly_opus']);
    expect(parsed.windows.first.usedPercent, 37);
    expect(parsed.windows.first.resetsAt!.toUtc().hour, 4);
    final extra = parsed.credits.single;
    expect(extra.used, closeTo(12.34, 1e-9));
    expect(extra.limit, 50);
    expect(extra.currency, 'USD');
  });

  test('weekly-only plans produce no empty session window', () {
    final parsed = parseClaudeOAuthUsage({
      'five_hour': null,
      'seven_day': {'utilization': 12.0, 'resets_at': '2025-11-08T04:59:59+00:00'},
      'seven_day_sonnet': {'utilization': 4.0, 'resets_at': null},
    });
    expect(parsed.windows.map((w) => w.id), ['weekly', 'weekly_sonnet']);
    // An unusable five-hour entry is dropped too, not rendered as 0%.
    final noUtilization = parseClaudeOAuthUsage({
      'five_hour': {'utilization': null, 'resets_at': null},
      'seven_day': {'utilization': 12.0, 'resets_at': null},
    });
    expect(noUtilization.windows.map((w) => w.id), ['weekly']);
  });

  test('plan names', () {
    expect(claudePlanName('max', 'default_claude_max_20x'), 'Max 20x');
    expect(claudePlanName('pro', null), 'Pro');
    expect(claudePlanName(null, null), isNull);
  });

  test('credential merge preserves unrelated fields', () {
    final original = jsonEncode(_credentialsJson(expiresAtMs: 1));
    final merged = const ClaudeCredentials(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    ).mergeInto(original);
    final root = jsonDecode(merged) as Map<String, Object?>;
    expect((root['mcpOAuth'] as Map)['keep'], 'me');
    final oauth = root['claudeAiOauth'] as Map;
    expect(oauth['accessToken'], 'new-access');
    expect(oauth['subscriptionType'], 'max');
  });

  group('ClaudeProvider with mocked HTTP', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tokenbar_claude'));
    tearDown(() => dir.deleteSync(recursive: true));

    AccountConfig account() => AccountConfig(
      id: 'c-${dir.path.hashCode}',
      providerId: 'claude',
      label: 'Me',
      homeDir: dir.path,
    );

    test('fetches usage with beta header and profile email', () async {
      File('${dir.path}/.credentials.json').writeAsStringSync(
        jsonEncode(_credentialsJson(expiresAtMs: DateTime.utc(2100).millisecondsSinceEpoch)),
      );
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        if (r.url.path == '/api/oauth/usage') {
          return http.Response(
            File('test/fixtures/claude_oauth_usage.json').readAsStringSync(),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'account': {'email_address': 'me@example.com'},
          }),
          200,
        );
      });
      final s = await ClaudeProvider().fetchSafely(account(), FetchContext(client: client));
      expect(s.error, isNull);
      expect(s.plan, 'Max 20x');
      expect(s.email, 'me@example.com');
      expect(s.weekly!.usedPercent, 12);
      final usageReq = requests.firstWhere((r) => r.url.path == '/api/oauth/usage');
      expect(usageReq.headers['anthropic-beta'], 'oauth-2025-04-20');
      expect(usageReq.headers['User-Agent'], startsWith('claude-code/'));
    });

    test('expired token without opt-in refresh asks to run claude', () async {
      File('${dir.path}/.credentials.json')
          .writeAsStringSync(jsonEncode(_credentialsJson(expiresAtMs: 1000)));
      final s = await ClaudeProvider().fetchSafely(
        account(),
        FetchContext(client: MockClient((_) async => http.Response('', 500))),
      );
      expect(s.error, contains('过期'));
      expect(s.errorHint, contains('claude'));
    });

    test('opt-in refresh writes rotated tokens back to the file', () async {
      final file = File('${dir.path}/.credentials.json')
        ..writeAsStringSync(jsonEncode(_credentialsJson(expiresAtMs: 1000)));
      final client = MockClient((r) async {
        if (r.url.host == 'platform.claude.com') {
          expect(r.bodyFields['grant_type'], 'refresh_token');
          expect(r.bodyFields['refresh_token'], 'sk-ant-ort01-refresh');
          return http.Response(
            jsonEncode({'access_token': 'fresh', 'refresh_token': 'rotated', 'expires_in': 28800}),
            200,
          );
        }
        if (r.url.path == '/api/oauth/usage') {
          expect(r.headers['Authorization'], 'Bearer fresh');
          return http.Response(
            File('test/fixtures/claude_oauth_usage.json').readAsStringSync(),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final s = await ClaudeProvider().fetchSafely(
        account(),
        FetchContext(client: client, allowClaudeTokenRefresh: true),
      );
      expect(s.error, isNull);
      final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final oauth = saved['claudeAiOauth'] as Map;
      expect(oauth['refreshToken'], 'rotated');
      expect((saved['mcpOAuth'] as Map)['keep'], 'me');
    });

    test('missing profile scope is reported', () async {
      File('${dir.path}/.credentials.json').writeAsStringSync(
        jsonEncode(
          _credentialsJson(
            expiresAtMs: DateTime.utc(2100).millisecondsSinceEpoch,
            scopes: ['user:inference'],
          ),
        ),
      );
      final s = await ClaudeProvider().fetchSafely(
        account(),
        FetchContext(client: MockClient((_) async => http.Response('', 500))),
      );
      expect(s.error, contains('user:profile'));
    });

    test('429 sets backoff for following fetches', () async {
      File('${dir.path}/.credentials.json').writeAsStringSync(
        jsonEncode(_credentialsJson(expiresAtMs: DateTime.utc(2100).millisecondsSinceEpoch)),
      );
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        return http.Response('', 429, headers: {'retry-after': '120'});
      });
      final provider = ClaudeProvider();
      final first = await provider.fetchSafely(account(), FetchContext(client: client));
      final second = await provider.fetchSafely(account(), FetchContext(client: client));
      expect(first.error, contains('限流'));
      expect(second.error, contains('限流'));
      expect(calls, 1);
    });
  });
}
