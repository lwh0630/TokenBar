import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tokenbar_core/tokenbar_core.dart' show localAccessSupported;

import '../app/design/background.dart';
import '../l10n/app_localizations.dart';

/// Interface language. [system] follows the device: Chinese when the device's
/// primary language is Chinese, English otherwise.
enum AppLanguage { system, zh, en }

/// Optional self-hosted server sync. Accounts added on this device are always
/// fetched directly from the provider (except on web, which has no local
/// access and is served by the server itself).
enum SyncMode {
  /// No server.
  local,

  /// Also show accounts other devices pushed to the server.
  server,

  /// Also push this device's results to the server.
  localPush;

  String label(AppLocalizations l) => switch (this) {
    SyncMode.local => l.syncModeOff,
    SyncMode.server => l.syncModeServerView,
    SyncMode.localPush => l.syncModePush,
  };

  bool get fetchesLocally => !kIsWeb;
  bool get usesServer => this != SyncMode.local;
}

bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Phones have dart:io but no desktop CLI / app logins to reuse.
bool get canUseLocalLogins => localAccessSupported && isDesktopPlatform;

bool get isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = AppLanguage.system,
    this.refreshMinutes = 5,
    this.notificationsEnabled = true,
    this.thresholds = const [20, 5],
    this.notifyOnReset = true,
    required this.syncMode,
    this.serverUrl = '',
    this.serverToken = '',
    this.deviceName = '',
    this.allowCliFallback = true,
    this.allowClaudeRefresh = false,
    this.launchAtStartup = false,
    this.minimizeToTray = true,
    this.hideDockIcon = false,
    this.trayAccountId = '',
    this.autoCheckUpdates = true,
    this.skippedVersion = '',
    this.background = BackgroundStyle.aurora,
    this.backgroundImage = '',
    this.backgroundDim = 0.45,
  });

  factory AppSettings.defaults() => AppSettings(
    syncMode: kIsWeb ? SyncMode.server : SyncMode.local,
    serverUrl: kIsWeb ? Uri.base.origin : '',
  );

  final ThemeMode themeMode;
  final AppLanguage language;
  final int refreshMinutes;
  final bool notificationsEnabled;

  /// Remaining-percent thresholds that trigger a low-quota notification.
  final List<int> thresholds;
  final bool notifyOnReset;
  final SyncMode syncMode;
  final String serverUrl;
  final String serverToken;
  final String deviceName;
  final bool allowCliFallback;
  final bool allowClaudeRefresh;
  final bool launchAtStartup;
  final bool minimizeToTray;

  /// macOS only: run as a menu-bar app without a Dock icon.
  final bool hideDockIcon;

  /// Account the tray icon / menu-bar title follows; empty = the most constrained one.
  final String trayAccountId;
  final bool autoCheckUpdates;

  /// Release tag the user chose not to be reminded about.
  final String skippedVersion;

  /// Window background: a gradient preset or the picture at [backgroundImage].
  final BackgroundStyle background;

  /// Path of the stored background picture (copied into the app's own folder).
  final String backgroundImage;

  /// Veil strength over the picture, 0..0.85.
  final double backgroundDim;

  bool get serverConfigured => serverUrl.trim().isNotEmpty && serverToken.trim().isNotEmpty;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppLanguage? language,
    int? refreshMinutes,
    bool? notificationsEnabled,
    List<int>? thresholds,
    bool? notifyOnReset,
    SyncMode? syncMode,
    String? serverUrl,
    String? serverToken,
    String? deviceName,
    bool? allowCliFallback,
    bool? allowClaudeRefresh,
    bool? launchAtStartup,
    bool? minimizeToTray,
    bool? hideDockIcon,
    String? trayAccountId,
    bool? autoCheckUpdates,
    String? skippedVersion,
    BackgroundStyle? background,
    String? backgroundImage,
    double? backgroundDim,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    language: language ?? this.language,
    refreshMinutes: refreshMinutes ?? this.refreshMinutes,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    thresholds: thresholds ?? this.thresholds,
    notifyOnReset: notifyOnReset ?? this.notifyOnReset,
    syncMode: syncMode ?? this.syncMode,
    serverUrl: serverUrl ?? this.serverUrl,
    serverToken: serverToken ?? this.serverToken,
    deviceName: deviceName ?? this.deviceName,
    allowCliFallback: allowCliFallback ?? this.allowCliFallback,
    allowClaudeRefresh: allowClaudeRefresh ?? this.allowClaudeRefresh,
    launchAtStartup: launchAtStartup ?? this.launchAtStartup,
    minimizeToTray: minimizeToTray ?? this.minimizeToTray,
    hideDockIcon: hideDockIcon ?? this.hideDockIcon,
    trayAccountId: trayAccountId ?? this.trayAccountId,
    autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
    skippedVersion: skippedVersion ?? this.skippedVersion,
    background: background ?? this.background,
    backgroundImage: backgroundImage ?? this.backgroundImage,
    backgroundDim: backgroundDim ?? this.backgroundDim,
  );

  /// Non-secret fields (the server token lives in secure storage).
  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'language': language.name,
    'refreshMinutes': refreshMinutes,
    'notificationsEnabled': notificationsEnabled,
    'thresholds': thresholds,
    'notifyOnReset': notifyOnReset,
    'syncMode': syncMode.name,
    'serverUrl': serverUrl,
    'deviceName': deviceName,
    'allowCliFallback': allowCliFallback,
    'allowClaudeRefresh': allowClaudeRefresh,
    'launchAtStartup': launchAtStartup,
    'minimizeToTray': minimizeToTray,
    'hideDockIcon': hideDockIcon,
    'trayAccountId': trayAccountId,
    'autoCheckUpdates': autoCheckUpdates,
    'skippedVersion': skippedVersion,
    'background': background.name,
    'backgroundImage': backgroundImage,
    'backgroundDim': backgroundDim,
  };

  factory AppSettings.fromJson(Map<String, Object?> json, {String token = ''}) {
    final d = AppSettings.defaults();
    T pick<T>(String key, T fallback) => json[key] is T ? json[key] as T : fallback;
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == json['themeMode'],
        orElse: () => d.themeMode,
      ),
      // Unknown or missing values (older files, future languages) fall back to "system".
      language: AppLanguage.values.firstWhere(
        (l) => l.name == json['language'],
        orElse: () => d.language,
      ),
      refreshMinutes: pick<int>('refreshMinutes', d.refreshMinutes),
      notificationsEnabled: pick<bool>('notificationsEnabled', d.notificationsEnabled),
      thresholds: (json['thresholds'] as List?)?.whereType<int>().toList() ?? d.thresholds,
      notifyOnReset: pick<bool>('notifyOnReset', d.notifyOnReset),
      syncMode: SyncMode.values.firstWhere(
        (m) => m.name == json['syncMode'],
        orElse: () => d.syncMode,
      ),
      serverUrl: pick<String>('serverUrl', d.serverUrl),
      serverToken: token,
      deviceName: pick<String>('deviceName', d.deviceName),
      allowCliFallback: pick<bool>('allowCliFallback', d.allowCliFallback),
      allowClaudeRefresh: pick<bool>('allowClaudeRefresh', d.allowClaudeRefresh),
      launchAtStartup: pick<bool>('launchAtStartup', d.launchAtStartup),
      minimizeToTray: pick<bool>('minimizeToTray', d.minimizeToTray),
      hideDockIcon: pick<bool>('hideDockIcon', d.hideDockIcon),
      trayAccountId: pick<String>('trayAccountId', d.trayAccountId),
      autoCheckUpdates: pick<bool>('autoCheckUpdates', d.autoCheckUpdates),
      skippedVersion: pick<String>('skippedVersion', d.skippedVersion),
      background: BackgroundStyle.values.firstWhere(
        (b) => b.name == json['background'],
        orElse: () => d.background,
      ),
      backgroundImage: pick<String>('backgroundImage', d.backgroundImage),
      backgroundDim: json['backgroundDim'] is num
          ? (json['backgroundDim'] as num).toDouble().clamp(0.0, 0.85)
          : d.backgroundDim,
    );
  }
}
