import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:token_bar/services/persistence.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

/// In-memory [SecretStore] whose behaviour can mimic the broken ones.
class _FakeStore implements SecretStore {
  _FakeStore({this.failWrites = false, this.dropWrites = false});

  /// Like macOS -34018: writing throws, reading finds nothing (null).
  bool failWrites;

  /// Writing "succeeds" but nothing is stored.
  bool dropWrites;
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('errSecMissingEntitlement (-34018)');
    if (!dropWrites) data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

AccountConfig _account(String secret) => AccountConfig(
  id: 'zai-1',
  providerId: 'zai',
  label: 'z.ai',
  sourceType: SourceType.apiKey,
  secret: secret,
);

Future<List<AccountConfig>> _reload(SharedPreferences prefs, SecretStore store) =>
    Persistence.withStore(prefs, store).loadAccounts();

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('secret lives in the secure store and leaves no plain-text copy', () async {
    final store = _FakeStore();
    await Persistence.withStore(prefs, store).saveAccounts([_account('sk-1')]);
    expect(store.data['tokenbar.secret.zai-1'], 'sk-1');
    expect(prefs.getKeys().where((k) => k.startsWith('fallback.')), isEmpty);
    expect((await _reload(prefs, store)).single.secret, 'sk-1');
  });

  test('survives a restart when the secure store rejects writes and reads null', () async {
    // Reproduces #6: the ad-hoc signed macOS build.
    final store = _FakeStore(failWrites: true);
    await Persistence.withStore(prefs, store).saveAccounts([_account('sk-1')]);
    expect((await _reload(prefs, store)).single.secret, 'sk-1');
  });

  test('survives a restart when the secure store silently drops writes', () async {
    final store = _FakeStore(dropWrites: true);
    await Persistence.withStore(prefs, store).saveAccounts([_account('sk-1')]);
    expect((await _reload(prefs, store)).single.secret, 'sk-1');
  });

  test('moves the fallback copy into the secure store once it works again', () async {
    final broken = _FakeStore(failWrites: true);
    await Persistence.withStore(prefs, broken).saveAccounts([_account('sk-1')]);
    expect(prefs.getString('fallback.tokenbar.secret.zai-1'), 'sk-1');

    final fixed = _FakeStore();
    expect((await _reload(prefs, fixed)).single.secret, 'sk-1');
    expect(fixed.data['tokenbar.secret.zai-1'], 'sk-1');
    expect(prefs.getString('fallback.tokenbar.secret.zai-1'), isNull);
  });

  test('a newer secret replaces an older one that is stuck in the fallback', () async {
    final broken = _FakeStore(failWrites: true);
    await Persistence.withStore(prefs, broken).saveAccounts([_account('old')]);
    await Persistence.withStore(prefs, broken).saveAccounts([_account('new')]);
    expect((await _reload(prefs, broken)).single.secret, 'new');
  });

  test('deleting an account secret clears both copies', () async {
    final broken = _FakeStore(failWrites: true);
    final p = Persistence.withStore(prefs, broken);
    await p.saveAccounts([_account('sk-1')]);
    await p.deleteAccountSecret('zai-1');
    expect(prefs.getString('fallback.tokenbar.secret.zai-1'), isNull);

    final store = _FakeStore();
    final q = Persistence.withStore(prefs, store);
    await q.saveAccounts([_account('sk-2')]);
    await q.deleteAccountSecret('zai-1');
    expect(store.data, isEmpty);
    expect((await _reload(prefs, store)).single.secret, isNull);
  });
}
