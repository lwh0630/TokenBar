import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/account.dart';
import '../../models/model_usage.dart';
import '../../models/usage_snapshot.dart';
import '../../platform/platform.dart' as platform;
import '../../util/json_utils.dart';
import '../browser_cookie_source.dart';
import '../fields.dart';
import '../provider.dart';
import 'cursor_session.dart';
import 'cursor_usage_events.dart';
import 'cursor_usage_parser.dart';

/// Cursor plan usage from cursor.com's dashboard API, authenticated with the
/// local Cursor login (read-only) or a pasted cursor.com cookie.
class CursorProvider extends UsageProvider {
  static const _baseUrl = 'https://cursor.com';
  static final Map<String, String?> _emailByCookie = {};

  /// Events per page, as CodexBar's `CursorUsageEventsFetcher` requests.
  static const _eventPageSize = 1000;

  /// Safety cap: 20 pages (20k events) per billing cycle. Beyond that the per-model
  /// rows are reported as unavailable rather than summed from a partial list.
  static const _maxEventPages = 20;

  @override
  String get id => 'cursor';

  @override
  String get displayName => 'Cursor';

  @override
  int get brandColor => 0xFF5E6AD2;

  @override
  List<SourceType> get supportedSources => const [SourceType.localCli, SourceType.apiKey];

  @override
  String get setupHint =>
      '本机模式读取 Cursor 桌面端的登录状态（只读，不刷新令牌）。'
      '手动模式：浏览器登录 cursor.com，在开发者工具里复制请求的 Cookie（含 WorkosCursorSessionToken）粘贴进来，手机也能用。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.cookie(
      label: 'cursor.com Cookie',
      hint: 'WorkosCursorSessionToken=...',
      help: '浏览器登录 cursor.com → 开发者工具 → 网络 → 任一请求的 Cookie 请求头；桌面端也可留空，自动读取浏览器登录',
      required: false,
    ),
    cookieSourceField,
  ];

  @override
  String get manualSourceLabel => '手动粘贴 Cookie';

  @override
  String get localSourceLabel => '本机 Cursor 登录';

  @override
  String? validateManual(FieldValues values) {
    final secret = values[ProviderField.secretKey];
    if (secret == null || CursorSession.fromManual(secret) != null) return null;
    return '无法识别：需要包含 WorkosCursorSessionToken 的 Cookie';
  }

  @override
  Future<bool> hasLocalLogin(AccountConfig account) async =>
      platform.localAccessSupported &&
      await loadLocalCursorSession(userDataDir: account.homeDir) != null;

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final session = await _session(account, ctx);
    if (session.isExpired(ctx.now())) {
      throw ProviderException(
        'Cursor 登录已过期',
        hint: session.source == 'manual' ? '重新复制 cursor.com 的 Cookie' : '打开 Cursor 让它自动续期登录',
        statusCode: 401,
      );
    }
    final results = await Future.wait([
      _get('/api/usage-summary', session, ctx),
      _email(session, ctx),
    ]);
    final usage = parseCursorUsageSummary(results[0] as Map<String, Object?>);
    final models = await _modelUsage(session, usage.cycleStart, ctx);
    return UsageSnapshot(
      accountId: account.id,
      providerId: id,
      fetchedAt: ctx.now(),
      plan: usage.plan,
      email: (results[1] as String?) ?? session.email,
      source: switch (session.source) {
        'app' => 'cursor-app',
        'cli' => 'cursor-agent',
        _ => 'cookie',
      },
      windows: usage.windows,
      credits: usage.credits,
      extras: cursorModelExtras(models),
    );
  }

  /// Per-model usage for the current billing cycle from the dashboard events feed.
  ///
  /// Best-effort: any failure or unrecognised page yields null (shown as unavailable),
  /// and never fails the quota snapshot itself.
  Future<List<CursorModelUsage>?> _modelUsage(
    CursorSession session,
    DateTime? cycleStart,
    FetchContext ctx,
  ) async {
    if (cycleStart == null) return null;
    final events = await _fetchEvents(session, cycleStart, ctx.now(), ctx);
    return events == null ? null : summarizeCursorModelUsage(events);
  }

  /// Per-model usage over time for the history chart, from the same events feed. Works
  /// with the local Cursor login and with a pasted cookie. Never throws: any failure,
  /// expired login or unreconcilable page set yields null.
  @override
  Future<ModelUsageSeries?> fetchModelUsage(
    AccountConfig account,
    FetchContext ctx, {
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final session = await _session(account, ctx);
      if (session.isExpired(ctx.now())) return null;
      final events = await _fetchEvents(session, from, to, ctx);
      if (events == null) return null;
      return buildCursorModelUsageSeries(events, from: from, to: to);
    } catch (_) {
      return null;
    }
  }

  /// Every event in `[start, end]`, or null when the feed cannot be read completely (at
  /// most [_maxEventPages] pages; never a partial list). Any failure yields null.
  Future<List<CursorUsageEvent>?> _fetchEvents(
    CursorSession session,
    DateTime start,
    DateTime end,
    FetchContext ctx,
  ) async {
    try {
      final pages = <List<CursorUsageEvent>>[];
      int? expectedTotal;
      var completed = false;
      for (var page = 1; page <= _maxEventPages; page++) {
        final json = await _post(
          '/api/dashboard/get-filtered-usage-events',
          {
            'page': page,
            'pageSize': _eventPageSize,
            'startDate': '${start.millisecondsSinceEpoch}',
            'endDate': '${end.millisecondsSinceEpoch}',
          },
          session,
          ctx,
        );
        final parsed = parseCursorUsageEventsPage(json);
        if (parsed == null) return null;
        if (parsed.total != null) {
          if (expectedTotal != null && expectedTotal != parsed.total) return null;
          expectedTotal = parsed.total;
        }
        if (parsed.events.isEmpty) {
          completed = true;
          break;
        }
        pages.add(parsed.events);
        if (parsed.events.length < _eventPageSize) {
          completed = true;
          break;
        }
      }
      if (!completed) return null;
      return reconcileCursorEventPages(pages, expectedTotal);
    } catch (_) {
      return null;
    }
  }

  Future<CursorSession> _session(AccountConfig account, FetchContext ctx) async {
    if (account.sourceType == SourceType.apiKey) {
      // The signed-in browser's cookies when allowed (desktop, read-only), else the pasted one.
      final resolved = await resolveAccountCookie(
        this,
        account,
        ctx,
        hosts: const ['cursor.com', 'www.cursor.com'],
        requiredNames: const ['WorkosCursorSessionToken'],
      );
      final session = CursorSession.fromManual(resolved.header);
      if (session == null) {
        throw ProviderException('无法识别的 Cursor Cookie', hint: '需要包含 WorkosCursorSessionToken');
      }
      return session;
    }
    if (!platform.localAccessSupported) {
      throw ProviderException('此平台无法读取本机 Cursor 登录', hint: '改用"手动粘贴 Cookie"方式');
    }
    final session = await loadLocalCursorSession(userDataDir: account.homeDir);
    if (session == null) {
      throw ProviderException('未找到 Cursor 登录', hint: '打开 Cursor 桌面端并登录，或改用手动粘贴 Cookie');
    }
    return session;
  }

  Future<Map<String, Object?>> _get(String path, CursorSession session, FetchContext ctx) async {
    final response = await ctx.client
        .get(
          Uri.parse('$_baseUrl$path'),
          headers: {'Accept': 'application/json', 'Cookie': session.cookieHeader},
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response, session);
  }

  /// POST with a JSON body. Cursor enforces CSRF on these endpoints, so `Origin` must match.
  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
    CursorSession session,
    FetchContext ctx,
  ) async {
    final response = await ctx.client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Cookie': session.cookieHeader,
            'Origin': _baseUrl,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    return _decode(response, session);
  }

  Map<String, Object?> _decode(http.Response response, CursorSession session) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ProviderException(
        'Cursor 拒绝了登录凭证 (HTTP ${response.statusCode})',
        hint: session.source == 'manual' ? '重新复制 cursor.com 的 Cookie' : '在 Cursor 中重新登录',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw ProviderException(
        'Cursor 接口错误 HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final json = decodeJsonObject(utf8.decode(response.bodyBytes));
    if (json == null) throw ProviderException('Cursor 接口返回了无效数据');
    return json;
  }

  Future<String?> _email(CursorSession session, FetchContext ctx) async {
    if (_emailByCookie.containsKey(session.cookieHeader)) {
      return _emailByCookie[session.cookieHeader];
    }
    String? email;
    try {
      email = asString((await _get('/api/auth/me', session, ctx))['email']);
    } catch (_) {
      email = null;
    }
    return _emailByCookie[session.cookieHeader] = email;
  }
}
