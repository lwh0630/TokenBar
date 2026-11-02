import 'dart:convert';

import '../../models/account.dart';
import '../../models/credits.dart';
import '../../models/rate_window.dart';
import '../../models/usage_snapshot.dart';
import '../../platform/platform.dart' as platform;
import '../../util/json_utils.dart';
import '../common.dart';
import '../fields.dart';
import '../http_support.dart';
import '../provider.dart';

DateTime? _utcDate(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (day != null) return DateTime.utc(int.parse(day[1]!), int.parse(day[2]!), int.parse(day[3]!));
  return DateTime.tryParse(s)?.toUtc();
}

String _titleWords(String s) => s
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
    .join(' ');

double _nonNeg(double v) => v < 0 ? 0 : v;

double _clampPct(double v) => v.clamp(0, 100).toDouble();

// ------------------------------------------------------------------ Copilot

const _copilotEditorHeaders = {
  'Editor-Version': 'vscode/1.96.2',
  'Editor-Plugin-Version': 'copilot-chat/0.26.7',
  'User-Agent': 'GitHubCopilotChat/0.26.7',
  'X-Github-Api-Version': '2025-04-01',
};

String normalizeCopilotHost(String? raw) {
  var text = raw?.trim() ?? '';
  if (text.isEmpty) return 'github.com';
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return 'github.com';
  final host = uri.host.toLowerCase().replaceAll(RegExp(r'\.+$'), '');
  if (host.isEmpty) return 'github.com';
  return uri.hasPort && uri.port != 443 ? '$host:${uri.port}' : host;
}

String copilotApiHost(String host) {
  if (host == 'github.com') return 'api.github.com';
  return host.startsWith('api.') ? host : 'api.$host';
}

class _CopilotQuota {
  const _CopilotQuota({
    required this.entitlement,
    required this.remaining,
    required this.entitlementDecoded,
    required this.remainingDecoded,
    this.creditsUsed,
    this.percentRemaining,
    this.hasQuota = true,
    this.tokenBasedBilling = false,
    this.unlimited = false,
  });

  final double entitlement;
  final double remaining;
  final bool entitlementDecoded;
  final bool remainingDecoded;
  final double? creditsUsed;
  final double? percentRemaining;
  final bool hasQuota;
  final bool tokenBasedBilling;
  final bool unlimited;

  bool get isPlaceholder {
    if (!hasQuota) return true;
    if (unlimited) return false;
    if (entitlement == 0 && remaining == 0 && percentRemaining == null) return true;
    return entitlementDecoded && remainingDecoded && entitlement == 0 && remaining == 0;
  }

  bool get usable => !isPlaceholder && percentRemaining != null;

  _CopilotQuota withCredits(double? credits) => _CopilotQuota(
    entitlement: entitlement,
    remaining: remaining,
    entitlementDecoded: entitlementDecoded,
    remainingDecoded: remainingDecoded,
    creditsUsed: credits,
    percentRemaining: percentRemaining,
    hasQuota: hasQuota,
    tokenBasedBilling: tokenBasedBilling,
    unlimited: unlimited,
  );
}

_CopilotQuota? _decodeCopilotQuota(Object? raw) {
  final m = asMap(raw);
  if (m == null) return null;
  final entitlement = asDouble(m['entitlement']);
  final remaining = asDouble(m['remaining']);
  final unlimited = asBool(m['unlimited']) ?? false;
  final derived = entitlement != null && entitlement > 0 && remaining != null
      ? remaining / entitlement * 100
      : null;
  return _CopilotQuota(
    entitlement: entitlement ?? 0,
    remaining: remaining ?? 0,
    entitlementDecoded: entitlement != null,
    remainingDecoded: remaining != null,
    creditsUsed: asDouble(m['credits_used']),
    percentRemaining: unlimited ? 100 : (asDouble(m['percent_remaining']) ?? derived),
    hasQuota: asBool(m['has_quota']) ?? true,
    tokenBasedBilling: asBool(m['token_based_billing']) ?? false,
    unlimited: unlimited,
  );
}

({_CopilotQuota? premium, _CopilotQuota? completions, _CopilotQuota? chat}) _directCopilotQuotas(
  Map<String, Object?> snapshots,
) {
  _CopilotQuota? keep(_CopilotQuota? q) =>
      q == null || (q.isPlaceholder && q.creditsUsed == null && !q.tokenBasedBilling) ? null : q;
  var premium = keep(_decodeCopilotQuota(snapshots['premium_interactions']));
  var completions = keep(_decodeCopilotQuota(snapshots['completions']));
  var chat = keep(_decodeCopilotQuota(snapshots['chat']));
  _CopilotQuota? firstUsable;
  for (final entry in snapshots.entries) {
    final q = keep(_decodeCopilotQuota(entry.value));
    if (q == null) continue;
    firstUsable ??= q;
    final name = entry.key.toLowerCase();
    if (name.contains('chat')) {
      chat ??= q;
    } else if (name.contains('premium')) {
      premium ??= q;
    } else if (name.contains('completion') || name.contains('code')) {
      completions ??= q;
    }
  }
  if (premium == null && completions == null && chat == null) chat = firstUsable;
  return (premium: premium, completions: completions, chat: chat);
}

_CopilotQuota? _monthlyCopilotQuota(double? monthly, double? limited) {
  if (monthly == null || limited == null || monthly <= 0) return null;
  final entitlement = monthly;
  final remaining = _nonNeg(limited);
  return _CopilotQuota(
    entitlement: entitlement,
    remaining: remaining,
    entitlementDecoded: true,
    remainingDecoded: true,
    percentRemaining: _clampPct(remaining / entitlement * 100),
  );
}

bool _copilotUsable(_CopilotQuota? q) => q != null && q.usable;

_CopilotQuota? _preferCopilotQuota(_CopilotQuota? direct, _CopilotQuota? fallback) {
  if (direct?.unlimited == true && _copilotUsable(fallback)) {
    return fallback!.withCredits(direct!.creditsUsed);
  }
  if (_copilotUsable(direct)) return direct;
  if (!_copilotUsable(fallback)) return null;
  return direct?.creditsUsed != null ? fallback!.withCredits(direct!.creditsUsed) : fallback;
}

RateWindow? _copilotWindow(String id, String label, _CopilotQuota? q, DateTime? resetsAt) {
  if (q == null || q.unlimited || q.isPlaceholder || q.percentRemaining == null) return null;
  return quotaWindow(
    id,
    label,
    usedPercent: _nonNeg(100 - q.percentRemaining!),
    resetsAt: resetsAt,
  );
}

({String plan, List<RateWindow> windows, List<Credits> credits}) parseCopilotUsage(
  Map<String, Object?> json,
) {
  final direct = _directCopilotQuotas(asMap(json['quota_snapshots']) ?? const {});
  final monthly = asMap(json['monthly_quotas']);
  final limited = asMap(json['limited_user_quotas']);
  final premium = _copilotUsable(direct.premium) ? direct.premium : null;
  final completions = _preferCopilotQuota(
    direct.completions,
    _monthlyCopilotQuota(asDouble(monthly?['completions']), asDouble(limited?['completions'])),
  );
  final chat = _preferCopilotQuota(
    direct.chat,
    _monthlyCopilotQuota(asDouble(monthly?['chat']), asDouble(limited?['chat'])),
  );
  final resetsAt = _utcDate(asString(json['quota_reset_date']));
  final directQuotas = [direct.premium, direct.completions, direct.chat];
  final tokenBilling =
      asBool(json['token_based_billing']) == true ||
      directQuotas.any((quota) => quota?.tokenBasedBilling == true);
  final unlimited = directQuotas.any((quota) => quota?.unlimited == true);
  final premiumWindow = _copilotWindow('copilot-premium', '高级请求', premium, resetsAt);
  final completionsWindow = _copilotWindow(
    'copilot-completions',
    tokenBilling ? 'AI Credits' : '代码补全',
    completions,
    resetsAt,
  );
  final chatWindow = _copilotWindow('copilot-chat', '聊天', chat, resetsAt);
  if (premiumWindow == null &&
      completionsWindow == null &&
      chatWindow == null &&
      !tokenBilling &&
      !unlimited) {
    throw ProviderException('Copilot 返回的额度数据无法解析', hint: '稍后重试，或在 GitHub 查看 Copilot 用量');
  }
  // A zero placeholder must not hide a real quota's counter. These counters
  // may describe shared pools, so select one rather than adding them.
  final creditsUsed =
      premium?.creditsUsed ??
      completions?.creditsUsed ??
      chat?.creditsUsed ??
      direct.premium?.creditsUsed ??
      direct.completions?.creditsUsed ??
      direct.chat?.creditsUsed;
  final hasSignal = tokenBilling || unlimited || (creditsUsed ?? 0) > 0;
  final plan = asString(json['copilot_plan']) ?? 'unknown';
  return (
    plan: _titleWords(plan),
    windows: [?premiumWindow, ?completionsWindow, ?chatWindow],
    credits: [
      if (creditsUsed != null && hasSignal)
        Credits(
          id: 'copilot-seat-credits',
          label: 'Credits 已用',
          used: creditsUsed,
          resetsAt: resetsAt,
        ),
    ],
  );
}

class CopilotProvider extends UsageProvider {
  @override
  String get id => 'copilot';

  @override
  String get displayName => 'GitHub Copilot';

  @override
  int get brandColor => 0xFFA855F7;

  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];

  @override
  String get setupHint =>
      '粘贴已开通 Copilot 的 GitHub OAuth 令牌（如 gho_ 开头），不是短期 Copilot 服务令牌。GitHub Enterprise 用户在下方填写主机。手机也能用。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(
      label: 'GitHub Token',
      hint: 'gho_...',
      envVars: ['COPILOT_API_TOKEN'],
      help: '使用 GitHub OAuth 令牌；普通 PAT 不保证可用。仅在本机安全保存，不会发送给 TokenBar 服务器',
    ),
    ProviderField(
      key: 'enterpriseHost',
      label: 'GitHub Enterprise 主机',
      kind: FieldKind.text,
      required: false,
      hint: '留空即 github.com，例如 octocorp.ghe.com',
    ),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final values = FieldValues.of(this, account);
    final host = normalizeCopilotHost(values['enterpriseHost']);
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('https://${copilotApiHost(host)}/copilot_internal/user'),
      headers: {'Authorization': 'token ${bareToken(values.secret)}', ..._copilotEditorHeaders},
      authHint: 'GitHub 令牌已失效或没有 Copilot 权限，请重新生成 Token',
    );
    final usage = parseCopilotUsage(json);
    return snapshot(
      account,
      ctx,
      plan: usage.plan,
      source: 'api-key',
      windows: usage.windows,
      credits: usage.credits,
    );
  }
}

// ------------------------------------------------------------------- Gemini

const _codeAssistBase = 'https://cloudcode-pa.googleapis.com/v1internal';
const _geminiWebSignature = '2/dWbCvkVB0X16r9NPnxifeOAAqdCqMf0xeWvau9yPy7g=';
const _geminiShutdownError = 'Google 已停止个人版 Gemini CLI OAuth（AI Pro / Ultra / 个人账户，2026 年 6 月起）';
const _geminiShutdownHint = '改用 Workspace / 教育版 / Code Assist 账户，或改用 gemini.google.com 的 Cookie';

class GeminiLocalCredentials {
  const GeminiLocalCredentials({required this.accessToken, this.idToken, this.expiresAt});

  final String accessToken;
  final String? idToken;
  final DateTime? expiresAt;

  bool isExpired(DateTime now) {
    final exp = expiresAt;
    return exp != null && !exp.isAfter(now);
  }
}

GeminiLocalCredentials? parseGeminiLocalCredentials({String? oauthJson, String? settingsJson}) {
  final settings = decodeJsonObject(settingsJson ?? '{}');
  final authType = asString(asMap(asMap(settings?['security'])?['auth'])?['selectedType']);
  if (authType == 'api-key' || authType == 'gemini-api-key') {
    throw ProviderException(
      'Gemini CLI 当前使用 API Key 认证，TokenBar 暂不支持',
      hint: '在 Gemini CLI 中改用 Google 账号登录',
    );
  }
  if (authType == 'vertex-ai') {
    throw ProviderException(
      'Gemini CLI 当前使用 Vertex AI 认证，TokenBar 暂不支持',
      hint: '在 Gemini CLI 中改用 Google 账号登录',
    );
  }
  final json = decodeJsonObject(oauthJson ?? '');
  final token = asString(json?['access_token']);
  if (json == null || token == null) return null;
  final expiry = asDouble(json['expiry_date']);
  return GeminiLocalCredentials(
    accessToken: token,
    idToken: asString(json['id_token']),
    expiresAt: expiry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiry.toInt(), isUtc: true),
  );
}

bool geminiDeprecated(String body) {
  final lower = body.toLowerCase();
  return lower.contains('unsupported_client') ||
      lower.contains('ineligibletiererror') ||
      (lower.contains('no longer supported') && lower.contains('gemini code assist')) ||
      (lower.contains('migrate') && lower.contains('antigravity') && lower.contains('gemini'));
}

class GeminiCodeAssist {
  const GeminiCodeAssist({this.project, this.tier, this.paidTier});

  final String? project;
  final String? tier;
  final String? paidTier;

  String? plan(String? hostedDomain) =>
      paidTier ??
      switch (tier) {
        'standard-tier' => 'Paid',
        'free-tier' => hostedDomain == null ? 'Free' : 'Workspace',
        'legacy-tier' => 'Legacy',
        _ => null,
      };
}

GeminiCodeAssist parseGeminiCodeAssist(Map<String, Object?> json, {String? hostedDomain}) {
  final paid = asString(asMap(json['paidTier'])?['name']);
  final tier = asString(asMap(json['currentTier'])?['id']);
  final ineligible = (asList(json['ineligibleTiers']) ?? const <Object?>[]).map(asMap).nonNulls;
  final unsupported = ineligible.any(
    (t) =>
        asString(t['reasonCode'])?.toUpperCase() == 'UNSUPPORTED_CLIENT' ||
        (asString(t['reasonMessage']) ?? '').toLowerCase().contains('unsupported_client'),
  );
  if (tier == null && paid == null && hostedDomain == null && unsupported) {
    throw ProviderException(_geminiShutdownError, hint: _geminiShutdownHint);
  }
  final projectRaw = json['cloudaicompanionProject'];
  final project = projectRaw is String
      ? asString(projectRaw)
      : asString(asMap(projectRaw)?['id']) ?? asString(asMap(projectRaw)?['projectId']);
  return GeminiCodeAssist(project: project, tier: tier, paidTier: paid);
}

String? geminiProjectId(Map<String, Object?>? json) {
  for (final p in (asList(json?['projects']) ?? const <Object?>[]).map(asMap).nonNulls) {
    final id = asString(p['projectId']);
    if (id != null &&
        (id.startsWith('gen-lang-client') ||
            asMap(p['labels'])?.containsKey('generative-language') == true)) {
      return id;
    }
  }
  return null;
}

List<RateWindow> parseGeminiQuotaBuckets(Map<String, Object?> json) {
  final buckets = asList(json['buckets']);
  if (buckets == null) throw ProviderException('Gemini 配额响应格式已变化');
  final lowest = <String, ({double percentLeft, DateTime? resetsAt})>{};
  for (final raw in buckets) {
    final b = asMap(raw);
    final model = asString(b?['modelId']);
    final fraction = asDouble(b?['remainingFraction']);
    if (model == null || fraction == null) continue;
    final left = fraction * 100;
    final current = lowest[model];
    if (current == null || left < current.percentLeft) {
      lowest[model] = (percentLeft: left, resetsAt: _utcDate(asString(b?['resetTime'])));
    }
  }
  if (lowest.isEmpty) throw ProviderException('Gemini 配额响应中没有可用的 buckets');

  RateWindow? group(String id, String label, bool Function(String model) match) {
    ({double percentLeft, DateTime? resetsAt})? best;
    for (final e in lowest.entries) {
      if (!match(e.key.toLowerCase())) continue;
      if (best == null || e.value.percentLeft < best.percentLeft) best = e.value;
    }
    final chosen = best;
    if (chosen == null) return null;
    return quotaWindow(
      id,
      label,
      usedPercent: 100 - chosen.percentLeft,
      resetsAt: chosen.resetsAt,
      windowMinutes: 1440,
    );
  }

  return [
    ?group('gemini-pro', 'Pro', (m) => m.contains('pro')),
    ?group('gemini-flash', 'Flash', (m) => m.contains('flash') && !m.contains('flash-lite')),
    ?group('gemini-flash-lite', 'Flash Lite', (m) => m.contains('flash-lite')),
  ];
}

({String? plan, List<RateWindow> windows}) parseGeminiWebUsage(String body) {
  final text = body.replaceFirst(RegExp(r"^\)\]\}'\s*"), '');
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw ProviderException('Gemini 网页返回了无法识别的数据');
  }
  Map<String, Object?>? data;
  for (final entry in asList(decoded) ?? const <Object?>[]) {
    final d = asMap(asMap(entry)?['data']);
    if (d != null && d.containsKey('viewer')) {
      data = d;
      break;
    }
  }
  if (data == null) throw ProviderException('Gemini 网页返回了无法识别的数据');
  final viewer = asMap(data['viewer']);
  if (viewer == null) {
    throw ProviderException(
      'Gemini 网页会话已失效',
      hint: '在浏览器打开 gemini.google.com/usage 重新登录，再粘贴新的 Cookie',
    );
  }
  final usage = asMap(asMap(viewer['rpcs'])?['getUsageInfo']);
  if (usage == null) throw ProviderException('Gemini 网页用量结构已变化');
  final pools = (asList(usage['pools']) ?? const <Object?>[]).map(asMap).nonNulls.toList();

  RateWindow? poolWindow(String type, String id, String label, int minutes) {
    final pool = pools.where((p) => p['poolType'] == type).firstOrNull;
    final used = asDouble(pool?['percentageUsed']);
    if (used == null || used < 0) return null;
    final reset = asString(asMap(pool?['gxu'])?['windowRefreshesAt']);
    final resetsAt = reset != null && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(reset)
        ? DateTime.tryParse(reset)?.toUtc()
        : null;
    return quotaWindow(
      id,
      label,
      usedPercent: (used * 100).clamp(0, 100).toDouble(),
      resetsAt: resetsAt,
      windowMinutes: minutes,
    );
  }

  final windows = [
    ?poolWindow('GXU_FIVE_HOURLY', RateWindow.sessionId, '5 小时', 300),
    ?poolWindow('GXU_WEEKLY', RateWindow.weeklyId, '每周', 10080),
  ];
  if (windows.isEmpty) throw ProviderException('此 Google 账户没有 Gemini 应用用量窗口');
  return (plan: asString(usage['subscriptionTier']) == 'TIER1' ? 'Pro' : null, windows: windows);
}

class GeminiProvider extends UsageProvider {
  @override
  String get id => 'gemini';

  @override
  String get displayName => 'Gemini';

  @override
  int get brandColor => 0xFFAB87EA;

  @override
  List<SourceType> get supportedSources => const [SourceType.localCli, SourceType.apiKey];

  @override
  String get setupHint =>
      '本机模式读取 Gemini CLI 的 ~/.gemini/oauth_creds.json（只读，不刷新，过期后请在 Gemini CLI 里重新登录）。'
      '手动模式可粘贴 OAuth access token，或 gemini.google.com 的 Cookie（含 Cookie 时走 Gemini 应用用量）。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(
      label: 'OAuth Token 或 Cookie',
      hint: 'ya29... 或 Cookie: ...',
      help: 'OAuth token 来自 ~/.gemini/oauth_creds.json 的 access_token；Cookie 来自 gemini.google.com 的请求头',
    ),
  ];

  @override
  String get manualSourceLabel => '手动粘贴 Token / Cookie';

  @override
  String get localSourceLabel => '本机 Gemini CLI 登录';

  @override
  Future<bool> hasLocalLogin(AccountConfig account) async {
    try {
      return await _readLocal(account) != null;
    } on ProviderException {
      return false;
    }
  }

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    if (account.sourceType == SourceType.apiKey) {
      final pasted = FieldValues.of(this, account).secret;
      if (pasted.contains('=')) return _fetchWeb(account, ctx, pasted);
      return _fetchOAuth(account, ctx, token: bareToken(pasted), source: 'api-key');
    }
    final creds = await _readLocal(account);
    if (creds == null) {
      throw ProviderException('未找到 Gemini CLI 登录', hint: '在终端运行 gemini 完成 Google 登录，或改用手动粘贴 Token');
    }
    if (creds.isExpired(ctx.now())) {
      throw ProviderException('Gemini 登录已过期', hint: '在 Gemini CLI 里重新登录一次（运行 gemini）');
    }
    return _fetchOAuth(
      account,
      ctx,
      token: creds.accessToken,
      source: 'local',
      idToken: creds.idToken,
    );
  }

  Future<GeminiLocalCredentials?> _readLocal(AccountConfig account) async {
    final home = account.homeDir ?? platform.homeDirectory();
    if (!platform.localAccessSupported || home == null) return null;
    return parseGeminiLocalCredentials(
      oauthJson: await platform.readTextFile(
        platform.joinPath(home, '.gemini', 'oauth_creds.json'),
      ),
      settingsJson: await platform.readTextFile(
        platform.joinPath(home, '.gemini', 'settings.json'),
      ),
    );
  }

  Future<UsageSnapshot> _fetchOAuth(
    AccountConfig account,
    FetchContext ctx, {
    required String token,
    required String source,
    String? idToken,
  }) async {
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final claims = decodeJwtPayload(idToken);
    final hostedDomain = asString(claims?['hd']);
    final assist = await _loadCodeAssist(ctx, headers, hostedDomain);
    final project = assist.project ?? await _findProject(ctx, headers);
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse('$_codeAssistBase:retrieveUserQuota'),
      method: 'POST',
      headers: headers,
      body: project == null ? <String, Object?>{} : {'project': project},
      timeout: const Duration(seconds: 15),
    );
    if (r.statusCode == 401) {
      throw ProviderException(
        'Gemini 登录已过期',
        hint: source == 'local' ? '在 Gemini CLI 中重新登录一次' : '重新从 oauth_creds.json 复制 access_token',
      );
    }
    if (!r.ok && geminiDeprecated(r.body)) {
      throw ProviderException(_geminiShutdownError, hint: _geminiShutdownHint);
    }
    checkStatus(displayName, r);
    final json = asMap(r.json);
    if (json == null) throw ProviderException('Gemini 返回了无法解析的配额数据');
    return snapshot(
      account,
      ctx,
      plan: assist.plan(hostedDomain),
      email: asString(claims?['email']),
      source: source,
      windows: parseGeminiQuotaBuckets(json),
    );
  }

  Future<GeminiCodeAssist> _loadCodeAssist(
    FetchContext ctx,
    Map<String, String> headers,
    String? hostedDomain,
  ) async {
    HttpResult? r;
    try {
      r = await sendRequest(
        ctx,
        displayName,
        Uri.parse('$_codeAssistBase:loadCodeAssist'),
        method: 'POST',
        headers: headers,
        body: {
          'metadata': {'ideType': 'GEMINI_CLI', 'pluginType': 'GEMINI'},
        },
        timeout: const Duration(seconds: 10),
      );
    } on ProviderException {
      return const GeminiCodeAssist();
    }
    if (!r.ok) {
      if (geminiDeprecated(r.body)) {
        throw ProviderException(_geminiShutdownError, hint: _geminiShutdownHint);
      }
      return const GeminiCodeAssist();
    }
    final json = asMap(r.json);
    return json == null
        ? const GeminiCodeAssist()
        : parseGeminiCodeAssist(json, hostedDomain: hostedDomain);
  }

  Future<String?> _findProject(FetchContext ctx, Map<String, String> headers) async {
    try {
      final r = await sendRequest(
        ctx,
        displayName,
        Uri.parse('https://cloudresourcemanager.googleapis.com/v1/projects'),
        headers: headers,
        timeout: const Duration(seconds: 10),
      );
      return r.ok ? geminiProjectId(asMap(r.json)) : null;
    } on ProviderException {
      return null;
    }
  }

  Future<UsageSnapshot> _fetchWeb(AccountConfig account, FetchContext ctx, String input) async {
    final variables = jsonEncode({
      'g1Request': {
        'entrypoints': ['GEMINI_USAGE_SETTINGS_UPGRADE_BANNER'],
      },
      'workspaceRequest': {'recommendationsForSurfaceRequests': <Object>[]},
    });
    final uri = Uri.https(
      'gemini.google.com',
      '/_/BardChatUi/graphql/schemas/GEMINI_WEB_GRAPHQL/executeQuery',
      {'query_signature': _geminiWebSignature, 'variables': variables},
    );
    final r = await sendRequest(
      ctx,
      displayName,
      uri,
      headers: {
        'Cookie': normalizeCookieHeader(input),
        'Referer': 'https://gemini.google.com/usage',
      },
      timeout: const Duration(seconds: 15),
    );
    if (r.statusCode == 401 || r.statusCode == 403 || (r.ok && r.body.trimLeft().startsWith('<'))) {
      throw ProviderException(
        'Gemini 网页会话已失效',
        hint: '在浏览器打开 gemini.google.com/usage 重新登录，再粘贴新的 Cookie',
      );
    }
    checkStatus(displayName, r);
    final parsed = parseGeminiWebUsage(r.body);
    return snapshot(account, ctx, plan: parsed.plan, source: 'web', windows: parsed.windows);
  }
}

// --------------------------------------------------------------------- Kiro

const _kiroTokenSql = "SELECT value FROM auth_kv WHERE key = 'kirocli:odic:token'";
const _kiroProfileSql = "SELECT value FROM state WHERE key = 'api.codewhisperer.profile'";

String? _cleanPath(String? raw, String? home) {
  final t = raw?.trim();
  if (t == null || t.isEmpty) return null;
  return t.startsWith('~') && home != null ? '$home${t.substring(1)}' : t;
}

/// `data.sqlite3` of kiro-cli: `KIRO_DATA_DIR`, then `XDG_DATA_HOME`, then `~/.local/share`.
String? kiroStateDbPath(String? dataDirOverride) {
  final home = platform.homeDirectory();
  final override = _cleanPath(dataDirOverride ?? platform.envVar('KIRO_DATA_DIR'), home);
  if (override != null) return platform.joinPath(override, 'data.sqlite3');
  final xdg = _cleanPath(platform.envVar('XDG_DATA_HOME'), home);
  final dataHome = xdg ?? (home == null ? null : platform.joinPath(home, '.local', 'share'));
  return dataHome == null ? null : platform.joinPath(dataHome, 'kiro-cli', 'data.sqlite3');
}

({String accessToken, String profileArn}) parseKiroIdentity(
  String? tokenJson,
  String? profileJson,
) {
  final token = asString(decodeJsonObject(tokenJson ?? '')?['access_token']);
  final arn = asString(decodeJsonObject(profileJson ?? '')?['arn']);
  if (token == null || arn == null) {
    throw ProviderException('未找到 Kiro CLI 登录', hint: '在终端运行 kiro-cli login，然后重试');
  }
  return (accessToken: token, profileArn: arn);
}

Uri kiroUsageEndpoint(String arn) {
  final parts = arn.split(':');
  final resource = parts.length >= 6 ? parts.sublist(5).join(':') : '';
  if (parts.length < 6 ||
      parts[0] != 'arn' ||
      parts[1] != 'aws' ||
      parts[2] != 'codewhisperer' ||
      !resource.startsWith('profile/') ||
      resource.length <= 'profile/'.length ||
      RegExp(r'[\s\x00-\x1f]').hasMatch(arn)) {
    throw ProviderException('Kiro 配置文件 ARN 无法识别', hint: '重新运行 kiro-cli login');
  }
  final url = switch (parts[3]) {
    'us-east-1' => 'https://codewhisperer.us-east-1.amazonaws.com/',
    'eu-central-1' => 'https://q.eu-central-1.amazonaws.com/',
    _ => null,
  };
  if (url == null) throw ProviderException('Kiro 区域 ${parts[3]} 暂不支持');
  return Uri.parse(url);
}

DateTime? _kiroReset(double? seconds) {
  if (seconds == null || seconds < 1000000000 || seconds > 4102444800) return null;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true);
}

({String? plan, List<RateWindow> windows, List<Credits> credits, Map<String, String> extras})
parseKiroUsageLimits(Map<String, Object?> json) {
  final credits = (asList(json['usageBreakdownList']) ?? const <Object?>[])
      .map(asMap)
      .nonNulls
      .where((m) => m['resourceType'] == 'CREDIT')
      .toList();
  if (credits.length != 1) {
    throw ProviderException('Kiro 用量数据格式已变化', hint: '在 Kiro 中查看用量，或更新 TokenBar');
  }
  final credit = credits.single;
  final planLimit = asDouble(credit['usageLimitWithPrecision']);
  final totalUsed = asDouble(credit['currentUsageWithPrecision']);
  final overageUsed = asDouble(credit['currentOveragesWithPrecision']) ?? 0;
  final hasBonus = (asList(credit['bonuses']) ?? const <Object?>[]).isNotEmpty;
  if (planLimit == null ||
      totalUsed == null ||
      planLimit < 0 ||
      overageUsed < 0 ||
      totalUsed < overageUsed) {
    throw ProviderException('Kiro 用量数据无效');
  }
  final planUsed = totalUsed - overageUsed;
  if (!hasBonus && planUsed > planLimit + 0.01) throw ProviderException('Kiro 用量数据无效');

  final overageStatus = asString(asMap(json['overageConfiguration'])?['overageStatus']);
  final overageCap = overageStatus == 'ENABLED'
      ? asDouble(credit['overageCapWithPrecision'])
      : null;
  final reset = _kiroReset(asDouble(credit['nextDateReset'] ?? json['nextDateReset']));
  final currency = asString(credit['currency']) ?? 'USD';
  final overageCharges = asDouble(credit['overageCharges']);
  final overageRate = asDouble(credit['overageRate']);

  final windows = <RateWindow>[];
  final rows = <Credits>[];
  if (!hasBonus && planLimit > 0) {
    windows.add(
      quotaWindow('kiro-credits', '套餐积分', usedPercent: pct(planUsed, planLimit), resetsAt: reset),
    );
    rows.add(
      Credits(
        id: 'kiro-credits-used',
        label: '套餐积分已用',
        used: planUsed,
        limit: planLimit,
        resetsAt: reset,
      ),
    );
  }
  if (overageCap != null && overageCap > 0) {
    windows.add(
      quotaWindow(
        'kiro-overage',
        '超额用量',
        usedPercent: pct(overageUsed, overageCap),
        resetsAt: reset,
      ),
    );
    if (overageCharges != null && overageRate != null && overageRate > 0) {
      rows.add(
        spendRow(
          'kiro-overage-cost',
          overageCharges,
          limit: overageCap * overageRate,
          label: '超额费用',
          currency: currency,
          resetsAt: reset,
        ),
      );
    }
  }
  final planName = asString(asMap(json['subscriptionInfo'])?['subscriptionTitle']);
  return (
    plan: planName == null ? null : _titleWords(planName),
    windows: windows,
    credits: rows,
    extras: hasBonus ? {'奖励积分': '已包含在内，套餐用量无法单独拆分'} : const {},
  );
}

class KiroProvider extends UsageProvider {
  @override
  String get id => 'kiro';

  @override
  String get displayName => 'Kiro';

  @override
  int get brandColor => 0xFF9046FF;

  @override
  List<SourceType> get supportedSources => const [SourceType.localCli];

  @override
  String get setupHint =>
      '仅桌面端：读取 kiro-cli 保存在本机数据库里的登录（只读，不刷新令牌）。需先在终端运行 kiro-cli login。'
      '账户的"本机目录"可填写 kiro-cli 数据目录（含 data.sqlite3）。';

  @override
  String get localSourceLabel => '本机 kiro-cli 登录';

  @override
  Future<bool> hasLocalLogin(AccountConfig account) async {
    final path = kiroStateDbPath(account.homeDir);
    return path != null && await platform.readSqliteText(path, _kiroTokenSql) != null;
  }

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final path = kiroStateDbPath(account.homeDir);
    if (path == null || !platform.localAccessSupported) {
      throw ProviderException('无法定位 Kiro CLI 数据目录', hint: '在账户的"本机目录"中填写 kiro-cli 数据目录');
    }
    final identity = parseKiroIdentity(
      await platform.readSqliteText(path, _kiroTokenSql),
      await platform.readSqliteText(path, _kiroProfileSql),
    );
    final json = await fetchJsonObject(
      ctx,
      displayName,
      kiroUsageEndpoint(identity.profileArn),
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-amz-json-1.0',
        'X-Amz-Target': 'AmazonCodeWhispererService.GetUsageLimits',
        'Authorization': 'Bearer ${identity.accessToken}',
      },
      body: {'profileArn': identity.profileArn},
      authHint: '登录已过期，在终端运行 kiro-cli login 重新登录',
      timeout: const Duration(seconds: 10),
    );
    final usage = parseKiroUsageLimits(json);
    return snapshot(
      account,
      ctx,
      plan: usage.plan,
      source: 'local',
      windows: usage.windows,
      credits: usage.credits,
      extras: usage.extras,
    );
  }
}

// --------------------------------------------------------------- JetBrains

const _jetBrainsIdes = [
  ('IntelliJIdea', 'IntelliJ IDEA'),
  ('PyCharm', 'PyCharm'),
  ('WebStorm', 'WebStorm'),
  ('GoLand', 'GoLand'),
  ('CLion', 'CLion'),
  ('DataGrip', 'DataGrip'),
  ('RubyMine', 'RubyMine'),
  ('Rider', 'Rider'),
  ('PhpStorm', 'PhpStorm'),
  ('AppCode', 'AppCode'),
  ('Fleet', 'Fleet'),
  ('AndroidStudio', 'Android Studio'),
  ('RustRover', 'RustRover'),
  ('Aqua', 'Aqua'),
  ('DataSpell', 'DataSpell'),
];

String? jetBrainsIdeName(String dirName) {
  final lower = dirName.toLowerCase();
  for (final (prefix, name) in _jetBrainsIdes) {
    if (!lower.startsWith(prefix.toLowerCase())) continue;
    final version = dirName.substring(prefix.length).trim();
    return version.isEmpty ? name : '$name $version';
  }
  return null;
}

String _xmlDecode(String s) => s
    .replaceAll('&#10;', '\n')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&apos;', "'");

String? _xmlOption(String component, String name) {
  final byName = RegExp(
    r'''<option[^>]*name\s*=\s*["']''' + name + r'''["'][^>]*value\s*=\s*["']([^"']*)["']''',
  ).firstMatch(component);
  if (byName != null) return byName[1];
  return RegExp(
    r'''<option[^>]*value\s*=\s*["']([^"']*)["'][^>]*name\s*=\s*["']''' + name + r'''["']''',
  ).firstMatch(component)?[1];
}

({String? type, List<RateWindow> windows, List<Credits> credits}) parseJetBrainsQuotaXml(
  String xml,
) {
  final component = RegExp(
    r'''<component[^>]*name\s*=\s*["']AIAssistantQuotaManager2["'][^>]*>([\s\S]*?)</component>''',
  ).firstMatch(xml)?.group(1);
  final quotaRaw = component == null ? null : _xmlOption(component, 'quotaInfo');
  if (quotaRaw == null) {
    throw ProviderException('JetBrains AI 配置中没有额度信息', hint: '在 IDE 中打开 AI Assistant 后再试');
  }
  final quota = decodeJsonObject(_xmlDecode(quotaRaw));
  if (quota == null) throw ProviderException('无法解析 JetBrains AI 额度数据');

  final nextRaw = component == null ? null : _xmlOption(component, 'nextRefill');
  final refill = nextRaw == null ? null : decodeJsonObject(_xmlDecode(nextRaw));
  final resetsAt = _utcDate(asString(refill?['next']));

  final tariff = asMap(quota['tariffQuota']);
  final useTariff =
      tariff != null && asDouble(tariff['current']) != null && asDouble(tariff['maximum']) != null;
  final source = (useTariff ? tariff : null) ?? quota;
  final used = asDouble(source['current']) ?? 0;
  final maximum = asDouble(source['maximum']) ?? 0;
  final usedPercent = maximum > 0 ? _clampPct(used / maximum * 100) : 0.0;

  final topUp = asMap(quota['topUpQuota']);
  final topMax = asDouble(topUp?['maximum']);
  final topAvailable = asDouble(topUp?['available']);
  return (
    type: asString(quota['type']),
    windows: [
      quotaWindow('jetbrains-monthly', '本月额度', usedPercent: usedPercent, resetsAt: resetsAt),
    ],
    credits: [
      if (topMax != null &&
          topMax.isFinite &&
          topMax > 0 &&
          topAvailable != null &&
          topAvailable >= 0)
        balanceRow(
          'jetbrains-topup',
          (topAvailable < topMax ? topAvailable : topMax) / 100000,
          label: '加油包剩余',
          currency: null,
        ),
    ],
  );
}

class JetBrainsProvider extends UsageProvider {
  @override
  String get id => 'jetbrains';

  @override
  String get displayName => 'JetBrains AI';

  @override
  int get brandColor => 0xFFFF3399;

  @override
  List<SourceType> get supportedSources => const [SourceType.localCli];

  @override
  List<ProviderField> get fields => const [];

  @override
  String get localSourceLabel => '本机 JetBrains IDE';

  @override
  String get setupHint =>
      '仅桌面端：读取 IDE 的 AI Assistant 额度文件（只读，无需网络）。'
      '账户的"本机目录"填写 IDE 配置目录，例如 %APPDATA%\\JetBrains\\IntelliJIdea2025.3（需含 options 子目录）。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final dir = account.homeDir?.trim();
    if (dir == null || dir.isEmpty) {
      throw ProviderException('未指定 JetBrains IDE 配置目录', hint: '在账户的"本机目录"中填写 IDE 配置目录');
    }
    final xml = platform.localAccessSupported
        ? await platform.readTextFile(
            platform.joinPath(dir, 'options', 'AIAssistantQuotaManager2.xml'),
          )
        : null;
    if (xml == null) {
      throw ProviderException('未找到 JetBrains AI 额度文件', hint: '确认目录正确，并在 IDE 中启用 AI Assistant');
    }
    final parsed = parseJetBrainsQuotaXml(xml);
    final dirName = dir.split(RegExp(r'[\\/]+')).where((s) => s.isNotEmpty).lastOrNull ?? '';
    final ide = jetBrainsIdeName(dirName);
    return snapshot(
      account,
      ctx,
      source: 'local',
      windows: parsed.windows,
      credits: parsed.credits,
      extras: {'IDE': ?ide, '额度类型': ?parsed.type},
    );
  }
}

// --------------------------------------------------------------------- Amp

const _ampAmount = r'([0-9][0-9,]*(?:\.[0-9]+)?)';
const _ampSubSuffix =
    r'\s*' +
    _ampAmount +
    r'\s*%\s+other\s+usage\s+and\s+' +
    _ampAmount +
    r'\s*%\s+orb\s+usage\s+remaining\s*-\s*resets\s+upon\s+renewal\s+in\s+([0-9][0-9,]*)\s+(days?|months?)(?:\s+-\s+https?://\S+)?\s*$';

String _ampClean(String raw) =>
    raw.replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '').replaceAll('**', '');

List<String>? _ampMatch(String text, String pattern) {
  final m = RegExp(pattern, multiLine: true, caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  return [for (var i = 1; i <= m.groupCount; i++) (m.group(i) ?? '').trim()];
}

List<List<String>> _ampAll(String text, String pattern) => [
  for (final m in RegExp(pattern, multiLine: true, caseSensitive: false).allMatches(text))
    [for (var i = 1; i <= m.groupCount; i++) (m.group(i) ?? '').trim()],
];

double? _ampNum(String? s) => s == null ? null : double.tryParse(s.replaceAll(',', ''));

({DateTime start, DateTime end})? _ampPeriod(String text) {
  final m = _ampMatch(text, r'\bperiod\s+(\d{4}-\d{2}-\d{2})\s+to\s+(\d{4}-\d{2}-\d{2})\b');
  if (m == null) return null;
  final start = _utcDate(m[0]);
  final end = _utcDate(m[1]);
  if (start == null || end == null || !end.isAfter(start)) return null;
  return (start: start, end: end);
}

DateTime _ampRenewal(DateTime now, int value, String unit) {
  final u = now.toUtc();
  return unit.toLowerCase().startsWith('month')
      ? DateTime.utc(u.year, u.month + value, u.day)
      : u.add(Duration(days: value));
}

/// Parses Amp's human-readable usage text (CLI output or API `displayText`).
({String? email, String? plan, List<RateWindow> windows, List<Credits> credits})
parseAmpDisplayText(String raw, DateTime now) {
  final text = _ampClean(raw);
  final identity = _ampMatch(text, r'^\s*Signed in as\s+([^\s(]+)(?:\s+\(([^\r\n)]+)\))?\s*$');
  final windows = <RateWindow>[];
  final credits = <Credits>[];
  String? plan;

  final freeAbs = _ampMatch(
    text,
    r'^\s*Amp Free:\s*\$?' +
        _ampAmount +
        r'\s*/\s*\$?' +
        _ampAmount +
        r'\s+remaining(?:\s*\(replenishes\s*\+\$?' +
        _ampAmount +
        r'\s*/\s*hour\))?',
  );
  final freePct = _ampMatch(text, r'^\s*Amp Free:\s*' + _ampAmount + r'\s*%\s+remaining');
  final freeRemaining = _ampNum(freeAbs?[0]);
  final freeQuota = _ampNum(freeAbs?[1]);
  if (freeRemaining != null && freeQuota != null && freeQuota > 0) {
    final hourly = _ampNum(freeAbs?[2]) ?? 0;
    final rounded = (freeQuota / hourly).round();
    final hours = hourly > 0 ? (rounded < 1 ? 1 : rounded) : null;
    windows.add(
      quotaWindow(
        'amp-free',
        '免费额度',
        usedPercent: pct(_nonNeg(freeQuota - freeRemaining), freeQuota),
        windowMinutes: hours == null ? null : hours * 60,
      ),
    );
  } else if (_ampNum(freePct?[0]) != null) {
    windows.add(
      quotaWindow(
        'amp-free',
        '免费额度',
        usedPercent: 100 - _clampPct(_ampNum(freePct![0])!),
        windowMinutes: 1440,
      ),
    );
  }

  final tier = _ampMatch(
    text,
    r'^\s*Amp\s+([^\r\n]+?)\s+Tier:\s*agent\s+usage\s+\$' +
        _ampAmount +
        r'\s+of\s+\$' +
        _ampAmount +
        r'\s+remaining\b([^\r\n]*?)resets\s+upon\s+renewal\s+in\s+([0-9][0-9,]*)\s+(days?|months?)\b',
  );
  final tierRemaining = _ampNum(tier?[1]);
  final tierLimit = _ampNum(tier?[2]);
  final legacy = tier != null
      ? null
      : _ampMatch(text, r'^\s*Subscription\s+(.+?):' + _ampSubSuffix) ??
            _ampMatch(text, r'^\s*Amp\s+(.+?)\s+Subscription:' + _ampSubSuffix);
  if (tier != null && tierRemaining != null && tierLimit != null && tierLimit > 0) {
    final period = _ampPeriod(tier[3]);
    final renewal = int.tryParse(tier[4].replaceAll(',', ''));
    final resetsAt = period?.end ?? (renewal == null ? null : _ampRenewal(now, renewal, tier[5]));
    final minutes = period?.end.difference(period.start).inMinutes;
    plan = tier[0];
    windows.add(
      quotaWindow(
        'amp-agent',
        'Agent 用量',
        usedPercent: pct(tierLimit - tierRemaining, tierLimit),
        resetsAt: resetsAt,
        windowMinutes: minutes,
      ),
    );
    final orb = _ampMatch(
      tier[3],
      r'\borb\s+usage\s+' +
          _ampAmount +
          r'h\s+of\s+' +
          _ampAmount +
          r'h\s+a1\.small\s+orb\s+hours\s+remaining\b',
    );
    final orbRemaining = _ampNum(orb?[0]);
    final orbLimit = _ampNum(orb?[1]);
    if (orbRemaining != null && orbLimit != null && orbLimit > 0) {
      windows.add(
        quotaWindow(
          'amp-orb',
          'Orb 用量',
          usedPercent: pct(orbLimit - orbRemaining, orbLimit),
          resetsAt: resetsAt,
        ),
      );
    }
  } else if (legacy != null && legacy.length == 5) {
    final other = _ampNum(legacy[1]);
    final orb = _ampNum(legacy[2]);
    final value = int.tryParse(legacy[3].replaceAll(',', ''));
    if (other != null && orb != null && value != null) {
      final resetsAt = _ampRenewal(now, value, legacy[4]);
      plan = legacy[0];
      windows.add(
        quotaWindow(
          'amp-agent',
          'Agent 用量',
          usedPercent: 100 - _clampPct(other),
          resetsAt: resetsAt,
        ),
      );
      windows.add(
        quotaWindow('amp-orb', 'Orb 用量', usedPercent: 100 - _clampPct(orb), resetsAt: resetsAt),
      );
    }
  }

  final individual = _ampNum(
    _ampMatch(text, r'^\s*Individual credits:\s*\$?' + _ampAmount + r'\s+remaining')?[0],
  );
  if (individual != null) {
    credits.add(balanceRow('amp-individual', individual, label: '个人余额', currency: 'USD'));
  }
  for (final w in _ampAll(text, r'^\s*Workspace\s+(.+?):\s*\$?' + _ampAmount + r'\s+remaining')) {
    final value = _ampNum(w[1]);
    if (w[0].isNotEmpty && value != null) {
      credits.add(
        balanceRow('amp-workspace-${w[0]}', value, label: 'Workspace ${w[0]}', currency: 'USD'),
      );
    }
  }

  if (windows.isEmpty && credits.isEmpty) {
    if (identity == null && RegExp(r'sign in|log in|login', caseSensitive: false).hasMatch(text)) {
      throw ProviderException('Amp 访问令牌无效或已过期', hint: '到 ampcode.com 的设置页重新生成访问令牌');
    }
    throw ProviderException('Amp 用量文本中没有可识别的额度', hint: '确认账户已开通 Amp Free 或订阅');
  }
  return (email: identity?[0], plan: plan, windows: windows, credits: credits);
}

class AmpProvider extends UsageProvider {
  @override
  String get id => 'amp';

  @override
  String get displayName => 'Amp';

  @override
  int get brandColor => 0xFFF34E3F;

  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];

  @override
  String get setupHint => '粘贴 ampcode.com 设置页的 Access Token，查询 Amp Free、订阅、个人与工作区余额。手机也能用。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(
      label: 'Access Token',
      envVars: ['AMP_API_KEY'],
      help: '在 ampcode.com 设置页生成的访问令牌',
    ),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final token = bareToken(FieldValues.of(this, account).secret);
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse('https://ampcode.com/api/internal?userDisplayBalanceInfo'),
      method: 'POST',
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: {'method': 'userDisplayBalanceInfo', 'params': <String, Object?>{}},
      timeout: const Duration(seconds: 15),
    );
    final json = asMap(r.json);
    final error = asMap(json?['error']);
    if (r.statusCode == 401 || r.statusCode == 403 || error?['code'] == 'auth-required') {
      throw ProviderException('Amp 访问令牌无效或已过期', hint: '到 ampcode.com 的设置页重新生成访问令牌后粘贴');
    }
    if (json?['ok'] == false) {
      throw ProviderException('Amp 返回错误: ${asString(error?['message']) ?? '未知错误'}');
    }
    checkStatus(displayName, r);
    final text = asString(asMap(json?['result'])?['displayText']);
    if (text == null) throw ProviderException('Amp 返回了空的用量文本');
    final usage = parseAmpDisplayText(text, ctx.now());
    return snapshot(
      account,
      ctx,
      plan: usage.plan,
      email: usage.email,
      source: 'api-key',
      windows: usage.windows,
      credits: usage.credits,
    );
  }
}

// --------------------------------------------------------------------- Kilo

Map<String, Object?>? _kiloData(Map<String, Object?>? entry) =>
    asMap(asMap(asMap(entry?['result'])?['data'])?['json']);

List<Map<String, Object?>?> kiloEntries(Object? json) {
  final items = switch (json) {
    List() => json,
    Map() => [for (var i = 0; i < 3; i++) json[i.toString()]],
    _ => const <Object?>[],
  };
  return [for (final e in items) asMap(e)];
}

Map<String, Object?> _kiloRequired(List<Map<String, Object?>?> entries, int i) {
  final entry = i < entries.length ? entries[i] : null;
  final error = asMap(entry?['error']);
  if (error != null) {
    final message =
        asString(asMap(error['json'])?['message']) ?? asString(error['message']) ?? '未知错误';
    throw ProviderException('Kilo 返回错误: $message');
  }
  final data = _kiloData(entry);
  if (data == null) throw ProviderException('Kilo 返回了无法识别的数据');
  return data;
}

({String? plan, List<RateWindow> windows, List<Credits> credits}) parseKiloUsage(
  List<Map<String, Object?>?> entries,
) {
  final credit = _kiloRequired(entries, 0);
  final pass = _kiloRequired(entries, 1);
  final topUp = _kiloData(entries.length > 2 ? entries[2] : null);

  final blocks = (asList(credit['creditBlocks']) ?? asList(credit['blocks']) ?? const <Object?>[])
      .map(asMap)
      .nonNulls
      .toList();
  var used = 0.0;
  var total = 0.0;
  for (final b in blocks) {
    final micro = asDouble(b['amount_mUsd']);
    double? blockUsed;
    double? blockTotal;
    if (micro != null) {
      blockTotal = micro / 1e6;
      blockUsed = _nonNeg(blockTotal - (asDouble(b['balance_mUsd']) ?? 0) / 1e6);
    } else {
      blockUsed = asDouble(
        pick(b, const ['usedCredits', 'used', 'consumed', 'spent', 'creditsUsed']),
      );
      final remaining = asDouble(
        pick(b, const ['remainingCredits', 'remaining', 'creditsRemaining']),
      );
      blockTotal =
          asDouble(pick(b, const ['totalCredits', 'total', 'creditsTotal', 'limit'])) ??
          (blockUsed != null && remaining != null ? blockUsed + remaining : null);
    }
    if (blockUsed != null && blockTotal != null) {
      used += blockUsed;
      total += blockTotal;
    }
  }
  if (blocks.isEmpty) {
    final balance = asDouble(credit['totalBalance_mUsd']);
    if (balance == null) throw ProviderException('Kilo 返回的积分数据无法识别');
    total = balance / 1e6;
  }
  final remaining = _nonNeg(total - used);

  final windows = <RateWindow>[quotaWindow('kilo-credits', '积分', usedPercent: pct(used, total))];
  final rows = <Credits>[balanceRow('kilo-balance', remaining, label: '剩余积分', currency: 'USD')];

  final sub =
      asMap(pass['subscription']) ??
      (pass.containsKey('currentPeriodUsageUsd') ||
              pass.containsKey('currentPeriodBaseCreditsUsd') ||
              pass.containsKey('currentPeriodBonusCreditsUsd')
          ? pass
          : null);
  if (sub != null) {
    final passUsed = _nonNeg(asDouble(sub['currentPeriodUsageUsd']) ?? 0);
    final base = _nonNeg(asDouble(sub['currentPeriodBaseCreditsUsd']) ?? 0);
    final bonus = _nonNeg(asDouble(sub['currentPeriodBonusCreditsUsd']) ?? 0);
    final passTotal = base + bonus;
    final resetsAt = [
      sub['nextBillingAt'],
      sub['nextRenewalAt'],
      sub['renewsAt'],
      sub['renewAt'],
    ].map(parseFlexibleDate).nonNulls.firstOrNull;
    windows.add(
      quotaWindow(
        'kilo-pass',
        'Kilo Pass',
        usedPercent: pct(passUsed, passTotal),
        resetsAt: resetsAt,
      ),
    );
    rows.add(
      spendRow(
        'kilo-pass-spend',
        passUsed,
        limit: passTotal,
        label: 'Kilo Pass 本周期',
        resetsAt: resetsAt,
      ),
    );
  }

  final planName =
      asString(asMap(pass['plan'])?['name']) ??
      asString(pass['planName']) ??
      asString(pass['tier']) ??
      asString(pass['tierName']) ??
      asString(pass['passName']) ??
      asString(pass['subscriptionName']) ??
      asString(asMap(sub?['plan'])?['name']);
  final autoTopUp = asBool(topUp?['enabled']) == true;
  final plan = [planName, if (autoTopUp) '自动充值'].whereType<String>().join(' · ');
  return (plan: plan.isEmpty ? null : plan, windows: windows, credits: rows);
}

class KiloProvider extends UsageProvider {
  @override
  String get id => 'kilo';

  @override
  String get displayName => 'Kilo';

  @override
  int get brandColor => 0xFFF27027;

  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey, SourceType.localCli];

  @override
  String get setupHint =>
      '粘贴 Kilo API Key（apiKey 模式），或在桌面端选择"本机登录"读取 kilo auth login 保存的 ~/.local/share/kilo/auth.json（只读）。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(
      label: 'API Key',
      envVars: ['KILO_API_KEY'],
      help: '在 kilo.ai 账户设置中生成的 API Key',
    ),
    ProviderField(
      key: 'orgId',
      label: '组织 ID',
      kind: FieldKind.text,
      required: false,
      hint: '个人账户留空',
    ),
  ];

  @override
  String get localSourceLabel => '本机 Kilo CLI 登录';

  @override
  Future<bool> hasLocalLogin(AccountConfig account) async {
    try {
      await _cliToken(account);
      return true;
    } on ProviderException {
      return false;
    }
  }

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final values = FieldValues.of(this, account);
    final isApiKey = account.sourceType == SourceType.apiKey;
    final token = isApiKey ? bareToken(values.secret) : await _cliToken(account);
    final org = values['orgId'];
    final uri = Uri.https(
      'app.kilo.ai',
      '/api/trpc/user.getCreditBlocks,kiloPass.getState,user.getAutoTopUpPaymentMethod',
      {
        'batch': '1',
        'input': jsonEncode({
          '0': {'json': null},
          '1': {'json': null},
          '2': {'json': null},
        }),
      },
    );
    final r = await sendRequest(
      ctx,
      displayName,
      uri,
      headers: {'Authorization': 'Bearer $token', 'X-KILOCODE-ORGANIZATIONID': ?org},
      timeout: const Duration(seconds: 15),
    );
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw ProviderException(
        'Kilo 认证失败 (HTTP ${r.statusCode})',
        hint: isApiKey ? '检查 API Key 是否正确' : '在终端运行 kilo auth login 重新登录',
        statusCode: r.statusCode,
      );
    }
    checkStatus(displayName, r);
    final usage = parseKiloUsage(kiloEntries(r.json));
    return snapshot(
      account,
      ctx,
      plan: usage.plan,
      source: isApiKey ? 'api-key' : 'local',
      windows: usage.windows,
      credits: usage.credits,
    );
  }

  Future<String> _cliToken(AccountConfig account) async {
    final home = account.homeDir ?? platform.homeDirectory();
    final path = home == null || !platform.localAccessSupported
        ? null
        : platform.joinPath(platform.joinPath(home, '.local', 'share'), 'kilo', 'auth.json');
    final text = path == null ? null : await platform.readTextFile(path);
    if (text == null) {
      throw ProviderException('未找到 Kilo CLI 登录', hint: '在终端运行 kilo auth login');
    }
    final token = asString(asMap(decodeJsonObject(text)?['kilo'])?['access']);
    if (token == null) {
      throw ProviderException('Kilo CLI 登录文件无效', hint: '在终端运行 kilo auth login 重新登录');
    }
    return token;
  }
}

// -------------------------------------------------------------------- Hyper

final _hyperTeamLink = RegExp(
  r'/teams/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
);
final _hyperSessionBalance = RegExp(
  r'Hypercredits Available[\s\S]{0,400}?text-5xl font-bold">\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*<',
);

double? parseHyperSessionBalance(String html) {
  final m = _hyperSessionBalance.firstMatch(html);
  return m == null ? null : double.tryParse(m[1]!.replaceAll(',', ''));
}

Credits _hyperCredit(double balance) =>
    Credits(id: 'hyper-balance', label: '余额 (HC)', balance: balance);

class HyperProvider extends UsageProvider {
  @override
  String get id => 'hyper';

  @override
  String get displayName => 'Charm Hyper';

  @override
  int get brandColor => 0xFFFF60FF;

  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];

  @override
  String get setupHint =>
      '填写 Charm Hyper API Key，或粘贴 hyper.charm.land 的 Cookie（二者都填时优先 Cookie）。查询 Hypercredits 余额。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(
      label: 'API Key',
      required: false,
      envVars: ['HYPER_API_KEY'],
      help: '用于 /v1/credits，仅发送到 hyper.charm.land',
    ),
    ProviderField(
      key: 'cookie',
      label: 'hyper.charm.land Cookie',
      kind: FieldKind.secret,
      required: false,
      multiline: true,
      hint: 'session=...',
      help: '浏览器登录 hyper.charm.land → 开发者工具 → 网络 → 任一请求的 Cookie 请求头',
    ),
  ];

  @override
  String? validateManual(FieldValues values) =>
      values[ProviderField.secretKey] == null && values['cookie'] == null
      ? '需要填写 API Key 或 Cookie'
      : null;

  @override
  String get manualSourceLabel => '手动填写 Key / Cookie';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final values = FieldValues.of(this, account);
    final rawKey = values[ProviderField.secretKey];
    final key = rawKey == null ? null : bareToken(rawKey);
    final cookie = values['cookie'];
    if (key == null && cookie == null) {
      throw ProviderException(
        '未填写 Charm Hyper 凭证',
        hint: '登录 hyper.charm.land 后粘贴 Cookie，或填写 API Key',
      );
    }
    if (cookie != null) {
      double? balance;
      try {
        balance = await _sessionBalance(ctx, cookie);
      } on ProviderException {
        if (key == null) rethrow;
      }
      if (balance != null) {
        return snapshot(account, ctx, source: 'web', credits: [_hyperCredit(balance)]);
      }
      if (key == null) {
        throw ProviderException('Charm Hyper 会话已过期', hint: '重新复制 hyper.charm.land 的 Cookie 后粘贴');
      }
    }
    if (key == null) throw ProviderException('未填写 Charm Hyper API Key');
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse('https://hyper.charm.land/v1/credits'),
      headers: {'Authorization': 'Bearer $key'},
      timeout: const Duration(seconds: 10),
    );
    if (r.statusCode == 401) {
      throw ProviderException(
        'Charm Hyper API Key 被拒绝 (HTTP 401)',
        hint: '检查 API Key 是否正确',
        statusCode: 401,
      );
    }
    if (r.statusCode == 403) {
      throw ProviderException('Charm Hyper API Key 无权访问额度 (HTTP 403)', statusCode: 403);
    }
    if (r.statusCode == 429) {
      throw ProviderException('Charm Hyper 额度请求过于频繁 (HTTP 429)', hint: '稍后再试', statusCode: 429);
    }
    checkStatus(displayName, r);
    final balance = asMap(r.json)?['balance'];
    if (balance is! num || !balance.isFinite || balance < 0) {
      throw ProviderException('Charm Hyper 返回的余额不是非负数字');
    }
    return snapshot(account, ctx, source: 'api-key', credits: [_hyperCredit(balance.toDouble())]);
  }

  Future<double?> _sessionBalance(FetchContext ctx, String cookie) async {
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse('https://hyper.charm.land/'),
      headers: {'Cookie': normalizeCookieHeader(cookie), 'Accept': 'text/html'},
      timeout: const Duration(seconds: 8),
    );
    final rejected =
        r.statusCode == 401 ||
        r.statusCode == 403 ||
        (r.statusCode >= 300 && r.statusCode < 400) ||
        (r.statusCode == 200 && !_hyperTeamLink.hasMatch(r.body));
    if (rejected) return null;
    checkStatus(displayName, r);
    final balance = parseHyperSessionBalance(r.body);
    if (balance == null) {
      throw ProviderException(
        'Charm Hyper 仪表盘中找不到余额',
        hint: '确认 Cookie 来自 hyper.charm.land 的仪表盘页面',
      );
    }
    return balance;
  }
}

// ----------------------------------------------------------------- Registry

/// Providers in this group. The lead registers them in `ProviderRegistry`.
final List<UsageProvider> localAuthAProviders = [
  CopilotProvider(),
  GeminiProvider(),
  KiroProvider(),
  JetBrainsProvider(),
  AmpProvider(),
  KiloProvider(),
  HyperProvider(),
];
