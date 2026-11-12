import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// Runs [providerId] against canned responses keyed by URL path substring.
Future<(UsageSnapshot, List<http.Request>)> _run(
  String providerId,
  Map<String, Object> routes, {
  String? secret = 'test-key',
  Map<String, String> options = const {},
  DateTime? now,
}) async {
  final requests = <http.Request>[];
  final client = MockClient((r) async {
    requests.add(r);
    for (final e in routes.entries) {
      if (r.url.toString().contains(e.key)) {
        final v = e.value;
        return v is int
            ? http.Response('{}', v)
            : http.Response.bytes((v as String).codeUnits, 200);
      }
    }
    return http.Response('not found', 404);
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
    FetchContext(client: client, clock: () => now ?? DateTime.utc(2026, 10, 20, 12)),
  );
  return (s, requests);
}

Credits _credit(UsageSnapshot s, String id) => s.credits.firstWhere((c) => c.id == id);

void main() {
  group('field storage', () {
    test('single primary secret stays raw, several become JSON', () {
      expect(SecretBundle.encode({'secret': 'abc'}), 'abc');
      final both = SecretBundle.encode({'secret': 'abc', 'platformToken': 'xyz'})!;
      expect(SecretBundle.decode(both), {'secret': 'abc', 'platformToken': 'xyz'});
      expect(SecretBundle.decode('{not json'), {'secret': '{not json'});
    });

    test('cookie helpers accept header, cURL and bare values', () {
      expect(normalizeCookieHeader('Cookie: a=1; b=2'), 'a=1; b=2');
      expect(normalizeCookieHeader("curl 'https://x' -H 'cookie: s=1; t=2'"), 's=1; t=2');
      expect(cookieHeaderFor('eyJhbGc.x.y', 'session'), 'session=eyJhbGc.x.y');
      expect(cookieValue('a=1; session=xyz', 'session'), 'xyz');
    });

    test('cookie normalization strips copy artifacts that break the header', () {
      // Tab-separated `Cookie` label, as copied from some DevTools layouts.
      expect(normalizeCookieHeader('Cookie\tSEARCH_SAMESITE=x; NID=y'), 'SEARCH_SAMESITE=x; NID=y');
      // Line-wrapped copies stay one header; a bare pair is never mistaken for a label.
      expect(normalizeCookieHeader('a=1;\nb=2'), 'a=1; b=2');
      expect(normalizeCookieHeader('cookie=plain'), 'cookie=plain');
      // Control and non-ASCII characters (zero-width, full-width, BOM) are dropped.
      expect(normalizeCookieHeader('a=1; b=2\u200b\u3000\uff01'), 'a=1; b=2');
      // Garbage without any pair gets a user-facing error instead of a raw
      // FormatException from dart:io.
      expect(
        () => normalizeCookieHeader('随便粘贴的一句话'),
        throwsA(isA<ProviderException>().having((e) => e.hint, 'hint', isNotNull)),
      );
      // A literal ellipsis means the value was copied from a truncating UI
      // preview — the middle of the credential is missing, so fail loudly.
      expect(
        () => normalizeCookieHeader('a=1; b=2\u2026c=3'),
        throwsA(isA<ProviderException>().having((e) => e.message, 'message', contains('截断'))),
      );
    });

    test('gateway URLs: https anywhere, http only on private hosts', () {
      expect(isPrivateHost('192.168.1.5'), isTrue);
      expect(isPrivateHost('example.com'), isFalse);
    });
  });

  test('deepseek balance prefers USD', () async {
    final (s, req) = await _run('deepseek', {
      '/user/balance': _fixture('deepseek_balance_usd.json'),
    });
    expect(s.error, isNull);
    expect(_credit(s, 'deepseek-balance').balance, 50);
    expect(_credit(s, 'deepseek-balance').currency, 'USD');
    expect(_credit(s, 'deepseek-granted').balance, 10);
    expect(req.single.headers['Authorization'], 'Bearer test-key');
  });

  test('deepseek picks CNY when USD is empty', () async {
    final (s, _) = await _run('deepseek', {
      '/user/balance': _fixture('deepseek_balance_cny_over_empty_usd.json'),
    });
    expect(_credit(s, 'deepseek-balance').currency, 'CNY');
    expect(_credit(s, 'deepseek-balance').balance, 100);
  });

  test('deepseek platform token path', () async {
    final (s, req) = await _run('deepseek', {
      'get_user_summary': _fixture('deepseek_platform_user_summary.json'),
    }, secret: SecretBundle.encode({'platformToken': 'tok'}));
    expect(_credit(s, 'deepseek-balance').balance, closeTo(8.47, 1e-9));
    expect(req.single.headers['x-client-platform'], 'web');
  });

  test('moonshot region and deficit', () async {
    final (s, req) = await _run(
      'moonshot',
      {'/balance': _fixture('moonshot_balance_deficit.json')},
      options: {'region': 'china'},
    );
    expect(req.single.url.host, 'api.moonshot.cn');
    expect(_credit(s, 'moonshot-balance').currency, 'CNY');
    expect(s.extras['欠费'], '¥0.42');
  });

  test('openai falls back to credit grants', () async {
    final (s, _) = await _run('openai', {
      '/organization/costs': 403,
      'credit_grants': _fixture('openai_credit_grants.json'),
    }, now: DateTime.utc(2026, 10, 20));
    expect(s.source, 'billing-api');
    expect(s.windows.single.usedPercent, 25);
    expect(_credit(s, 'openai-credits').used, 25);
    expect(
      s.windows.single.resetsAt,
      DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true),
    );
  });

  test('openai admin costs are summed', () async {
    final (s, _) = await _run('openai', {
      '/organization/costs': _fixture('openai_costs_page.json'),
    });
    expect(s.source, 'admin-api');
    expect(_credit(s, 'openai-spend').used, greaterThan(0));
  });

  test('venice DIEM allocation', () async {
    final (s, _) = await _run('venice', {'/billing/balance': _fixture('venice_balance_diem.json')});
    expect(s.windows.single.usedPercent, closeTo(9.5, 1e-9));
    final (u, _) = await _run('venice', {'/billing/balance': _fixture('venice_balance_usd.json')});
    expect(u.windows.single.usedPercent, 0);
    expect(u.extras['余额'], contains('25.75'));
  });

  test('deepinfra balance and spend limit', () async {
    final (s, _) = await _run('deepinfra', {
      '/payment/checklist': _fixture('deepinfra_checklist.json'),
      '/payment/usage': _fixture('deepinfra_usage.json'),
    });
    expect(_credit(s, 'deepinfra-balance').balance, closeTo(95.81, 1e-9));
    expect(_credit(s, 'deepinfra-month').used, closeTo(3.94, 1e-9));
    expect(_credit(s, 'deepinfra-month').limit, 20);
  });

  test('fireworks discovers slug and skips other currencies', () async {
    final (s, req) = await _run('fireworks', {
      '/billing/summary': _fixture('fireworks_billing_summary.json'),
      '/v1/accounts': _fixture('fireworks_accounts.json'),
    });
    expect(s.plan, 'fixture-team');
    expect(_credit(s, 'fireworks-spend').used, closeTo(0.53, 1e-9));
    expect(req.last.url.path, '/v1/accounts/fixture-team/billing/summary');
  });

  test('xai prepaid balance and live estimate', () async {
    final (s, req) = await _run(
      'xai',
      {
        '/prepaid/balance': _fixture('xai_balance.json'),
        '/invoice/preview': _fixture('xai_invoice_preview.json'),
      },
      options: {'teamId': 'team-1234'},
    );
    expect(_credit(s, 'xai-prepaid').balance, 10);
    expect(_credit(s, 'xai-live').balance, closeTo(6.5, 1e-9));
    expect(req.first.url.path, '/v1/billing/teams/team-1234/prepaid/balance');
  });

  test('vercel team credits', () async {
    final (s, _) = await _run('vercel', {'/v1/credits': _fixture('vercel_credits.json')});
    expect(_credit(s, 'vercel-balance').balance, 95.5);
    expect(_credit(s, 'vercel-used').used, 4.5);
  });

  test('vercel personal budget with pagination', () async {
    final (s, req) = await _run(
      'vercel',
      {
        '/v2/user': _fixture('vercel_user.json'),
        'cursor=page': _fixture('vercel_budgets_page2.json'),
        '/budgets/list': _fixture('vercel_budgets_page.json'),
      },
      secret: SecretBundle.encode({'accessToken': 'tok'}),
      options: {'teamId': 'team_fixture'},
      now: DateTime.utc(2026, 10, 14, 12),
    );
    expect(s.error, isNull);
    expect(req, hasLength(3));
    expect(s.windows.single.usedPercent, 25);
    expect(s.windows.single.resetsAt, DateTime.utc(2026, 11, 1));
    expect(s.windows.single.windowMinutes, 44640);
  });

  test('atlas cloud balance', () async {
    final (s, _) = await _run('atlascloud', {'/balance': _fixture('atlascloud_balance.json')});
    expect(_credit(s, 'atlascloud-balance').balance, 95.5);
  });

  test('hugging face usage + ZeroGPU', () async {
    final (s, _) = await _run('huggingface', {
      'usage-v2': _fixture('huggingface_usage_v2.json'),
      'zero-gpu': _fixture('huggingface_zero_gpu_quota.json'),
      'whoami': '{"name":"fixture-a","email":"tester@example.com","isPro":true}',
    });
    expect(s.windows.single.usedPercent, closeTo(40, 1e-9));
    expect(_credit(s, 'huggingface-inference').used, closeTo(0.45, 1e-9));
    expect(s.plan, 'PRO');
  });

  test('elevenlabs credits and voice slots', () async {
    final (s, req) = await _run('elevenlabs', {
      '/subscription': _fixture('elevenlabs_subscription.json'),
    });
    expect(req.single.headers['xi-api-key'], 'test-key');
    expect(s.windows.map((w) => w.usedPercent), [25, 20, 50]);
    expect(
      s.windows.first.resetsAt,
      DateTime.fromMillisecondsSinceEpoch(1738356858 * 1000, isUtc: true),
    );
    expect(s.plan, 'Creator');
  });

  test('litellm personal and team budgets', () async {
    final (s, req) = await _run(
      'litellm',
      {
        '/key/info': '{"info":{"user_id":"user-123","team_id":"team-456"}}',
        '/user/info': _fixture('litellm_user_info.json'),
      },
      options: {'baseUrl': 'https://proxy.example.com/litellm/v1/'},
    );
    expect(req.first.url.toString(), 'https://proxy.example.com/litellm/key/info');
    expect(s.windows[0].usedPercent, closeTo(70.78457208333327, 1e-6));
    expect(s.windows[1].usedPercent, closeTo(21.53245658499998, 1e-6));
    expect(s.email, 'litellm-user@example.com');
  });

  test('litellm rejects public http', () async {
    final (s, req) = await _run('litellm', {}, options: {'baseUrl': 'http://proxy.example.com'});
    expect(req, isEmpty);
    expect(s.error, contains('地址无效'));
  });

  test('sub2api subscription windows', () async {
    final (s, req) = await _run(
      'sub2api',
      {'/v1/usage': _fixture('sub2api_subscription.json')},
      options: {'baseUrl': 'https://api.example.com'},
    );
    expect(req.single.url.path, '/v1/usage');
    expect(s.windows.take(3).map((w) => w.usedPercent), [20, 25, 30]);
    expect(s.plan, 'Claude Team');
    final (q, _) = await _run(
      'sub2api',
      {'/v1/usage': _fixture('sub2api_quota_limited.json')},
      options: {'baseUrl': 'https://api.example.com/v1'},
    );
    expect(q.windows.first.usedPercent, 25);
    expect(q.windows[1].windowMinutes, 300);
  });

  test('bifrost root budgets sorted by duration', () async {
    final (s, req) = await _run(
      'bifrost',
      {'/quota': _fixture('bifrost_quota.json')},
      options: {'baseUrl': 'https://bifrost.example.com/gateway/'},
    );
    expect(
      req.single.url.toString(),
      'https://bifrost.example.com/gateway/api/governance/virtual-keys/quota',
    );
    expect(req.single.headers['x-bf-vk'], 'test-key');
    expect(s.windows[0].usedPercent, closeTo(33.736, 1e-9));
    expect(s.windows[1].usedPercent, 10);
    expect(_credit(s, 'bifrost-budget').limit, 125);
    expect(s.email, 'fixture-team');
  });

  test('llm proxy quota stats', () async {
    final (s, _) = await _run(
      'llmproxy',
      {'/v1/quota-stats': _fixture('llmproxy_quota_stats.json')},
      options: {'baseUrl': 'http://192.168.1.10:8000'},
    );
    expect(s.windows.single.usedPercent, 58);
    expect(s.plan, '3/4 个 Key 可用');
    expect(_credit(s, 'llmproxy-spend').used, 15.5);
  });

  test('clawrouter budget ledger', () async {
    final (s, _) = await _run('clawrouter', {'/v1/usage': _fixture('clawrouter_budgeted.json')});
    expect(s.windows.single.usedPercent, closeTo(0.024, 1e-9));
    expect(s.windows.single.resetsAt, DateTime.utc(2026, 8, 1));
    expect(_credit(s, 'clawrouter-budget').limit, 25);
    final (u, _) = await _run('clawrouter', {'/v1/usage': _fixture('clawrouter_unmetered.json')});
    expect(u.windows, isEmpty);
    expect(_credit(u, 'clawrouter-spend').used, 1.25);
  });

  test('aixy budgets', () async {
    final (s, _) = await _run('aixy', {'/v1/usage': _fixture('aixy_key_usage.json')});
    expect(s.error, isNull);
    expect(s.windows[0].usedPercent, 30);
    expect(s.windows[0].windowMinutes, 43200);
    expect(s.windows[1].usedPercent, 40);
    expect(_credit(s, 'aixy-spend').used, 1.25);
  });

  test('tavily plan + key credits', () async {
    final (s, _) = await _run('tavily', {'/usage': _fixture('tavily_usage.json')});
    expect(s.windows.map((w) => w.usedPercent), [50, 75]);
    expect(s.plan, 'Bootstrap');
    final (u, _) = await _run('tavily', {'/usage': _fixture('tavily_unlimited_key.json')});
    expect(u.windows.single.usedPercent, 1);
  });

  test('linkup balance', () async {
    final (s, _) = await _run('linkup', {'/credits/balance': _fixture('linkup_balance.json')});
    expect(_credit(s, 'linkup-balance').balance, closeTo(123.46, 0.01));
  });

  test('zai quota percent', () async {
    final (s, _) = await _run('zai', {'/quota/limit': _fixture('zai_quota_limit.json')});
    expect(s.error, isNull);
    expect(s.windows.first.usedPercent, 42);
  });

  test('openrouter credits balance', () async {
    final (s, _) = await _run('openrouter', {'/credits': _fixture('openrouter_credits.json')});
    expect(s.error, isNull);
    expect(_credit(s, 'openrouter-balance').balance, 60);
  });

  test('warp request limit and bonus grants', () async {
    final (s, req) = await _run('warp', {'graphql': _fixture('warp_request_limit.json')});
    expect(s.error, isNull);
    expect(req.single.method, 'POST');
    expect(s.windows.first.usedPercent, closeTo(5 / 1500 * 100, 0.001));
    expect(s.windows[1].usedPercent, closeTo(20 / 35 * 100, 0.01));
  });

  test('synthetic quotas', () async {
    final (g, _) = await _run('synthetic', {
      '/v2/quotas': _fixture('synthetic_generic_quotas.json'),
    });
    expect(g.error, isNull);
    expect(g.windows.map((w) => w.usedPercent), containsAll([25, 75]));
    final (c, _) = await _run('synthetic', {
      '/v2/quotas': _fixture('synthetic_credit_quotas.json'),
    });
    expect(c.error, isNull);
    expect(_credit(c, 'synthetic-credits').limit, 36);
  });

  test('neuralwatt kWh, key allowance and balance', () async {
    final (s, _) = await _run('neuralwatt', {'/v1/quota': _fixture('neuralwatt_quota.json')});
    expect(s.error, isNull);
    expect(s.windows[0].usedPercent, closeTo(69.51, 0.01));
    expect(s.windows[0].windowMinutes, 30 * 1440);
    expect(s.windows[1].usedPercent, 25);
    expect(_credit(s, 'neuralwatt-balance').balance, closeTo(32.68, 0.01));
    expect(s.plan, 'Standard plan');
  });

  test('zenmux flows, payg optional', () async {
    final (s, _) = await _run('zenmux', {
      'subscription/detail': _fixture('zenmux_subscription.json'),
      'payg': 404,
    });
    expect(s.error, isNull);
    expect(s.plan, 'Ultra plan');
    expect(s.windows[0].usedPercent, closeTo(7.15, 0.001));
    expect(s.windows[1].usedPercent, closeTo(6.73, 0.001));
  });

  test('exa month spend', () async {
    final (s, req) = await _run(
      'exa',
      {'/usage': _fixture('exa_api_key_usage.json')},
      options: {'apiKeyId': 'key 1'},
    );
    expect(s.error, isNull);
    expect(_credit(s, 'exa-spend').used, 45.67);
    expect(req.single.url.path, contains('key%201'));
    expect(req.single.headers['x-api-key'], 'test-key');
  });

  test('fal balance', () async {
    final (s, req) = await _run('fal', {'/billing': _fixture('fal_billing.json')});
    expect(s.error, isNull);
    expect(_credit(s, 'fal-balance').balance, 42.5);
    expect(req.single.headers['Authorization'], 'Key test-key');
  });

  test('soniox monthly budget', () async {
    final (s, _) = await _run('soniox', {
      '/balance': _fixture('soniox_balance.json'),
      '/usage/monthly': _fixture('soniox_usage_monthly.json'),
    });
    expect(s.error, isNull);
    expect(s.windows.single.usedPercent, closeTo(6, 0.001));
    expect(s.windows.single.resetsAt, DateTime.utc(2026, 11));
  });

  test('poe points', () async {
    final (s, _) = await _run('poe', {'/current_balance': _fixture('poe_balance.json')});
    expect(_credit(s, 'poe-points').balance, 1500);
  });

  test('aerostack tokens', () async {
    final (s, _) = await _run('aerostack', {
      '/billing/usage': _fixture('aerostack_billing_usage.json'),
    });
    expect(s.error, isNull);
    expect(s.windows.single.usedPercent, 15);
    expect(s.plan, 'starter');
  });

  test('cosmic input/output tokens', () async {
    final (s, req) = await _run(
      'cosmic',
      {'/projects/usage': _fixture('cosmic_project_usage.json')},
      options: {'projectId': 'project &other=value'},
    );
    expect(s.error, isNull);
    expect(s.windows.map((w) => w.usedPercent), [25, 10]);
    expect(req.single.url.queryParameters['project_id'], 'project &other=value');
    expect(parseCosmicAllowance('1.5M'), 1500000);
  });

  test('flora workspace balance', () async {
    final (s, req) = await _run(
      'flora',
      {'/usage': _fixture('flora_workspace_usage.json')},
      options: {'workspaceId': 'ws_fixture123'},
      now: DateTime.utc(2026, 3, 17, 12),
    );
    expect(s.error, isNull);
    expect(
      req.single.url.toString(),
      'https://app.flora.ai/api/v1/workspaces/ws_fixture123/usage?start_date=2026-03-01&end_date=2026-03-17',
    );
    expect(_credit(s, 'flora-available').balance, 128.4);
    expect(_credit(s, 'flora-month').used, 12.5);
  });

  test('future agi dimensions', () async {
    final (s, req) = await _run('futureagi', {
      'usage-overview': _fixture('futureagi_usage_overview.json'),
    }, secret: SecretBundle.encode({'secret': 'k', 'secretKey': 's'}));
    expect(s.error, isNull);
    expect(s.windows.map((w) => w.usedPercent), [25, 100]);
    expect(s.windows.first.windowMinutes, 44640);
    expect(req.single.headers['X-Secret-Key'], 's');
  });

  test('gitkraken personal and org pools', () async {
    final (s, req) = await _run(
      'gitkraken',
      {'/ai-tasks/usage': _fixture('gitkraken_ai_tasks_usage.json')},
      options: {'orgId': 'org-fixture'},
    );
    expect(s.error, isNull);
    expect(s.windows.map((w) => w.usedPercent), [3.125, 20]);
    expect(req.single.headers['gk-org-id'], 'org-fixture');
  });

  test('sail research cents to USD', () async {
    final (s, _) = await _run('sailresearch', {
      '/usage/summary': _fixture('sailresearch_usage_summary.json'),
    });
    expect(s.error, isNull);
    expect(_credit(s, 'sail-balance').balance, closeTo(123.46, 0.01));
    expect(_credit(s, 'sail-spend').used, 12.34);
  });

  test('munito day/month limits', () async {
    final (s, _) = await _run('munito', {
      '/limits': _fixture('munito_limits.json'),
      '/organization': _fixture('munito_organization.json'),
    });
    expect(s.error, isNull);
    expect(s.windows.map((w) => w.usedPercent), [8.5, closeTo(12.34, 0.001)]);
    expect(_credit(s, 'munito-spend').limit, 1000);
  });

  test('sofya credits', () async {
    final (s, _) = await _run('sofya', {'/auth/me': _fixture('sofya_auth_me.json')});
    expect(s.error, isNull);
    expect(s.credits.map((c) => c.balance), [1034, 997, 37]);
    expect(s.plan, 'Free tier');
  });

  test('chatbox plan / top-up pools', () async {
    final (s, req) = await _run('chatbox', {
      '/realtime': _fixture('chatbox_realtime_license.json'),
    });
    expect(s.error, isNull);
    expect(req.single.headers['Authorization'], 'test-key');
    expect(s.windows[0].usedPercent, 20);
    expect(s.windows[0].resetsAt, DateTime.utc(2026, 11));
    expect(s.windows[1].usedPercent, 12.5);
  });

  test('ibm bob bobcoins and region guard', () async {
    final (s, req) = await _run('ibmbob', {
      '/profile': _fixture('ibmbob_profile.json'),
      '/teams/': _fixture('ibmbob_team_budget.json'),
    });
    expect(s.error, isNull);
    expect(s.windows.single.usedPercent, closeTo(12.5 / 80 * 100, 0.001));
    expect(req.first.headers['Authorization'], 'Apikey test-key');
    expect(ibmBobAuthorization('header.eyJzdWIiOiJ1c2VyIn0.signature'), startsWith('Bearer '));
    for (final bad in [
      'evil.example',
      'bob.ibm.com.evil.example',
      'x@evil.example',
      'us-east.bob.ibm.com:443',
    ]) {
      expect(() => ibmBobRegionalBase(bad), throwsA(isA<ProviderException>()));
    }
    expect(ibmBobRegionalBase('eu-de.bob.ibm.com'), 'https://api.eu-de.bob.ibm.com');
  });

  test('kimi count windows', () async {
    final (s, req) = await _run('kimi', {
      '/coding/v1/usages': _fixture('kimi_code_api_usages.json'),
    });
    expect(s.error, isNull);
    expect(req.single.url.host, 'api.kimi.com');
    expect(s.windows[0].usedPercent, closeTo(214 / 2048 * 100, 0.001));
    expect(s.windows[1].usedPercent, closeTo(69.5, 0.001));
    expect(s.windows[1].windowMinutes, 300);
  });

  test('kimi ratio pools win over counters', () async {
    final (s, _) = await _run('kimi', {
      '/coding/v1/usages': _fixture('kimi_code_api_ratio_pools.json'),
    });
    expect(s.error, isNull);
    final session = s.windows.firstWhere((w) => w.id == RateWindow.sessionId);
    expect(session.usedPercent, 0);
    expect(session.resetsAt, DateTime.utc(2026, 9, 16, 20, 15, 44));
    final monthly = s.windows.firstWhere((w) => w.id == 'kimi-monthly');
    expect(monthly.usedPercent, closeTo(0.56, 0.001));
  });

  test('minimax token plan remains', () async {
    final (s, req) = await _run('minimax', {
      '/token_plan/remains': _fixture('minimax_token_plan_remains.json'),
    }, now: DateTime.fromMillisecondsSinceEpoch(1782050596000, isUtc: true));
    expect(s.error, isNull);
    expect(req.single.url.host, 'api.minimaxi.com');
    expect(s.windows.map((w) => w.usedPercent), [0, 30]);
    expect(s.windows[0].resetsAt, DateTime.fromMillisecondsSinceEpoch(1782057600000, isUtc: true));
  });

  test('v0 billing and rate limits', () async {
    final (s, req) = await _run(
      'v0',
      {
        '/user/billing': _fixture('v0_token_billing.json'),
        '/rate-limits': _fixture('v0_rate_limits.json'),
      },
      options: {'scope': 'project-demo'},
    );
    expect(s.error, isNull);
    expect(s.windows.map((w) => w.usedPercent), [25, 20]);
    expect(s.windows[0].resetsAt, DateTime.fromMillisecondsSinceEpoch(1800003600000, isUtc: true));
    expect(req.first.url.queryParameters['scope'], 'project-demo');
  });

  test('devpass plan credits', () async {
    final (s, _) = await _run('devpass', {'/v1/key': _fixture('devpass_key_usage.json')});
    expect(s.error, isNull);
    expect(s.plan, 'DevPass Pro');
    expect(s.windows[0].usedPercent, closeTo(25 / 237 * 100, 0.001));
    expect(s.windows[1].windowMinutes, 10080);
    expect(_credit(s, 'devpass-key').used, 31.42);
  });

  test('xkiro daily free tokens', () async {
    final (s, _) = await _run('xkiro', {'/v1/usage': _fixture('xkiro_usage.json')});
    expect(s.error, isNull);
    expect(s.windows.single.usedPercent, closeTo(124035 / 5000000 * 100, 0.0001));
    expect(s.windows.single.resetsAt, DateTime.utc(2026, 10, 21));
    expect(s.plan, 'Pay as you go');
  });

  test('ai& paginated exact cost sum', () async {
    final (s, req) = await _run('aiand', {
      'after_id': _fixture('aiand_logs_final_page.json'),
      '/logs': _fixture('aiand_logs_first_page.json'),
    });
    expect(s.error, isNull);
    expect(req, hasLength(2));
    final c = _credit(s, 'aiand-30d');
    expect(c.currency, 'JPY');
    expect(c.used, closeTo(20.62344, 1e-9));
    expect(sumDecimalStrings(['0.1', '0.2']), 0.3);
  });

  test('groq prometheus rates', () async {
    final (s, req) = await _run('groq', {'/api/v1/query': _fixture('groq_prometheus_scalar.json')});
    expect(s.error, isNull);
    expect(req, hasLength(4));
    expect(s.extras['请求速率'], '240 次/分钟');
    expect(s.extras['Token 速率'], '480 tok/分钟');
  });

  test('401 surfaces the auth hint', () async {
    final (s, _) = await _run('tavily', {'/usage': 401});
    expect(s.error, contains('401'));
  });
}
