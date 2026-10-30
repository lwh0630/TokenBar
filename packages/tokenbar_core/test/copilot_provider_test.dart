import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/src/providers/api/local_auth_a_providers.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

// Synthetic schema-shaped examples only; no captured account data.
const _token = 'gho_synthetic-copilot-test-token';
final _now = DateTime.utc(2031, 5, 20, 12);

Map<String, Object?> _fixture([String name = 'copilot_user_individual_token_billing.json']) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> _quotas(Map<String, Object?> json) =>
    json['quota_snapshots']! as Map<String, Object?>;

Map<String, Object?> _quota(Map<String, Object?> json, String id) =>
    _quotas(json)[id]! as Map<String, Object?>;

AccountConfig _account({Map<String, String> options = const {}}) => AccountConfig(
  id: 'synthetic-copilot',
  providerId: 'copilot',
  label: 'Copilot test',
  sourceType: SourceType.apiKey,
  secret: _token,
  options: options,
);

FetchContext _context(http.Client client) => FetchContext(client: client, clock: () => _now);

http.Response _json(Object value, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('registry enables only Copilot from the unintegrated local-auth group', () {
    final provider = ProviderRegistry.instance.byId('copilot');
    expect(provider, isA<CopilotProvider>());
    expect(provider!.supportedSources, [SourceType.apiKey]);
    final tokenField = provider.fields.first;
    expect(tokenField.key, ProviderField.secretKey);
    expect(tokenField.label, 'GitHub Token');
    expect(tokenField.isSecure, isTrue);
    expect(tokenField.envVars, ['COPILOT_API_TOKEN']);
    expect(provider.fields.last.key, 'enterpriseHost');
    for (final id in ['gemini', 'kiro', 'jetbrains', 'amp', 'kilo', 'hyper']) {
      expect(ProviderRegistry.instance.byId(id), isNull, reason: id);
    }
  });

  test(
    'registered provider fetches seat credits using the GitHub token without exposing it',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return _json(_fixture());
      });
      addTearDown(client.close);
      final account = _account();
      final snapshot = await ProviderRegistry.instance
          .byId('copilot')!
          .fetchSafely(account, _context(client));

      expect(snapshot.error, isNull);
      expect(snapshot.providerId, 'copilot');
      expect(snapshot.plan, 'Individual');
      expect(snapshot.source, 'api-key');
      expect(snapshot.credits.single.used, 360);
      expect(snapshot.window('copilot-completions')!.remainingPercent, closeTo(70, 1e-9));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.github.com/copilot_internal/user');
      expect(request.headers['Authorization'], 'token $_token');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers['Editor-Version'], 'vscode/1.96.2');
      expect(request.headers['Editor-Plugin-Version'], 'copilot-chat/0.26.7');
      expect(request.headers['User-Agent'], 'GitHubCopilotChat/0.26.7');
      expect(request.headers['X-Github-Api-Version'], '2025-04-01');
      expect(request.body, isEmpty);
      expect(jsonEncode(account.toJson()), isNot(contains(_token)));
      expect(jsonEncode(snapshot.toJson()), isNot(contains(_token)));
    },
  );

  test('zero premium placeholder does not hide completion credits or precise percentages', () {
    final usage = parseCopilotUsage(_fixture());
    expect(usage.windows.map((window) => window.id), ['copilot-completions', 'copilot-chat']);
    final completions = usage.windows.first;
    expect(completions.label, 'AI Credits');
    expect(completions.usedPercent, closeTo(30, 1e-9));
    expect(completions.resetsAt, DateTime.utc(2031, 6, 1));
    expect(usage.windows.last.usedPercent, closeTo(37.5, 1e-9));
    final credits = usage.credits.single;
    expect(credits.id, 'copilot-seat-credits');
    expect(credits.used, 360);
    expect(credits.limit, isNull);
    expect(credits.balance, isNull);
    expect(credits.currency, isNull);

    // The reported percentage takes precedence over rounded integer counts.
    final rounded = _fixture();
    _quota(
      rounded,
      'chat',
    ).addAll({'remaining': 49, 'quota_remaining': 49.6, 'percent_remaining': 62});
    expect(parseCopilotUsage(rounded).windows.last.usedPercent, closeTo(38, 1e-9));
  });

  for (final topLevelBilling in [null, false]) {
    test('quota token billing is recognized with top-level flag $topLevelBilling', () {
      final json = _fixture('copilot_user_business_token_billing.json');
      json['token_based_billing'] = topLevelBilling;
      _quota(json, 'premium_interactions')['token_based_billing'] = true;
      final usage = parseCopilotUsage(json);
      expect(usage.windows, isEmpty);
      expect(usage.credits.single.used, 31);
    });
  }

  test('quota-only token billing labels completion credits without a top-level flag', () {
    final json = _fixture()..remove('token_based_billing');
    final usage = parseCopilotUsage(json);
    expect(usage.windows.first.id, 'copilot-completions');
    expect(usage.windows.first.label, 'AI Credits');
    expect(usage.credits.single.used, 360);
  });

  test('quota-only token billing without counters does not invent a quota window', () {
    final usage = parseCopilotUsage({
      'copilot_plan': 'business',
      'quota_snapshots': {
        'premium_interactions': {
          'token_based_billing': true,
          'has_quota': false,
          'entitlement': 0,
          'remaining': 0,
        },
      },
    });
    expect(usage.windows, isEmpty);
    expect(usage.credits, isEmpty);
  });

  test('has_quota false cannot create a usable window while its credit counter is retained', () {
    final usage = parseCopilotUsage({
      'copilot_plan': 'business',
      'quota_snapshots': {
        'completions': {
          'has_quota': false,
          'token_based_billing': true,
          'entitlement': 1200,
          'remaining': 1200,
          'percent_remaining': 100,
          'credits_used': 31,
        },
      },
    });
    expect(usage.windows, isEmpty);
    expect(usage.credits.single.used, 31);
  });

  test('legacy Free monthly completion quota is labeled as code completions', () {
    final usage = parseCopilotUsage({
      'copilot_plan': 'free',
      'monthly_quotas': {'completions': 1200, 'chat': 80},
      'limited_user_quotas': {'completions': 900, 'chat': 16},
    });
    expect(usage.windows.map((window) => window.id), ['copilot-completions', 'copilot-chat']);
    expect(usage.windows.first.label, '代码补全');
    expect(usage.windows.first.usedPercent, 25);
    expect(usage.windows.last.usedPercent, 80);
    expect(usage.credits, isEmpty);
  });

  test('direct completion quota takes precedence over legacy monthly fallback', () {
    final json = _fixture();
    json['monthly_quotas'] = {'completions': 1200};
    json['limited_user_quotas'] = {'completions': 600};
    final usage = parseCopilotUsage(json);
    expect(usage.windows.first.id, 'copilot-completions');
    expect(usage.windows.first.usedPercent, closeTo(30, 1e-9));
    expect(usage.credits.single.used, 360);
  });

  test('legacy premium window keeps its id and request label', () {
    final usage = parseCopilotUsage(_fixture('copilot_user_metered.json'));
    expect(usage.windows.map((window) => window.id), ['copilot-premium', 'copilot-chat']);
    expect(usage.windows.first.label, '高级请求');
    expect(usage.windows.first.usedPercent, closeTo(10, 1e-9));
  });

  test('shared seat credit counters are selected once instead of being added', () {
    final json = _fixture();
    _quota(json, 'chat')['credits_used'] = 360;
    final usage = parseCopilotUsage(json);
    expect(usage.credits.single.used, 360);

    _quotas(json)['premium_interactions'] = {
      'entitlement': 300,
      'remaining': 293,
      'percent_remaining': 97.6,
      'credits_used': 7,
    };
    expect(parseCopilotUsage(json).credits.single.used, 7);
  });

  test('valid chat credits outrank a premium placeholder when completions are absent', () {
    final json = _fixture();
    _quotas(json).remove('completions');
    _quota(json, 'chat')['credits_used'] = 5;
    final usage = parseCopilotUsage(json);
    expect(usage.windows.single.id, 'copilot-chat');
    expect(usage.credits.single.used, 5);
  });

  test('zero credits without an entitlement remains a counter with no invented allowance', () {
    final json = _fixture('copilot_user_business_token_billing.json');
    _quota(json, 'premium_interactions')['credits_used'] = 0;
    final usage = parseCopilotUsage(json);
    expect(usage.windows, isEmpty);
    expect(usage.credits.single.used, 0);
    expect(usage.credits.single.limit, isNull);
  });

  test('fully exhausted completion quota remains a real window', () {
    final json = _fixture();
    _quotas(json).remove('chat');
    _quota(
      json,
      'completions',
    ).addAll({'remaining': 0, 'quota_remaining': 0, 'percent_remaining': 0, 'credits_used': 1200});
    final usage = parseCopilotUsage(json);
    expect(usage.windows.single.id, 'copilot-completions');
    expect(usage.windows.single.usedPercent, 100);
    expect(usage.credits.single.used, 1200);
  });

  test('unlimited plans preserve their counter without a synthetic quota window', () {
    final usage = parseCopilotUsage({
      'copilot_plan': 'business',
      'quota_snapshots': {
        'completions': {'unlimited': true, 'credits_used': 31},
      },
    });
    expect(usage.windows, isEmpty);
    expect(usage.credits.single.used, 31);
  });

  test('unrecognized metered response remains a parse error', () {
    expect(() => parseCopilotUsage({'copilot_plan': 'free'}), throwsA(isA<ProviderException>()));
  });

  test('enterprise host uses the same GitHub-token endpoint without a device login', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return _json(_fixture());
    });
    addTearDown(client.close);
    final snapshot = await CopilotProvider().fetchSafely(
      _account(options: {'enterpriseHost': 'https://OctoCorp.ghe.com/login'}),
      _context(client),
    );
    expect(snapshot.error, isNull);
    expect(requests.single.url.toString(), 'https://api.octocorp.ghe.com/copilot_internal/user');
    expect(requests.single.headers['Authorization'], 'token $_token');
  });

  for (final status in [401, 403]) {
    test('HTTP $status reports authentication guidance without leaking the token', () async {
      final client = MockClient((_) async => _json({'message': 'Bad credentials'}, status));
      addTearDown(client.close);
      final snapshot = await CopilotProvider().fetchSafely(_account(), _context(client));
      expect(snapshot.error, contains('HTTP $status'));
      expect(snapshot.errorHint, contains('GitHub'));
      expect(snapshot.windows, isEmpty);
      expect(snapshot.credits, isEmpty);
      expect(jsonEncode(snapshot.toJson()), isNot(contains(_token)));
    });
  }
}
