import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/src/providers/api/cookie_b_providers.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

// Synthetic schema-shaped examples only; no captured account data.
const _cookie = 'api-platform_serviceToken=test-session; userId=test-user';
final _now = DateTime.utc(2031, 5, 20, 12);

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _plan({bool expired = false, String? end = '2031-06-01 00:00:00'}) => {
  'code': 0,
  'data': {'planCode': 'standard', 'currentPeriodEnd': end, 'expired': expired},
};

Map<String, Object?> _usage(Map<String, Object?> item) => {
  'code': 0,
  'data': {
    'monthUsage': {
      'items': [item],
    },
  },
};

Future<(UsageSnapshot, List<http.Request>)> _fetch({
  UsageProvider? provider,
  String cookie = _cookie,
  Map<String, Object?>? plan,
  Map<String, Object?>? usage,
  Map<String, http.Response> responses = const {},
}) async {
  final requests = <http.Request>[];
  final replies = {
    'balance': _json({
      'code': 0,
      'data': {
        'balance': '12.50',
        'currency': 'CNY',
        'cashBalance': '10.00',
        'giftBalance': '2.50',
      },
    }),
    'tokenPlan/detail': _json(plan ?? _plan()),
    'tokenPlan/usage': _json(usage ?? _usage({'used': 240, 'limit': 960, 'percent': 0.25})),
    ...responses,
  };
  final client = MockClient((request) async {
    requests.add(request);
    return replies[request.url.path.replaceFirst('/api/v1/', '')] ?? http.Response('', 404);
  });
  addTearDown(client.close);
  final snapshot = await (provider ?? MiMoProvider()).fetchSafely(
    AccountConfig(
      id: 'synthetic-mimo',
      providerId: 'mimo',
      label: 'MiMo test',
      sourceType: SourceType.apiKey,
      secret: cookie,
    ),
    FetchContext(client: client, clock: () => _now),
  );
  return (snapshot, requests);
}

void main() {
  test('registry exposes MiMo without enabling the other unintegrated cookie providers', () async {
    final provider = ProviderRegistry.instance.byId('mimo');
    expect(provider, isA<MiMoProvider>());
    expect(provider!.supportedSources, [SourceType.apiKey]);
    expect(provider.fields.single.isSecure, isTrue);
    expect(ProviderRegistry.instance.byId('sakana'), isNull);

    final (snapshot, requests) = await _fetch(provider: provider);
    expect(snapshot.hasError, isFalse);
    expect(snapshot.providerId, 'mimo');
    expect(snapshot.source, 'web');
    expect(snapshot.plan, 'Standard');
    expect(snapshot.credits.single.balance, 12.5);
    expect(snapshot.credits.single.currency, 'CNY');
    expect(snapshot.window('mimo-plan')!.usedPercent, 25);
    expect(snapshot.window('mimo-plan')!.resetsAt, DateTime.utc(2031, 6, 1));
    expect(requests.map((r) => r.url.path), [
      '/api/v1/balance',
      '/api/v1/tokenPlan/detail',
      '/api/v1/tokenPlan/usage',
    ]);
  });

  test('sends only the documented MiMo cookies to the fixed HTTPS endpoints', () async {
    final (snapshot, requests) = await _fetch(
      cookie:
          'Cookie: $_cookie; unrelated=do-not-forward; api-platform_ph=test-ph; '
          'api-platform_slh=test-slh',
    );
    expect(snapshot.hasError, isFalse);
    for (final request in requests) {
      expect(request.method, 'GET');
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'platform.xiaomimimo.com');
      expect(request.followRedirects, isFalse);
      expect(
        request.headers['cookie'],
        '$_cookie; api-platform_ph=test-ph; api-platform_slh=test-slh',
      );
      expect(request.headers['origin'], 'https://platform.xiaomimimo.com');
      expect(request.headers['authorization'], isNull);
    }
    final serialized = jsonEncode(snapshot.toJson());
    expect(serialized, isNot(contains('test-session')));
    expect(serialized, isNot(contains('test-user')));
    expect(serialized, isNot(contains('do-not-forward')));
  });

  for (final cookie in ['', 'userId=test-user', 'api-platform_serviceToken=test-session']) {
    test('incomplete Cookie is rejected before any request: ${cookie.split('=').first}', () async {
      final (snapshot, requests) = await _fetch(cookie: cookie);
      expect(snapshot.hasError, isTrue);
      expect(requests, isEmpty);
      expect(snapshot.credits, isEmpty);
      expect(snapshot.windows, isEmpty);
      expect(snapshot.error, isNot(contains('test-session')));
    });
  }

  // The upstream MiMo snapshot and the existing cookie-provider test treat
  // item.percent as a fraction; do not guess its unit from its magnitude.
  for (final (fraction, expected) in [(0.0, 0.0), (0.01, 1.0), (0.25, 25.0), (1.0, 100.0)]) {
    test('usage fraction $fraction becomes $expected percent', () async {
      final (snapshot, _) = await _fetch(
        usage: _usage({'used': 240, 'limit': 960, 'percent': fraction}),
      );
      expect(snapshot.window('mimo-plan')!.usedPercent, closeTo(expected, 1e-9));
    });
  }

  for (final (label, plan) in [
    ('expired flag with future end', _plan(expired: true)),
    ('expired flag without end', _plan(expired: true, end: null)),
    ('period ended', _plan(end: '2031-05-20 11:59:59')),
    ('period ends exactly now', _plan(end: '2031-05-20 12:00:00')),
  ]) {
    test('$label does not publish an available plan quota', () async {
      final (snapshot, _) = await _fetch(
        plan: plan,
        usage: _usage({'used': 0, 'limit': 960, 'percent': 0}),
      );
      expect(snapshot.hasError, isFalse);
      expect(snapshot.credits.single.balance, 12.5);
      expect(snapshot.windows, isEmpty);
      expect(snapshot.tightestWindow, isNull);
      expect(snapshot.extras['套餐状态'], '已过期');
    });
  }

  test('period ending in the future still publishes current usage', () async {
    final (snapshot, _) = await _fetch(plan: _plan(end: '2031-05-20 12:00:01'));
    expect(snapshot.window('mimo-plan')!.remainingPercent, 75);
    expect(snapshot.extras.containsKey('套餐状态'), isFalse);
  });

  for (final item in [
    {'used': 240, 'limit': 960},
    {'used': 240, 'limit': 960, 'percent': 'invalid'},
    {'used': 240, 'limit': 960, 'percent': 'NaN'},
    {'used': 240, 'limit': 960, 'percent': 'Infinity'},
    {'limit': 960, 'percent': 0.25},
  ]) {
    test('incomplete usage $item preserves balance without inventing available quota', () async {
      final (snapshot, _) = await _fetch(usage: _usage(item));
      expect(snapshot.hasError, isFalse);
      expect(snapshot.credits.single.balance, 12.5);
      expect(snapshot.windows, isEmpty);
    });
  }

  for (final (label, part, response) in [
    ('detail server error', 'tokenPlan/detail', http.Response('', 500)),
    ('detail invalid JSON', 'tokenPlan/detail', http.Response('not JSON', 200)),
    ('usage rejected', 'tokenPlan/usage', http.Response('', 403)),
    ('usage invalid JSON', 'tokenPlan/usage', http.Response('not JSON', 200)),
    ('usage API error', 'tokenPlan/usage', _json({'code': 401})),
  ]) {
    test('optional $label preserves account balance', () async {
      final (snapshot, _) = await _fetch(responses: {part: response});
      expect(snapshot.hasError, isFalse);
      expect(snapshot.credits.single.balance, 12.5);
      if (part == 'tokenPlan/usage') {
        expect(snapshot.windows, isEmpty);
      }
    });
  }

  for (final status in [302, 401, 403]) {
    test('balance HTTP $status reports authentication failure without leaking Cookie', () async {
      final (snapshot, requests) = await _fetch(
        responses: {'balance': http.Response('test-session must not be echoed', status)},
      );
      expect(snapshot.hasError, isTrue);
      expect(snapshot.error, isNot(contains('test-session')));
      expect(snapshot.errorHint, contains('platform.xiaomimimo.com'));
      expect(snapshot.errorHint, contains('Cookie'));
      expect(snapshot.credits, isEmpty);
      expect(requests, hasLength(1));
      expect(requests.single.followRedirects, isFalse);
    });
  }
}
