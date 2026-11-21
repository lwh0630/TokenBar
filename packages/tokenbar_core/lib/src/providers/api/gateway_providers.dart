import '../../models/account.dart';
import '../../models/credits.dart';
import '../../models/rate_window.dart';
import '../../models/usage_snapshot.dart';
import '../../util/json_utils.dart';
import '../common.dart';
import '../fields.dart';
import '../http_support.dart';
import '../provider.dart';

/// Self-hosted / hosted API gateways that expose a per-key usage endpoint.
abstract class _GatewayProvider extends UsageProvider {
  String get keyEnv;
  String get urlEnv;
  String? get defaultUrl => null;
  String get keyLabel => 'API Key';

  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];

  @override
  List<ProviderField> get fields => [
    ProviderField.apiKey(label: keyLabel, envVars: [keyEnv]),
    ProviderField(
      key: 'baseUrl',
      label: '服务地址',
      kind: FieldKind.url,
      required: defaultUrl == null,
      defaultValue: defaultUrl,
      hint: defaultUrl ?? 'https://gateway.example.com',
      help: '公网需 https；局域网 / 本机可用 http',
      envVars: [urlEnv],
    ),
  ];

  @override
  String? validateManual(FieldValues values) {
    final url = values['baseUrl'];
    if (url == null) return null;
    try {
      gatewayBaseUrl(displayName, url);
      return null;
    } on ProviderException catch (e) {
      return e.message;
    }
  }

  ({String key, String base}) creds(AccountConfig account) {
    final v = FieldValues.of(this, account);
    return (key: bareToken(v.secret), base: gatewayBaseUrl(displayName, v.require('baseUrl')));
  }

  String withoutV1(String base) => base.replaceFirst(RegExp(r'/v1$'), '');
}

// ------------------------------------------------------------------ LiteLLM

({RateWindow? window, Credits? credits}) liteLlmBudget(
  String id,
  String label,
  Object? spendRaw,
  Object? maxRaw,
  Object? resetRaw, {
  required bool team,
}) {
  final spend = asDouble(spendRaw) ?? 0;
  final limit = asDouble(maxRaw) ?? 0;
  final reset = parseFlexibleDate(resetRaw);
  final window = limit > 0
      ? quotaWindow(id, label, usedPercent: pct(spend, limit), resetsAt: reset)
      : null;
  final credits = spend > 0 || limit > 0
      ? spendRow(
          id,
          spend,
          limit: limit,
          label: '${team ? '团队' : '个人'}${limit > 0 ? '预算' : '花费'}',
          resetsAt: reset,
        )
      : null;
  return (window: window, credits: credits);
}

class LiteLlmProvider extends _GatewayProvider {
  @override
  String get id => 'litellm';
  @override
  String get displayName => 'LiteLLM';
  @override
  int get brandColor => 0xFF4C89F0;
  @override
  String get keyEnv => 'LITELLM_API_KEY';
  @override
  String get urlEnv => 'LITELLM_BASE_URL';
  @override
  String get keyLabel => '虚拟 Key';
  @override
  String get setupHint => '自建 LiteLLM Proxy 的虚拟 Key（不需要 master key），查询个人 / 团队预算与花费。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final c = creds(account);
    final base = withoutV1(c.base);
    final headers = {'Authorization': 'Bearer ${c.key}'};
    Future<Map<String, Object?>> get(String path) =>
        fetchJsonObject(ctx, displayName, Uri.parse('$base$path'), headers: headers);

    final keyInfo = await sendRequest(
      ctx,
      displayName,
      Uri.parse('$base/key/info'),
      headers: headers,
    );
    if (const {401, 403, 404}.contains(keyInfo.statusCode)) {
      return _spendReport(account, ctx, base, headers);
    }
    checkStatus(displayName, keyInfo);
    final info = asMap(asMap(keyInfo.json)?['info']) ?? const {};
    final userId = asString(info['user_id']);
    final teamId = asString(info['team_id']);
    if (userId == null && teamId == null) {
      throw ProviderException('LiteLLM 的 key/info 里没有 user_id 或 team_id');
    }

    final windows = <RateWindow>[];
    final credits = <Credits>[];
    String? email;
    String? org;
    void add(({RateWindow? window, Credits? credits}) b) {
      if (b.window != null) windows.add(b.window!);
      if (b.credits != null) credits.add(b.credits!);
    }

    if (userId != null) {
      final json = await get('/user/info?user_id=${Uri.encodeQueryComponent(userId)}');
      final u = asMap(json['user_info']) ?? const {};
      email = asString(u['user_email']) ?? asString(u['user_alias']);
      var personal = liteLlmBudget(
        'litellm-personal',
        '个人预算',
        u['spend'],
        u['max_budget'],
        u['budget_reset_at'],
        team: false,
      );
      final rawTeams = (asList(json['teams']) ?? const [])
          .map(asMap)
          .whereType<Map<String, Object?>>()
          .toList();
      final mine = teamId == null
          ? null
          : rawTeams.where((t) => asString(t['team_id']) == teamId).firstOrNull;
      // No personal limit: fall back to this user's budget inside the key's team (a member
      // override, else the team's default member budget). Both are optional extras.
      if (teamId != null && personal.window == null) {
        final member = await _teamMemberBudget(ctx, base, headers, userId, teamId, mine);
        if (member != null) personal = member;
      }
      add(personal);
      if (mine != null) {
        org = asString(mine['team_alias']);
        add(
          liteLlmBudget(
            'litellm-team',
            '团队预算',
            mine['spend'],
            mine['max_budget'],
            mine['budget_reset_at'],
            team: true,
          ),
        );
      }
    } else {
      final t =
          asMap(
            (await get('/team/info?team_id=${Uri.encodeQueryComponent(teamId!)}'))['team_info'],
          ) ??
          const {};
      org = asString(t['team_alias']);
      add(
        liteLlmBudget(
          'litellm-team',
          '团队预算',
          t['spend'],
          t['max_budget'],
          t['budget_reset_at'],
          team: true,
        ),
      );
    }
    return snapshot(
      account,
      ctx,
      email: email,
      plan: org,
      source: 'api-key',
      windows: windows,
      credits: credits,
    );
  }

  /// The user's own budget inside the key's team (CodexBar litellm.ts). The membership must
  /// belong to [userId] and to [teamId] (or carry no team); team-wide spend is never compared
  /// with a member limit, and any failure just leaves the personal budget as it was.
  Future<({RateWindow? window, Credits? credits})?> _teamMemberBudget(
    FetchContext ctx,
    String base,
    Map<String, String> headers,
    String userId,
    String teamId,
    Map<String, Object?>? team,
  ) async {
    Map<String, Object?>? member(Object? rows) {
      for (final row in (asList(rows) ?? const []).map(asMap)) {
        if (row == null || asString(row['user_id']) != userId) continue;
        final rowTeam = row['team_id'];
        if (rowTeam == null || asString(rowTeam) == teamId) return row;
      }
      return null;
    }

    try {
      final mine = member(team?['team_memberships']);
      var table = asMap(mine?['litellm_budget_table']) ?? const <String, Object?>{};
      var spend = asDouble(mine?['spend']);
      if (asDouble(table['max_budget']) == null || spend == null) {
        final r = await sendRequest(
          ctx,
          displayName,
          Uri.parse('$base/team/info?team_id=${Uri.encodeQueryComponent(teamId)}'),
          headers: headers,
          timeout: const Duration(seconds: 8),
        );
        if (r.ok) {
          final root = asMap(r.json) ?? const <String, Object?>{};
          final info = asMap(root['team_info']) ?? const <String, Object?>{};
          final responseId = asString(info['team_id']) ?? asString(root['team_id']);
          if (responseId != null && responseId != teamId) return null;
          final fallback = member(info['team_memberships'] ?? root['team_memberships']);
          if (table['max_budget'] == null) {
            table = asMap(fallback?['litellm_budget_table']) ?? const <String, Object?>{};
            if (table['max_budget'] == null) {
              table = asMap(info['team_member_budget_table']) ?? const <String, Object?>{};
            }
          }
          spend ??= asDouble(fallback?['spend']);
        }
      }
      final limit = asDouble(table['max_budget']);
      if (limit == null || limit <= 0 || spend == null) return null;
      return liteLlmBudget(
        'litellm-personal',
        '个人预算',
        spend,
        limit,
        table['budget_reset_at'],
        team: false,
      );
    } on ProviderException {
      return null;
    }
  }

  Future<UsageSnapshot> _spendReport(
    AccountConfig account,
    FetchContext ctx,
    String base,
    Map<String, String> headers,
  ) async {
    final now = ctx.now().toUtc();
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final query = '?start_date=${day(startOfUtcMonth(now))}&end_date=${day(now)}';
    var r = await sendRequest(
      ctx,
      displayName,
      Uri.parse('$base/key/spend/report$query'),
      headers: headers,
    );
    if (const {401, 403, 404}.contains(r.statusCode)) {
      r = await sendChecked(
        ctx,
        displayName,
        Uri.parse('$base/user/spend/report$query'),
        headers: headers,
      );
    }
    checkStatus(displayName, r);
    final rows = asList(r.json);
    if (rows == null || rows.isEmpty) throw ProviderException('LiteLLM 花费报表为空');
    final total = rows
        .map(asMap)
        .fold<double>(0, (s, row) => s + (asDouble(row?['total_cost']) ?? 0));
    return snapshot(
      account,
      ctx,
      source: 'api-key',
      credits: [spendRow('litellm-spend', total, label: '本月花费')],
    );
  }
}

// ------------------------------------------------------------------ sub2api

UsageSnapshot parseSub2Api(UsageSnapshot base, Map<String, Object?> json) {
  if (json['isValid'] == false) {
    throw ProviderException('sub2api 拒绝了 API Key', hint: '检查 Key 是否启用并已分配到分组', statusCode: 401);
  }
  final quota = asMap(json['quota']);
  final unit = asString(json['unit']) ?? asString(quota?['unit']) ?? 'USD';
  final windows = <RateWindow>[];
  void win(String id, String label, Object? used, Object? limit, int? minutes) {
    final l = asDouble(limit) ?? 0;
    if (l > 0) {
      windows.add(
        quotaWindow(id, label, usedPercent: pct(asDouble(used) ?? 0, l), windowMinutes: minutes),
      );
    }
  }

  final sub = asMap(json['subscription']);
  if (sub != null) {
    win('sub2api-daily', '每日额度', sub['daily_usage_usd'], sub['daily_limit_usd'], 1440);
    win('sub2api-weekly', '每周额度', sub['weekly_usage_usd'], sub['weekly_limit_usd'], 10080);
    win('sub2api-monthly', '每月额度', sub['monthly_usage_usd'], sub['monthly_limit_usd'], 43200);
  } else if (quota != null) {
    win('sub2api-quota', '额度', quota['used'], quota['limit'], null);
  }
  for (final r
      in (asList(json['rate_limits']) ?? const []).map(asMap).whereType<Map<String, Object?>>()) {
    final w = asString(r['window']);
    final limit = asDouble(r['limit']) ?? 0;
    if (w == null || limit <= 0) continue;
    final (label, minutes) = switch (w) {
      '5h' => ('5 小时限额', 300),
      '1d' => ('每日限额', 1440),
      '7d' => ('7 天限额', 10080),
      _ => ('$w 限额', null),
    };
    windows.add(
      quotaWindow(
        'sub2api-rl-$w',
        label,
        usedPercent: pct(asDouble(r['used']) ?? 0, limit),
        resetsAt: parseFlexibleDate(r['reset_at']),
        windowMinutes: minutes,
      ),
    );
  }
  final balance = asDouble(json['balance']);
  final plan = asString(json['planName']);
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    plan: plan,
    source: 'api-key',
    windows: windows,
    credits: [if (balance != null) balanceRow('sub2api-balance', balance, currency: unit)],
  );
}

class Sub2ApiProvider extends _GatewayProvider {
  @override
  String get id => 'sub2api';
  @override
  String get displayName => 'sub2api';
  @override
  int get brandColor => 0xFF14B8A6;
  @override
  String get keyEnv => 'SUB2API_API_KEY';
  @override
  String get urlEnv => 'SUB2API_BASE_URL';
  @override
  String get keyLabel => '分组 API Key';
  @override
  String get setupHint => '自建 sub2api 实例的分组 API Key，查询日 / 周 / 月额度和限流窗口。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final c = creds(account);
    var url = c.base;
    if (!url.endsWith('/v1') && !url.endsWith('/v1/usage')) url = '$url/v1';
    if (!url.endsWith('/usage')) url = '$url/usage';
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('$url?days=30&timezone=UTC'),
      headers: {'Authorization': 'Bearer ${c.key}'},
      authHint: '检查 Key 是否启用并已分配到分组',
    );
    return parseSub2Api(snapshot(account, ctx), json);
  }
}

// ------------------------------------------------------------------ Bifrost

/// Root-scope budgets of a Bifrost virtual key -> windows + first budget's spend.
UsageSnapshot parseBifrost(UsageSnapshot base, Map<String, Object?> json) {
  final budgets = (asList(json['budgets']) ?? const [])
      .map(asMap)
      .whereType<Map<String, Object?>>()
      .where((b) => asString(b['id']) != null)
      .toList();
  if (json['is_active'] == false && budgets.isEmpty) {
    throw ProviderException('Bifrost 虚拟 Key 已停用', statusCode: 403);
  }
  double limitOf(Map<String, Object?> b) {
    var limit = asDouble(b['max_limit']) ?? 0;
    final amount = asDouble(b['override_amount']) ?? 0;
    final mode = asString(b['override_mode']);
    final cycles = asInt(b['override_cycles_remaining']) ?? 0;
    if (amount > 0 && (mode == 'forever' || (mode == 'cycles' && cycles > 0))) limit += amount;
    return limit;
  }

  String durationLabel(String? d) => switch (d) {
    '1h' => '每小时',
    '1d' => '每日',
    '1w' => '每周',
    '1M' => '每月',
    '1Q' => '每季度',
    '1Y' => '每年',
    null => '预算',
    final other => other,
  };
  int order(String? d) {
    final m = RegExp(r'^(\d+)(d|w|M|Q|Y|h|m)$').firstMatch(d ?? '');
    if (m == null) return 1 << 40;
    final unit = {
      'm': 60,
      'h': 3600,
      'd': 86400,
      'w': 604800,
      'M': 2592000,
      'Q': 7776000,
      'Y': 31536000,
    }[m[2]]!;
    return int.parse(m[1]!) * unit;
  }

  budgets.sort((a, b) {
    final c = order(asString(a['reset_duration'])).compareTo(order(asString(b['reset_duration'])));
    return c != 0 ? c : asString(a['id'])!.compareTo(asString(b['id'])!);
  });
  final windows = <RateWindow>[];
  for (final b in budgets) {
    final limit = limitOf(b);
    if (limit <= 0) continue;
    final source = asString(b['source_name']);
    windows.add(
      quotaWindow(
        'bifrost-budget-${b['id']}',
        [?source, durationLabel(asString(b['reset_duration']))].join(' · '),
        usedPercent: pct(asDouble(b['current_usage']) ?? 0, limit),
      ),
    );
  }
  final first = budgets.firstOrNull;
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    email: asString(json['virtual_key_name']),
    plan: first == null ? null : asString(first['source_name']),
    source: 'api-key',
    windows: windows,
    credits: [
      if (first != null)
        spendRow(
          'bifrost-budget',
          asDouble(first['current_usage']) ?? 0,
          limit: limitOf(first),
          label: durationLabel(asString(first['reset_duration'])),
        ),
    ],
    extras: {if (json['is_active'] == false) '状态': 'Key 已停用'},
  );
}

class BifrostProvider extends _GatewayProvider {
  @override
  String get id => 'bifrost';
  @override
  String get displayName => 'Bifrost';
  @override
  int get brandColor => 0xFF33C09E;
  @override
  String get keyEnv => 'BIFROST_API_KEY';
  @override
  String get urlEnv => 'BIFROST_BASE_URL';
  @override
  String get keyLabel => '虚拟 Key';
  @override
  String get setupHint => '自建 Bifrost 网关的虚拟 Key，查询预算用量。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final c = creds(account);
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('${c.base}/api/governance/virtual-keys/quota'),
      headers: {'x-bf-vk': c.key},
      timeout: const Duration(seconds: 15),
    );
    return parseBifrost(snapshot(account, ctx), json);
  }
}

// ---------------------------------------------------------------- LLM Proxy

UsageSnapshot parseLlmProxy(UsageSnapshot base, Map<String, Object?> json, DateTime now) {
  final providers = asMap(json['providers']);
  if (providers == null) throw ProviderException('LLM Proxy 返回数据缺少 providers');
  double? minRemaining;
  DateTime? reset;
  var active = 0;
  var total = 0;
  var cost = 0.0;
  for (final p in providers.values.map(asMap).whereType<Map<String, Object?>>()) {
    active += asInt(p['active_count']) ?? 0;
    total += asInt(p['credential_count']) ?? 0;
    cost += asDouble(p['approx_cost']) ?? 0;
    final groups = p['quota_groups'];
    final list = groups is List ? groups : (groups is Map ? groups.values.toList() : const []);
    for (final g in list.map(asMap).whereType<Map<String, Object?>>()) {
      final remaining = asDouble(g['remaining_percent']);
      if (remaining != null && (minRemaining == null || remaining < minRemaining)) {
        minRemaining = remaining;
      }
      final at = parseFlexibleDate(g['reset_time']);
      if (at != null && at.isAfter(now) && (reset == null || at.isBefore(reset))) reset = at;
    }
  }
  final summaryCost = asDouble(asMap(json['summary'])?['approx_cost']);
  final spend = summaryCost ?? (cost > 0 ? cost : null);
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    plan: '$active/$total 个 Key 可用',
    source: 'api-key',
    windows: [
      if (minRemaining != null)
        quotaWindow(
          'llmproxy-quota',
          '额度',
          usedPercent: (100 - minRemaining).clamp(0, 100).toDouble(),
          resetsAt: reset,
        ),
    ],
    credits: [if (spend != null) spendRow('llmproxy-spend', spend, label: '估算花费', resetsAt: reset)],
  );
}

class LlmProxyProvider extends _GatewayProvider {
  @override
  String get id => 'llmproxy';
  @override
  String get displayName => 'LLM Proxy';
  @override
  int get brandColor => 0xFF24B47E;
  @override
  String get keyEnv => 'LLM_PROXY_API_KEY';
  @override
  String get urlEnv => 'LLM_PROXY_BASE_URL';
  @override
  String get setupHint => '自建 LLM-API-Key-Proxy 的 Key，查询 quota-stats（剩余额度最少的分组）。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final c = creds(account);
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('${withoutV1(c.base)}/v1/quota-stats'),
      headers: {'Authorization': 'Bearer ${c.key}'},
    );
    return parseLlmProxy(snapshot(account, ctx), json, ctx.now());
  }
}

// --------------------------------------------------------------- ClawRouter

UsageSnapshot parseClawRouter(UsageSnapshot base, Map<String, Object?> json) {
  final budget = asMap(json['budget']);
  final usage = asMap(json['usage']);
  final summary = asMap(usage?['summary']);
  if (budget == null || summary == null || asList(usage?['providers']) == null) {
    throw ProviderException('ClawRouter 返回数据格式无法识别');
  }
  double? micros(Object? v) => v == null ? null : (asDouble(v) ?? 0) / 1e6;
  final limit = micros(budget['limitMicros']);
  final spent = micros(budget['spentMicros']);
  final actual = micros(summary['actualCostMicros']) ?? 0;
  DateTime? reset;
  final key = RegExp(r'(\d{4})-(\d{2})$').firstMatch(asString(budget['windowKey']) ?? '');
  if (key != null) reset = DateTime.utc(int.parse(key[1]!), int.parse(key[2]!) + 1);
  final providers = asList(usage!['providers'])!.length;
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    plan: budget['configured'] == true ? '月度预算' : '不限额',
    source: 'api-key',
    windows: [
      if (limit != null && spent != null && limit > 0)
        quotaWindow('clawrouter-budget', '月度预算', usedPercent: pct(spent, limit), resetsAt: reset),
    ],
    credits: [
      if (limit != null && spent != null)
        spendRow('clawrouter-budget', spent, limit: limit, label: '本月', resetsAt: reset)
      else if (actual > 0)
        spendRow('clawrouter-spend', actual, label: '本月'),
    ],
    extras: {'路由服务商': '$providers'},
  );
}

class ClawRouterProvider extends _GatewayProvider {
  @override
  String get id => 'clawrouter';
  @override
  String get displayName => 'ClawRouter';
  @override
  int get brandColor => 0xFF596EF6;
  @override
  String get keyEnv => 'CLAWROUTER_API_KEY';
  @override
  String get urlEnv => 'CLAWROUTER_BASE_URL';
  @override
  String? get defaultUrl => 'https://clawrouter.openclaw.ai';
  @override
  String get setupHint => 'ClawRouter 策略 Key（clawrouter.openclaw.ai/dashboard/access），查询月度预算。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final c = creds(account);
    if (!c.base.startsWith('https://')) throw ProviderException('ClawRouter 地址必须是 https://');
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('${withoutV1(c.base)}/v1/usage'),
      headers: {'Authorization': 'Bearer ${c.key}'},
    );
    return parseClawRouter(snapshot(account, ctx), json);
  }
}

// --------------------------------------------------------------------- Aixy

UsageSnapshot parseAixy(UsageSnapshot base, Map<String, Object?> json) {
  if (json['object'] != 'key.usage' || json['currency'] != 'USD') {
    throw ProviderException('Aixy 返回了不支持的数据格式');
  }
  final key = asMap(json['key']) ?? const {};
  final keyId = asString(key['id']);
  final windows = <({bool hard, bool known, RateWindow w})>[];
  const scopes = {
    'organization': '组织',
    'project': '项目',
    'team': '团队',
    'user': '用户',
    'api_key': 'Key',
  };
  const intervals = {'daily': '每日', 'weekly': '每周', 'monthly': '每月', 'lifetime': '总计'};
  for (final b
      in (asList(json['budgets']) ?? const []).map(asMap).whereType<Map<String, Object?>>()) {
    final limit = asDouble(b['limit_usd']) ?? 0;
    final appliesToKey = (asList(b['applies_to']) ?? const [])
        .map(asMap)
        .every((a) => a != null && asString(a['api_key_id']) == keyId);
    if (limit <= 0 || !appliesToKey) continue;
    final hard = b['enforcement'] == 'hard';
    final availability = asMap(b['availability']) ?? const {};
    final known = hard ? availability['status'] == 'available' : b['spend_status'] == 'available';
    final used = hard
        ? (asDouble(availability['spent_usd']) ?? 0) + (asDouble(availability['reserved_usd']) ?? 0)
        : asDouble(b['spend_usd']) ?? 0;
    final starts = parseFlexibleDate(b['starts_at']);
    final resets = parseFlexibleDate(b['resets_at']);
    final minutes = starts != null && resets != null ? resets.difference(starts).inMinutes : null;
    final label =
        '${scopes[b['scope']] ?? b['scope']} · ${intervals[b['interval']] ?? b['interval']}${hard ? '' : '（监控）'}';
    windows.add((
      hard: hard,
      known: known,
      w: quotaWindow(
        'aixy-${b['id']}',
        label,
        usedPercent: known ? pct(used, limit) : 0,
        resetsAt: resets,
        windowMinutes: (minutes ?? 0) > 0 ? minutes : null,
      ),
    ));
  }
  windows.sort((a, b) {
    if (a.hard != b.hard) return a.hard ? -1 : 1;
    if (a.known != b.known) return a.known ? -1 : 1;
    return b.w.usedPercent.compareTo(a.w.usedPercent);
  });
  final spend = asDouble(asMap(json['usage'])?['spend_usd']);
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    plan: asString(key['name']) ?? keyId,
    source: 'api-key',
    windows: [for (final w in windows.where((w) => w.known)) w.w],
    credits: [if (spend != null) spendRow('aixy-spend', spend, label: '近 7 天花费')],
  );
}

class AixyProvider extends _GatewayProvider {
  @override
  String get id => 'aixy';
  @override
  String get displayName => 'Aixy';
  @override
  int get brandColor => 0xFF123650;
  @override
  String get keyEnv => 'AIXY_API_KEY';
  @override
  String get urlEnv => 'AIXY_BASE_URL';
  @override
  String? get defaultUrl => 'https://api.aixy-gateway.com';
  @override
  String get setupHint => 'Aixy 网关的项目 Key（gak_...），查询适用于该 Key 的预算。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final c = creds(account);
    final result = await sendRequest(
      ctx,
      displayName,
      Uri.parse('${withoutV1(c.base)}/v1/usage'),
      headers: {'Authorization': 'Bearer ${c.key}'},
    );
    if (result.statusCode == 404) {
      throw ProviderException('这个 Aixy 部署没有用量接口', hint: '升级网关或检查服务地址');
    }
    final json = asMap(checkStatus(displayName, result).json);
    if (json == null) throw ProviderException('Aixy 返回了无法解析的数据');
    return parseAixy(snapshot(account, ctx), json);
  }
}
