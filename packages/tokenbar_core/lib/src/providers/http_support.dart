import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/json_utils.dart';
import 'provider.dart';

/// A browser-like UA for dashboard endpoints that reject unknown clients.
const browserUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.0 Safari/605.1.15';

class HttpResult {
  HttpResult(this.statusCode, this.body, this.headers);

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get ok => statusCode >= 200 && statusCode < 300;

  Object? get json {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

/// Sends a request and returns the raw result; only network failures and
/// timeouts throw.
Future<HttpResult> sendRequest(
  FetchContext ctx,
  String provider,
  Uri url, {
  String method = 'GET',
  Map<String, String> headers = const {},
  Object? body,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final request = http.Request(method, url)
    ..headers.addAll({'Accept': 'application/json', ...headers});
  if (body != null) {
    if (body is String) {
      request.body = body;
    } else if (body is Map<String, String> && headers['Content-Type']?.contains('form') == true) {
      request.bodyFields = body;
    } else {
      request.headers.putIfAbsent('Content-Type', () => 'application/json');
      request.body = jsonEncode(body);
    }
  }
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

/// Like [sendRequest] but maps non-2xx statuses to [ProviderException]s.
/// [authHint] is shown for 401/403.
Future<HttpResult> sendChecked(
  FetchContext ctx,
  String provider,
  Uri url, {
  String method = 'GET',
  Map<String, String> headers = const {},
  Object? body,
  String authHint = '检查凭证是否正确或已过期',
  Duration timeout = const Duration(seconds: 20),
}) async {
  final result = await sendRequest(
    ctx,
    provider,
    url,
    method: method,
    headers: headers,
    body: body,
    timeout: timeout,
  );
  return checkStatus(provider, result, authHint: authHint);
}

/// Returns [result] when 2xx, else throws the matching [ProviderException].
HttpResult checkStatus(String provider, HttpResult result, {String authHint = '检查凭证是否正确或已过期'}) {
  if (result.ok) return result;
  final detail = errorDetail(result.body);
  final suffix = detail == null ? '' : ': $detail';
  if (result.statusCode == 401 || result.statusCode == 403) {
    throw ProviderException(
      '$provider 拒绝了凭证 (HTTP ${result.statusCode})$suffix',
      hint: authHint,
      statusCode: result.statusCode,
    );
  }
  if (result.statusCode == 429) {
    throw ProviderException('$provider 请求过于频繁 (HTTP 429)', hint: '稍后再试', statusCode: 429);
  }
  throw ProviderException(
    '$provider 接口错误 HTTP ${result.statusCode}$suffix',
    statusCode: result.statusCode,
  );
}

/// GETs/POSTs and decodes a JSON object (or throws).
Future<Map<String, Object?>> fetchJsonObject(
  FetchContext ctx,
  String provider,
  Uri url, {
  String method = 'GET',
  Map<String, String> headers = const {},
  Object? body,
  String authHint = '检查凭证是否正确或已过期',
  Duration timeout = const Duration(seconds: 20),
}) async {
  final result = await sendChecked(
    ctx,
    provider,
    url,
    method: method,
    headers: headers,
    body: body,
    authHint: authHint,
    timeout: timeout,
  );
  final map = asMap(result.json);
  if (map == null) {
    throw ProviderException(
      '$provider 返回了无法解析的数据',
      hint: _looksLikeHtml(result.body) ? '可能需要重新登录' : null,
    );
  }
  return map;
}

bool _looksLikeHtml(String body) => body.trimLeft().startsWith('<');

/// Best-effort short error message from a JSON error body.
String? errorDetail(String body) {
  final map = decodeJsonObject(body);
  if (map == null) return null;
  final error = map['error'];
  final candidates = [
    if (error is Map) error['message'],
    if (error is String) error,
    map['message'],
    map['detail'],
    map['msg'],
  ];
  for (final c in candidates) {
    final s = asString(c);
    if (s != null) return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
  return null;
}

/// Parses ISO-8601 strings, epoch seconds or epoch milliseconds.
DateTime? parseFlexibleDate(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final asNum = num.tryParse(trimmed);
    if (asNum == null) return DateTime.tryParse(trimmed)?.toUtc();
    value = asNum;
  }
  if (value is num) {
    if (value <= 0) return null;
    final ms = value > 1e12 ? value.toInt() : (value * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  return null;
}

/// Normalizes user input that may be a full `Cookie:` header line, a cURL
/// snippet's `-H 'Cookie: …'`/`-b '…'` argument, or the bare header value.
/// Strips copy artifacts (a `Cookie` label with colon/tab separator, line
/// wraps, control and non-ASCII characters) that would make dart:io reject
/// the header value.
String normalizeCookieHeader(String input) {
  var text = input.trim();
  final curl = RegExp(
    r'''(?:-H\s+['"]cookie:\s*|(?:-b|--cookie)\s+['"])([^'"]+)['"]''',
    caseSensitive: false,
  ).firstMatch(text);
  if (curl != null) text = curl.group(1)!;
  // `Cookie: value` and the tab-separated `Cookie\tvalue` form DevTools can
  // produce; a bare pair like `cookie=1` has no separator and is kept whole.
  text = text.replaceFirst(RegExp(r'^cookie(?::|\s)\s*', caseSensitive: false), '');
  // Wrapped copies put each pair on its own line.
  text = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
  // A tab between pairs separates them; a tab inside a value is a copy artifact.
  text = text.replaceAll('\t', '; ');
  // A literal U+2026 means the value was copied from a UI preview that
  // truncates long headers — the middle of the cookie is simply missing.
  // Fail loudly instead of silently shipping a mangled credential.
  if (text.contains('\u2026')) {
    throw ProviderException(
      'Cookie 被截断了（值里带有省略号 …）',
      hint: '预览面板里的长值是显示截断的。请在 DevTools 的 Request Headers 里找到 Cookie 一行，右键选「复制值」',
    );
  }
  // Header values must be printable ASCII: drop zero-width/full-width or
  // other non-ASCII characters and remaining control characters.
  text = text.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  text = text.trim();
  // A bare value (a single token, no separators) is legitimate input —
  // callers wrap it as `name=value`. Anything structured (pairs separated by
  // `;` or spaces) must contain at least one `=`, and input that cleaned to
  // nothing is garbage. Both misfires would fail at the server anyway.
  final bareValue = text.isNotEmpty && !text.contains(RegExp(r'[\s;=]'));
  if (text.isEmpty || (!bareValue && !text.contains('='))) {
    throw ProviderException(
      'Cookie 格式无法识别',
      hint: '在 DevTools 的 Network 面板选中请求，在 Request Headers 的 Cookie 一行右键「复制值」，只粘贴值本身',
    );
  }
  return text;
}

/// Value of one cookie in a Cookie header, or null.
String? cookieValue(String cookieHeader, String name) {
  for (final part in cookieHeader.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    if (part.substring(0, i).trim() == name) return part.substring(i + 1).trim();
  }
  return null;
}

/// Accepts either a full Cookie header or a bare value of [name].
String cookieHeaderFor(String input, String name) {
  final header = normalizeCookieHeader(input);
  final looksLikeHeader = header.contains(';') || RegExp(r'^[\w\-.]+=[^=]').hasMatch(header);
  return looksLikeHeader ? header : '$name=$header';
}

/// Strips an optional `Bearer ` prefix.
String bareToken(String input) =>
    input.trim().replaceFirst(RegExp(r'^bearer\s+', caseSensitive: false), '');
