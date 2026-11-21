import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

// Synthetic, schema-shaped bodies only (CodexBar plugin contracts); no captured account data.

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<(UsageSnapshot, List<http.Request>)> _run(
  String providerId,
  http.Response Function(http.Request) respond, {
  String secret = 'test-key',
  Map<String, String> options = const {},
}) async {
  final requests = <http.Request>[];
  final client = MockClient((r) async {
    requests.add(r);
    return respond(r);
  });
  final provider = ProviderRegistry.instance.byId(providerId)!;
  final account = AccountConfig(
    id: 'a',
    providerId: providerId,
    label: providerId,
    sourceType: SourceType.apiKey,
    secret: secret,
    options: options,
  );
  final s = await provider.fetchSafely(
    account,
    FetchContext(client: client, clock: () => DateTime.utc(2031, 5, 20, 12)),
  );
  return (s, requests);
}

Credits _credit(UsageSnapshot s, String id) => s.credits.firstWhere((c) => c.id == id);

void main() {
  group('abliteration.ai', () {
    test('balance is total minus usage and the meter is the used share', () async {
      final (s, requests) = await _run(
        'abliteration',
        (_) => _json({
          'data': {'total_credits': 50.0, 'total_usage': 12.5},
        }),
      );
      expect(s.error, isNull);
      expect(requests.single.url.toString(), 'https://api.abliteration.ai/v1/credits');
      expect(requests.single.headers['Authorization'], 'Bearer test-key');
      expect(_credit(s, 'abliteration-balance').balance, 37.5);
      expect(s.windows.single.usedPercent, 25);
      expect(s.windows.single.resetsAt, isNull);
    });

    test('overspend floors the balance at zero and caps the meter', () async {
      final (s, _) = await _run(
        'abliteration',
        (_) => _json({
          'data': {'total_credits': 5, 'total_usage': 7.25},
        }),
      );
      expect(_credit(s, 'abliteration-balance').balance, 0);
      expect(s.windows.single.usedPercent, 100);
    });

    test('zero total keeps the amounts without inventing a percentage', () async {
      final (s, _) = await _run(
        'abliteration',
        (_) => _json({
          'data': {'total_credits': 0, 'total_usage': 0},
        }),
      );
      expect(s.windows, isEmpty);
      expect(_credit(s, 'abliteration-balance').balance, 0);
    });

    test('missing, negative or non-numeric counters fail closed', () async {
      for (final data in [
        <String, Object?>{'total_credits': 5},
        {'total_credits': -1, 'total_usage': 0},
        {'total_credits': '5', 'total_usage': 0},
      ]) {
        final (s, _) = await _run('abliteration', (_) => _json({'data': data}));
        expect(s.error, isNotNull, reason: '$data');
      }
    });

    test('a rejected key is reported with the status', () async {
      final (s, _) = await _run('abliteration', (_) => _json({}, 401));
      expect(s.error, contains('401'));
    });
  });

  group('TrustedRouter', () {
    Map<String, Object?> body({Object? limit = 10000000, Object? remaining = 7500000}) => {
      'data': {
        'usage_microdollars': 42000000,
        'usage_daily_microdollars': 1500000,
        'usage_weekly_microdollars': 9000000,
        'usage_monthly_microdollars': 30000000,
        'limit_microdollars': limit,
        'limit_remaining_microdollars': remaining,
      },
    };

    test('uses the API remaining amount and does not recompute it', () async {
      final (s, requests) = await _run('trustedrouter', (_) => _json(body()));
      expect(s.error, isNull);
      expect(requests.single.url.toString(), 'https://api.trustedrouter.com/v1/key');
      expect(_credit(s, 'trustedrouter-remaining').balance, 7.5);
      expect(s.windows.single.usedPercent, 25);
      expect(_credit(s, 'trustedrouter-today').used, 1.5);
      expect(_credit(s, 'trustedrouter-month').used, 30);
      expect(s.extras['累计'], r'$42.00');
    });

    test('a null limit means unlimited: spend only, no meter', () async {
      final (s, _) = await _run('trustedrouter', (_) => _json(body(limit: null, remaining: null)));
      expect(s.error, isNull);
      expect(s.windows, isEmpty);
      expect(s.credits.any((c) => c.id == 'trustedrouter-remaining'), isFalse);
    });

    test('a zero-dollar limit stays visible without a gauge', () async {
      final (s, _) = await _run('trustedrouter', (_) => _json(body(limit: 0, remaining: 0)));
      expect(s.windows, isEmpty);
      expect(_credit(s, 'trustedrouter-remaining').balance, 0);
    });

    test('limit without remaining, fractional or negative amounts fail closed', () async {
      for (final b in [
        body(limit: 5000000, remaining: null),
        body(limit: null, remaining: 5000000),
        body(limit: 1.5),
        body(remaining: -1),
      ]) {
        final (s, _) = await _run('trustedrouter', (_) => _json(b));
        expect(s.error, isNotNull, reason: '$b');
      }
    });
  });

  group('Tripo', () {
    test('balance is already the available amount; frozen is separate', () async {
      final (s, requests) = await _run(
        'tripo',
        (_) => _json({
          'code': 0,
          'data': {'balance': 125.5, 'frozen': 20},
        }),
      );
      expect(s.error, isNull);
      expect(requests.single.url.toString(), 'https://openapi.tripo3d.ai/v3/account/balance');
      final c = _credit(s, 'tripo-balance');
      expect(c.balance, 125.5);
      expect(c.currency, isNull);
      expect(s.extras['冻结积分'], '20');
      expect(s.windows, isEmpty);
    });

    test('a non-zero code, or a missing / negative amount, is an error', () async {
      for (final b in [
        {'code': 1001, 'data': {}},
        {
          'code': 0,
          'data': {'balance': 1},
        },
        {
          'code': 0,
          'data': {'balance': -1, 'frozen': 0},
        },
        {'data': {}},
      ]) {
        final (s, _) = await _run('tripo', (_) => _json(b));
        expect(s.error, isNotNull, reason: '$b');
      }
    });
  });

  group('SiliconFlow', () {
    Map<String, Object?> body({Object? total = '12.34', String? status = 'normal'}) => {
      'code': 20000,
      'status': true,
      'data': {'totalBalance': total, 'chargeBalance': '10', 'balance': '2.34', 'status': ?status},
    };

    test('international accounts read USD from api.siliconflow.com', () async {
      final (s, requests) = await _run('siliconflow', (_) => _json(body()));
      expect(s.error, isNull);
      expect(requests.single.url.toString(), 'https://api.siliconflow.com/v1/user/info');
      final c = _credit(s, 'siliconflow-balance');
      expect(c.balance, 12.34);
      expect(c.currency, 'USD');
      expect(s.extras['充值余额'], r'$10.00');
      expect(s.extras.containsKey('状态'), isFalse);
    });

    test('the China region uses CNY and a non-normal status is shown', () async {
      final (s, requests) = await _run(
        'siliconflow',
        (_) => _json(body(status: 'frozen')),
        options: {'region': 'cn'},
      );
      expect(requests.single.url.host, 'api.siliconflow.cn');
      expect(_credit(s, 'siliconflow-balance').currency, 'CNY');
      expect(s.extras['状态'], 'frozen');
    });

    test('the retired China API (410 / code 20092) is explained', () async {
      final (gone, _) = await _run('siliconflow', (_) => _json({}, 410), options: {'region': 'cn'});
      expect(gone.error, contains('下线'));
      final (coded, _) = await _run('siliconflow', (_) => _json({'code': 20092, 'status': false}));
      expect(coded.error, contains('下线'));
    });

    test('bad credentials and malformed amounts fail', () async {
      final (auth, _) = await _run('siliconflow', (_) => _json({'code': 30014, 'status': false}));
      expect(auth.error, contains('凭证'));
      for (final total in <Object?>['abc', '1e3', null, true]) {
        final (s, _) = await _run('siliconflow', (_) => _json(body(total: total)));
        expect(s.error, isNotNull, reason: '$total');
      }
    });
  });

  group('MiMo Token Plan key', () {
    Map<String, Object?> plan({
      int total = 1000,
      int used = 250,
      int? remaining,
      String? start = '2031-05-01 00:00:00',
      String? end = '2031-06-01 00:00:00',
    }) => {
      'object': 'token_plan',
      'plan_code': 'standard',
      'quota': {
        'total_credits': total,
        'used_credits': used,
        'remaining_credits': remaining ?? (total - used).clamp(0, total),
      },
      'period': {'start_at': ?start, 'end_at': ?end},
    };

    test('a tp- key reads the regional endpoint without any cookie', () async {
      final (s, requests) = await _run(
        'mimo',
        (_) => _json(plan()),
        secret: 'tp-abc',
        options: {'region': 'sgp'},
      );
      expect(s.error, isNull);
      expect(
        requests.single.url.toString(),
        'https://token-plan-sgp.xiaomimimo.com/v1/platform/token_plan',
      );
      expect(requests.single.headers['Authorization'], 'Bearer tp-abc');
      expect(requests.single.headers.containsKey('Cookie'), isFalse);
      expect(s.plan, 'Standard');
      final w = s.windows.single;
      expect(w.usedPercent, 25);
      expect(w.resetsAt, DateTime.utc(2031, 6, 1));
      expect(w.windowMinutes, 31 * 24 * 60);
      expect(s.credits, isEmpty);
    });

    test('the region defaults to China mainland', () async {
      final (_, requests) = await _run('mimo', (_) => _json(plan()), secret: 'tp-abc');
      expect(requests.single.url.host, 'token-plan-cn.xiaomimimo.com');
    });

    test('zero total shows no window; dates are optional', () async {
      final (s, _) = await _run(
        'mimo',
        (_) => _json(plan(total: 0, used: 0, start: null, end: null)),
        secret: 'tp-abc',
      );
      expect(s.error, isNull);
      expect(s.windows, isEmpty);
    });

    test('inconsistent remaining credits or a reversed period fail', () async {
      for (final b in [
        plan(remaining: 5),
        plan(start: '2031-06-01 00:00:00', end: '2031-05-01 00:00:00'),
        plan(end: '2031-06-01'),
        {...plan(), 'object': 'something_else'},
      ]) {
        final (s, _) = await _run('mimo', (_) => _json(b), secret: 'tp-abc');
        expect(s.error, isNotNull, reason: '$b');
      }
    });

    test('validation accepts a tp- key and still checks cookies', () {
      final mimo = ProviderRegistry.instance.byId('mimo')!;
      FieldValues values(String secret) =>
          FieldValues(mimo.displayName, mimo.fields, {ProviderField.secretKey: secret});
      expect(mimo.validateManual(values('tp-abc')), isNull);
      expect(mimo.validateManual(values('api-platform_serviceToken=x; userId=1')), isNull);
      expect(mimo.validateManual(values('sk-inference-key')), isNotNull);
    });
  });
}
