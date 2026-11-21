import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/credits.dart';
import '../models/model_usage.dart';
import '../models/rate_window.dart';
import '../models/usage_snapshot.dart';
import '../platform/browser_cookies.dart' show BrowserCookieEnvironment;
import 'fields.dart';

/// Shared dependencies for a fetch.
class FetchContext {
  FetchContext({
    http.Client? client,
    DateTime Function()? clock,
    this.allowClaudeTokenRefresh = false,
    this.allowCliFallback = true,
    this.browserCookies,
    this.userAgent = 'TokenBar',
  }) : client = client ?? http.Client(),
       clock = clock ?? DateTime.now;

  final http.Client client;
  final DateTime Function() clock;

  /// Opt-in: refresh an expired Claude token and write it back to the
  /// Claude Code credentials file (rotates the refresh token).
  final bool allowClaudeTokenRefresh;

  /// Allow launching provider CLIs (e.g. `codex app-server`) as a fallback.
  final bool allowCliFallback;

  /// Opt-in: lets providers that support it read the signed-in browser's cookies (read-only,
  /// desktop only, see `resolveCookieHeader`). Null (the default) means never touch a browser,
  /// which is what every test relies on; the app and the CLI pass one explicitly.
  final BrowserCookieEnvironment? browserCookies;
  final String userAgent;

  DateTime now() => clock();
}

/// A user-facing failure with an optional actionable hint.
class ProviderException implements Exception {
  ProviderException(this.message, {this.hint, this.statusCode});

  final String message;
  final String? hint;
  final int? statusCode;

  @override
  String toString() => hint == null ? message : '$message ($hint)';
}

abstract class UsageProvider {
  String get id;
  String get displayName;

  /// ARGB brand color used by the UI.
  int get brandColor;

  List<SourceType> get supportedSources;

  /// True when [SourceType.localCli] needs files/processes on this machine.
  bool get needsLocalAccess => supportedSources.contains(SourceType.localCli);

  /// Short guidance shown when adding an account.
  String get setupHint;

  /// Settings of the [SourceType.apiKey] source, rendered by the editor.
  List<ProviderField> get fields => const [ProviderField.apiKey()];

  String get manualSourceLabel => fields.firstOrNull?.label ?? 'API Key';
  String get localSourceLabel => '本机登录';

  /// Rejects malformed manual input before saving; null when acceptable.
  String? validateManual(FieldValues values) => null;

  /// Whether a usable local login exists for [account] (used to auto-add
  /// providers on first launch). Must not modify any credentials.
  Future<bool> hasLocalLogin(AccountConfig account) async => false;

  /// True when every required manual field can come from environment
  /// variables on this machine.
  bool get configuredByEnvironment {
    if (!supportedSources.contains(SourceType.apiKey)) return false;
    final needed = fields.where((f) => f.required && f.defaultValue == null).toList();
    if (needed.isEmpty) return fields.any((f) => f.isSecure && FieldValues.envValue(f) != null);
    return needed.every((f) => f.envVars.isNotEmpty && FieldValues.envValue(f) != null);
  }

  /// Source to use when auto-adding this provider, or null when nothing is
  /// set up on this machine.
  Future<SourceType?> detectLocalSetup(AccountConfig candidate) async {
    if (needsLocalAccess && await hasLocalLogin(candidate)) return SourceType.localCli;
    if (configuredByEnvironment) return SourceType.apiKey;
    return null;
  }

  /// Snapshot skeleton for [account] with this provider's id and `now`.
  UsageSnapshot snapshot(
    AccountConfig account,
    FetchContext ctx, {
    String? plan,
    String? email,
    String? source,
    List<RateWindow> windows = const [],
    List<Credits> credits = const [],
    Map<String, String> extras = const {},
  }) => UsageSnapshot(
    accountId: account.id,
    providerId: id,
    fetchedAt: ctx.now(),
    plan: plan,
    email: email,
    source: source,
    windows: windows,
    credits: credits,
    extras: extras,
  );

  /// Fetches usage. Implementations should throw [ProviderException] for
  /// expected failures; [fetchSafely] converts them into error snapshots.
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx);

  /// Per-model usage over `[from, to]` for a stacked bar chart, or null when this
  /// service has no per-model data (the default) or it cannot be read right now.
  ///
  /// Best-effort: implementations return null instead of throwing, so it can never
  /// affect the quota refresh. Buckets follow [modelUsageBucketWidth]. Only model names
  /// and numbers may be returned — never prompts, file paths or credentials.
  Future<ModelUsageSeries?> fetchModelUsage(
    AccountConfig account,
    FetchContext ctx, {
    required DateTime from,
    required DateTime to,
  }) async => null;

  Future<UsageSnapshot> fetchSafely(AccountConfig account, FetchContext ctx) async {
    try {
      final snapshot = await fetch(account, ctx);
      return snapshot.copyWith(accountLabel: account.label);
    } on ProviderException catch (e) {
      return UsageSnapshot.failure(
        accountId: account.id,
        providerId: id,
        fetchedAt: ctx.now(),
        accountLabel: account.label,
        error: e.message,
        errorHint: e.hint,
      );
    } catch (e) {
      return UsageSnapshot.failure(
        accountId: account.id,
        providerId: id,
        fetchedAt: ctx.now(),
        accountLabel: account.label,
        error: '$e',
      );
    }
  }
}
