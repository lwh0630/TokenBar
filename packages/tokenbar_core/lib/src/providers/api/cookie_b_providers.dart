import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../models/account.dart';
import '../../models/credits.dart';
import '../../models/rate_window.dart';
import '../../models/usage_snapshot.dart';
import '../../util/json_utils.dart';
import '../common.dart';
import '../fields.dart';
import '../http_support.dart';
import '../provider.dart';

const _chromeUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';
const _safariUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3 Safari/605.1.15';
const _linuxUa =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36';
const _formType = 'application/x-www-form-urlencoded';

typedef _Usage = ({String? plan, List<RateWindow> windows, Map<String, String> extras});

// ----------------------------------------------------------------- shared

Map<String, String> _cookiePairs(String header) {
  final pairs = <String, String>{};
  for (final part in header.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final name = part.substring(0, i).trim();
    final value = part.substring(i + 1).trim();
    if (name.isNotEmpty && value.isNotEmpty) pairs.putIfAbsent(name, () => value);
  }
  return pairs;
}

/// Keeps only the named cookies, in header order.
String _keepCookies(String header, Set<String> names) {
  final kept = <String>[];
  for (final part in header.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    if (names.contains(part.substring(0, i).trim())) kept.add(part.trim());
  }
  return kept.join('; ');
}

String? _cookieProblem(String header, List<String> required) {
  if (header.isEmpty) return '请粘贴 Cookie 请求头';
  final names = _cookiePairs(header);
  final missing = [
    for (final n in required)
      if (!names.containsKey(n)) n,
  ];
  return missing.isEmpty ? null : '缺少 ${missing.join('、')}';
}

/// Cookie-only providers: the user pastes a Cookie header; nothing is read locally.
abstract class _CookieProvider extends UsageProvider {
  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];

  @override
  String get manualSourceLabel => '手动粘贴 Cookie';

  String? cookieProblem(String header) => _cookieProblem(header, const []);

  @override
  String? validateManual(FieldValues values) =>
      cookieProblem(normalizeCookieHeader(values[ProviderField.secretKey] ?? ''));

  String cookieOf(AccountConfig account) {
    final header = normalizeCookieHeader(FieldValues.of(this, account).secret);
    final problem = cookieProblem(header);
    if (problem != null) throw ProviderException('$displayName $problem', hint: setupHint);
    return header;
  }
}

ProviderException _loginRequired(String provider) =>
    ProviderException('$provider 需要重新登录', hint: '在对应控制台重新登录后，粘贴新的 Cookie 请求头', statusCode: 401);

/// Fixed-decimal grouping used by the console labels (e.g. `5,000`, `11.97`).
String _groupNum(double v) {
  var text = v.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  final negative = text.startsWith('-');
  if (negative) text = text.substring(1);
  final parts = text.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  final joined = parts.length > 1 ? '$whole.${parts[1]}' : whole;
  return negative ? '-$joined' : joined;
}

String _capitalized(String text) => text
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

String _monthDay(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

/// Parses `yyyy-MM-dd[ HH:mm[:ss]]` as UTC; other values go through [parseFlexibleDate].
DateTime? _plainDate(Object? value) {
  if (value is! String) return parseFlexibleDate(value);
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$')
      .firstMatch(value.trim());
  if (m == null) return parseFlexibleDate(value);
  return DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4] ?? '0'),
    int.parse(m[5] ?? '0'),
    int.parse(m[6] ?? '0'),
  );
}

/// Recursively expands string values that are themselves JSON objects/arrays.
Object? _expandEmbedded(Object? value) {
  if (value is String) {
    final text = value.trim();
    if (!(text.startsWith('{') || text.startsWith('['))) return value;
    try {
      return _expandEmbedded(jsonDecode(text));
    } on FormatException {
      return value;
    }
  }
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), _expandEmbedded(v)));
  if (value is List) return value.map(_expandEmbedded).toList();
  return value;
}

/// Breadth-first search for [key] (case-insensitive). Keys are tried in order,
/// so earlier keys take priority over later ones anywhere in the tree.
T? _firstAcross<T>(Object? root, List<String> keys, T? Function(Object?) convert) {
  for (final key in keys) {
    final lower = key.toLowerCase();
    final queue = <Object?>[root];
    for (var i = 0; i < queue.length; i++) {
      final node = queue[i];
      if (node is Map) {
        for (final e in node.entries) {
          if (e.key.toString().toLowerCase() != lower) continue;
          final hit = convert(e.value);
          if (hit != null) return hit;
        }
        queue.addAll(node.values);
      } else if (node is List) {
        queue.addAll(node);
      }
    }
  }
  return null;
}

Object? _decodeJsonOr(String text, String message) {
  try {
    return jsonDecode(text);
  } on FormatException {
    throw ProviderException(message);
  }
}

Object? _firstKeyValue(Map<String, Object?>? m, List<String> keys) {
  if (m == null) return null;
  for (final key in keys) {
    final v = m[key];
    if (v != null) return v;
  }
  return null;
}

double? _firstKeyNum(Map<String, Object?>? m, List<String> keys) =>
    asDouble(_firstKeyValue(m, keys));

String? _firstKeyString(Map<String, Object?>? m, List<String> keys) =>
    asString(_firstKeyValue(m, keys));

double? _finite(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

bool _truthy(Object? v) =>
    v == true ||
    v == 1 ||
    (v is String && const {'true', '1', 'yes', 'active', 'valid'}.contains(v.trim().toLowerCase()));

double? _digitsNumber(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String && RegExp(r'^\d+(?:\.\d+)?$').hasMatch(v)) return double.tryParse(v);
  return null;
}

String _traceId() {
  final rnd = Random.secure();
  String hex(int n) => List.generate(n, (_) => rnd.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + rnd.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
}

String? _header(Map<String, String> headers, String name) {
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == name) return e.value;
  }
  return null;
}

/// Like [sendRequest] but never follows redirects, so a login bounce is visible.
Future<HttpResult> _sendNoRedirect(
  FetchContext ctx,
  String provider,
  Uri url, {
  String method = 'GET',
  Map<String, String> headers = const {},
  String? body,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final request = http.Request(method, url)
    ..followRedirects = false
    ..headers.addAll({'Accept': 'application/json', ...headers});
  if (body != null) request.body = body;
  try {
    final streamed = await ctx.client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    return HttpResult(
      response.statusCode,
      utf8.decode(response.bodyBytes, allowMalformed: true),
      response.headers,
    );
  } on TimeoutException {
    throw ProviderException('$provider 请求超时', hint: '检查网络后重试');
  } on http.ClientException catch (e) {
    throw ProviderException('$provider 网络错误: ${e.message}', hint: '检查网络或代理设置');
  }
}

// ------------------------------------------------------------- Xiaomi MiMo

const _mimoBase = 'https://platform.xiaomimimo.com/api/v1';

class MiMoProvider extends _CookieProvider {
  @override
  String get id => 'mimo';
  @override
  String get displayName => 'Xiaomi MiMo';
  @override
  int get brandColor => 0xFFFF6900;
  @override
  String get setupHint =>
      '浏览器登录 platform.xiaomimimo.com，在开发者工具里复制任一请求的 Cookie 请求头（需包含 api-platform_serviceToken 与 userId），查询余额与 Token Plan 用量。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(
      label: 'platform.xiaomimimo.com Cookie',
      hint: 'api-platform_serviceToken=...; userId=...',
    ),
  ];

  @override
  String? cookieProblem(String header) =>
      _cookieProblem(header, const ['api-platform_serviceToken', 'userId']);

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final headers = {
      'Accept': 'application/json, text/plain, */*',
      'Cookie': _keepCookies(cookieOf(account), const {
        'api-platform_serviceToken',
        'userId',
        'api-platform_ph',
        'api-platform_slh',
      }),
      'Accept-Language': 'en-US,en;q=0.9',
      'x-timeZone': 'UTC+01:00',
      'Origin': 'https://platform.xiaomimimo.com',
      'Referer': 'https://platform.xiaomimimo.com/#/console/balance',
      'User-Agent': _chromeUa,
    };
    final balance = parseMiMoBalance(await _mimoGet(ctx, '$_mimoBase/balance', headers));
    final plan = parseMiMoPlan(await _mimoOptional(ctx, '$_mimoBase/tokenPlan/detail', headers));
    final tokens = parseMiMoTokenUsage(
      await _mimoOptional(ctx, '$_mimoBase/tokenPlan/usage', headers),
    );
    final cash = balance.cash;
    final gift = balance.gift;
    final planCode = plan.planCode;
    final planExpired =
        plan.expired || (plan.periodEnd != null && !plan.periodEnd!.isAfter(ctx.now()));
    return snapshot(
      account,
      ctx,
      plan: planCode == null ? null : _capitalized(planCode),
      source: 'web',
      windows: [
        if (tokens.limit > 0 && !planExpired)
          quotaWindow(
            'mimo-plan',
            '套餐额度',
            usedPercent: (tokens.percent * 100).clamp(0, 100).toDouble(),
            resetsAt: plan.periodEnd,
            windowMinutes: plan.periodEnd == null ? null : 43200,
          ),
      ],
      credits: [
        balanceRow('mimo-balance', balance.balance, label: '余额', currency: balance.currency),
      ],
      extras: {
        if (tokens.limit > 0)
          '套餐用量':
              '${_groupNum(tokens.used.toDouble())} / ${_groupNum(tokens.limit.toDouble())} Credits',
        if (cash != null && gift != null)
          '余额明细':
              'Paid: ${moneyText(cash, balance.currency)} / Granted: ${moneyText(gift, balance.currency)}',
        if (planExpired) '套餐状态': '已过期',
      },
    );
  }

  Future<Map<String, Object?>> _mimoGet(
    FetchContext ctx,
    String url,
    Map<String, String> headers,
  ) async {
    final r = await _sendNoRedirect(
      ctx,
      displayName,
      Uri.parse(url),
      headers: headers,
      timeout: const Duration(seconds: 20),
    );
    if (r.statusCode == 401 || (r.statusCode >= 300 && r.statusCode < 400)) {
      throw ProviderException(
        'Xiaomi MiMo 登录已过期',
        hint: '在 platform.xiaomimimo.com 重新登录后复制 Cookie',
        statusCode: 401,
      );
    }
    if (r.statusCode == 403) {
      throw ProviderException(
        'Xiaomi MiMo 拒绝了这个 Cookie',
        hint: '重新复制 platform.xiaomimimo.com 的 Cookie',
        statusCode: 403,
      );
    }
    if (!r.ok) {
      throw ProviderException('Xiaomi MiMo 接口错误 HTTP ${r.statusCode}', statusCode: r.statusCode);
    }
    return asMap(r.json) ?? (throw ProviderException('Xiaomi MiMo 返回了无法解析的数据'));
  }

  /// Plan detail and usage are optional: a failure just hides that part.
  Future<Map<String, Object?>?> _mimoOptional(
    FetchContext ctx,
    String url,
    Map<String, String> headers,
  ) async {
    try {
      return await _mimoGet(ctx, url, headers);
    } on ProviderException {
      return null;
    }
  }
}

ProviderException _mimoCodeError(int? code, String? message) => switch (code) {
  401 => ProviderException(
    'Xiaomi MiMo 登录已过期',
    hint: '在 platform.xiaomimimo.com 重新登录后复制 Cookie',
    statusCode: 401,
  ),
  403 => ProviderException(
    'Xiaomi MiMo 拒绝了这个 Cookie',
    hint: '重新复制 platform.xiaomimimo.com 的 Cookie',
    statusCode: 403,
  ),
  _ => ProviderException('Xiaomi MiMo 返回错误: ${message ?? 'code $code'}'),
};

({double balance, String currency, double? cash, double? gift}) parseMiMoBalance(
  Map<String, Object?> json,
) {
  final code = asInt(json['code']);
  if (code != 0) throw _mimoCodeError(code, asString(json['message']));
  final data = asMap(json['data']) ?? (throw ProviderException('Xiaomi MiMo 返回中没有余额数据'));
  final balance = asDouble(data['balance']) ?? (throw ProviderException('Xiaomi MiMo 余额格式无效'));
  final currency = asString(data['currency']) ?? (throw ProviderException('Xiaomi MiMo 缺少币种'));
  return (
    balance: balance,
    currency: currency,
    cash: asDouble(data['cashBalance']),
    gift: asDouble(data['giftBalance']),
  );
}

({String? planCode, DateTime? periodEnd, bool expired}) parseMiMoPlan(Map<String, Object?>? json) {
  final data = json == null || asInt(json['code']) != 0 ? null : asMap(json['data']);
  if (data == null) return (planCode: null, periodEnd: null, expired: false);
  return (
    planCode: asString(data['planCode']),
    periodEnd: _plainDate(asString(data['currentPeriodEnd'])),
    expired: data['expired'] == true,
  );
}

({int used, int limit, double percent}) parseMiMoTokenUsage(Map<String, Object?>? json) {
  const none = (used: 0, limit: 0, percent: 0.0);
  if (json == null || asInt(json['code']) != 0) return none;
  final items = asList(asMap(asMap(json['data'])?['monthUsage'])?['items']);
  final item = asMap(items?.firstOrNull);
  if (item == null) return none;
  final used = asInt(item['used']);
  final limit = asInt(item['limit']);
  final percent = asDouble(item['percent']);
  if (used == null || limit == null || percent == null || !percent.isFinite) return none;
  return (used: used, limit: limit, percent: percent);
}

// ------------------------------------------------------------------- Sakana

class SakanaProvider extends _CookieProvider {
  @override
  String get id => 'sakana';
  @override
  String get displayName => 'Sakana AI';
  @override
  int get brandColor => 0xFF2975DB;
  @override
  String get setupHint =>
      '浏览器登录 console.sakana.ai，打开 Billing 页面，在开发者工具里复制请求的 Cookie 请求头，查询 5 小时 / 每周额度。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(label: 'console.sakana.ai Cookie', hint: 'Cookie: ...'),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final cookie = cookieOf(account);
    final headers = {
      'Cookie': cookie,
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    final page = await _sendNoRedirect(
      ctx,
      displayName,
      Uri.parse('https://console.sakana.ai/billing'),
      headers: headers,
    );
    if (page.statusCode == 401 ||
        page.statusCode == 403 ||
        (page.statusCode >= 300 && page.statusCode < 400)) {
      throw ProviderException('Sakana 需要重新登录', hint: '重新从浏览器复制 Cookie 请求头', statusCode: 401);
    }
    if (page.statusCode != 200) {
      throw ProviderException(
        'Sakana 账单页请求失败 (HTTP ${page.statusCode})',
        statusCode: page.statusCode,
      );
    }
    final billing = parseSakanaBilling(page.body);
    var payg = const <Credits>[];
    try {
      final optional = await _sendNoRedirect(
        ctx,
        displayName,
        Uri.parse('https://console.sakana.ai/billing?tab=payAsYouGo'),
        headers: headers,
        timeout: const Duration(seconds: 5),
      );
      if (optional.statusCode == 200) payg = parseSakanaPayAsYouGo(optional.body);
    } on ProviderException {
      payg = const <Credits>[];
    }
    return snapshot(
      account,
      ctx,
      plan: billing.plan,
      source: 'web',
      windows: billing.windows,
      credits: payg,
    );
  }
}

({List<RateWindow> windows, String? plan}) parseSakanaBilling(String html) {
  if (html.isEmpty) throw ProviderException('Sakana 账单页面解析失败: 页面为空');
  final primary = _sakanaWindow(html, '5-hour', RateWindow.sessionId, '5 小时', 300);
  final secondary = _sakanaWindow(html, 'Weekly', RateWindow.weeklyId, '每周', 10080);
  if (primary == null && secondary == null) {
    throw ProviderException('Sakana 账单页面解析失败: 未找到用量窗口');
  }
  final plan = _capture(
    r'''<div[^>]*data-slot="card-title"[^>]*>[\s\S]*?<span>\s*([^<]+?)\s*</span>''',
    html,
  );
  final price = _capture(
    r'''<div[^>]*data-slot="card-title"[^>]*>[\s\S]*?<span>[^<]+</span>\s*<span[^>]*>\s*([^<]+?)\s*</span>''',
    html,
  );
  final loginMethod = [?plan, ?price].join(' ');
  return (windows: [?primary, ?secondary], plan: loginMethod.isEmpty ? null : loginMethod);
}

String? _capture(String pattern, String text) {
  final value = RegExp(pattern, caseSensitive: false).firstMatch(text)?.group(1)?.trim();
  return value == null || value.isEmpty ? null : value;
}

RateWindow? _sakanaWindow(String html, String label, String id, String title, int minutes) {
  final match = RegExp(
    '<p[^>]*>\\s*${RegExp.escape(label)}\\s*</p>',
    caseSensitive: false,
  ).firstMatch(html);
  if (match == null) return null;
  final rest = html.substring(match.end);
  final boundary = RegExp(
    r'''<p[^>]*>\s*(?:5-hour|Weekly)\s*</p>|<div[^>]*data-slot=(?:"card"|'card'|"card-title"|'card-title')[^>]*>''',
    caseSensitive: false,
  ).firstMatch(rest);
  final body = rest.substring(0, boundary?.start ?? rest.length).trim();
  if (body.isEmpty) return null;
  final used = double.tryParse(
    _capture(r'<p[^>]*>\s*([0-9]+(?:\.[0-9]+)?)% used\s*</p>', body) ?? '',
  );
  if (used == null || used < 0 || used > 100) {
    throw ProviderException('Sakana 账单页面解析失败: $label 用量百分比无效');
  }
  return quotaWindow(
    id,
    title,
    usedPercent: used,
    resetsAt: _sakanaResetDate(_capture(r'<p[^>]*>\s*Resets on ([^<]+?)\s*</p>', body)),
    windowMinutes: minutes,
  );
}

DateTime? _sakanaResetDate(String? text) {
  final m = RegExp(
    r'^(\w+) (\d{1,2}), (\d{4}) at (\d{1,2}):(\d{2}) (AM|PM)$',
    caseSensitive: false,
  ).firstMatch(text ?? '');
  if (m == null) return null;
  const months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];
  final month = months.indexOf(m[1]!.toLowerCase());
  final day = int.parse(m[2]!);
  final hour = int.parse(m[4]!);
  final minute = int.parse(m[5]!);
  if (month < 0 || hour < 1 || hour > 12 || minute > 59) return null;
  final pm = m[6]!.toUpperCase() == 'PM';
  final date = DateTime.utc(int.parse(m[3]!), month + 1, day, hour % 12 + (pm ? 12 : 0), minute);
  return date.month == month + 1 && date.day == day ? date : null;
}

List<Credits> parseSakanaPayAsYouGo(String html) {
  double? amount(String? v) => v == null ? null : double.tryParse(v.replaceAll(',', ''));
  final balance = amount(
    _capture(
      r'<h2[^>]*>\s*Credit balance\s*</h2>[\s\S]{0,900}?<p[^>]*tabular-nums[^"]*"[^>]*>\$?([0-9][0-9,]*(?:\.[0-9]+)?)</p>',
      html,
    ),
  );
  if (balance == null || !balance.isFinite) return const <Credits>[];
  final usage = amount(
    _capture(
      r'<h2[^>]*>\s*Usage\s*</h2>\s*<span[^>]*>\s*Total(?:<!--\s*-->)?:\s*(?:<!--\s*-->)?\$?([0-9][0-9,]*(?:\.[0-9]+)?)\s*</span>',
      html,
    ),
  );
  final period = _capture(
    r'aria-label="Usage date range"[^>]*>([\s\S]*?)</button>',
    html,
  )?.replaceAll(RegExp('<!--.*?-->'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return [
    balanceRow('sakana-balance', balance, label: '预付余额'),
    if (usage != null && usage.isFinite)
      spendRow(
        'sakana-usage',
        usage,
        label: period == null || period.isEmpty ? '按量用量' : '按量用量 ($period)',
      ),
  ];
}

// ------------------------------------------------------------------ Raycast

class RaycastProvider extends _CookieProvider {
  @override
  String get id => 'raycast';
  @override
  String get displayName => 'Raycast';
  @override
  int get brandColor => 0xFFFF6363;
  @override
  String get setupHint =>
      '浏览器登录 www.raycast.com，打开 settings 页面，在开发者工具里复制 Cookie 请求头（需包含 __raycast_session），查询 AI credits 余额。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(label: 'raycast.com Cookie', hint: '__raycast_session=…; csrf_token=…'),
  ];

  @override
  String? cookieProblem(String header) => _cookieProblem(header, const ['__raycast_session']);

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final cookie = _keepCookies(cookieOf(account), const {'__raycast_session', 'csrf_token'});
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse('https://www.raycast.com/frontend_api/current_user/ai_credits'),
      headers: {
        'Cookie': cookie,
        'Accept': 'application/json',
        'Origin': 'https://www.raycast.com',
        'Referer': 'https://www.raycast.com/settings',
        'User-Agent': _chromeUa,
      },
      timeout: const Duration(seconds: 15),
    );
    if (r.statusCode == 401) {
      throw ProviderException(
        'Raycast 网站登录已过期',
        hint: '在 www.raycast.com/settings 重新登录后复制 Cookie',
        statusCode: 401,
      );
    }
    if (r.statusCode == 403) {
      throw ProviderException('这个账户无权查看 Raycast AI credits', statusCode: 403);
    }
    if (r.statusCode == 429) {
      throw ProviderException('Raycast credits 请求过于频繁', hint: '稍后再试', statusCode: 429);
    }
    if (r.statusCode >= 500) {
      throw ProviderException('Raycast credits 接口暂不可用 (HTTP ${r.statusCode})');
    }
    if (!r.ok) {
      throw ProviderException(
        'Raycast credits 接口返回 HTTP ${r.statusCode}',
        statusCode: r.statusCode,
      );
    }

    final c = parseRaycastCredits(r.body);
    final remaining = c.remaining;
    final total = c.total;
    final renewal = c.renewal;
    final windows = <RateWindow>[];
    final credits = <Credits>[];
    final extras = <String, String>{};
    if (remaining != null && total != null && total > 0) {
      windows.add(
        quotaWindow(
          'raycast-credits',
          '积分',
          usedPercent: pct(max(0, total - remaining), total),
          resetsAt: renewal,
        ),
      );
      extras['余额'] = '${_rayAmount(remaining)} / ${_rayAmount(total)} credits left';
    } else {
      if (remaining != null) {
        credits.add(balanceRow('raycast-left', remaining, label: '剩余', currency: null));
      }
      if (total != null) {
        credits.add(balanceRow('raycast-total', total, label: '总额', currency: null));
      }
      if (renewal != null) extras['下次刷新'] = renewal.toIso8601String();
    }
    return snapshot(
      account,
      ctx,
      plan: c.plan,
      source: 'web',
      windows: windows,
      credits: credits,
      extras: extras,
    );
  }
}

Never _rayFail(String field) => throw ProviderException('Raycast 返回的 credits 数据格式无法识别: $field');

double? _rayNumber(Object? value, String field) {
  if (value == null) return null;
  if (value is num) return value.isFinite ? value.toDouble() : _rayFail(field);
  if (value is! String) _rayFail(field);
  final text = value.trim();
  if (!RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$').hasMatch(text)) _rayFail(field);
  final parsed = double.tryParse(text);
  return parsed != null && parsed.isFinite ? parsed : _rayFail(field);
}

/// No thousands grouping, matching the CodexBar meter footnote.
String _rayAmount(double v) {
  if (v == v.truncateToDouble()) return v.toInt().toString();
  final text = v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  return text.endsWith('.') ? text.substring(0, text.length - 1) : text;
}

String? _rayPlan(String? tier) => switch (tier) {
  'pro' => 'Pro',
  'pro_plus' => 'Pro+',
  'max' => 'Max',
  _ => tier,
};

({double? remaining, double? total, DateTime? renewal, String? plan}) parseRaycastCredits(
  String body,
) {
  final root = asMap(_decodeJsonOr(body, 'Raycast 返回的不是 JSON')) ?? _rayFail('expected an object');
  final remaining = _rayNumber(root['remaining_balance_credits'], 'remaining_balance_credits');
  final total = _rayNumber(root['total_balance_credits'], 'total_balance_credits');
  if (remaining == null && total == null) _rayFail('no credit amounts');
  if ((remaining ?? 0) < 0) _rayFail('remaining_balance_credits');
  if ((total ?? 0) < 0) _rayFail('total_balance_credits');
  final nextRaw = root['next_credits_at'];
  DateTime? renewal;
  if (nextRaw != null) {
    if (nextRaw is! String) _rayFail('next_credits_at');
    renewal = DateTime.tryParse(nextRaw.trim())?.toUtc() ?? _rayFail('next_credits_at');
  }
  final fundingRaw = root['funding_subscription'];
  final funding = fundingRaw == null
      ? <String, Object?>{}
      : (asMap(fundingRaw) ?? _rayFail('funding_subscription'));
  return (
    remaining: remaining,
    total: total,
    renewal: renewal,
    plan: _rayPlan(asString(funding['tier'])),
  );
}

// ---------------------------------------------------------------- Replicate

class ReplicateProvider extends _CookieProvider {
  @override
  String get id => 'replicate';
  @override
  String get displayName => 'Replicate';
  @override
  int get brandColor => 0xFF000000;
  @override
  String get setupHint =>
      '浏览器登录 replicate.com，打开 account/billing 页面，在开发者工具里复制 Cookie 请求头（需包含 sessionid），查询本月花费与余额。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(label: 'replicate.com Cookie', hint: 'sessionid=...'),
  ];

  @override
  String? cookieProblem(String header) => _cookieProblem(header, const ['sessionid']);

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final cookie = cookieOf(account);
    final headers = {'Cookie': cookie, 'Accept': 'text/html', 'User-Agent': _chromeUa};
    final page = await sendRequest(
      ctx,
      displayName,
      Uri.parse('https://replicate.com/account/billing'),
      headers: headers,
      timeout: const Duration(seconds: 8),
    );
    _replicateCheck(page);
    final who = findReplicateAccount(page.body);
    if (who == null) {
      if (_replicateSignedOut(page.body)) throw _replicateExpired();
      throw ProviderException('Replicate 账单页面格式已变化', hint: '无法识别账户信息，请稍后重试');
    }
    final base =
        'https://replicate.com/api/${who.kind == 'organization' ? 'organizations' : 'users'}/${Uri.encodeComponent(who.username)}';
    final invoices = await sendRequest(
      ctx,
      displayName,
      Uri.parse('$base/invoices'),
      headers: {'Cookie': cookie},
      timeout: const Duration(seconds: 8),
    );
    _replicateCheck(invoices);
    final used = _replicateSpend(invoices.body, ctx.now());
    double? balance;
    try {
      final credit = await sendRequest(
        ctx,
        displayName,
        Uri.parse('$base/unused-credit'),
        headers: {'Cookie': cookie},
        timeout: const Duration(seconds: 2),
      );
      if (credit.ok) balance = _replicateMoney(asMap(credit.json)?['unused_credit']);
    } on ProviderException {
      balance = null;
    }
    return snapshot(
      account,
      ctx,
      source: 'web',
      credits: [
        Credits(
          id: 'replicate-spend',
          label: '本月花费',
          used: used,
          balance: balance,
          currency: 'USD',
        ),
      ],
      extras: {'账户': who.username, if (who.kind == 'organization') '类型': '组织'},
    );
  }
}

ProviderException _replicateExpired() =>
    ProviderException('Replicate 登录已过期', hint: '重新登录后粘贴新的 Cookie 请求头', statusCode: 401);

void _replicateCheck(HttpResult r) {
  if (r.statusCode == 401 || r.statusCode == 403) throw _replicateExpired();
  if (r.statusCode == 429) {
    throw ProviderException('Replicate 请求过于频繁', hint: '稍后再试', statusCode: 429);
  }
  if (r.statusCode == 408 || r.statusCode >= 500) {
    throw ProviderException('Replicate 账单服务暂不可用 (HTTP ${r.statusCode})', hint: '稍后再试');
  }
  if (!r.ok) {
    throw ProviderException('Replicate 接口错误 HTTP ${r.statusCode}', statusCode: r.statusCode);
  }
}

bool _replicateSignedOut(String html) =>
    RegExp(r'<title>\s*Sign in\s*\|\s*Replicate\s*</title>', caseSensitive: false).hasMatch(html) &&
    RegExp(
      r'''<a\b[^>]*\bhref=["']\/login\/github\/(?:\?[^"']*)?["']''',
      caseSensitive: false,
    ).hasMatch(html);

/// Finds `account: {kind, username}` inside `react-component-props` JSON blobs.
({String kind, String username})? findReplicateAccount(String html) {
  final scripts = RegExp(r'<script\b([^>]*)>([\s\S]*?)</script\s*>', caseSensitive: false);
  final idAttr = RegExp(
    r'''\bid\s*=\s*(["'])react-component-props[^"']*\1''',
    caseSensitive: false,
  );
  final typeAttr = RegExp(r'''\btype\s*=\s*(["'])application/json\1''', caseSensitive: false);
  var visited = 0;
  for (final m in scripts.allMatches(html)) {
    if (visited >= 4000) break;
    final attrs = m[1]!;
    if (!idAttr.hasMatch(attrs) || !typeAttr.hasMatch(attrs)) continue;
    Object? payload;
    try {
      payload = jsonDecode(m[2]!);
    } on FormatException {
      continue;
    }
    final queue = <Object?>[payload];
    for (var index = 0; index < queue.length && visited < 4000; index++, visited++) {
      final item = queue[index];
      final object = asMap(item);
      final candidate = asMap(object?['account']);
      final kind = asString(candidate?['kind']);
      final username = asString(candidate?['username']);
      if (candidate != null && (kind == 'user' || kind == 'organization') && username != null) {
        return (kind: kind!, username: username);
      }
      final Iterable<Object?> children = item is List
          ? item
          : (object?.values ?? const <Object?>[]);
      for (final child in children) {
        if (queue.length >= 4000) break;
        if (child is Map || child is List) queue.add(child);
      }
    }
  }
  return null;
}

double? _replicateMoney(Object? v) {
  if (v is! String || !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(v.trim())) return null;
  final n = double.tryParse(v.trim());
  return n != null && n.isFinite && n >= 0 ? n : null;
}

double _replicateSpend(String body, DateTime now) {
  final root = asMap(_decodeJsonOr(body, 'Replicate 账单 JSON 无法解析'));
  final invoices =
      asList(root?['invoices']) ?? (throw ProviderException('Replicate 账单缺少 invoices'));
  Map<String, Object?>? current;
  for (final raw in invoices) {
    final invoice = asMap(raw);
    if (invoice == null || invoice['type'] != 'monthly-usage') continue;
    final endedBefore = invoice['ended_before'];
    if (endedBefore == null) {
      current = invoice;
      break;
    }
    if (endedBefore is! String || endedBefore.trim().isEmpty) continue;
    final end = DateTime.tryParse(endedBefore.trim());
    if (end != null && end.isAfter(now)) {
      current = invoice;
      break;
    }
  }
  if (current == null) throw ProviderException('Replicate 没有本月用量账单');
  return _replicateMoney(current['total_cost_before_adjustments']) ??
      (throw ProviderException('Replicate 账单金额无效'));
}

// ----------------------------------------------------------------- TypeSafe

const _typesafeOrigin = 'https://console.typesafe.ai';
const _typesafeBilling = '$_typesafeOrigin/settings/billing';

class TypeSafeProvider extends _CookieProvider {
  @override
  String get id => 'typesafe';
  @override
  String get displayName => 'TypeSafe';
  @override
  int get brandColor => 0xFF111111;
  @override
  String get setupHint =>
      '浏览器登录 console.typesafe.ai，打开 settings/billing 页面，复制请求的完整 Cookie 请求头（推理 API Key 无法替代控制台登录）。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(label: 'console.typesafe.ai Cookie', hint: 'Cookie: ...'),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final cookie = cookieOf(account);
    var action = await _discoverAction(ctx, cookie);
    var response = await _postBilling(ctx, cookie, action);
    if (response.statusCode == 404 &&
        _header(response.headers, 'x-nextjs-action-not-found') == '1') {
      action = await _discoverAction(ctx, cookie);
      response = await _postBilling(ctx, cookie, action);
    }
    _typesafeStatus(response);
    if (_typesafeLoginPage(response.body)) throw _typesafeExpired();
    final billing =
        asMap(asMap(_typesafeResult(response.body)['data'])?['billing']) ??
        (throw ProviderException('TypeSafe 账单响应格式已变化: 缺少 billing'));
    final spent = _finite(billing['spent']);
    final balance = _finite(billing['balance']);
    if (spent == null || balance == null) throw ProviderException('TypeSafe 账单响应格式已变化: 缺少金额');
    final cycle = asString(billing['cycleLabel']);
    final planRaw = asString(billing['plan']);
    final planLabel = planRaw == null
        ? null
        : planRaw == 'free_plan'
        ? 'Free'
        : planRaw
              .split(RegExp(r'[_-]+'))
              .where((p) => p.isNotEmpty)
              .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
              .join(' ');

    final creditLines = <String>[];
    for (final item in asList(billing['credits']) ?? const <Object?>[]) {
      final credit = asMap(item);
      final amount = _finite(credit?['amount']);
      final remaining = _finite(credit?['remaining']);
      final expiresAt = credit?['expiresAt'];
      if (amount == null || remaining == null || remaining <= 0 || expiresAt is! String) continue;
      final expires = DateTime.tryParse(expiresAt)?.toUtc();
      if (expires == null) continue;
      creditLines.add(
        '${_groupNum(remaining)} of ${_groupNum(amount)}, expires ${_monthDay(expires)}',
      );
    }
    const maxCreditLines = 20;
    return snapshot(
      account,
      ctx,
      plan: planLabel,
      source: 'web',
      credits: [
        Credits(
          id: 'typesafe-spend',
          label: cycle == null ? '花费' : '本周期花费',
          used: spent,
          balance: balance,
          currency: 'USD',
        ),
      ],
      extras: {
        '计费周期': ?cycle,
        '余额': moneyText(balance, 'USD'),
        for (var i = 0; i < creditLines.length && i < maxCreditLines; i++)
          'Credit ${i + 1}': creditLines[i],
        if (creditLines.length > maxCreditLines) '更多额度': '${creditLines.length - maxCreditLines}',
      },
    );
  }

  Future<String> _discoverAction(FetchContext ctx, String cookie) async {
    final page = await _sendNoRedirect(
      ctx,
      displayName,
      Uri.parse(_typesafeBilling),
      headers: {'Cookie': cookie, 'Accept': 'text/html', 'User-Agent': _linuxUa},
      timeout: const Duration(seconds: 6),
    );
    _typesafeStatus(page);
    if (_typesafeLoginPage(page.body)) throw _typesafeExpired();
    final chunks = <String>[];
    final scripts = RegExp(r'''<script\b[^>]*\bsrc=["']([^"']+)["'][^>]*>''', caseSensitive: false);
    for (final m in scripts.allMatches(page.body)) {
      if (chunks.length >= 60) break;
      final src = m[1]!;
      final url = src.startsWith('/') ? '$_typesafeOrigin$src' : src;
      if (!url.startsWith('$_typesafeOrigin/') ||
          !RegExp(r'\.js(?:$|\?)', caseSensitive: false).hasMatch(url)) {
        continue;
      }
      if (!chunks.contains(url)) chunks.add(url);
    }
    ProviderException? failure;
    for (final url in chunks) {
      try {
        final chunk = await sendRequest(
          ctx,
          displayName,
          Uri.parse(url),
          headers: {'User-Agent': _linuxUa},
          timeout: const Duration(seconds: 2),
        );
        if (chunk.statusCode == 429 || chunk.statusCode == 408 || chunk.statusCode >= 500) {
          _typesafeStatus(chunk);
        }
        if (!chunk.ok) continue;
        final action = RegExp(
          r'"([0-9a-f]{40,})"[^)]{0,150}"getBillingOverviewResult"',
          caseSensitive: false,
        ).firstMatch(chunk.body)?.group(1);
        if (action != null) return action;
      } on ProviderException catch (e) {
        failure ??= e;
      }
    }
    final pending = failure;
    if (pending != null) throw pending;
    throw ProviderException('TypeSafe 账单页面格式已变化: 未找到 action id');
  }

  Future<HttpResult> _postBilling(FetchContext ctx, String cookie, String action) =>
      _sendNoRedirect(
        ctx,
        displayName,
        Uri.parse(_typesafeBilling),
        method: 'POST',
        headers: {
          'Cookie': cookie,
          'Origin': _typesafeOrigin,
          'Next-Action': action,
          'Accept': 'text/x-component',
          'Content-Type': 'application/json',
          'User-Agent': _linuxUa,
        },
        body: '[]',
        timeout: const Duration(seconds: 6),
      );
}

ProviderException _typesafeExpired() => ProviderException(
  'TypeSafe 登录已过期',
  hint: '重新登录 console.typesafe.ai 后粘贴新的 Cookie 请求头',
  statusCode: 401,
);

bool _typesafeLoginPage(String body) =>
    RegExp(r'\\?"\(auth\)\\?",\{\\?"children\\?":\[\\?"login\\?"').hasMatch(body);

void _typesafeStatus(HttpResult r) {
  if (r.statusCode == 401 || r.statusCode == 403 || (r.statusCode >= 300 && r.statusCode < 400)) {
    throw _typesafeExpired();
  }
  if (r.statusCode == 429) {
    throw ProviderException('TypeSafe 请求过于频繁', hint: '稍后再试', statusCode: 429);
  }
  if (r.statusCode == 408 || r.statusCode >= 500) {
    throw ProviderException('TypeSafe 账单服务暂不可用', hint: '稍后再试');
  }
  if (!r.ok) {
    throw ProviderException('TypeSafe 接口错误 HTTP ${r.statusCode}', statusCode: r.statusCode);
  }
}

/// The billing action answers as `text/x-component` lines (`N:{json}`); the
/// first object carrying an `ok` key is the result.
Map<String, Object?> _typesafeResult(String body) {
  for (final line in body.split(RegExp(r'\r?\n'))) {
    final sep = line.indexOf(':');
    if (sep < 1) continue;
    Object? candidate;
    try {
      candidate = jsonDecode(line.substring(sep + 1));
    } on FormatException {
      continue;
    }
    final object = asMap(candidate);
    if (object == null || !object.containsKey('ok')) continue;
    if (object['ok'] != true) throw ProviderException('TypeSafe 账单请求失败');
    return object;
  }
  throw ProviderException('TypeSafe 账单响应格式已变化: 缺少 result');
}

// ------------------------------------------------------------- Claude Platform

const _claudeHost = 'https://platform.claude.com';

class ClaudePlatformProvider extends _CookieProvider {
  @override
  String get id => 'claudeplatform';
  @override
  String get displayName => 'Claude Platform';
  @override
  int get brandColor => 0xFFCC7C5E;
  @override
  String get setupHint =>
      '浏览器登录 platform.claude.com，在开发者工具里复制 Cookie 请求头（需包含 sessionKey）。只读取 API 组织的预付额度与本月花费；管理员 / 推理 API Key 无法查询账单。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(label: 'platform.claude.com Cookie', hint: 'sessionKey=sk-ant-…'),
  ];

  @override
  String? cookieProblem(String header) => _cookieProblem(header, const ['sessionKey']);

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final cookie = cookieOf(account);
    Future<HttpResult> get(String path) => sendRequest(
      ctx,
      displayName,
      Uri.parse('$_claudeHost$path'),
      headers: {'Cookie': cookie, 'Accept': 'application/json'},
      timeout: const Duration(seconds: 60),
    );

    final orgsResponse = await get('/api/organizations');
    _claudeCheck(orgsResponse, forbiddenIsSession: true);
    final orgs = asList(orgsResponse.json) ?? (throw _claudeParseError('organizations'));
    final candidates = <({String id, String? name})>[];
    for (final raw in orgs) {
      final org = asMap(raw) ?? (throw _claudeParseError('organization'));
      final capabilities = asList(org['capabilities']);
      if (capabilities == null || !capabilities.contains('api')) continue;
      final id = asString(org['uuid']);
      if (id == null || !RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(id)) {
        throw _claudeParseError('organization ID');
      }
      candidates.add((id: id, name: asString(org['name'])));
    }
    if (candidates.isEmpty) {
      throw ProviderException(
        '这个 Claude 账户没有 Claude Console API 组织',
        hint: '在 platform.claude.com 创建一个 API 组织',
        statusCode: 403,
      );
    }

    ({String id, String? name})? picked;
    Map<String, Object?>? balanceObject;
    for (final candidate in candidates) {
      final r = await get('/api/organizations/${candidate.id}/prepaid/credits');
      if (r.statusCode == 403) continue;
      _claudeCheck(r);
      balanceObject = asMap(r.json) ?? (throw _claudeParseError('credit balance'));
      picked = candidate;
      break;
    }
    if (picked == null || balanceObject == null) {
      throw ProviderException('Claude Console 账单访问被拒绝', hint: '请让组织所有者授予账单访问权限', statusCode: 403);
    }

    final currency = asString(balanceObject['currency']) ?? 'USD';
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) throw _claudeParseError('currency');
    var exponent = 2;
    if (balanceObject['balance'] != null) {
      final inner = asMap(balanceObject['balance']) ?? (throw _claudeParseError('balance'));
      final creditsObject = inner['credits'] == null
          ? const <String, Object?>{}
          : (asMap(inner['credits']) ?? (throw _claudeParseError('balance credits')));
      final reported = creditsObject['exponent'];
      if (reported != null) {
        if (reported is! int || reported < 0 || reported > 4) {
          throw _claudeParseError('currency exponent');
        }
        exponent = reported;
      }
    }
    final scale = pow(10, exponent).toDouble();
    String money(num minor) => moneyText(minor / scale, currency);
    final balance = _claudeMinor(balanceObject['amount']) / scale;

    final now = ctx.now();
    final grants = <_ClaudeGrant>[];
    for (final (field, purchased) in [('promo_tranches', false), ('tranches', true)]) {
      final list = balanceObject[field];
      if (list == null) continue;
      for (final raw in asList(list) ?? (throw _claudeParseError(field))) {
        final t = asMap(raw) ?? (throw _claudeParseError('credit grant'));
        final granted = _claudeMinor(t['granted_amount_minor_units'], 'granted credit');
        final remaining = _claudeMinor(t['remaining_amount_minor_units'], 'remaining credit');
        final expiresAt = _claudeTimestamp(t['expires_at']);
        if (granted <= 0 || (expiresAt != null && !expiresAt.isAfter(now))) continue;
        grants.add(
          _ClaudeGrant(
            label: asString(t['name']) ?? (purchased ? 'Purchased credit' : 'API credit'),
            program: asString(t['program_id']),
            purchased: purchased,
            remaining: max(0, remaining),
            granted: granted,
            expiresAt: expiresAt,
          ),
        );
      }
    }
    grants.sort((a, b) {
      final ea = a.expiresAt;
      final eb = b.expiresAt;
      if (ea == null && eb == null) return 0;
      if (ea == null) return 1;
      if (eb == null) return -1;
      return ea.compareTo(eb);
    });

    final subscription = grants
        .where((g) => g.program == 'subscription_api_credit' && g.remaining > 0)
        .firstOrNull;
    final purchasedGrants = grants.where((g) => g.purchased).toList();
    final purchased =
        purchasedGrants.where((g) => g.remaining > 0).firstOrNull ?? purchasedGrants.firstOrNull;

    String amounts(_ClaudeGrant g) => '${money(g.remaining)} of ${money(g.granted)} left';
    String describe(_ClaudeGrant g) {
      final expiry = g.expiresAt;
      if (expiry == null) return amounts(g);
      final year = expiry.year == now.year ? '' : ', ${expiry.year}';
      return '${amounts(g)} · Expires ${_monthDay(expiry)}$year (UTC)';
    }

    String spendText;
    try {
      final r = await get('/api/organizations/${picked.id}/current_spend');
      _claudeCheck(r);
      final spend = asMap(r.json) ?? (throw _claudeParseError('spend'));
      final amount = _claudeMinor(spend['amount'], 'spend');
      if (amount < 0) throw _claudeParseError('spend');
      spendText = money(amount);
    } on ProviderException {
      spendText = 'Unavailable';
    }

    final extras = <String, String>{
      if (picked.name != null) '组织': picked.name!,
      if (subscription != null) 'API 额度': describe(subscription),
      if (purchased != null) '预付购买额度': describe(purchased),
      for (final g in grants)
        if (!identical(g, subscription) && !identical(g, purchased))
          '其他额度 · ${g.label}': describe(g),
      '本月花费 (UTC)': spendText,
    };

    return snapshot(
      account,
      ctx,
      source: 'web',
      windows: [
        if (subscription != null)
          quotaWindow(
            'claudeplatform-api',
            'API 额度',
            usedPercent: pct(subscription.granted - subscription.remaining, subscription.granted),
          ),
        if (purchased != null)
          quotaWindow(
            'claudeplatform-purchased',
            '预付购买额度',
            usedPercent: pct(purchased.granted - purchased.remaining, purchased.granted),
          ),
      ],
      credits: [
        Credits(
          id: 'claudeplatform-balance',
          label: '预付余额',
          used: balance,
          balance: balance,
          currency: currency,
        ),
      ],
      extras: extras,
    );
  }
}

class _ClaudeGrant {
  const _ClaudeGrant({
    required this.label,
    required this.program,
    required this.purchased,
    required this.remaining,
    required this.granted,
    required this.expiresAt,
  });

  final String label;
  final String? program;
  final bool purchased;
  final int remaining;
  final int granted;
  final DateTime? expiresAt;
}

int _claudeMinor(Object? value, [String field = 'credit balance']) {
  if (value is int) return value;
  throw _claudeParseError(field);
}

DateTime? _claudeTimestamp(Object? value) {
  final raw = asString(value);
  if (raw == null || !RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(raw)) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

ProviderException _claudeParseError(String field) =>
    ProviderException('Claude Console 返回的 $field 无法解析', hint: '接口格式可能已变化，请稍后重试');

void _claudeCheck(HttpResult r, {bool forbiddenIsSession = false}) {
  if (r.statusCode == 401 || (forbiddenIsSession && r.statusCode == 403)) {
    throw ProviderException(
      'Claude Console 登录已过期',
      hint: '在 platform.claude.com 重新登录，或粘贴新的 Cookie 请求头',
      statusCode: 401,
    );
  }
  if (r.statusCode == 429) {
    throw ProviderException('Claude Console 请求过于频繁', hint: '几分钟后再试', statusCode: 429);
  }
  if (r.statusCode >= 500) {
    throw ProviderException('Claude Console 暂不可用 (HTTP ${r.statusCode})', hint: '稍后再试');
  }
  if (!r.ok) {
    throw ProviderException('Claude Console 接口错误 HTTP ${r.statusCode}', statusCode: r.statusCode);
  }
}

// ------------------------------------------------ Aliyun OneConsole (shared)

const _oneConsolePatterns = [
  r'"secToken"\s*:\s*"([^"]+)"',
  r'"sec_token"\s*:\s*"([^"]+)"',
  r'''secToken['"]?\s*[:=]\s*['"]([^'"]+)['"]''',
  r'''sec_token['"]?\s*[:=]\s*['"]([^'"]+)['"]''',
  r'''csrfToken['"]?\s*[:=]\s*['"]([^'"]+)['"]''',
];

const _aliCodingPatterns = [
  r'SEC_TOKEN\s*:\s*"([^"]+)"',
  r"SEC_TOKEN\s*:\s*'([^']+)'",
  r'secToken\s*:\s*"([^"]+)"',
  r'sec_token\s*:\s*"([^"]+)"',
  r"sec_token\s*:\s*'([^']+)'",
  r'"SEC_TOKEN"\s*:\s*"([^"]+)"',
  r'"sec_token"\s*:\s*"([^"]+)"',
];

String? _tokenInHtml(String html, List<String> extra) {
  for (final pattern in [..._oneConsolePatterns, ...extra]) {
    final value = RegExp(pattern).firstMatch(html)?.group(1)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String _originOf(String url) {
  final u = Uri.parse(url);
  return '${u.scheme}://${u.host}';
}

/// Resolves the Aliyun `sec_token` that every OneConsole gateway POST needs.
/// Coding Plan tries the dashboard, then user-info, then the cookie; token plan
/// and Qwen try the cookie before user-info ([cookieFirst]).
Future<String?> _oneConsoleSecToken(
  FetchContext ctx,
  String provider,
  String cookie, {
  required String dashboard,
  required bool cookieFirst,
  List<String> extraPatterns = const [],
}) async {
  try {
    final page = await sendRequest(
      ctx,
      provider,
      Uri.parse(dashboard),
      headers: {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Cookie': cookie,
        'User-Agent': _safariUa,
      },
      timeout: const Duration(seconds: 20),
    );
    if (page.statusCode == 200) {
      final token = _tokenInHtml(page.body, extraPatterns);
      if (token != null) return token;
    }
  } on ProviderException {
    // Fall through to the other sources.
  }
  final fromCookie = cookieValue(cookie, 'sec_token');
  final cookieToken = fromCookie == null || fromCookie.isEmpty ? null : fromCookie;
  if (cookieFirst && cookieToken != null) return cookieToken;
  final origin = _originOf(dashboard);
  try {
    final info = await sendRequest(
      ctx,
      provider,
      Uri.parse('$origin/tool/user/info.json'),
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'Cookie': cookie,
        'Referer': '$origin/',
        'User-Agent': _safariUa,
      },
      timeout: const Duration(seconds: 20),
    );
    if (info.ok) {
      final token = _firstAcross(_expandEmbedded(info.json), [
        'secToken',
        'sec_token',
        'csrfToken',
        'token',
      ], asString);
      if (token != null) return token;
    }
  } on ProviderException {
    // Fall through.
  }
  return cookieToken;
}

/// One gateway POST: decodes the envelope and maps login / gateway errors.
Object? _gatewayDecode(String provider, String body) {
  if (body.trim().isEmpty) throw ProviderException('$provider 返回了空内容');
  final Object? decoded;
  try {
    decoded = _expandEmbedded(jsonDecode(body));
  } on FormatException {
    final lower = body.toLowerCase();
    if (lower.contains('<html') &&
        (lower.contains('login') || lower.contains('sign in') || lower.contains('signin'))) {
      throw _loginRequired(provider);
    }
    throw ProviderException('$provider 返回了无法解析的数据');
  }
  _gatewayCheck(provider, decoded);
  return decoded;
}

void _gatewayCheck(String provider, Object? root) {
  final m = asMap(root);
  if (m == null) return;
  final code = asString(m['code']) ?? '';
  final message = asString(m['message']) ?? asString(m['msg']) ?? '';
  final status = asInt(m['statusCode']);
  final lower = '$code $message'.toLowerCase();
  if (status == 401 || status == 403) {
    throw ProviderException('$provider 拒绝了这个 Cookie', hint: '重新复制 Cookie 请求头', statusCode: status);
  }
  if (lower.contains('login') || lower.contains('log in')) throw _loginRequired(provider);
  if (m['successResponse'] == false || m['Success'] == false) {
    throw ProviderException('$provider 返回错误: ${message.isEmpty ? '未知错误' : message}');
  }
}

// ---------------------------------------------------- Alibaba Coding Plan

const _aliQuotaAction = 'zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2';

class _AliRegion {
  const _AliRegion({
    required this.gateway,
    required this.dashboard,
    required this.referer,
    required this.rpcBase,
    required this.rpcAction,
    required this.domain,
    required this.site,
    required this.commodity,
    required this.regionId,
  });

  final String gateway;
  final String dashboard;
  final String referer;
  final String rpcBase;
  final String rpcAction;
  final String domain;
  final String site;
  final String commodity;
  final String regionId;

  String get apiKeyUrl =>
      '$gateway/data/api.json?action=$_aliQuotaAction&product=broadscope-bailian&api=queryCodingPlanInstanceInfoV2&currentRegionId=$regionId';

  String get rpcUrl =>
      '$rpcBase/data/api.json?action=$rpcAction&product=sfm_bailian&api=$_aliQuotaAction&_v=undefined';
}

const _aliIntlRegion = _AliRegion(
  gateway: 'https://modelstudio.console.alibabacloud.com',
  dashboard: 'https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan',
  referer: 'https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan',
  rpcBase: 'https://bailian-singapore-cs.alibabacloud.com',
  rpcAction: 'IntlBroadScopeAspnGateway',
  domain: 'modelstudio.console.alibabacloud.com',
  site: 'MODELSTUDIO_ALIBABACLOUD',
  commodity: 'sfm_codingplan_public_intl',
  regionId: 'ap-southeast-1',
);

const _aliCnRegion = _AliRegion(
  gateway: 'https://bailian.console.aliyun.com',
  dashboard: 'https://bailian.console.aliyun.com/cn-beijing/?tab=model#/efm/coding_plan',
  referer: 'https://bailian.console.aliyun.com/cn-beijing/?tab=model',
  rpcBase: 'https://bailian-cs.console.aliyun.com',
  rpcAction: 'BroadScopeAspnGateway',
  domain: 'bailian.console.aliyun.com',
  site: 'BAILIAN_ALIYUN',
  commodity: 'sfm_codingplan_public_cn',
  regionId: 'cn-beijing',
);

class AlibabaCodingPlanProvider extends _CookieProvider {
  @override
  String get id => 'alibabacodingplan';
  @override
  String get displayName => 'Alibaba Coding Plan';
  @override
  int get brandColor => 0xFFFF6A00;
  @override
  String get setupHint =>
      '推荐：浏览器登录 Model Studio（国际）或 百炼（中国站），复制控制台请求的 Cookie 请求头。备选：百炼 API Key（有些账号的 API Key 不返回 Coding Plan 额度）。';
  @override
  List<ProviderField> get fields => const [
    ProviderField(
      key: ProviderField.secretKey,
      label: 'Cookie（推荐）',
      multiline: true,
      required: false,
      hint: 'login_aliyunid_ticket=...; sec_token=...',
      help: '百炼控制台 → 开发者工具 → 网络 → 任一请求的 Cookie 请求头',
      envVars: ['ALIBABA_CODING_PLAN_COOKIE'],
    ),
    ProviderField(
      key: 'apiKey',
      label: 'API Key（备选）',
      required: false,
      envVars: ['ALIBABA_CODING_PLAN_API_KEY', 'ALIBABA_QWEN_API_KEY', 'DASHSCOPE_API_KEY'],
    ),
    ProviderField(
      key: 'region',
      label: '区域',
      kind: FieldKind.choice,
      defaultValue: 'intl',
      choices: [FieldChoice('intl', '国际站 Model Studio'), FieldChoice('cn', '中国站 百炼')],
    ),
  ];

  @override
  String? validateManual(FieldValues values) {
    final cookie = normalizeCookieHeader(values[ProviderField.secretKey] ?? '');
    final key = values['apiKey'];
    if (cookie.isEmpty && (key == null || key.isEmpty)) return '请粘贴 Cookie 请求头或 API Key';
    if (cookie.isNotEmpty && !cookie.contains('=')) return 'Cookie 格式无效，需要 name=value 形式';
    return null;
  }

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final v = FieldValues.of(this, account);
    final cookieRaw = v[ProviderField.secretKey];
    final cookie = cookieRaw == null ? null : normalizeCookieHeader(cookieRaw);
    final apiKeyRaw = v['apiKey'];
    final apiKey = apiKeyRaw == null ? null : bareToken(apiKeyRaw);
    final region = v['region'] == 'cn' ? _aliCnRegion : _aliIntlRegion;
    final hasCookie = cookie != null && cookie.isNotEmpty;
    final hasKey = apiKey != null && apiKey.isNotEmpty;
    if (!hasCookie && !hasKey) {
      throw ProviderException('未填写阿里云百炼 Cookie 或 API Key', hint: setupHint);
    }
    if (hasCookie) {
      try {
        return await _cookieFetch(account, ctx, cookie, region);
      } on ProviderException catch (e) {
        if (!hasKey || (e.statusCode != 401 && e.statusCode != 403)) rethrow;
      }
    }
    return _apiKeyFetch(account, ctx, apiKey!, region);
  }

  Future<UsageSnapshot> _cookieFetch(
    AccountConfig account,
    FetchContext ctx,
    String cookie,
    _AliRegion region,
  ) async {
    final sec = await _oneConsoleSecToken(
      ctx,
      displayName,
      cookie,
      dashboard: region.dashboard,
      cookieFirst: false,
      extraPatterns: _aliCodingPatterns,
    );
    if (sec == null) throw _loginRequired('阿里云百炼控制台');
    final anonymousId = cookieValue(cookie, 'cna');
    final csrf = cookieValue(cookie, 'login_aliyunid_csrf') ?? cookieValue(cookie, 'csrf');
    final headers = {
      'Content-Type': _formType,
      'Accept': '*/*',
      'Cookie': cookie,
      'X-Requested-With': 'XMLHttpRequest',
      'User-Agent': _chromeUa,
      'Origin': region.gateway,
      'Referer': region.referer,
      if (csrf != null && csrf.isNotEmpty) 'x-xsrf-token': csrf,
      if (csrf != null && csrf.isNotEmpty) 'x-csrf-token': csrf,
    };
    final params = jsonEncode({
      'Api': _aliQuotaAction,
      'V': '1.0',
      'Data': {
        'queryCodingPlanInstanceInfoRequest': {
          'commodityCode': region.commodity,
          'onlyLatestOne': true,
        },
        'cornerstoneParam': {
          'feTraceId': _traceId(),
          'feURL': region.dashboard,
          'protocol': 'V2',
          'console': 'ONE_CONSOLE',
          'productCode': 'p_efm',
          'domain': region.domain,
          'consoleSite': region.site,
          'userNickName': '',
          'userPrincipalName': '',
          'xsp_lang': 'en-US',
          if (anonymousId != null && anonymousId.isNotEmpty) 'X-Anonymous-Id': anonymousId,
        },
      },
    });
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse(region.rpcUrl),
      method: 'POST',
      headers: headers,
      body: {'params': params, 'region': region.regionId, 'sec_token': sec},
      timeout: const Duration(seconds: 30),
    );
    if (r.statusCode == 401 || r.statusCode == 403) throw _loginRequired('阿里云百炼控制台');
    if (!r.ok) throw ProviderException('阿里云百炼接口错误 HTTP ${r.statusCode}', statusCode: r.statusCode);
    final parsed = parseAlibabaCodingPlanBody(r.body, ctx.now(), apiKey: false);
    return snapshot(
      account,
      ctx,
      plan: parsed.plan,
      source: 'web',
      windows: parsed.windows,
      extras: parsed.extras,
    );
  }

  Future<UsageSnapshot> _apiKeyFetch(
    AccountConfig account,
    FetchContext ctx,
    String key,
    _AliRegion region,
  ) async {
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse(region.apiKeyUrl),
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $key',
        'x-api-key': key,
        'X-DashScope-API-Key': key,
        'User-Agent': _chromeUa,
        'Origin': region.gateway,
        'Referer': region.dashboard,
      },
      body: {
        'queryCodingPlanInstanceInfoRequest': {'commodityCode': region.commodity},
      },
      timeout: const Duration(seconds: 30),
    );
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw ProviderException(
        '百炼 API Key 无效或没有 Coding Plan 权限',
        hint: '检查 API Key',
        statusCode: 401,
      );
    }
    if (!r.ok) throw ProviderException('阿里云百炼接口错误 HTTP ${r.statusCode}', statusCode: r.statusCode);
    final parsed = parseAlibabaCodingPlanBody(r.body, ctx.now(), apiKey: true);
    return snapshot(
      account,
      ctx,
      plan: parsed.plan,
      source: 'api-key',
      windows: parsed.windows,
      extras: parsed.extras,
    );
  }
}

/// Coding Plan quota payload (cookie or API-key path). Throws on login/API errors.
({String? plan, List<RateWindow> windows, Map<String, String> extras}) parseAlibabaCodingPlanBody(
  String body,
  DateTime now, {
  required bool apiKey,
}) {
  final root = _expandEmbedded(_decodeJsonOr(body, '阿里云百炼返回了无法解析的数据'));
  final top = asMap(root) ?? (throw ProviderException('阿里云百炼返回的数据格式无法识别'));

  final statusCode = _firstAcross(top, ['statusCode', 'status_code', 'code'], asInt);
  if (statusCode != null && statusCode != 0 && statusCode != 200) {
    final message =
        _firstAcross(top, ['statusMessage', 'status_msg', 'message', 'msg'], asString) ??
        'status code $statusCode';
    final lower = message.toLowerCase();
    if (statusCode == 401 ||
        statusCode == 403 ||
        lower.contains('api key') ||
        lower.contains('unauthorized')) {
      throw ProviderException('阿里云百炼拒绝了凭证', hint: message, statusCode: 401);
    }
    throw ProviderException('阿里云百炼返回错误: $message');
  }
  final codeText = (_firstAcross(top, ['code', 'status', 'statusCode'], asString) ?? '')
      .toLowerCase();
  final messageText = (_firstAcross(top, ['message', 'msg', 'statusMessage'], asString) ?? '')
      .toLowerCase();
  if (codeText.contains('needlogin') ||
      codeText.contains('login') ||
      messageText.contains('log in') ||
      messageText.contains('login')) {
    if (apiKey) {
      throw ProviderException('API Key 在该地区不可用', hint: '改用 Cookie 方式或切换区域', statusCode: 403);
    }
    throw _loginRequired('阿里云百炼控制台');
  }
  if (apiKey &&
      (messageText.contains('console session') ||
          messageText.contains('api key mode may be unavailable'))) {
    throw ProviderException('API Key 在该地区不可用', hint: '改用 Cookie 方式或切换区域', statusCode: 403);
  }

  final rawInstances =
      _firstAcross<List<Object?>>(top, [
        'codingPlanInstanceInfos',
        'coding_plan_instance_infos',
      ], asList) ??
      const <Object?>[];
  final instances = rawInstances.map(asMap).whereType<Map<String, Object?>>().toList();
  Map<String, Object?>? selected;
  var best = 0;
  for (final instance in instances) {
    final score = _aliActiveScore(instance, now);
    if (score > best) {
      best = score;
      selected = instance;
    }
  }
  selected ??= instances.firstOrNull;
  final selectedActive = selected != null && _aliActiveScore(selected, now) > 0;
  final Map<String, Object?>? quota;
  if (instances.length > 1 && selectedActive) {
    quota = _quotaObject(selected);
  } else {
    quota = _quotaObject(selected ?? const <String, Object?>{}) ?? _quotaObject(top);
  }
  final q = quota ?? const <String, Object?>{};

  final windows = <RateWindow>[];
  final extras = <String, String>{};
  final fiveUsed = _firstKeyNum(q, ['per5HourUsedQuota', 'perFiveHourUsedQuota']);
  final fiveTotal = _firstKeyNum(q, ['per5HourTotalQuota', 'perFiveHourTotalQuota']);
  if (fiveUsed != null && fiveTotal != null && fiveTotal > 0) {
    windows.add(
      quotaWindow(
        'alibaba-5h',
        '5 小时',
        usedPercent: pct(fiveUsed, fiveTotal),
        resetsAt: _fiveHourReset(
          _plainDate(
            _firstKeyValue(q, ['per5HourQuotaNextRefreshTime', 'perFiveHourQuotaNextRefreshTime']),
          ),
          now,
        ),
        windowMinutes: 300,
      ),
    );
    extras['5 小时用量'] = '${_groupNum(fiveUsed)} / ${_groupNum(fiveTotal)} used';
  }
  final weekUsed = _firstKeyNum(q, ['perWeekUsedQuota']);
  final weekTotal = _firstKeyNum(q, ['perWeekTotalQuota']);
  if (weekUsed != null && weekTotal != null && weekTotal > 0) {
    windows.add(
      quotaWindow(
        'alibaba-weekly',
        '每周',
        usedPercent: pct(weekUsed, weekTotal),
        resetsAt: _plainDate(_firstKeyValue(q, ['perWeekQuotaNextRefreshTime'])),
        windowMinutes: 10080,
      ),
    );
    extras['每周用量'] = '${_groupNum(weekUsed)} / ${_groupNum(weekTotal)} used';
  }
  final monthUsed = _firstKeyNum(q, ['perBillMonthUsedQuota', 'perMonthUsedQuota']);
  final monthTotal = _firstKeyNum(q, ['perBillMonthTotalQuota', 'perMonthTotalQuota']);
  if (monthUsed != null && monthTotal != null && monthTotal > 0) {
    windows.add(
      quotaWindow(
        'alibaba-monthly',
        '每月',
        usedPercent: pct(monthUsed, monthTotal),
        resetsAt: _plainDate(
          _firstKeyValue(q, ['perBillMonthQuotaNextRefreshTime', 'perMonthQuotaNextRefreshTime']),
        ),
        windowMinutes: 43200,
      ),
    );
    extras['每月用量'] = '${_groupNum(monthUsed)} / ${_groupNum(monthTotal)} used';
  }

  final planName =
      _firstKeyString(selected, [
        'planName',
        'plan_name',
        'instanceName',
        'instance_name',
        'packageName',
        'package_name',
      ]) ??
      _firstAcross(top, ['planName', 'plan_name', 'packageName', 'package_name'], asString);
  if (windows.isEmpty) {
    final fallbackOk = instances.isEmpty ? _aliActiveScore(top, now) > 0 : selectedActive;
    if (fallbackOk && planName != null) {
      return (plan: planName, windows: const [], extras: const {});
    }
    throw ProviderException('未找到套餐额度数据', hint: '请在百炼控制台确认 Coding Plan 已开通');
  }
  return (plan: planName, windows: windows, extras: extras);
}

Map<String, Object?>? _quotaObject(Object? node) {
  final explicit = _firstAcross(node, ['codingPlanQuotaInfo', 'coding_plan_quota_info'], asMap);
  if (explicit != null) return explicit;
  const keys = [
    'per5HourUsedQuota',
    'per5HourTotalQuota',
    'perWeekUsedQuota',
    'perWeekTotalQuota',
    'perBillMonthUsedQuota',
    'perBillMonthTotalQuota',
  ];
  final queue = <Object?>[node];
  for (var i = 0; i < queue.length; i++) {
    final cur = queue[i];
    if (cur is! Map) continue;
    if (keys.any(cur.containsKey)) return asMap(cur);
    queue.addAll(cur.values);
  }
  return null;
}

int _aliActiveScore(Map<String, Object?> instance, DateTime now) {
  final status = (_firstKeyString(instance, ['status', 'instanceStatus']) ?? '').toUpperCase();
  if (status == 'VALID' || status == 'ACTIVE') return 3;
  if (const {
    'EXPIRED',
    'INVALID',
    'INACTIVE',
    'DISABLED',
    'TERMINATED',
    'STOPPED',
  }.contains(status)) {
    return -1;
  }
  final active = instance['isActive'] ?? instance['active'];
  if (active != null) return _truthy(active) ? 3 : -1;
  final end = _plainDate(
    _firstKeyValue(instance, ['endTime', 'periodEndTime', 'expireTime', 'expirationTime']),
  );
  return end != null && end.isAfter(now) ? 1 : 0;
}

/// 5-hour windows reset at least a minute out; stale timestamps roll forward 5 h.
DateTime _fiveHourReset(DateTime? raw, DateTime now) {
  final floor = now.add(const Duration(seconds: 60));
  if (raw != null && raw.isAfter(floor)) return raw;
  final rolled = raw?.add(const Duration(hours: 5));
  if (rolled != null && rolled.isAfter(floor)) return rolled;
  return now.add(const Duration(hours: 5));
}

// ----------------------------------------- Alibaba Token Plan + Qwen Cloud

class _Personal {
  const _Personal({
    required this.base,
    required this.origin,
    required this.dashboard,
    required this.action,
    required this.site,
    required this.commodity,
    required this.region,
    this.switchUser = false,
  });

  final String base;
  final String origin;
  final String dashboard;
  final String action;
  final String site;
  final String commodity;
  final String region;
  final bool switchUser;
}

/// Personal/Solo rolling-window usage: usage (required, retried), then
/// subscription and quota-config (both optional).
Future<_Usage> _personalUsage(
  FetchContext ctx,
  String provider,
  String cookie,
  _Personal p, {
  required bool requireSec,
  required String? defaultPlan,
}) async {
  final sec = await _oneConsoleSecToken(
    ctx,
    provider,
    cookie,
    dashboard: p.dashboard,
    cookieFirst: true,
  );
  if (sec == null && requireSec) throw _loginRequired(provider);
  Object? usage;
  for (var attempt = 0; attempt < 3; attempt++) {
    usage = await _personalCall(ctx, provider, cookie, p, sec, 'usage', const {});
    if (_hasPersonalWindows(usage)) break;
    if (attempt < 2) await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  if (!_hasPersonalWindows(usage)) {
    throw ProviderException('$provider 暂未返回个人套餐用量', hint: '稍后再试，或在控制台确认套餐已开通');
  }
  Object? subscription;
  Object? quotaConfig;
  try {
    subscription = await _personalCall(ctx, provider, cookie, p, sec, 'subscription', {
      'commodityCode': p.commodity,
    });
  } on ProviderException {
    subscription = null;
  }
  try {
    quotaConfig = await _personalCall(ctx, provider, cookie, p, sec, 'quota-config', const {});
  } on ProviderException {
    quotaConfig = null;
  }
  return _parsePersonalUsage(usage, subscription, quotaConfig, defaultPlan: defaultPlan);
}

bool _hasPersonalWindows(Object? root) =>
    _firstAcross(root, ['per5HourPercentage'], asDouble) != null ||
    _firstAcross(root, ['per1WeekPercentage'], asDouble) != null ||
    _firstAcross(root, ['per1MonthPercentage'], asDouble) != null;

Future<Object?> _personalCall(
  FetchContext ctx,
  String provider,
  String cookie,
  _Personal p,
  String? sec,
  String name,
  Map<String, Object?> data,
) async {
  final csrf = cookieValue(cookie, 'login_aliyunid_csrf') ?? cookieValue(cookie, 'csrf');
  final anonymousId = cookieValue(cookie, 'cna');
  final cornerstone = <String, Object?>{
    'feTraceId': _traceId(),
    'feURL': p.dashboard,
    'protocol': 'V2',
    'console': 'ONE_CONSOLE',
    'productCode': 'p_efm',
    'domain': Uri.parse(p.dashboard).host,
    if (p.switchUser) 'switchUserType': 3,
    'consoleSite': p.site,
    'userNickName': '',
    'userPrincipalName': '',
    'xsp_lang': 'en-US',
    if (anonymousId != null && anonymousId.isNotEmpty) 'X-Anonymous-Id': anonymousId,
  };
  final api = 'zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/$name';
  final headers = {
    'Content-Type': _formType,
    'Accept': 'application/json, text/plain, */*',
    'Cookie': cookie,
    'Origin': p.origin,
    'Referer': p.dashboard,
    'X-Requested-With': 'XMLHttpRequest',
    'User-Agent': _chromeUa,
    if (csrf != null && csrf.isNotEmpty) 'x-xsrf-token': csrf,
    if (csrf != null && csrf.isNotEmpty) 'x-csrf-token': csrf,
  };
  final r = await sendRequest(
    ctx,
    provider,
    Uri.parse(
      '${p.base}/data/api.json?action=${p.action}&product=sfm_bailian&api=$api&_v=undefined',
    ),
    method: 'POST',
    headers: headers,
    body: {
      'product': 'sfm_bailian',
      'action': p.action,
      'region': p.region,
      'language': 'en-US',
      'params': jsonEncode({
        'Api': api,
        'V': '1.0',
        'Data': {...data, 'cornerstoneParam': cornerstone},
      }),
      'sec_token': ?sec,
    },
    timeout: const Duration(seconds: 30),
  );
  if (r.statusCode == 401 || r.statusCode == 403) {
    throw ProviderException(
      '$provider 拒绝了这个 Cookie',
      hint: '重新复制 Cookie 请求头',
      statusCode: r.statusCode,
    );
  }
  if (!r.ok) {
    throw ProviderException('$provider 接口错误 HTTP ${r.statusCode}', statusCode: r.statusCode);
  }
  return _gatewayDecode(provider, r.body);
}

/// Per-window ratio (0..1) → percent, reset time and total from quota-config.
_Usage _parsePersonalUsage(
  Object? usage,
  Object? subscription,
  Object? quotaConfig, {
  required String? defaultPlan,
}) {
  final planCode = _firstAcross(subscription, [
    'specCode',
    'spec_code',
    'planName',
    'plan_name',
  ], asString)?.toLowerCase();
  final plan = planCode == null
      ? defaultPlan
      : const {'lite', 'standard', 'pro', 'max'}.contains(planCode)
      ? _capitalized(planCode)
      : planCode;
  final quota = planCode == null ? null : _mapForKey(quotaConfig, planCode);
  final windows = <RateWindow>[];
  final extras = <String, String>{};

  void window({
    required String ratioKey,
    required String resetKey,
    required String id,
    required String label,
    required int minutes,
    required List<String> quotaKeys,
  }) {
    final ratio = _firstAcross(usage, [ratioKey], asDouble);
    if (ratio == null) return;
    final resetsAt = parseFlexibleDate(_firstAcross<Object>(usage, [resetKey], (v) => v));
    windows.add(
      quotaWindow(
        id,
        label,
        usedPercent: (ratio * 100).clamp(0, 100).toDouble(),
        resetsAt: resetsAt,
        windowMinutes: minutes,
      ),
    );
    final total = _firstKeyNum(quota, quotaKeys);
    if (total != null) {
      extras['$label 用量'] = '${_groupNum(ratio * total)} / ${_groupNum(total)} credits used';
    }
  }

  window(
    ratioKey: 'per5HourPercentage',
    resetKey: 'per5HourResetTime',
    id: RateWindow.sessionId,
    label: '5 小时',
    minutes: 300,
    quotaKeys: const ['five_hour', 'fiveHour'],
  );
  window(
    ratioKey: 'per1WeekPercentage',
    resetKey: 'per1WeekResetTime',
    id: RateWindow.weeklyId,
    label: '每周',
    minutes: 10080,
    quotaKeys: const ['weekly'],
  );
  window(
    ratioKey: 'per1MonthPercentage',
    resetKey: 'per1MonthResetTime',
    id: 'personal-monthly',
    label: '每月',
    minutes: 43200,
    quotaKeys: const ['monthly'],
  );
  if (windows.isEmpty) throw ProviderException('个人套餐用量格式无法识别');
  return (plan: plan, windows: windows, extras: extras);
}

Map<String, Object?>? _mapForKey(Object? root, String key) {
  final queue = <Object?>[root];
  for (var i = 0; i < queue.length; i++) {
    final node = queue[i];
    if (node is Map) {
      final hit = asMap(node[key]);
      if (hit != null) return hit;
      queue.addAll(node.values);
    } else if (node is List) {
      queue.addAll(node);
    }
  }
  return null;
}

class _TokenRegion {
  const _TokenRegion({
    required this.gateway,
    required this.quoteBase,
    required this.dashboard,
    required this.productCode,
    required this.region,
    this.personal,
  });

  final String gateway;
  final String quoteBase;
  final String dashboard;
  final String productCode;
  final String region;
  final _Personal? personal;
}

const _tokenRegions = {
  'intl': _TokenRegion(
    gateway: 'https://modelstudio.console.alibabacloud.com',
    quoteBase: 'https://modelstudio.console.alibabacloud.com',
    dashboard: 'https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=plan#/efm/subscription/token-plan',
    productCode: 'sfm_tokenplanteams_dp_intl',
    region: 'ap-southeast-1',
  ),
  'cn': _TokenRegion(
    gateway: 'https://bailian.console.aliyun.com',
    quoteBase: 'https://bailian.console.aliyun.com',
    dashboard:
        'https://bailian.console.aliyun.com/cn-beijing?tab=plan#/efm/subscription/token-plan',
    productCode: 'sfm_tokenplanteams_dp_cn',
    region: 'cn-beijing',
  ),
  'intl-personal': _TokenRegion(
    gateway: 'https://modelstudio.console.alibabacloud.com',
    quoteBase: 'https://bailian-singapore-cs.alibabacloud.com',
    dashboard: 'https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=plan#/efm/subscription/token-plan/personal',
    productCode: 'sfm_tokenplansolo_public_intl',
    region: 'ap-southeast-1',
    personal: _Personal(
      base: 'https://bailian-singapore-cs.alibabacloud.com',
      origin: 'https://modelstudio.console.alibabacloud.com',
      dashboard: 'https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=plan#/efm/subscription/token-plan/personal',
      action: 'IntlBroadScopeAspnGateway',
      site: 'MODELSTUDIO_ALBABACLOUD',
      commodity: 'sfm_tokenplansolo_public_intl',
      region: 'ap-southeast-1',
      switchUser: true,
    ),
  ),
  'cn-personal': _TokenRegion(
    gateway: 'https://bailian.console.aliyun.com',
    quoteBase: 'https://bailian-cs.console.aliyun.com',
    dashboard: 'https://bailian.console.aliyun.com/cn-beijing?tab=plan#/efm/subscription/token-plan/personal',
    productCode: 'sfm_tokenplansolo_public_cn',
    region: 'cn-beijing',
    personal: _Personal(
      base: 'https://bailian-cs.console.aliyun.com',
      origin: 'https://bailian.console.aliyun.com',
      dashboard: 'https://bailian.console.aliyun.com/cn-beijing?tab=plan#/efm/subscription/token-plan/personal',
      action: 'BroadScopeAspnGateway',
      site: 'BAILIAN_ALIYUN',
      commodity: 'sfm_tokenplansolo_public_cn',
      region: 'cn-beijing',
      switchUser: true,
    ),
  ),
};

const _teamTotalKeys = [
  'totalQuota',
  'totalValue',
  'TotalValue',
  'cycleTotalValue',
  'CycleTotalValue',
];
const _teamRemainingKeys = [
  'totalSurplusValue',
  'TotalSurplusValue',
  'SurplusValue',
  'cycleSurplusValue',
  'CycleSurplusValue',
];
const _teamUsedKeys = ['usedQuota', 'UsedValue'];

class AlibabaTokenPlanProvider extends _CookieProvider {
  @override
  String get id => 'alibabatokenplan';
  @override
  String get displayName => 'Alibaba Token Plan';
  @override
  int get brandColor => 0xFFFF6A00;
  @override
  String get setupHint =>
      '浏览器登录阿里云百炼 / Model Studio 控制台，打开 Token Plan 页面，复制请求的 Cookie 请求头；区域里选择对应站点与团队版 / 个人版。接口为非公开接口，可能变动。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(label: '百炼控制台 Cookie', hint: 'login_aliyunid_ticket=...; sec_token=...'),
    ProviderField(
      key: 'region',
      label: '站点与套餐',
      kind: FieldKind.choice,
      defaultValue: 'intl',
      choices: [
        FieldChoice('intl', '国际站 团队版'),
        FieldChoice('cn', '中国站 团队版'),
        FieldChoice('intl-personal', '国际站 个人版'),
        FieldChoice('cn-personal', '中国站 个人版'),
      ],
    ),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final cookie = cookieOf(account);
    final region = _tokenRegions[FieldValues.of(this, account)['region']] ?? _tokenRegions['intl']!;
    final personal = region.personal;
    if (personal != null) {
      final usage = await _personalUsage(
        ctx,
        displayName,
        cookie,
        personal,
        requireSec: false,
        defaultPlan: 'Personal',
      );
      return snapshot(
        account,
        ctx,
        plan: usage.plan,
        source: 'web',
        windows: usage.windows,
        extras: usage.extras,
      );
    }
    final team = await _teamSummary(ctx, cookie, region);
    return snapshot(
      account,
      ctx,
      plan: team.plan,
      source: 'web',
      windows: team.windows,
      extras: team.extras,
    );
  }

  Future<_Usage> _teamSummary(FetchContext ctx, String cookie, _TokenRegion region) async {
    final sec = await _oneConsoleSecToken(
      ctx,
      displayName,
      cookie,
      dashboard: region.dashboard,
      cookieFirst: true,
    );
    final csrf = cookieValue(cookie, 'login_aliyunid_csrf') ?? cookieValue(cookie, 'csrf');
    final headers = {
      'Content-Type': _formType,
      'Accept': '*/*',
      'Cookie': cookie,
      'X-Requested-With': 'XMLHttpRequest',
      'User-Agent': _chromeUa,
      if (csrf != null && csrf.isNotEmpty) 'x-xsrf-token': csrf,
      if (csrf != null && csrf.isNotEmpty) 'x-csrf-token': csrf,
    };
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse(
        '${region.quoteBase}/data/api.json?action=GetSubscriptionSummary&product=BssOpenAPI-V3&_tag=',
      ),
      method: 'POST',
      headers: headers,
      body: {
        'product': 'BssOpenAPI-V3',
        'action': 'GetSubscriptionSummary',
        'params': jsonEncode({'ProductCode': region.productCode}),
        'region': region.region,
        'sec_token': ?sec,
      },
      timeout: const Duration(seconds: 20),
    );
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw ProviderException(
        '阿里云 Token Plan 拒绝了这个 Cookie',
        hint: '重新复制 Cookie 请求头',
        statusCode: r.statusCode,
      );
    }
    if (!r.ok) {
      throw ProviderException('阿里云 Token Plan 接口错误 HTTP ${r.statusCode}', statusCode: r.statusCode);
    }
    return _parseAlibabaTokenPlanTeam(_gatewayDecode(displayName, r.body), ctx.now());
  }
}

_Usage _parseAlibabaTokenPlanTeam(Object? root, DateTime now) {
  final total = _firstAcross(root, _teamTotalKeys, asDouble);
  final remaining = _firstAcross(root, _teamRemainingKeys, asDouble);
  final usedRaw = _firstAcross(root, _teamUsedKeys, asDouble);
  final count = _firstAcross(root, ['totalCount', 'TotalCount'], asDouble);
  if (total == null && remaining == null && usedRaw == null) {
    return (plan: null, windows: const [], extras: const {});
  }
  final reset = _firstAcross(root, [
    'NearestExpireDate',
    'nextRefreshTime',
    'resetTime',
    'periodEndTime',
  ], _plainDate);
  final plan = (count ?? 0) > 0 || total != null ? 'TOKEN PLAN' : null;
  final windows = <RateWindow>[];
  final extras = <String, String>{};
  if (total != null && total > 0) {
    final used = usedRaw ?? total - (remaining ?? 0);
    windows.add(
      quotaWindow(
        'alibaba-token-team',
        '套餐额度',
        usedPercent: pct(used, total),
        resetsAt: reset,
        windowMinutes: 43200,
      ),
    );
    extras['额度'] = '${_groupNum(used)} / ${_groupNum(total)} used';
    if (remaining != null) extras['剩余'] = _groupNum(remaining);
  }
  return (plan: plan, windows: windows, extras: extras);
}

const _qwenBase = 'https://home.qwencloud.com';

const _qwenIndividual = _Personal(
  base: 'https://cs-data.qwencloud.com',
  origin: _qwenBase,
  dashboard: '$_qwenBase/billing/subscription/token-plan-individual',
  action: 'IntlBroadScopeAspnGateway',
  site: 'QWENCLOUD',
  commodity: 'sfm_tokenplansolo_public_intl',
  region: 'ap-southeast-1',
);

class QwenCloudProvider extends _CookieProvider {
  @override
  String get id => 'qwencloud';
  @override
  String get displayName => 'Qwen Cloud';
  @override
  int get brandColor => 0xFF615CED;
  @override
  String get setupHint =>
      '浏览器登录 home.qwencloud.com，在开发者工具里复制任一请求的 Cookie 请求头。团队版与个人版都会自动识别（先团队、再个人）。接口为非公开接口，可能变动。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(label: 'home.qwencloud.com Cookie', hint: 'Cookie: ...'),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final cookie = cookieOf(account);
    ProviderException? teamError;
    try {
      final team = await _qwenTeam(ctx, cookie);
      if (team != null) {
        return snapshot(
          account,
          ctx,
          plan: team.plan,
          source: 'web',
          windows: team.windows,
          extras: team.extras,
        );
      }
    } on ProviderException catch (e) {
      teamError = e;
    }
    try {
      final usage = await _personalUsage(
        ctx,
        displayName,
        cookie,
        _qwenIndividual,
        requireSec: true,
        defaultPlan: null,
      );
      return snapshot(
        account,
        ctx,
        plan: usage.plan,
        source: 'web',
        windows: usage.windows,
        extras: usage.extras,
      );
    } on ProviderException catch (e) {
      throw teamError ?? e;
    }
  }

  /// Team plan via the console RPC; null when the account has no active team subscription.
  Future<_Usage?> _qwenTeam(FetchContext ctx, String cookie) async {
    final teamHeaders = {
      'Accept': 'application/json',
      'Referer': '$_qwenBase/analytics/token-plan/team',
      'Cookie': cookie,
    };
    final info = _qwenJson(
      await sendRequest(
        ctx,
        displayName,
        Uri.parse('$_qwenBase/tool/user/info.json'),
        headers: teamHeaders,
        timeout: const Duration(seconds: 8),
      ),
    );
    final sec = asString(asMap(info['data'])?['secToken']);
    if (sec == null) throw _loginRequired('Qwen Cloud Team');

    Future<Map<String, Object?>> rpc(
      String product,
      String action,
      String region,
      Map<String, String> params, {
      String? language,
    }) async {
      final r = await sendRequest(
        ctx,
        displayName,
        Uri.parse('$_qwenBase/data/api.json?product=$product&action=$action'),
        method: 'POST',
        headers: {...teamHeaders, 'Origin': _qwenBase, 'Content-Type': _formType},
        body: {
          'product': product,
          'action': action,
          'sec_token': sec,
          'region': region,
          'language': ?language,
          'params': jsonEncode(params),
        },
        timeout: const Duration(seconds: 8),
      );
      final root = _qwenJson(r);
      final data = asMap(root['data']);
      if (root['successResponse'] == false || data?['Success'] == false) {
        throw ProviderException('Qwen Cloud Team $action 失败', hint: '稍后再试');
      }
      if ((root['successResponse'] != true && root['code'] != '200') || data == null) {
        throw _teamField('gateway envelope');
      }
      return data;
    }

    final human = await rpc('ea-service', 'LoadHumanInfo', 'ap-southeast-1', const {});
    final nbid = asString(asMap(asMap(human['Data'])?['SellerInfoDto'])?['Nbid']);
    final summary = await rpc('BssOpenAPI-V3', 'GetSeatSubscriptionSummary', 'cn-hangzhou', {
      'productCode': 'sfm_tokenplanteams_dp_intl',
      'Nbid': ?nbid,
    }, language: 'zh-CN');
    final data = summary['Data'] == null
        ? <String, Object?>{}
        : (asMap(summary['Data']) ?? (throw _teamField('subscription')));
    if (data.isEmpty) return null;
    final groups =
        asList(data['SubscriptionGroupList']) ?? (throw _teamField('subscription groups'));
    if (groups.isEmpty) return null;
    final start = _digitsNumber(data['StartTime']);
    final end = _digitsNumber(data['EndTime']);
    if (start == null || end == null || start <= 0 || end <= start) {
      throw _teamField('subscription period');
    }
    final nowMs = ctx.now().millisecondsSinceEpoch;
    if (nowMs < start || nowMs >= end) return null;
    if (data['ProductCode'] != 'sfm_tokenplanteams_dp_intl') {
      throw _teamField('subscription product');
    }
    if (groups.length != 1) throw _teamField('multiple credit pools');
    final group = asMap(groups.first) ?? (throw _teamField('subscription group'));
    final equityList = asList(group['EquityList']) ?? (throw _teamField('credit equity'));
    final equities = equityList
        .map(asMap)
        .whereType<Map<String, Object?>>()
        .where((e) => e['EquityCode'] == 'credit_value')
        .toList();
    if (equities.length != 1) throw _teamField('credit equity');
    final total = _digitsNumber(equities.first['TotalValue']) ?? (throw _teamField('credit count'));
    final remaining =
        _digitsNumber(equities.first['SurplusValue']) ?? (throw _teamField('credit count'));
    if (total <= 0 || remaining > total) throw _teamField('credit count');
    final used = total - remaining;

    final assigned = group['SubscriptionAssignedNumber'];
    final seats = group['SubscriptionTotalNumber'];
    final flush = group['NextCycleFlushTime'];
    final reset = flush == null ? null : _digitsNumber(flush);
    if (flush != null && (reset == null || reset <= 0)) throw _teamField('cycle reset');
    final specType = asString(group['SpecType']);
    final specLabel = specType != null && RegExp(r'^[a-z][a-z0-9_-]{0,39}$').hasMatch(specType)
        ? '${_capitalized(specType)} Team'
        : 'Team Token Plan';
    return (
      plan: specLabel,
      windows: [
        quotaWindow(
          'qwen-team',
          '团队额度',
          usedPercent: pct(used, total),
          resetsAt: reset == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(reset.toInt(), isUtc: true),
        ),
      ],
      extras: {
        'Credits': '${_groupNum(used)} / ${_groupNum(total)} credits used',
        'Remaining': '${_groupNum(remaining)} credits',
        if (assigned is int && seats is int && assigned >= 0 && seats >= assigned)
          'Seats': '$assigned / $seats',
      },
    );
  }

  Map<String, Object?> _qwenJson(HttpResult r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw ProviderException(
        'Qwen Cloud Team 登录已过期',
        hint: '重新登录 home.qwencloud.com 后复制 Cookie',
        statusCode: r.statusCode,
      );
    }
    if (r.statusCode == 429) {
      throw ProviderException('Qwen Cloud Team 请求过于频繁', hint: '稍后再试', statusCode: 429);
    }
    if (!r.ok) {
      throw ProviderException(
        'Qwen Cloud Team 接口返回 HTTP ${r.statusCode}',
        statusCode: r.statusCode,
      );
    }
    final root =
        asMap(_decodeJsonOr(r.body, 'Qwen Cloud Team 返回了无法解析的数据')) ??
        (throw _teamField('response'));
    final code = asString(root['code']);
    if (code != null &&
        const {'ConsoleNeedLogin', 'BailianGateway.Login.NotLogined', 'NO_LOGIN'}.contains(code)) {
      throw _loginRequired('Qwen Cloud Team');
    }
    return root;
  }

  ProviderException _teamField(String field) =>
      ProviderException('Qwen Cloud Team 返回了不支持的 $field', hint: '请到用量页面检查');
}

// ------------------------------------------------------------------ OpenCode

const _ocBase = 'https://opencode.ai/console/api';
const _ocCookieNames = {'auth', '__Host-auth', '__Host-console_session'};

class OpenCodeProvider extends _CookieProvider {
  @override
  String get id => 'opencode';
  @override
  String get displayName => 'OpenCode';
  @override
  int get brandColor => 0xFF3B82F6;
  @override
  String get setupHint =>
      '浏览器登录 opencode.ai，在开发者工具里复制请求的 Cookie 请求头（需包含 auth 或 __Host-console_session）。工作区 ID 可留空自动发现。';
  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(label: 'opencode.ai Cookie', hint: 'auth=...; __Host-console_session=...'),
    ProviderField(
      key: 'workspaceId',
      label: '工作区 ID（可选）',
      kind: FieldKind.text,
      required: false,
      hint: 'wrk_...',
      envVars: ['CODEXBAR_OPENCODE_WORKSPACE_ID'],
    ),
  ];

  @override
  String? cookieProblem(String header) => header.isEmpty
      ? '请粘贴 Cookie 请求头'
      : (_keepCookies(header, _ocCookieNames).isEmpty
            ? 'Cookie 中没有 OpenCode 登录信息 (auth / __Host-console_session)'
            : null);

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final cookie = _keepCookies(cookieOf(account), _ocCookieNames);
    final raw = FieldValues.of(this, account)['workspaceId'];
    final String workspace;
    if (raw == null) {
      workspace = await _discoverWorkspace(ctx, cookie);
    } else {
      workspace =
          _opencodeWorkspaceId(raw) ??
          (throw ProviderException(
            '工作区 ID 无效',
            hint: '填写 wrk_ 或 org_ 开头的 ID，或 opencode.ai 控制台 URL',
          ));
    }

    final statusText = await _consoleText(ctx, cookie, '$_ocBase/go/status', workspace: workspace);
    final statusJson = _decodeJsonOr(statusText, 'OpenCode Console 返回了无效数据');
    final statusMap = asMap(statusJson);
    final quota = _opencodeQuota(statusMap, ctx.now());
    if (quota != null) {
      return snapshot(
        account,
        ctx,
        source: 'web',
        windows: quota.windows,
        extras: {if (quota.renewsAt != null) '下次续订': quota.renewsAt!.toIso8601String()},
      );
    }
    final noSubscription =
        statusJson == null ||
        (statusMap != null && statusMap.containsKey('access') && statusMap['access'] == null);
    if (!noSubscription) throw ProviderException('OpenCode 用量数据格式无法识别');
    return _opencodePayg(account, ctx, cookie, workspace);
  }

  Future<String> _discoverWorkspace(FetchContext ctx, String cookie) async {
    final rows =
        asList(
          _decodeJsonOr(await _consoleText(ctx, cookie, '$_ocBase/orgs'), 'OpenCode 工作区列表无法解析'),
        ) ??
        const <Object?>[];
    for (final row in rows) {
      final id = asString(asMap(row)?['id']);
      if (id != null && _opencodeWorkspaceId(id) == id) return id;
    }
    throw ProviderException('OpenCode Console 缺少工作区 ID', hint: '在账户设置里手动填写工作区 ID');
  }

  Future<String> _consoleText(
    FetchContext ctx,
    String cookie,
    String url, {
    String? workspace,
  }) async {
    final r = await sendRequest(
      ctx,
      displayName,
      Uri.parse(url),
      headers: {
        'Cookie': cookie,
        'User-Agent': 'CodexBar',
        'Accept': 'application/json',
        'x-org-id': ?workspace,
      },
      timeout: const Duration(seconds: 20),
    );
    if (r.statusCode == 401) {
      throw ProviderException(
        'OpenCode 登录已过期',
        hint: '重新复制 opencode.ai 的 Cookie 请求头',
        statusCode: 401,
      );
    }
    if (!r.ok) {
      throw ProviderException('OpenCode Console 返回 HTTP ${r.statusCode}', statusCode: r.statusCode);
    }
    return r.body;
  }

  /// Pay-as-you-go account: spend from the last 30 days, optional prepaid balance.
  Future<UsageSnapshot> _opencodePayg(
    AccountConfig account,
    FetchContext ctx,
    String cookie,
    String workspace,
  ) async {
    final org = asMap(
      _decodeJsonOr(
        await _consoleText(ctx, cookie, '$_ocBase/orgs/current', workspace: workspace),
        'Console 组织信息无法解析',
      ),
    );
    if (org?['hasGoSubscription'] != false) {
      throw ProviderException('OpenCode 用量接口不可用', hint: '该工作区有订阅但未返回用量');
    }
    final billingText = await _consoleText(
      ctx,
      cookie,
      '$_ocBase/billing/status',
      workspace: workspace,
    );
    final billing = asMap(_decodeJsonOr(billingText, 'Console 计费信息无法解析'));
    if (billing?['mode'] != 'pay-as-you-go') {
      throw ProviderException('没有可用的 OpenCode 按量计费账单', hint: '确认工作区的计费模式');
    }
    final summary = asMap(
      _decodeJsonOr(
        await _consoleText(ctx, cookie, '$_ocBase/usage/summary?range=30d', workspace: workspace),
        'Console 用量汇总无法解析',
      ),
    );
    final totalRaw = summary?['totalCostMicroCents'];
    final totalMicro = totalRaw is String && RegExp(r'^\d+$').hasMatch(totalRaw)
        ? double.tryParse(totalRaw)
        : _finite(totalRaw);
    if (totalMicro == null) throw ProviderException('OpenCode 用量汇总格式无效');
    final balanceMicro = _opencodeBalanceMicro(billing);
    return snapshot(
      account,
      ctx,
      source: 'web',
      credits: [
        Credits(
          id: 'opencode-spend',
          label: '近 30 天花费',
          used: totalMicro / 100000000,
          balance: balanceMicro == null ? null : balanceMicro / 100000000,
          currency: 'USD',
        ),
      ],
    );
  }
}

/// Prepaid balance (micro-cents) only for `prepaid` + `pay-as-you-go` billing.
double? _opencodeBalanceMicro(Map<String, Object?>? billing) {
  if (billing == null) return null;
  if (billing['billingMode'] != 'prepaid' || billing['mode'] != 'pay-as-you-go') return null;
  final raw = billing['balanceMicroCents'];
  if (raw is! String || !RegExp(r'^-?\d+$').hasMatch(raw)) return null;
  return double.tryParse(raw);
}

String? _opencodeWorkspaceId(String raw) {
  final text = raw.trim();
  final id = RegExp(r'^(?:wrk_|org_)[A-Za-z0-9_-]+$');
  if (id.hasMatch(text)) return text;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.host != 'opencode.ai') return null;
  final segments = uri.pathSegments;
  final i = segments.indexOf('console');
  if (i < 0 || i + 1 >= segments.length) return null;
  return id.hasMatch(segments[i + 1]) ? segments[i + 1] : null;
}

({List<RateWindow> windows, DateTime? renewsAt})? _opencodeQuota(
  Map<String, Object?>? root,
  DateTime now,
) {
  final access = asMap(root?['access']);
  final meters = asMap(access?['meters']);
  final fiveHour = asMap(meters?['fiveHour']);
  if (access == null || meters == null || fiveHour == null) return null;
  final primary = _opencodeWindow(fiveHour, now);
  if (primary == null) return null;
  final week = asMap(meters['week']);
  final weekly = week == null ? null : _opencodeWindow(week, now);
  final month = asMap(meters['month']);
  final monthlyRaw = month == null ? null : Map<String, Object?>.of(month);
  if (monthlyRaw != null && monthlyRaw['resetsAt'] == null) {
    monthlyRaw['resetsAt'] = access['endsAt'];
  }
  final monthly = monthlyRaw == null ? null : _opencodeWindow(monthlyRaw, now);
  final renewsAt = parseFlexibleDate(access['endsAt']);
  return (
    windows: [
      quotaWindow(
        RateWindow.sessionId,
        '5 小时',
        usedPercent: primary.percent,
        resetsAt: primary.resetsAt,
        windowMinutes: 300,
      ),
      if (weekly != null)
        quotaWindow(
          RateWindow.weeklyId,
          '每周',
          usedPercent: weekly.percent,
          resetsAt: weekly.resetsAt,
          windowMinutes: 10080,
        ),
      if (monthly != null)
        quotaWindow(
          'opencode-monthly',
          '每月',
          usedPercent: monthly.percent,
          resetsAt: monthly.resetsAt,
        ),
    ],
    renewsAt: renewsAt,
  );
}

({double percent, DateTime? resetsAt})? _opencodeWindow(Map<String, Object?> m, DateTime now) {
  var percent = _firstKeyNum(m, const ['usagePercent', 'usedPercent', 'percentUsed', 'percent']);
  final direct = percent != null;
  if (percent == null) {
    final used = _firstKeyNum(m, const [
      'used',
      'usage',
      'consumed',
      'count',
      'usedTokens',
      'usedMicroCents',
    ]);
    final limit = _firstKeyNum(m, const [
      'limit',
      'total',
      'quota',
      'max',
      'cap',
      'tokenLimit',
      'limitMicroCents',
    ]);
    if (used != null && limit != null && limit > 0) percent = used / limit * 100;
  }
  if (percent == null) return null;
  // Direct values may be fractions (0...1) on dashboard JSON.
  if (direct && percent >= 0 && percent <= 1) percent *= 100;
  final clamped = percent.clamp(0, 100).toDouble();
  final seconds = _firstKeyNum(m, const [
    'resetInSec',
    'resetInSeconds',
    'resetSeconds',
    'reset_sec',
  ]);
  final DateTime? resetsAt;
  if (seconds != null) {
    resetsAt = now.add(Duration(seconds: max(0, seconds.toInt())));
  } else {
    resetsAt = parseFlexibleDate(
      _firstKeyValue(m, const ['resetAt', 'resetsAt', 'reset_at', 'resets_at']),
    );
  }
  return (percent: clamped, resetsAt: resetsAt);
}
