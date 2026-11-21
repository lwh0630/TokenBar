import '../../platform/platform.dart' as platform;
import '../../util/json_utils.dart';

/// Tokens from Codex CLI's `auth.json` (`$CODEX_HOME/auth.json`).
class CodexCredentials {
  const CodexCredentials({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.accountId,
    this.expiresAt,
    this.email,
    this.planFromToken,
    this.isApiKey = false,
  });

  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final String? accountId;
  final DateTime? expiresAt;
  final String? email;
  final String? planFromToken;
  final bool isApiKey;

  bool isExpired(DateTime now) {
    final exp = expiresAt;
    return exp != null && !now.isBefore(exp);
  }

  /// Parses `auth.json`. Returns null when the file holds no usable tokens.
  static CodexCredentials? parse(String text) {
    final json = decodeJsonObject(text);
    if (json == null) return null;

    final tokens = asMap(json['tokens']);
    final access = tokens == null ? null : asString(pick(tokens, ['access_token', 'accessToken']));
    if (tokens != null && access != null) {
      final idToken = asString(pick(tokens, ['id_token', 'idToken']));
      final idClaims = decodeJwtPayload(idToken);
      final accessClaims = decodeJwtPayload(access);
      return CodexCredentials(
        accessToken: access,
        refreshToken: asString(pick(tokens, ['refresh_token', 'refreshToken'])),
        idToken: idToken,
        accountId:
            asString(pick(tokens, ['account_id', 'accountId'])) ??
            _accountIdFromClaims(idClaims) ??
            _accountIdFromClaims(accessClaims),
        expiresAt: epochSeconds(asInt(accessClaims?['exp'])),
        email: _emailFromClaims(idClaims) ?? _emailFromClaims(accessClaims),
        planFromToken: _planFromClaims(idClaims) ?? _planFromClaims(accessClaims),
      );
    }

    final apiKey = asString(json['OPENAI_API_KEY']);
    if (apiKey != null) {
      return CodexCredentials(accessToken: apiKey, isApiKey: true);
    }
    return null;
  }

  static String? _accountIdFromClaims(Map<String, Object?>? claims) {
    if (claims == null) return null;
    final direct = asString(claims['chatgpt_account_id']);
    if (direct != null) return direct;
    final auth = asMap(claims['https://api.openai.com/auth']);
    final nested = auth == null ? null : asString(auth['chatgpt_account_id']);
    if (nested != null) return nested;
    final orgs = asList(claims['organizations']);
    if (orgs != null) {
      for (final org in orgs) {
        final id = asString(asMap(org)?['id']);
        if (id != null) return id;
      }
    }
    return null;
  }

  static String? _emailFromClaims(Map<String, Object?>? claims) {
    if (claims == null) return null;
    return asString(claims['email']) ??
        asString(asMap(claims['https://api.openai.com/profile'])?['email']);
  }

  static String? _planFromClaims(Map<String, Object?>? claims) {
    if (claims == null) return null;
    return asString(asMap(claims['https://api.openai.com/auth'])?['chatgpt_plan_type']);
  }
}

Future<CodexCredentials?> readCodexCredentials(String home) async {
  final text = await platform.readTextFile(platform.joinPath(home, 'auth.json'));
  return text == null ? null : CodexCredentials.parse(text);
}

/// Resolves the Codex home for an account: explicit dir, `$CODEX_HOME`,
/// then `~/.codex`.
String? resolveCodexHome(String? override) {
  if (override != null && override.trim().isNotEmpty) return override.trim();
  final env = platform.envVar('CODEX_HOME');
  if (env != null) return env;
  final home = platform.homeDirectory();
  return home == null ? null : platform.joinPath(home, '.codex');
}

const defaultChatGptBaseUrl = 'https://chatgpt.com/backend-api/';

/// Reads `chatgpt_base_url` from Codex `config.toml` (comments ignored).
String? parseChatGptBaseUrl(String contents) {
  for (final rawLine in contents.split(RegExp(r'\r?\n'))) {
    final line = rawLine.split('#').first.trim();
    if (line.isEmpty) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    if (line.substring(0, eq).trim() != 'chatgpt_base_url') continue;
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value.trim();
  }
  return null;
}

String normalizeChatGptBaseUrl(String value) {
  var trimmed = value.trim();
  if (trimmed.isEmpty) trimmed = defaultChatGptBaseUrl;
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  if ((trimmed.startsWith('https://chatgpt.com') ||
          trimmed.startsWith('https://chat.openai.com')) &&
      !trimmed.contains('/backend-api')) {
    trimmed += '/backend-api';
  }
  return trimmed;
}

/// `/wham/usage` for ChatGPT backends, `/api/codex/usage` otherwise.
Uri codexUsageUri(String? configuredBaseUrl) {
  final base = normalizeChatGptBaseUrl(configuredBaseUrl ?? defaultChatGptBaseUrl);
  final path = base.contains('/backend-api') ? '/wham/usage' : '/api/codex/usage';
  return Uri.parse('$base$path');
}
