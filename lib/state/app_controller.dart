import 'dart:async';
import 'dart:math';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

import '../demo/demo_data.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';
import '../services/desktop.dart';
import '../services/history_store.dart';
import '../services/home_widget_bridge.dart';
import '../services/notifier.dart';
import '../services/persistence.dart';
import '../services/quota_alerts.dart';
import 'settings.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.persistence,
    required this.historyStore,
    required this.desktop,
    required this.notifier,
    required this.homeWidget,
    UsageProvider? Function(String providerId)? providerLookup,
    DateTime Function()? clock,
  }) : _providerLookup = providerLookup ?? ProviderRegistry.instance.byId,
       _clock = clock ?? DateTime.now;

  /// Resolves a provider by id (injectable for tests).
  final UsageProvider? Function(String providerId) _providerLookup;
  final DateTime Function() _clock;

  final Persistence persistence;
  final HistoryStore historyStore;
  final DesktopIntegration desktop;
  final Notifier notifier;
  final HomeWidgetBridge homeWidget;

  AppSettings settings = AppSettings.defaults();
  List<AccountConfig> accounts = [];
  final Map<String, UsageSnapshot> _snapshots = {};
  bool refreshing = false;
  DateTime? lastRefresh;
  String? syncError;

  /// Ticks for countdown labels.
  final ValueNotifier<DateTime> now = ValueNotifier(DateTime.now());

  /// Locale in effect for the current language setting and device languages.
  Locale get locale => resolveAppLocale(settings.language, PlatformDispatcher.instance.locales);

  /// Localized strings for code that runs outside the widget tree.
  AppLocalizations get l10n => lookupAppLocalizations(locale);

  Timer? _refreshTimer;
  Timer? _clockTimer;
  int _consecutiveFailures = 0;
  late QuotaAlertEngine _alerts;
  final _random = Random();

  /// Demo mode: fictional accounts and data, no network, no real storage.
  bool demo = false;
  DemoData? _demoData;

  void initDemo(DemoData data) {
    demo = true;
    _demoData = data;
    settings = AppSettings.defaults().copyWith(
      language: demoLanguage,
      notificationsEnabled: false,
      autoCheckUpdates: false,
      minimizeToTray: true,
    );
    accounts = data.accounts;
    _snapshots.addAll(data.snapshots);
    _alerts = QuotaAlertEngine({});
    lastRefresh = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) => now.value = DateTime.now());
    notifyListeners();
    unawaited(desktop.update(snapshots, l10n));
  }

  Future<void> init() async {
    settings = await persistence.loadSettings();
    accounts = await persistence.loadAccounts();
    final localIds = accounts.map((a) => a.id).toSet();
    for (final s in persistence.loadCachedSnapshots()) {
      _snapshots[s.accountId] = s;
      if (!localIds.contains(s.accountId)) _remoteIds.add(s.accountId);
    }
    _alerts = QuotaAlertEngine(persistence.loadNotifyState());

    if (accounts.isEmpty) await addDetectedAccounts();

    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) => now.value = DateTime.now());
    notifyListeners();
    unawaited(refresh());
  }

  /// Adds one account for each provider logged in on this machine that has
  /// no default-login account yet. Returns the providers added.
  Future<List<String>> addDetectedAccounts() async {
    if (demo || !canUseLocalLogins) return const [];
    final added = <AccountConfig>[];
    for (final p in ProviderRegistry.instance.all) {
      final candidate = AccountConfig(id: _newId(p.id), providerId: p.id, label: p.displayName);
      final source = await p.detectLocalSetup(candidate);
      if (source == null) continue;
      final exists = accounts.any(
        (a) =>
            a.providerId == p.id && a.sourceType == source && a.homeDir == null && a.secret == null,
      );
      if (!exists) added.add(candidate.copyWith(sourceType: source));
    }
    if (added.isNotEmpty) {
      accounts = [...accounts, ...added];
      await persistence.saveAccounts(accounts);
      notifyListeners();
    }
    return added.map((a) => ProviderRegistry.instance.byId(a.providerId)!.displayName).toList();
  }

  String _newId(String provider) =>
      '$provider-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 20).toRadixString(36)}';

  /// Snapshots to display: local accounts in configured order, then remote.
  List<UsageSnapshot> get snapshots {
    final result = <UsageSnapshot>[];
    final localIds = <String>{};
    if (settings.syncMode.fetchesLocally) {
      for (final a in accounts.where((a) => a.enabled)) {
        localIds.add(a.id);
        final s = _snapshots[a.id];
        if (s != null) result.add(s.copyWith(accountLabel: a.label));
      }
    }
    if (settings.syncMode.usesServer) {
      final remote =
          _snapshots.values.where((s) => !localIds.contains(s.accountId) && _isRemote(s)).toList()
            ..sort(
              (a, b) => (a.accountLabel ?? a.accountId).compareTo(b.accountLabel ?? b.accountId),
            );
      result.addAll(remote);
    }
    return result;
  }

  final Set<String> _remoteIds = {};
  bool _isRemote(UsageSnapshot s) => _remoteIds.contains(s.accountId);

  bool isLocalAccount(String accountId) =>
      settings.syncMode.fetchesLocally && accounts.any((a) => a.id == accountId);

  UsageSnapshot? snapshot(String accountId) => _snapshots[accountId];

  AccountConfig? account(String accountId) {
    for (final a in accounts) {
      if (a.id == accountId) return a;
    }
    return null;
  }

  // ---------------------------------------------------------------- refresh

  Future<void> refresh() async {
    if (refreshing) return;
    if (demo) {
      lastRefresh = DateTime.now();
      notifyListeners();
      return;
    }
    refreshing = true;
    notifyListeners();
    var anySuccess = false;
    try {
      final fresh = <UsageSnapshot>[];
      if (settings.syncMode.fetchesLocally) {
        final local = await _fetchLocal();
        fresh.addAll(local);
        anySuccess = local.any((s) => !s.hasError) || local.isEmpty;
      }
      if (settings.syncMode.usesServer && settings.serverConfigured) {
        anySuccess = await _sync(fresh) || anySuccess;
      } else if (settings.syncMode.usesServer) {
        syncError = l10n.syncNeedsServerConfig;
      } else {
        syncError = null;
      }
      await historyStore.add(fresh.where((s) => isLocalAccount(s.accountId)));
      _evaluateAlerts(fresh);
      lastRefresh = DateTime.now();
      await persistence.saveCachedSnapshots(_snapshots.values.toList());
    } catch (e) {
      debugPrint('refresh failed: $e');
    } finally {
      refreshing = false;
      _consecutiveFailures = anySuccess ? 0 : _consecutiveFailures + 1;
      _scheduleNext();
      notifyListeners();
      final shown = snapshots;
      unawaited(desktop.update(shown, l10n));
      unawaited(homeWidget.publish(shown, l10n));
    }
  }

  Future<List<UsageSnapshot>> _fetchLocal() async {
    final ctx = FetchContext(
      allowClaudeTokenRefresh: settings.allowClaudeRefresh,
      allowCliFallback: settings.allowCliFallback,
      userAgent: 'TokenBar/0.1',
    );
    final origin = settings.deviceName.isEmpty ? null : settings.deviceName;
    final futures = accounts.where((a) => a.enabled).map((a) async {
      final provider = ProviderRegistry.instance.byId(a.providerId);
      if (provider == null) {
        return UsageSnapshot.failure(
          accountId: a.id,
          providerId: a.providerId,
          fetchedAt: DateTime.now(),
          accountLabel: a.label,
          error: l10n.unsupportedProvider(a.providerId),
        );
      }
      final s = await provider.fetchSafely(a, ctx);
      return origin == null ? s : s.copyWith(origin: origin);
    });
    final results = await Future.wait(futures);
    for (final s in results) {
      _snapshots[s.accountId] = s.retainingDataFrom(_snapshots[s.accountId]);
    }
    ctx.client.close();
    return results;
  }

  TokenBarApiClient _api() =>
      TokenBarApiClient(baseUrl: settings.serverUrl.trim(), token: settings.serverToken.trim());

  /// Pushes local results (localPush) and pulls everything from the server.
  Future<bool> _sync(List<UsageSnapshot> local) async {
    final api = _api();
    try {
      if (settings.syncMode == SyncMode.localPush && local.isNotEmpty) {
        await api.push(
          local,
          origin: settings.deviceName.isEmpty ? 'desktop' : settings.deviceName,
        );
      }
      final remote = await api.latest();
      final localIds = settings.syncMode.fetchesLocally
          ? accounts.map((a) => a.id).toSet()
          : <String>{};
      _remoteIds
        ..clear()
        ..addAll(remote.map((s) => s.accountId).where((id) => !localIds.contains(id)));
      for (final s in remote) {
        if (!localIds.contains(s.accountId)) _snapshots[s.accountId] = s;
      }
      _snapshots.removeWhere((id, _) => !_remoteIds.contains(id) && !localIds.contains(id));
      syncError = null;
      return true;
    } catch (e) {
      syncError = l10n.syncFailed('$e');
      return false;
    } finally {
      api.close();
    }
  }

  void _scheduleNext() {
    _refreshTimer?.cancel();
    final base = Duration(minutes: settings.refreshMinutes);
    // Exponential backoff on repeated total failure, capped at 30 minutes.
    final factor = pow(2, min(_consecutiveFailures, 3)).toInt();
    var delay = base * factor;
    if (delay > const Duration(minutes: 30) && base < const Duration(minutes: 30)) {
      delay = const Duration(minutes: 30);
    }
    final jitter = (delay.inMilliseconds * 0.1 * (_random.nextDouble() * 2 - 1)).round();
    _refreshTimer = Timer(delay + Duration(milliseconds: jitter), refresh);
  }

  void _evaluateAlerts(List<UsageSnapshot> fresh) {
    if (!settings.notificationsEnabled) return;
    final candidates = [...fresh, ..._snapshots.values.where(_isRemote)];
    final seen = <String>{};
    for (final s in candidates) {
      if (!seen.add(s.accountId)) continue;
      final provider = ProviderRegistry.instance.byId(s.providerId);
      final alerts = _alerts.evaluate(
        s.copyWith(accountLabel: account(s.accountId)?.label),
        thresholds: settings.thresholds,
        notifyOnReset: settings.notifyOnReset,
        providerName: provider?.displayName ?? s.providerId,
        l10n: l10n,
      );
      for (final a in alerts) {
        unawaited(notifier.show(a.title, a.body, l10n));
      }
    }
    unawaited(persistence.saveNotifyState(_alerts.state));
  }

  // ---------------------------------------------------------------- history

  Future<List<UsagePoint>> history(String accountId, DateTime since) async {
    if (isLocalAccount(accountId)) return historyStore.query(accountId, since);
    if (!settings.serverConfigured) return const [];
    final api = _api();
    try {
      return await api.history(accountId: accountId, since: since);
    } finally {
      api.close();
    }
  }

  static const _modelUsageTtl = Duration(minutes: 2);
  static const _modelUsageTimeout = Duration(minutes: 2);
  final Map<String, ({DateTime at, ModelUsageSeries series})> _modelUsageCache = {};
  final Map<String, Future<ModelUsageSeries?>> _modelUsageInflight = {};

  /// Per-model usage over `[since, now]` for the account, or null when the
  /// service has no per-model data (or it cannot be read on this device).
  ///
  /// Only local accounts are answered: they are read straight from the service
  /// (Cursor events API, Codex session logs on desktop). Accounts that only exist
  /// on the sync server have no per-model data. Results are cached for two
  /// minutes (key: account + `since` rounded down to the hour) so switching the
  /// range back and forth does not re-read disks or re-request. Never throws.
  Future<ModelUsageSeries?> modelUsage(String accountId, DateTime since) async {
    try {
      if (demo) return _demoData?.modelUsage(accountId, since, _clock());
      if (!isLocalAccount(accountId)) return null;
      final account = this.account(accountId);
      final provider = account == null ? null : _providerLookup(account.providerId);
      if (account == null || provider == null) return null;
      // Local logins (Codex logs, Cursor app login) only exist on desktop.
      if (account.sourceType == SourceType.localCli && !canUseLocalLogins) return null;

      final now = _clock();
      final hour = DateTime(since.year, since.month, since.day, since.hour);
      final key = '$accountId|${hour.millisecondsSinceEpoch}';
      _modelUsageCache.removeWhere((_, v) => now.difference(v.at) >= _modelUsageTtl);
      final cached = _modelUsageCache[key];
      if (cached != null) return cached.series;

      return await (_modelUsageInflight[key] ??= _loadModelUsage(
        key,
        account,
        provider,
        since,
        now,
      ));
    } catch (e) {
      debugPrint('modelUsage failed: $e');
      return null;
    }
  }

  Future<ModelUsageSeries?> _loadModelUsage(
    String key,
    AccountConfig account,
    UsageProvider provider,
    DateTime since,
    DateTime now,
  ) async {
    final ctx = FetchContext(allowCliFallback: false, userAgent: 'TokenBar/0.1', clock: _clock);
    try {
      final series = await provider
          .fetchModelUsage(account, ctx, from: since, to: now)
          .timeout(_modelUsageTimeout);
      // Failures (null) are not cached so the next attempt can succeed.
      if (series != null) _modelUsageCache[key] = (at: _clock(), series: series);
      return series;
    } catch (e) {
      debugPrint('modelUsage ${provider.id} failed: ${e.runtimeType}');
      return null;
    } finally {
      _modelUsageInflight.remove(key);
      ctx.client.close();
    }
  }

  void _dropModelUsageCache(String accountId) =>
      _modelUsageCache.removeWhere((key, _) => key.startsWith('$accountId|'));

  // ---------------------------------------------------------------- accounts

  Future<void> addAccount({
    required String providerId,
    required String label,
    SourceType sourceType = SourceType.localCli,
    String? homeDir,
    String? secret,
    Map<String, String> options = const {},
  }) async {
    accounts = [
      ...accounts,
      AccountConfig(
        id: _newId(providerId),
        providerId: providerId,
        label: label,
        sourceType: sourceType,
        homeDir: (homeDir == null || homeDir.trim().isEmpty) ? null : homeDir.trim(),
        secret: secret,
        options: options,
      ),
    ];
    await persistence.saveAccounts(accounts);
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> updateAccount(AccountConfig updated) async {
    accounts = [for (final a in accounts) a.id == updated.id ? updated : a];
    _dropModelUsageCache(updated.id);
    await persistence.saveAccounts(accounts);
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> removeAccount(String id) async {
    accounts = accounts.where((a) => a.id != id).toList();
    _snapshots.remove(id);
    _dropModelUsageCache(id);
    await persistence.saveAccounts(accounts);
    await persistence.deleteAccountSecret(id);
    await historyStore.removeAccount(id);
    await persistence.saveCachedSnapshots(_snapshots.values.toList());
    notifyListeners();
    unawaited(desktop.update(snapshots, l10n));
  }

  /// [newIndex] is already adjusted for the removed item (onReorderItem).
  Future<void> moveAccount(int oldIndex, int newIndex) async {
    final list = [...accounts];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    accounts = list;
    await persistence.saveAccounts(accounts);
    notifyListeners();
  }

  // ---------------------------------------------------------------- settings

  Future<void> updateSettings(AppSettings next) async {
    final prev = settings;
    settings = next;
    await persistence.saveSettings(next);
    notifyListeners();
    if (prev.language != next.language) {
      // Tray menu, tooltip and widget text are rebuilt in the new language.
      unawaited(desktop.update(snapshots, l10n));
      unawaited(homeWidget.publish(snapshots, l10n));
    }
    if (prev.minimizeToTray != next.minimizeToTray) {
      await desktop.setMinimizeToTray(next.minimizeToTray);
    }
    if (prev.hideDockIcon != next.hideDockIcon) {
      await desktop.setHideDockIcon(next.hideDockIcon);
    }
    if (prev.trayAccountId != next.trayAccountId) {
      await desktop.setTrayAccount(next.trayAccountId);
    }
    if (prev.launchAtStartup != next.launchAtStartup) {
      await desktop.setLaunchAtStartup(next.launchAtStartup);
    }
    final dataSourceChanged =
        prev.syncMode != next.syncMode ||
        prev.serverUrl != next.serverUrl ||
        prev.serverToken != next.serverToken ||
        prev.allowClaudeRefresh != next.allowClaudeRefresh ||
        prev.allowCliFallback != next.allowCliFallback;
    if (dataSourceChanged) {
      if (prev.syncMode != next.syncMode) _remoteIds.clear();
      unawaited(refresh());
    } else if (prev.refreshMinutes != next.refreshMinutes) {
      _scheduleNext();
    }
  }

  /// Checks server reachability + token; returns null on success.
  Future<String?> testServer(String url, String token) async {
    final api = TokenBarApiClient(baseUrl: url.trim(), token: token.trim());
    try {
      final health = await api.health();
      if (health['authenticated'] != true) return l10n.serverTokenInvalid;
      await api.latest();
      return null;
    } catch (e) {
      return '$e';
    } finally {
      api.close();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    now.dispose();
    super.dispose();
  }
}
