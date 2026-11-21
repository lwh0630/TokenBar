import 'dart:convert';

import '../../models/account.dart';
import '../../models/credits.dart';
import '../../models/rate_window.dart';
import '../../models/usage_snapshot.dart';
import '../../util/json_utils.dart';
import '../common.dart';
import '../fields.dart';
import '../flex_quota.dart';
import '../http_support.dart';
import '../provider.dart';

// --------------------------------------------------------------------- z.ai

class _ZaiLimit {
  _ZaiLimit(this.type, this.unit, this.number, this.percent, this.windowMinutes, this.reset);

  final String type;
  final int unit;
  final int number;
  final double percent;
  final int? windowMinutes;
  final DateTime? reset;
}

UsageSnapshot parseZaiQuota(UsageSnapshot base, Map<String, Object?> root, DateTime now) {
  final data = asMap(root['data']);
  if (root['success'] != true || root['code'] != 200) {
    throw ProviderException('z.ai 额度接口错误: ${asString(root['msg']) ?? '无效响应'}');
  }
  final rawLimits = asList(data?['limits']);
  if (rawLimits == null) throw ProviderException('不支持的 z.ai 额度格式', hint: '到 z.ai 用量面板查看');
  const multipliers = {1: 1440, 3: 60, 5: 1, 6: 10080};
  final limits = <_ZaiLimit>[];
  for (final raw in rawLimits.map(asMap).whereType<Map<String, Object?>>()) {
    final type = raw['type'];
    if (type is! String || !const {'TOKENS_LIMIT', 'TIME_LIMIT', 'CREDIT_LIMIT'}.contains(type)) {
      continue;
    }
    final unit = raw['unit'];
    final number = raw['number'];
    final percentage = raw['percentage'];
    if (unit is! int || number is! int || percentage is! int) continue;
    final usage = asInt(raw['usage']);
    final current = asInt(raw['currentValue']);
    final remaining = asInt(raw['remaining']);
    var percent = percentage.toDouble();
    if (usage != null && usage > 0) {
      int? used;
      if (remaining != null) {
        used = current == null
            ? usage - remaining
            : (usage - remaining > current ? usage - remaining : current);
      } else if (current != null) {
        used = current;
      }
      if (used != null) percent = pct(used.clamp(0, usage), usage);
    }
    var minutes = number > 0 && multipliers[unit] != null ? number * multipliers[unit]! : null;
    if (type == 'TIME_LIMIT' && unit == 5 && number == 1) minutes = 43200;
    var reset = asInt(raw['nextResetTime']) == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(asInt(raw['nextResetTime'])!, isUtc: true);
    if (type != 'TIME_LIMIT' &&
        minutes == 300 &&
        reset != null &&
        reset.isAfter(now.add(const Duration(hours: 5, minutes: 1)))) {
      reset = null;
    }
    limits.add(_ZaiLimit(type, unit, number, percent.clamp(0, 100).toDouble(), minutes, reset));
  }
  final tokens = limits.where((l) => l.type != 'TIME_LIMIT').toList()
    ..sort((a, b) => (a.windowMinutes ?? 1 << 40).compareTo(b.windowMinutes ?? 1 << 40));
  final time = limits.where((l) => l.type == 'TIME_LIMIT').lastOrNull;
  String label(_ZaiLimit l) {
    if (l.type == 'TIME_LIMIT') return 'MCP';
    if (l.windowMinutes == 300) return '5 小时';
    return switch (l.unit) {
      1 => '${l.number} 天',
      3 => '${l.number} 小时',
      5 => '${l.number} 分钟',
      6 => l.number == 1 ? '每周' : '${l.number} 周',
      _ => '额度',
    };
  }

  RateWindow win(String id, _ZaiLimit l) => quotaWindow(
    id,
    label(l),
    usedPercent: l.percent,
    resetsAt: l.reset,
    windowMinutes: l.windowMinutes,
  );
  final primary = tokens.firstOrNull ?? time;
  final plan = [
    data!['planName'],
    data['plan'],
    data['plan_type'],
    data['packageName'],
    data['level'],
  ].map(asString).whereType<String>().firstOrNull;
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    plan: plan,
    source: 'api-key',
    windows: [
      if (primary != null)
        win(primary.windowMinutes == 300 ? RateWindow.sessionId : 'zai-primary', primary),
      if (tokens.length >= 2) win('zai-secondary', tokens.last),
      if (tokens.isNotEmpty && time != null) win('zai-mcp', time),
    ],
  );
}

class ZaiProvider extends UsageProvider {
  @override
  String get id => 'zai';
  @override
  String get displayName => 'z.ai / 智谱 GLM';
  @override
  int get brandColor => 0xFFE85A6A;
  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];
  @override
  String get setupHint =>
      'GLM Coding Plan 的 API Key（z.ai 国际站或 open.bigmodel.cn 国内站），查询 5 小时 / 周额度和 MCP 额度。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(
      envVars: [
        'Z_AI_API_KEY',
        'BIGMODEL_API_KEY',
        'ZHIPU_API_KEY',
        'ZHIPUAI_API_KEY',
        'GLM_API_KEY',
      ],
    ),
    ProviderField(
      key: 'region',
      label: '区域',
      kind: FieldKind.choice,
      defaultValue: 'bigmodel-cn',
      choices: [
        FieldChoice('bigmodel-cn', '国内站 open.bigmodel.cn'),
        FieldChoice('global', '国际站 api.z.ai'),
      ],
      envVars: ['Z_AI_REGION'],
    ),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final v = FieldValues.of(this, account);
    final china = v['region'] != 'global';
    final base = china ? 'https://open.bigmodel.cn' : 'https://api.z.ai';
    final key = bareToken(v.secret);
    final result = await sendRequest(
      ctx,
      displayName,
      Uri.parse('$base/api/monitor/usage/quota/limit'),
      headers: {'Authorization': 'Bearer $key'},
    );
    final root = asMap(result.json);
    // A BigModel CN prepaid-only account has no Coding Plan but can still report a balance.
    final noCodingPlan = china && isZaiNoCodingPlan(root);
    if (!noCodingPlan) {
      checkStatus(displayName, result, authHint: '检查 API Key 与所选区域是否一致');
    }
    if (root == null) throw ProviderException('$displayName 返回了无法解析的数据');
    var snap = noCodingPlan
        ? snapshot(account, ctx, source: 'api-key')
        : parseZaiQuota(snapshot(account, ctx), root, ctx.now());
    if (china) {
      final balance = await _fetchBalance(ctx, key);
      if (balance != null) {
        snap = UsageSnapshot(
          accountId: snap.accountId,
          providerId: snap.providerId,
          fetchedAt: snap.fetchedAt,
          plan: snap.plan,
          source: snap.source,
          windows: snap.windows,
          credits: [...snap.credits, balance.credits],
          extras: {...snap.extras, ...balance.extras},
        );
      }
    }
    if (noCodingPlan && snap.credits.isEmpty) {
      throw ProviderException('z.ai 额度接口错误: ${asString(root['msg'])}');
    }
    return snap;
  }

  /// Best-effort and CN-only: a failed balance lookup must never break the quota.
  Future<({Credits credits, Map<String, String> extras})?> _fetchBalance(
    FetchContext ctx,
    String key,
  ) async {
    try {
      final result = await sendRequest(
        ctx,
        displayName,
        Uri.parse('https://www.bigmodel.cn/api/biz/account/query-customer-account-report'),
        headers: {'Authorization': 'Bearer $key'},
        timeout: const Duration(seconds: 5),
      );
      if (result.statusCode != 200) return null;
      return parseZaiBalance(asMap(result.json));
    } on ProviderException {
      return null;
    }
  }
}

/// The quota API's answer for a BigModel CN account that only has prepaid credit.
bool isZaiNoCodingPlan(Map<String, Object?>? root) =>
    root != null &&
    root['success'] == false &&
    root['code'] == 500 &&
    root['msg'] == '当前用户不存在coding plan';

/// BigModel CN pay-as-you-go account balance (`query-customer-account-report`). The
/// available balance wins over the raw one; only real numbers count, so missing fields
/// never turn into a misleading ¥0.00.
({Credits credits, Map<String, String> extras})? parseZaiBalance(Map<String, Object?>? body) {
  if (body == null || body['success'] != true) return null;
  final data = asMap(body['data']) ?? const <String, Object?>{};
  final value = asDouble(data['availableBalance']) ?? asDouble(data['balance']);
  if (value == null) return null;
  final recharged = asDouble(data['rechargeAmount']);
  final granted = asDouble(data['giveAmount']);
  final spent = asDouble(data['totalSpendAmount']);
  return (
    credits: balanceRow('zai-balance', value, label: '账户余额', currency: 'CNY'),
    extras: {
      if (recharged != null) '累计充值': moneyText(recharged, 'CNY'),
      if (granted != null && granted > 0) '赠送金额': moneyText(granted, 'CNY'),
      if (spent != null) '累计消费': moneyText(spent, 'CNY'),
    },
  );
}

// --------------------------------------------------------------- OpenRouter

UsageSnapshot parseOpenRouter(
  UsageSnapshot base,
  Map<String, Object?>? credits,
  Map<String, Object?>? key,
) {
  final c = asMap(credits?['data']);
  final k = asMap(key?['data']);
  final totalCredits = asDouble(c?['total_credits']);
  final totalUsage = asDouble(c?['total_usage']);
  final balance = totalCredits != null && totalUsage != null
      ? (totalCredits - totalUsage).clamp(0, double.infinity).toDouble()
      : null;
  final limit = asDouble(k?['limit']);
  final remaining = asDouble(k?['limit_remaining']);
  final reset = asString(k?['limit_reset']);
  double? used;
  if (limit != null && remaining != null) {
    used = limit - remaining.clamp(0, limit);
  } else {
    used = switch (reset) {
      'daily' => asDouble(k?['usage_daily']),
      'weekly' => asDouble(k?['usage_weekly']),
      'monthly' => asDouble(k?['usage_monthly']),
      _ => asDouble(k?['usage']),
    };
  }
  final windows = <RateWindow>[
    if (limit != null && limit > 0 && used != null)
      quotaWindow(
        'openrouter-key',
        'Key 限额',
        usedPercent: pct(used, limit),
        windowMinutes: switch (reset) {
          'daily' => 1440,
          'weekly' => 10080,
          'monthly' => 43200,
          _ => null,
        },
      ),
  ];
  final management = k?['is_management_key'] == true;
  final spend = asDouble(k?['usage_monthly']) ?? asDouble(k?['usage']) ?? totalUsage;
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    source: 'api-key',
    windows: windows,
    credits: [
      if (balance != null) balanceRow('openrouter-balance', balance, label: 'Credits 余额'),
      if ((limit == null || limit <= 0) && !management && spend != null)
        spendRow(
          'openrouter-spend',
          spend,
          label: asDouble(k?['usage_monthly']) != null ? '本月（此 Key）' : '累计花费',
        ),
    ],
  );
}

class OpenRouterProvider extends UsageProvider {
  @override
  String get id => 'openrouter';
  @override
  String get displayName => 'OpenRouter';
  @override
  int get brandColor => 0xFF6467F2;
  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];
  @override
  String get setupHint => 'openrouter.ai 的 API Key，查询 credits 余额与 Key 限额。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(hint: 'sk-or-...', envVars: ['OPENROUTER_API_KEY']),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final headers = {
      'Authorization': 'Bearer ${bareToken(FieldValues.of(this, account).secret)}',
      'X-Title': 'TokenBar',
    };
    final results = await Future.wait([
      for (final path in ['/credits', '/key'])
        sendRequest(
          ctx,
          displayName,
          Uri.parse('https://openrouter.ai/api/v1$path'),
          headers: headers,
        ),
    ]);
    if (results.every((r) => !r.ok)) checkStatus(displayName, results.first);
    Map<String, Object?>? json(HttpResult r) => r.ok ? asMap(r.json) : null;
    return parseOpenRouter(snapshot(account, ctx), json(results[0]), json(results[1]));
  }
}

// --------------------------------------------------------------------- Warp

const _warpQuery =
    'query GetRequestLimitInfo(\$requestContext: RequestContext!) { user(requestContext: \$requestContext) '
    '{ __typename ... on UserOutput { user { requestLimitInfo { isUnlimited nextRefreshTime requestLimit '
    'requestsUsedSinceLastRefresh } bonusGrants { requestCreditsGranted requestCreditsRemaining expiration } '
    'workspaces { bonusGrantsInfo { grants { requestCreditsGranted requestCreditsRemaining expiration } } } } } } }';

UsageSnapshot parseWarp(UsageSnapshot base, Map<String, Object?> json) {
  final errors = asList(json['errors']);
  if (errors != null && errors.isNotEmpty) {
    final msg = errors
        .map((e) => asString(asMap(e)?['message']))
        .whereType<String>()
        .take(3)
        .join(' | ');
    throw ProviderException('Warp 接口错误: $msg');
  }
  final user = asMap(asMap(json['data'])?['user']);
  final typename = user?['__typename'];
  final inner = asMap(user?['user']);
  final info = asMap(inner?['requestLimitInfo']);
  if (user == null || (typename != null && typename != 'UserOutput') || info == null) {
    throw ProviderException('Warp 返回数据缺少 requestLimitInfo');
  }
  final unlimited =
      info['isUnlimited'] == true ||
      const {'true', '1', 'yes'}.contains(asString(info['isUnlimited']));
  final limit = asInt(info['requestLimit']) ?? 0;
  final used = asInt(info['requestsUsedSinceLastRefresh']) ?? 0;
  final grants = [
    ...(asList(inner!['bonusGrants']) ?? const []),
    for (final w
        in (asList(inner['workspaces']) ?? const []).map(asMap).whereType<Map<String, Object?>>())
      ...(asList(asMap(w['bonusGrantsInfo'])?['grants']) ?? const []),
  ].map(asMap).whereType<Map<String, Object?>>();
  var granted = 0;
  var remaining = 0;
  for (final g in grants) {
    granted += asInt(g['requestCreditsGranted']) ?? 0;
    remaining += asInt(g['requestCreditsRemaining']) ?? 0;
  }
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    plan: unlimited ? '不限量' : null,
    source: 'api-key',
    windows: [
      quotaWindow(
        'warp-requests',
        '请求额度',
        usedPercent: unlimited || limit <= 0 ? 0 : pct(used, limit),
        resetsAt: unlimited ? null : parseFlexibleDate(info['nextRefreshTime']),
      ),
      if (granted > 0 || remaining > 0)
        quotaWindow(
          'warp-bonus',
          '附加 Credits',
          usedPercent: granted > 0 ? pct(granted - remaining, granted) : (remaining > 0 ? 0 : 100),
        ),
    ],
    extras: {
      if (!unlimited) '请求': '$used / $limit',
      if (granted > 0) '附加 Credits': '剩余 $remaining / $granted',
    },
  );
}

class WarpProvider extends UsageProvider {
  @override
  String get id => 'warp';
  @override
  String get displayName => 'Warp';
  @override
  int get brandColor => 0xFF938BB4;
  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];
  @override
  String get setupHint => 'Warp 的 API Key，查询 AI 请求额度和附加 credits。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(envVars: ['WARP_API_KEY', 'WARP_TOKEN']),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final key = bareToken(FieldValues.of(this, account).secret);
    const os = {'category': 'macOS', 'name': 'macOS', 'version': '15.0.0'};
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo'),
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-warp-client-id': 'warp-app',
        'x-warp-os-category': os['category']!,
        'x-warp-os-name': os['name']!,
        'x-warp-os-version': os['version']!,
        'Authorization': 'Bearer $key',
        'User-Agent': 'Warp/1.0',
      },
      body: jsonEncode({
        'query': _warpQuery,
        'variables': {
          'requestContext': {'clientContext': <String, Object?>{}, 'osContext': os},
        },
        'operationName': 'GetRequestLimitInfo',
      }),
      timeout: const Duration(seconds: 15),
    );
    return parseWarp(snapshot(account, ctx), json);
  }
}

// ---------------------------------------------------------------- Synthetic

const _syntheticKeys = FlexKeys(
  limit: [
    'limit',
    'messagelimit',
    'messages',
    'maxrequests',
    'requestlimit',
    'quota',
    'max',
    'total',
    'capacity',
    'allowance',
  ],
  used: [
    'used',
    'usage',
    'usedmessages',
    'messagesused',
    'requests',
    'requestcount',
    'consumed',
    'spent',
  ],
  remaining: ['remaining', 'left', 'available', 'balance'],
  percentUsed: ['percentused', 'usedpercent', 'usagepercent', 'percent'],
  percentRemaining: ['percentremaining', 'remainingpercent'],
  reset: [
    'resetat',
    'resetsat',
    'renewat',
    'renewsat',
    'nexttickat',
    'nextregenat',
    'periodend',
    'expiresat',
    'endat', //
  ],
);

UsageSnapshot parseSynthetic(UsageSnapshot base, Object? body) {
  final root = body is List ? {'quotas': body} : (asMap(body) ?? const <String, Object?>{});
  final data = asMap(root['data']);
  Map<String, Object?>? slot(String key) => asMap(root[key]) ?? asMap(data?[key]);
  // New plans only enforce weekly credits (`planWeeklyLimit`, percentages are 0–100 even
  // below 1%); the rolling five-hour counter is retired for them (CodexBar synthetic.js).
  final planWeekly = slot('planWeeklyLimit');
  final hasPlanWeekly =
      planWeekly != null && parseFlexQuota(planWeekly, _syntheticKeys, ratioPercent: false) != null;
  final named = [
    if (!hasPlanWeekly) ('synthetic-5h', '5 小时滚动', slot('rollingFiveHourLimit')),
    if (hasPlanWeekly)
      ('synthetic-weekly', '每周额度', planWeekly)
    else
      ('synthetic-weekly', '每周 Token', slot('weeklyTokenLimit')),
    ('synthetic-search', '搜索（每小时）', asMap(slot('search')?['hourly'])),
  ];
  final windows = <RateWindow>[];
  Credits? credits;
  final extras = <String, String>{};
  if (named.any((n) => n.$3 != null)) {
    for (final (id, label, m) in named) {
      if (m == null) continue;
      final q = parseFlexQuota(
        m,
        _syntheticKeys,
        ratioPercent: !(hasPlanWeekly && m == planWeekly),
      );
      if (q != null) {
        windows.add(
          quotaWindow(
            id,
            label,
            usedPercent: q.usedPercent,
            resetsAt: q.resetsAt,
            windowMinutes: q.windowMinutes,
          ),
        );
      }
      final max = flexNumber(flexValue(m, ['maxcredits']));
      if (credits == null && max != null) {
        final rem = flexNumber(flexValue(m, ['remainingcredits']));
        final usedC = flexNumber(flexValue(m, ['usedcredits'])) ?? (rem == null ? null : max - rem);
        if (usedC != null) {
          credits = spendRow(
            'synthetic-credits',
            usedC,
            limit: max,
            label: '每周 Credits',
            resetsAt: q?.resetsAt,
          );
          // Regeneration details of the credit lane.
          final regenCredits = flexNumber(flexValue(m, ['nextregencredits']));
          final regenPercent = flexNumber(flexValue(m, ['nextregenpercent', 'tickpercent']));
          if (regenCredits != null) extras['下次恢复额度'] = '+${moneyText(regenCredits, 'USD')}';
          if (regenPercent != null) {
            extras['下次恢复比例'] = '+${regenPercent.toStringAsFixed(regenPercent % 1 == 0 ? 0 : 2)}%';
          }
        }
      }
    }
  } else {
    final container = [
      for (final k in ['quotas', 'quota', 'limits', 'usage', 'entries', 'subscription'])
        root[k] ?? data?[k],
    ].firstWhere((c) => c != null, orElse: () => data);
    final quotas = collectFlexQuotas(container, _syntheticKeys).take(3).toList();
    for (var i = 0; i < quotas.length; i++) {
      final q = quotas[i];
      windows.add(
        quotaWindow(
          'synthetic-$i',
          q.label ?? '额度 ${i + 1}',
          usedPercent: q.usedPercent,
          resetsAt: q.resetsAt,
          windowMinutes: q.windowMinutes,
        ),
      );
    }
  }
  if (windows.isEmpty && credits == null) throw ProviderException('Synthetic 返回数据缺少额度信息');
  final plan = [
    for (final k in ['plan', 'planName', 'plan_name', 'tier', 'package', 'packageName'])
      asString(root[k]) ?? asString(data?[k]),
  ].whereType<String>().firstOrNull;
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    plan: plan,
    source: 'api-key',
    windows: windows,
    credits: [?credits],
    extras: extras,
  );
}

class SyntheticProvider extends UsageProvider {
  @override
  String get id => 'synthetic';
  @override
  String get displayName => 'Synthetic';
  @override
  int get brandColor => 0xFF141414;
  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];
  @override
  String get setupHint => 'synthetic.new 的 API Key，查询滚动额度、每周额度与搜索额度。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(envVars: ['SYNTHETIC_API_KEY']),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final r = await sendChecked(
      ctx,
      displayName,
      Uri.parse('https://api.synthetic.new/v2/quotas'),
      headers: {'Authorization': 'Bearer ${bareToken(FieldValues.of(this, account).secret)}'},
    );
    return parseSynthetic(snapshot(account, ctx), r.json);
  }
}

// ------------------------------------------------------------------- Chutes

const _chutesKeys = FlexKeys(
  limit: [
    'limit',
    'cap',
    'max',
    'maximum',
    'quota',
    'quotalimit',
    'monthlycap',
    'monthlylimit',
    'requestlimit',
    'tokenlimit',
    'hardlimit',
    'total',
  ],
  used: [
    'used',
    'usage',
    'usedamount',
    'consumed',
    'consumedamount',
    'current',
    'currentusage',
    'requests',
    'requestcount',
    'tokens',
    'tokenusage',
    'monthlyusage',
  ],
  remaining: ['remaining', 'available', 'balance', 'left', 'remainingamount', 'availableamount'],
  percentUsed: ['percentused', 'usagepercent', 'usedpercent', 'utilization', 'utilizationpercent'],
  percentRemaining: ['percentremaining', 'remainingpercent'],
  reset: [
    'resetat',
    'resetsat',
    'resettime',
    'nextresetat',
    'renewsat',
    'renewalat',
    'periodend',
    'currentperiodend',
    'expiresat',
    'windowend',
    'endtime',
  ],
  label: [
    'label',
    'name',
    'title',
    'type',
    'quotatype',
    'period',
    'window',
    'windowname',
    'chuteid',
  ],
);

({FlexQuota? rolling, FlexQuota? monthly, List<FlexQuota> other, bool? active, String? plan})
parseChutes(Object? body) {
  final root = body is List ? {'quotas': body} : (asMap(body) ?? const <String, Object?>{});
  final quotas = collectFlexQuotas(root, _chutesKeys);
  bool isRolling(FlexQuota q) =>
      RegExp(r'rolling|4h|4 h|4-hour|four.hour').hasMatch((q.label ?? '').toLowerCase()) ||
      q.windowMinutes == 240;
  bool isMonthly(FlexQuota q) =>
      RegExp(r'month|billing|subscription').hasMatch((q.label ?? '').toLowerCase()) ||
      (q.windowMinutes ?? 0) >= 40320;
  final rolling = quotas.where(isRolling).firstOrNull;
  final monthly = quotas.where((q) => q != rolling && isMonthly(q)).firstOrNull;
  final sub =
      asMap(
        flexValue(root, ['subscription', 'subscriptionusage', 'currentsubscription', 'plan']),
      ) ??
      const {};
  Object? ctxValue(List<String> keys) => flexValue(root, keys) ?? flexValue(sub, keys);
  bool? active;
  final a = ctxValue(['active', 'isactive', 'subscriptionactive', 'hassubscription']);
  if (a is bool) active = a;
  final status = asString(ctxValue(['status', 'state', 'subscriptionstatus']))?.toLowerCase() ?? '';
  if (active == null && status.contains('active') && !status.contains('inactive')) active = true;
  if (active == null && RegExp('free|inactive|cancel|none|expired').hasMatch(status)) {
    active = false;
  }
  final plan = ctxValue(['planname', 'plan', 'tier', 'subscriptionplan', 'subscriptiontier']);
  return (
    rolling: rolling,
    monthly: monthly,
    other: quotas.where((q) => q != rolling && q != monthly).toList(),
    active: active,
    plan: plan is String ? plan : null,
  );
}

class ChutesProvider extends UsageProvider {
  @override
  String get id => 'chutes';
  @override
  String get displayName => 'Chutes';
  @override
  int get brandColor => 0xFF3184FF;
  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];
  @override
  String get setupHint => 'chutes.ai 的 API Key，查询 4 小时滚动额度和月度额度。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(envVars: ['CHUTES_API_KEY']),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final headers = {'Authorization': 'Bearer ${bareToken(FieldValues.of(this, account).secret)}'};
    Future<Object?> get(String path) async => (await sendChecked(
      ctx,
      displayName,
      Uri.parse('https://api.chutes.ai/users/me/$path'),
      headers: headers,
      authHint: 'Chutes 拒绝了 API Key',
      timeout: const Duration(seconds: 15),
    )).json;
    final sub = parseChutes(await get('subscription_usage'));
    var rolling = sub.rolling;
    var monthly = sub.monthly;
    final other = [...sub.other];
    if (rolling == null || monthly == null) {
      try {
        final raw = await get('quotas');
        final list = raw is List
            ? raw
            : asList(asMap(raw)?['quotas']) ?? asList(asMap(raw)?['data']);
        final enriched = <Map<String, Object?>>[];
        for (final item in (list ?? const []).map(asMap).whereType<Map<String, Object?>>()) {
          final id =
              asString(item['chute_id']) ??
              asString(item['chuteId']) ??
              asString(item['id']) ??
              item['chute_id']?.toString();
          Map<String, Object?>? usage;
          if (id != null) {
            try {
              usage = asMap(await get('quota_usage/${Uri.encodeComponent(id)}'));
            } on ProviderException catch (e) {
              if (e.statusCode == 401 || e.statusCode == 403) rethrow;
            }
          }
          enriched.add({...item, ...?usage});
        }
        final q = parseChutes(enriched.isEmpty ? raw : {'quotas': enriched});
        rolling ??= q.rolling;
        monthly ??= q.monthly;
        other.addAll(q.other);
      } on ProviderException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) rethrow;
      }
    }
    final primary = rolling ?? (monthly == null ? other.firstOrNull : null);
    final secondary =
        monthly ??
        (rolling != null ? other.firstOrNull : (primary != null ? other.elementAtOrNull(1) : null));
    RateWindow win(String id, String label, FlexQuota q, int? defMinutes) => quotaWindow(
      id,
      label,
      usedPercent: q.usedPercent,
      resetsAt: q.resetsAt,
      windowMinutes: q.windowMinutes ?? defMinutes,
    );
    return snapshot(
      account,
      ctx,
      plan: sub.plan ?? (sub.active == false ? '无有效订阅' : null),
      source: 'api-key',
      windows: [
        if (primary != null)
          rolling != null
              ? win('chutes-rolling', '4 小时', primary, 240)
              : win('chutes-primary', primary.label ?? '额度', primary, null),
        if (secondary != null)
          monthly != null
              ? win('chutes-monthly', '每月', secondary, 43200)
              : win('chutes-secondary', secondary.label ?? '额度', secondary, null),
      ],
    );
  }
}
