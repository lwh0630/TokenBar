import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

import '../state/settings.dart';

/// Where secrets are kept (the system secure storage in production).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [SecretStore] backed by `flutter_secure_storage`.
class SecureSecretStore implements SecretStore {
  const SecureSecretStore();

  // The macOS release build is only ad-hoc signed (no Apple developer account),
  // so it has no `keychain-access-groups` entitlement and the Data Protection
  // keychain (the plugin's default) rejects every write with -34018 while reads
  // return "not found". The classic login keychain works without entitlements.
  static const _secure = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) => _secure.read(key: key);

  @override
  Future<void> write(String key, String value) => _secure.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _secure.delete(key: key);
}

/// Settings + accounts in shared_preferences, secrets in secure storage.
class Persistence {
  Persistence._(this._prefs, {this.useSecureStorage = true, SecretStore? store})
    : _store = store ?? const SecureSecretStore();

  /// Test hook: open with a custom secret store (e.g. one that fails like an
  /// ad-hoc signed macOS build does).
  @visibleForTesting
  Persistence.withStore(SharedPreferences prefs, SecretStore store) : this._(prefs, store: store);

  static Future<Persistence> open() async => Persistence._(await SharedPreferences.getInstance());

  /// In-memory storage for demo mode: nothing is read from or written to the
  /// real preferences or the system secure storage.
  static Future<Persistence> openDemo() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    return Persistence._(await SharedPreferences.getInstance(), useSecureStorage: false);
  }

  final SharedPreferences _prefs;
  final bool useSecureStorage;
  final SecretStore _store;

  static const _settingsKey = 'tokenbar.settings';
  static const _accountsKey = 'tokenbar.accounts';
  static const _snapshotsKey = 'tokenbar.snapshots';
  static const _notifyStateKey = 'tokenbar.notifyState';
  static const _serverTokenKey = 'tokenbar.serverToken';
  static String _secretKey(String accountId) => 'tokenbar.secret.$accountId';

  /// A `fallback.<key>` entry only exists while the secure store could not take
  /// the value (a successful secure write removes it), so when present it is the
  /// freshest copy and wins over whatever the secure store returns.
  Future<String?> _readSecret(String key) async {
    final fallback = _prefs.getString('fallback.$key');
    if (!useSecureStorage) return fallback;
    if (fallback != null && fallback.isNotEmpty) {
      // Try to move it into the secure store, so the plain-text copy goes away
      // as soon as the store works again.
      await _writeSecret(key, fallback);
      return fallback;
    }
    try {
      // Some platforms report "not found" / a missing entitlement as null
      // instead of throwing; null just means "no secret".
      return await _store.read(key);
    } catch (e) {
      // Secure storage can be unavailable (e.g. Linux without libsecret,
      // insecure web context); the app keeps working without it.
      debugPrint('secure storage read failed: $e');
      return null;
    }
  }

  Future<void> _writeSecret(String key, String? value) async {
    final fallbackKey = 'fallback.$key';
    final empty = value == null || value.isEmpty;
    if (useSecureStorage) {
      try {
        if (empty) {
          await _store.delete(key);
        } else {
          await _store.write(key, value);
          // A write can "succeed" without persisting (or throw on some
          // platforms); only trust it when it reads back identically.
          if (await _store.read(key) != value) {
            throw StateError('secure storage did not persist the value');
          }
        }
        await _prefs.remove(fallbackKey);
        return;
      } catch (e) {
        debugPrint('secure storage write failed: $e');
        // An empty value still falls through to clear the fallback below.
      }
    }
    if (empty) {
      await _prefs.remove(fallbackKey);
    } else {
      await _prefs.setString(fallbackKey, value);
    }
  }

  Future<AppSettings> loadSettings() async {
    final raw = _prefs.getString(_settingsKey);
    final token = await _readSecret(_serverTokenKey) ?? '';
    if (raw == null) return AppSettings.defaults().copyWith(serverToken: token);
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, Object?>, token: token);
  }

  Future<void> saveSettings(AppSettings s) async {
    await _prefs.setString(_settingsKey, jsonEncode(s.toJson()));
    await _writeSecret(_serverTokenKey, s.serverToken);
  }

  Future<List<AccountConfig>> loadAccounts() async {
    final raw = _prefs.getString(_accountsKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, Object?>>();
    final accounts = <AccountConfig>[];
    for (final json in list) {
      final account = AccountConfig.fromJson(json);
      final secret = account.sourceType == SourceType.apiKey
          ? await _readSecret(_secretKey(account.id))
          : null;
      accounts.add(secret == null ? account : account.copyWith(secret: secret));
    }
    return accounts;
  }

  Future<void> saveAccounts(List<AccountConfig> accounts) async {
    await _prefs.setString(_accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
    for (final a in accounts) {
      if (a.sourceType == SourceType.apiKey) {
        await _writeSecret(_secretKey(a.id), a.secret);
      }
    }
  }

  Future<void> deleteAccountSecret(String accountId) => _writeSecret(_secretKey(accountId), null);

  /// Last snapshots, so the UI shows data instantly on launch.
  List<UsageSnapshot> loadCachedSnapshots() {
    final raw = _prefs.getString(_snapshotsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => UsageSnapshot.fromJson((e as Map).cast<String, Object?>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCachedSnapshots(List<UsageSnapshot> snapshots) =>
      _prefs.setString(_snapshotsKey, jsonEncode(snapshots.map((s) => s.toJson()).toList()));

  Map<String, Object?> loadNotifyState() {
    final raw = _prefs.getString(_notifyStateKey);
    return raw == null ? {} : (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  Future<void> saveNotifyState(Map<String, Object?> state) =>
      _prefs.setString(_notifyStateKey, jsonEncode(state));
}
