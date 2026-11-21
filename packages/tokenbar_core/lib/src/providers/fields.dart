import 'dart:convert';

import '../models/account.dart';
import '../platform/platform.dart' as platform;
import 'provider.dart';

enum FieldKind { secret, text, url, choice }

class FieldChoice {
  const FieldChoice(this.value, this.label);

  final String value;
  final String label;
}

/// One user-editable setting of a provider's manual (`SourceType.apiKey`)
/// source. Secure fields live in [AccountConfig.secret]; the rest in
/// [AccountConfig.options].
class ProviderField {
  const ProviderField({
    required this.key,
    required this.label,
    this.kind = FieldKind.secret,
    this.required = true,
    this.multiline = false,
    this.hint,
    this.help,
    this.defaultValue,
    this.choices = const [],
    this.envVars = const [],
  });

  /// Primary credential: an API key / token.
  const ProviderField.apiKey({
    String label = 'API Key',
    String? hint,
    String? help,
    List<String> envVars = const [],
    bool required = true,
  }) : this(
         key: secretKey,
         label: label,
         hint: hint,
         help: help,
         envVars: envVars,
         required: required,
       );

  /// Primary credential: a browser Cookie header.
  const ProviderField.cookie({
    String label = 'Cookie',
    String? hint,
    String? help,
    List<String> envVars = const [],
    bool required = true,
  }) : this(
         key: secretKey,
         label: label,
         multiline: true,
         hint: hint,
         help: help ?? '浏览器登录后，开发者工具 → 网络 → 任一请求的 Cookie 请求头',
         envVars: envVars,
         required: required,
       );

  const ProviderField.baseUrl({
    required String defaultValue,
    String label = 'Base URL',
    String? help,
    List<String> envVars = const [],
    bool required = false,
  }) : this(
         key: 'baseUrl',
         label: label,
         kind: FieldKind.url,
         required: required,
         defaultValue: defaultValue,
         help: help,
         envVars: envVars,
       );

  static const secretKey = 'secret';

  final String key;
  final String label;
  final FieldKind kind;
  final bool required;
  final bool multiline;
  final String? hint;
  final String? help;
  final String? defaultValue;
  final List<FieldChoice> choices;

  /// Desktop fallback when the field is empty (CodexBar-compatible names).
  final List<String> envVars;

  bool get isSecure => kind == FieldKind.secret;
}

/// Splits/joins the secure values stored in [AccountConfig.secret]: a single
/// primary credential is stored raw, several as a JSON object.
abstract final class SecretBundle {
  static Map<String, String> decode(String? secret) {
    if (secret == null || secret.isEmpty) return {};
    if (secret.startsWith('{')) {
      try {
        final map = jsonDecode(secret);
        if (map is Map && map.values.every((v) => v is String)) {
          return map.map((k, v) => MapEntry(k.toString(), v as String));
        }
      } on FormatException {
        // A raw credential that happens to start with "{".
      }
    }
    return {ProviderField.secretKey: secret};
  }

  static String? encode(Map<String, String> values) {
    final cleaned = {
      for (final e in values.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };
    if (cleaned.isEmpty) return null;
    if (cleaned.length == 1 && cleaned.containsKey(ProviderField.secretKey)) {
      return cleaned[ProviderField.secretKey];
    }
    return jsonEncode(cleaned);
  }
}

/// Resolved field values for one fetch: stored value, then env var
/// (desktop only), then default.
class FieldValues {
  FieldValues(this.provider, this.fields, this._values);

  factory FieldValues.of(UsageProvider provider, AccountConfig account) {
    final secrets = SecretBundle.decode(account.secret);
    final values = <String, String>{};
    for (final f in provider.fields) {
      final stored = f.isSecure ? secrets[f.key] : account.options[f.key];
      final value = _clean(stored) ?? envValue(f) ?? _clean(f.defaultValue);
      if (value != null) values[f.key] = value;
    }
    return FieldValues(provider.displayName, provider.fields, values);
  }

  final String provider;
  final List<ProviderField> fields;
  final Map<String, String> _values;

  String? operator [](String key) => _values[key];

  String get secret => require(ProviderField.secretKey);

  String require(String key) {
    final value = _values[key];
    if (value != null) return value;
    final field = fields.where((f) => f.key == key).firstOrNull;
    final label = field?.label ?? key;
    final env = field?.envVars ?? const [];
    throw ProviderException(
      '未填写 $provider 的 $label',
      hint: env.isEmpty ? '在账户设置中填写' : '在账户设置中填写，或设置环境变量 ${env.join(' / ')}',
    );
  }

  /// A base URL without trailing slash; rejects non-HTTP(S) schemes.
  String baseUrl([String key = 'baseUrl']) {
    final raw = require(key).replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      throw ProviderException('$provider 的地址无效: $raw', hint: '需要以 https:// 开头的完整地址');
    }
    return raw;
  }

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static String? envValue(ProviderField f) {
    if (!platform.localAccessSupported) return null;
    for (final name in f.envVars) {
      final v = platform.envVar(name);
      if (v != null) return v;
    }
    return null;
  }
}
