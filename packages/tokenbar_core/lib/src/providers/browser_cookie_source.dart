import '../models/account.dart';
import '../platform/browser_cookies.dart';
import '../platform/platform.dart' as platform;
import 'fields.dart';
import 'provider.dart';

/// Per-account choice between reading the signed-in browser's cookies and a pasted copy.
///
/// Browser cookies are read-only, desktop-only, only for the provider's own hosts, and never
/// stored: the header lives for one fetch (see AGENTS.md → "Browser cookie import").
const cookieSourceField = ProviderField(
  key: 'cookieSource',
  label: 'Cookie 来源',
  kind: FieldKind.choice,
  required: false,
  defaultValue: 'auto',
  choices: [FieldChoice('auto', '自动读取浏览器登录（桌面端，只读）'), FieldChoice('manual', '仅使用手动粘贴的 Cookie')],
);

/// True on platforms that have browser profiles TokenBar can read.
bool get browserCookiesAvailable => platform.isWindows || platform.isMacOS || platform.isLinux;

/// Whether the account's settings ask for browser cookies on this platform (the default on
/// desktop). Used by validation, which has no [FetchContext].
bool cookieSourceIsAuto(FieldValues values) =>
    browserCookiesAvailable && values['cookieSource'] != 'manual';

/// Cookie source for one fetch.
typedef ResolvedCookie = ({String header, String source});

/// The Cookie header to use: the signed-in browser's (when the account is on automatic and
/// the context allows it), else the [pasted] one. Throws a [ProviderException] with the
/// reader's reason when neither exists.
///
/// Automatic wins over a pasted copy because browsers rotate session tokens; a pasted copy is
/// the fallback, so an account keeps working when the browser store cannot be read.
Future<ResolvedCookie> resolveCookieHeader({
  required FetchContext ctx,
  required FieldValues values,
  required String provider,
  required List<String> hosts,
  List<String> requiredNames = const [],
  String? pasted,
}) async {
  final environment = ctx.browserCookies;
  final auto = environment != null && cookieSourceIsAuto(values);
  String? problem;
  if (auto) {
    final read = await readBrowserCookies(
      hosts: hosts,
      requiredNames: requiredNames,
      environment: environment,
    );
    final header = read.header;
    if (header != null) {
      return (header: header, source: 'browser:${read.browser?.name ?? 'unknown'}');
    }
    problem = read.problem;
  }
  if (pasted != null && pasted.trim().isNotEmpty) return (header: pasted.trim(), source: 'pasted');
  if (auto) {
    throw ProviderException(
      problem ?? '没有在浏览器里找到 $provider 的登录 Cookie',
      hint: '在 Firefox 或 Chrome / Edge 里登录 $provider 后刷新，或把「Cookie 来源」改为手动粘贴',
      statusCode: 401,
    );
  }
  throw ProviderException('未填写 $provider 的 Cookie', hint: '在账户设置中粘贴 Cookie');
}

/// Account-level convenience for providers whose primary secret is the Cookie.
Future<ResolvedCookie> resolveAccountCookie(
  UsageProvider provider,
  AccountConfig account,
  FetchContext ctx, {
  required List<String> hosts,
  List<String> requiredNames = const [],
}) => resolveCookieHeader(
  ctx: ctx,
  values: FieldValues.of(provider, account),
  provider: provider.displayName,
  hosts: hosts,
  requiredNames: requiredNames,
  pasted: FieldValues.of(provider, account)[ProviderField.secretKey],
);
