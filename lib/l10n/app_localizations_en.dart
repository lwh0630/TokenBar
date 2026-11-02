// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navQuota => 'Quota';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navSettings => 'Settings';

  @override
  String get refresh => 'Refresh';

  @override
  String get refreshNow => 'Refresh now';

  @override
  String get openTokenBar => 'Open TokenBar';

  @override
  String get quit => 'Quit';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get save => 'Save';

  @override
  String get later => 'Later';

  @override
  String get addAccount => 'Add account';

  @override
  String get systemDefault => 'System';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String hoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get resetImminent => 'Resetting soon';

  @override
  String get lessThanMinute => 'Less than 1 min';

  @override
  String countdownDaysHours(int days, int hours) {
    return '${days}d ${hours}h';
  }

  @override
  String countdownDays(int days) {
    return '${days}d';
  }

  @override
  String countdownHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String countdownHours(int hours) {
    return '${hours}h';
  }

  @override
  String countdownMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String resetsIn(String countdown) {
    return 'Resets in $countdown';
  }

  @override
  String resetTomorrow(String time) {
    return 'Tomorrow $time';
  }

  @override
  String resetWeekday(String weekday, String time) {
    return '$weekday $time';
  }

  @override
  String resetDate(String date, String time) {
    return '$date $time';
  }

  @override
  String monthDay(int month, int day) {
    return '$month/$day';
  }

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String timeWithAgo(String time, String ago) {
    return '$time ($ago)';
  }

  @override
  String updatedAgo(String time) {
    return 'Updated $time';
  }

  @override
  String get listSeparator => ', ';

  @override
  String get sentenceJoin => '. ';

  @override
  String get labelWeekly => 'Weekly';

  @override
  String get labelMonthly => 'Monthly';

  @override
  String get labelDaily => 'Daily';

  @override
  String get labelFiveHour => '5-hour';

  @override
  String get labelThisMonth => 'This month';

  @override
  String get labelToday => 'Today';

  @override
  String get labelQuota => 'Quota';

  @override
  String labelHours(int count) {
    return '$count-hour';
  }

  @override
  String labelDays(int count) {
    return '$count-day';
  }

  @override
  String get cursorMonthlyQuota => 'Monthly quota';

  @override
  String get cursorApiModels => 'API models';

  @override
  String get windowOpusWeekly => 'Opus weekly';

  @override
  String get windowSonnetWeekly => 'Sonnet weekly';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get creditsBalance => 'Credits balance';

  @override
  String get creditsSpendLimit => 'Monthly credits limit';

  @override
  String get extraUsage => 'Extra usage';

  @override
  String get cursorPlanUsage => 'This month\'s usage';

  @override
  String get cursorOnDemand => 'On-demand usage';

  @override
  String get cursorTeamOnDemand => 'Team on-demand usage';

  @override
  String get sourceCursorLocal => 'Cursor local login';

  @override
  String get sourceServer => 'Server';

  @override
  String get localLogin => 'Local login';

  @override
  String get remainingSuffix => 'left';

  @override
  String usedPercent(String value) {
    return 'Used $value';
  }

  @override
  String paceAhead(int percent) {
    return '$percent% ahead of pace';
  }

  @override
  String paceBehind(int percent) {
    return '$percent% behind pace';
  }

  @override
  String paceTooltip(int percent) {
    return 'Linear pace would leave $percent%';
  }

  @override
  String get noData => 'No data';

  @override
  String staleDataNotice(String error) {
    return 'Showing last data: $error';
  }

  @override
  String fromDevice(String origin) {
    return 'From $origin';
  }

  @override
  String get syncNeedsServerConfig => 'Enter the server URL and token in Settings first';

  @override
  String syncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String unsupportedProvider(String providerId) {
    return 'Unsupported service: $providerId';
  }

  @override
  String get serverTokenInvalid => 'Connected, but the token is invalid';

  @override
  String get syncModeOff => 'Off';

  @override
  String get syncModeServerView => 'View server data';

  @override
  String get syncModePush => 'Push this device';

  @override
  String get quotaLoading => 'Loading quotas…';

  @override
  String get noAccountsYetPanel => 'No accounts yet\nOpen TokenBar to add a service';

  @override
  String get noQuotaDataYet => 'No quota data yet';

  @override
  String get webEmptyMessage =>
      'No device has pushed data yet.\nOn your computer, turn on “Push this device” in TokenBar, or run tokenbar collect.';

  @override
  String get desktopEmptyMessage =>
      'Add a Codex, Claude or Cursor account.\nTokenBar reads the local login state and queries the official quota directly.';

  @override
  String get mobileEmptyMessage =>
      'Add a Cursor account (paste your cursor.com cookie) to see quota right away.\nCodex / Claude sign in on a computer; you can optionally sync them to your phone through a server.';

  @override
  String get serverSettings => 'Server settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsBackground => 'Background';

  @override
  String get backgroundAurora => 'Aurora';

  @override
  String get backgroundSunset => 'Sunset';

  @override
  String get backgroundOcean => 'Ocean';

  @override
  String get backgroundForest => 'Forest';

  @override
  String get backgroundGraphite => 'Graphite';

  @override
  String get backgroundImage => 'Custom image';

  @override
  String get backgroundChooseImage => 'Choose image';

  @override
  String get backgroundChangeImage => 'Change image';

  @override
  String get backgroundRemoveImage => 'Remove image';

  @override
  String get backgroundDim => 'Overlay strength';

  @override
  String get backgroundDimHint =>
      'A stronger overlay keeps text readable; a weaker one lets the picture show.';

  @override
  String get backgroundImageFailed => 'This image could not be used';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get sectionRefresh => 'Refresh';

  @override
  String get autoRefreshInterval => 'Auto-refresh interval';

  @override
  String get autoRefreshIntervalHint => 'Backs off after repeated failures, up to 30 minutes';

  @override
  String refreshMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get sectionNotifications => 'Notifications';

  @override
  String get lowQuotaAlerts => 'Low-quota alerts';

  @override
  String get alertThresholds => 'Alert thresholds (remaining)';

  @override
  String get resetAlerts => 'Reset alerts';

  @override
  String get resetAlertsHint => 'Notify after a low quota resets';

  @override
  String get sectionSyncOptional => 'Server sync (optional)';

  @override
  String get sectionServer => 'Server';

  @override
  String syncEnabled(String mode) {
    return 'Enabled: $mode';
  }

  @override
  String get syncDisabled => 'Off';

  @override
  String get syncOptionalHint =>
      'Works without a server. You only need a self-hosted TokenBar server to see desktop quotas on a phone or in a browser.';

  @override
  String get syncDescLocal =>
      'Every account is queried directly from this device; no server needed.';

  @override
  String get syncDescServerWeb => 'Shows quota data that devices pushed to this server.';

  @override
  String get syncDescServerDesktop =>
      'Besides local accounts, shows accounts that other devices pushed to your self-hosted server (for example Codex / Claude on a computer).';

  @override
  String get syncDescPush =>
      'Pushes this device\'s results to your self-hosted server for phones and browsers, and also shows accounts from other devices on the server.';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get accessToken => 'Access token';

  @override
  String get tokenHelperPush => 'Pushing requires the admin token (TOKENBAR_TOKEN)';

  @override
  String get tokenHelperRead => 'Read-only or admin token';

  @override
  String get deviceName => 'Device name';

  @override
  String get deviceNameHint => 'e.g. Office PC';

  @override
  String get savedSyncSettings => 'Sync settings saved';

  @override
  String get testConnection => 'Test connection';

  @override
  String get connectionOk => 'Connected';

  @override
  String connectionFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get sectionDataSources => 'Data sources';

  @override
  String get allowCliFallback => 'Allow Codex CLI fallback';

  @override
  String get allowCliFallbackHint =>
      'When the OAuth token expires, read usage through `codex app-server` (the CLI handles login refresh)';

  @override
  String get allowClaudeRefresh => 'Allow TokenBar to refresh Claude tokens';

  @override
  String get allowClaudeRefreshHint =>
      'When a token expires, TokenBar refreshes it and writes it back to ~/.claude/.credentials.json. Refreshing rotates the refresh token, so you may need to sign in again if Claude Code is running. Off by default.';

  @override
  String get sectionDesktop => 'Desktop';

  @override
  String get launchAtStartup => 'Launch at startup';

  @override
  String get minimizeToTray => 'Minimize to tray when closing the window';

  @override
  String get trayDisplay => 'Show in tray';

  @override
  String get trayDisplayHint =>
      'The account whose remaining quota the tray icon (and macOS menu-bar title) shows.';

  @override
  String get trayDisplayAuto => 'Auto (most constrained)';

  @override
  String get sectionAbout => 'About';

  @override
  String get updateChecking => 'Checking…';

  @override
  String get upToDate => 'You\'re up to date';

  @override
  String newVersionAvailable(String tag) {
    return 'New version $tag available';
  }

  @override
  String get checkFailedRateLimit => 'Check failed: too many requests, try again later';

  @override
  String get checkFailedNetwork => 'Check failed: can\'t reach GitHub';

  @override
  String get checkFailedFormat => 'Check failed: GitHub returned data that could not be read';

  @override
  String get viewUpdate => 'View update';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get autoCheckUpdates => 'Check for updates at launch';

  @override
  String get autoCheckUpdatesHint =>
      'Only requests the latest version number from GitHub; no account or usage data is sent';

  @override
  String get projectHome => 'Project home';

  @override
  String get aboutBlurb =>
      'Open-source, cross-platform AI quota monitor (MIT). Data fetching is inspired by steipete/CodexBar. Queries each provider\'s official API directly, reusing the read-only login state of local clients, and never collects passwords. The optional self-hosted server only stores quota snapshots, never tokens.';

  @override
  String get updateNoNotes => 'No release notes for this version.';

  @override
  String currentVersion(String version) {
    return 'Current version $version';
  }

  @override
  String get skipThisVersion => 'Skip this version';

  @override
  String get goToDownload => 'Download';

  @override
  String get usageNote =>
      'Usage is the percentage of each quota window used during that period. Different windows may count the same requests; pick the series to stack with the chips above.';

  @override
  String get historyNotEnough => 'Not enough history yet; it builds up with each refresh';

  @override
  String get metricUsage => 'Quota usage';

  @override
  String get metricCost => 'Cost';

  @override
  String get selectAtLeastOne => 'Select at least one item';

  @override
  String get noUsageChanges => 'No usage changes in this period';

  @override
  String get noCostChanges => 'No cost changes in this period';

  @override
  String get viewQuotaWindows => 'Quota';

  @override
  String get viewModels => 'Models';

  @override
  String get viewSpend => 'Spend';

  @override
  String get metricTokens => 'Tokens';

  @override
  String get seriesOther => 'Other';

  @override
  String get historyTotal => 'Total';

  @override
  String get historyEmptyTitle => 'No history yet';

  @override
  String get historyEmptyBody =>
      'History builds up over repeated refreshes. Keep the app running for a while and check back.';

  @override
  String historyEmptyModelBody(String source) {
    return 'Per-model usage is read from $source; nothing was recorded in this range.';
  }

  @override
  String modelNote(String source) {
    return 'Per-model usage is read from $source. Tokens include input, output and cache; providers may count them differently.';
  }

  @override
  String get modelSourceCursor => 'Cursor usage events';

  @override
  String get modelSourceCodex => 'Codex local logs';

  @override
  String get modelSourceLocal => 'local usage records';

  @override
  String get rangeDay => '24 hours';

  @override
  String get rangeWeek => '7 days';

  @override
  String get rangeMonth => '30 days';

  @override
  String get accountNotFound => 'Account not found';

  @override
  String get allQuotas => 'All quotas';

  @override
  String get usageHistory => 'Usage history';

  @override
  String historyLoadFailed(String error) {
    return 'Failed to load history: $error';
  }

  @override
  String get infoService => 'Service';

  @override
  String get infoPlan => 'Plan';

  @override
  String get infoAccount => 'Account';

  @override
  String get infoSource => 'Source';

  @override
  String get infoDevice => 'Device';

  @override
  String get infoUpdatedAt => 'Updated';

  @override
  String get infoLastError => 'Last error';

  @override
  String projectionRunsOut(String countdown) {
    return 'At this pace, runs out in about $countdown (before reset)';
  }

  @override
  String get exhaustedWaitingReset => 'Used up, waiting for reset';

  @override
  String projectedAtReset(String percent) {
    return 'At this pace, about $percent will be used by reset';
  }

  @override
  String get myAccounts => 'My accounts';

  @override
  String get dragToReorder => 'Drag to reorder';

  @override
  String get detectLocalLogins => 'Detect services signed in on this device';

  @override
  String get noNewLocalLogins => 'No new local sign-ins found';

  @override
  String addedAccounts(String names) {
    return 'Added: $names';
  }

  @override
  String get noAccountsList => 'No accounts yet';

  @override
  String get serverAccounts => 'Accounts on the server';

  @override
  String get serverNotConfigured => 'Server not configured';

  @override
  String get noRemoteAccounts => 'No accounts pushed by other devices yet.';

  @override
  String get mobileAccountsHint =>
      'Services that take an API key or a pasted cookie can be queried directly on your phone. Codex / Claude sign in on a computer only; to see them on your phone, turn on optional server sync in Settings.';

  @override
  String get defaultLogin => 'Default login';

  @override
  String defaultLoginAt(String home) {
    return 'Default login ($home)';
  }

  @override
  String get deleteAccountTitle => 'Delete account';

  @override
  String deleteAccountBody(String label) {
    return 'Delete “$label”? Its local history will be deleted too; CLI sign-ins are not affected.';
  }

  @override
  String get chooseService => 'Choose service';

  @override
  String get search => 'Search';

  @override
  String get serviceField => 'Service';

  @override
  String get displayName => 'Display name';

  @override
  String get editAccount => 'Edit account';

  @override
  String fillField(String label) {
    return 'Please enter $label';
  }

  @override
  String optionalField(String label) {
    return '$label (optional)';
  }

  @override
  String get cursorDataDirField => 'Cursor data directory (optional)';

  @override
  String get configDirField => 'Config directory (optional)';

  @override
  String get homeDirHelper =>
      'Leave blank for the default directory; with several accounts, give each one its own directory';

  @override
  String envDetected(String names) {
    return 'Environment variable $names detected; can be left blank';
  }

  @override
  String get storedInKeychain => 'Stored in the system secure storage';

  @override
  String get savedKeepUnchanged => 'Saved; leave blank to keep unchanged';

  @override
  String quotaResetTitle(String name, String window) {
    return '$name · $window quota reset';
  }

  @override
  String quotaResetBody(String remaining) {
    return 'Now $remaining left';
  }

  @override
  String lowQuotaTitle(String name, String window) {
    return '$name · $window quota low';
  }

  @override
  String lowQuotaBody(String remaining) {
    return '$remaining left';
  }

  @override
  String lowQuotaBodyWithReset(String remaining, String countdown) {
    return '$remaining left, resets in $countdown';
  }

  @override
  String get notificationChannelName => 'Quota alerts';

  @override
  String get notificationChannelDescription => 'Low-quota and reset alerts';

  @override
  String widgetUpdatedAt(String time) {
    return 'Updated $time';
  }
}
