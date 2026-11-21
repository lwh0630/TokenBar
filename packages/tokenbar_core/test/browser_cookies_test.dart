import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/src/platform/browser_cookies.dart';
import 'package:tokenbar_core/src/platform/process_types.dart';

/// Real temp files and real SQLite, but a pretend OS, clock and process runner, so no browser
/// or keychain is involved. Every value in here is synthetic.
class _Env extends BrowserCookieEnvironment {
  _Env(this._os, {this.commands = const {}});

  final BrowserCookieOs _os;
  final Map<String, ProcessOutput> commands;
  final List<String> ran = [];
  final Set<String> tools = {};

  @override
  BrowserCookieOs get os => _os;

  @override
  String? env(String name) => null;

  @override
  DateTime now() => DateTime.utc(2026, 11, 21);

  @override
  Future<ProcessOutput?> run(String executable, List<String> args) async {
    ran.add('$executable ${args.join(' ')}');
    return commands[executable];
  }

  @override
  Future<String?> findExecutable(String name) async =>
      tools.contains(name) ? '/usr/bin/$name' : null;
}

const _hostsUnderTest = ['platform.example.com'];
const _msUnix1601 = 11644473600000000;

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _cbcEncrypt(Uint8List key, Uint8List plain) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), Uint8List(16)..fillRange(0, 16, 0x20)),
        null,
      ),
    );
  return cipher.process(plain);
}

Uint8List _gcmEncrypt(Uint8List key, Uint8List nonce, Uint8List plain) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  return cipher.process(plain);
}

Uint8List _concat(List<List<int>> parts) => Uint8List.fromList([for (final p in parts) ...p]);

/// What Chromium stores for [value]: prefix + (host hash) + value, encrypted.
Uint8List _chromiumBlob(
  BrowserCookieOs os,
  Uint8List key,
  String host,
  String value, {
  required int dbVersion,
  String prefix = 'v10',
}) {
  final body = dbVersion >= 24
      ? _concat([SHA256Digest().process(_bytes(host)), _bytes(value)])
      : _bytes(value);
  if (os == BrowserCookieOs.windows) {
    final nonce = Uint8List.fromList(List.generate(12, (i) => i + 1));
    return _concat([_bytes(prefix), nonce, _gcmEncrypt(key, nonce, body)]);
  }
  return _concat([_bytes(prefix), _cbcEncrypt(key, body)]);
}

typedef _Row = ({
  String host,
  String name,
  String path,
  String value,
  Uint8List? blob,
  int? expires,
});

Future<String> _chromiumDb(
  Directory home,
  String userData,
  List<_Row> rows, {
  int version = 24,
  String profile = 'Default',
  bool inNetwork = true,
}) async {
  final dir = Directory('${home.path}/$userData/$profile${inNetwork ? '/Network' : ''}')
    ..createSync(recursive: true);
  final path = '${dir.path}/Cookies';
  final db = sqlite3.open(path)
    ..execute('CREATE TABLE meta(key TEXT UNIQUE NOT NULL, value TEXT)')
    ..execute(
      'CREATE TABLE cookies(host_key TEXT, name TEXT, path TEXT, value TEXT, '
      'encrypted_value BLOB, expires_utc INTEGER)',
    )
    ..execute("INSERT INTO meta VALUES('version', '$version')");
  for (final r in rows) {
    db.execute('INSERT INTO cookies VALUES(?, ?, ?, ?, ?, ?)', [
      r.host,
      r.name,
      r.path,
      r.value,
      r.blob ?? Uint8List(0),
      r.expires ?? 0,
    ]);
  }
  db.close();
  return path;
}

int get _futureExpiry => DateTime.utc(2027).microsecondsSinceEpoch + _msUnix1601;
int get _pastExpiry => DateTime.utc(2026).microsecondsSinceEpoch + _msUnix1601;

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('tokenbar-cookies-test-'));
  tearDown(() => home.deleteSync(recursive: true));

  int tempCopies() =>
      Directory.systemTemp.listSync().where((e) => e.path.contains('tokenbar-db-')).length;

  group('host matching', () {
    test('domain cookies match the host and its children, host-only cookies only the host', () {
      const hosts = ['platform.example.com'];
      expect(cookieDomainMatches('.example.com', hosts), isTrue);
      expect(cookieDomainMatches('.platform.example.com', hosts), isTrue);
      expect(cookieDomainMatches('platform.example.com', hosts), isTrue);
      expect(cookieDomainMatches('example.com', hosts), isFalse); // host-only on the parent
      expect(cookieDomainMatches('.sub.platform.example.com', hosts), isFalse);
      expect(cookieDomainMatches('.com', hosts), isFalse);
      expect(cookieDomainMatches('.evilexample.com', hosts), isFalse);
    });

    test('the SQL candidates cover host, parents and the dotted forms', () {
      expect(
        candidateCookieHosts(['a.b.example.com']),
        containsAll([
          'a.b.example.com',
          '.a.b.example.com',
          'b.example.com',
          '.b.example.com',
          'example.com',
          '.example.com',
        ]),
      );
      expect(candidateCookieHosts(['a.example.com']), isNot(contains('com')));
    });
  });

  group('Firefox', () {
    Future<void> firefoxDb(String profilesDir, String name, List<List<Object>> rows) async {
      final dir = Directory('${home.path}/$profilesDir/$name')..createSync(recursive: true);
      final db = sqlite3.open('${dir.path}/cookies.sqlite')
        ..execute(
          'CREATE TABLE moz_cookies(host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER)',
        );
      for (final r in rows) {
        db.execute('INSERT INTO moz_cookies VALUES(?, ?, ?, ?, ?)', r);
      }
      db.close();
    }

    test('reads matching, unexpired cookies only', () async {
      final nowSeconds = DateTime.utc(2026, 11, 21).millisecondsSinceEpoch ~/ 1000;
      await firefoxDb('Library/Application Support/Firefox/Profiles', 'abc.default-release', [
        ['.example.com', 'sid', '/', 'S1', nowSeconds + 1000],
        ['platform.example.com', 'token', '/', 'T1', nowSeconds + 1000],
        ['platform.example.com', 'old', '/', 'X', nowSeconds - 1000],
        ['other.com', 'leak', '/', 'L', nowSeconds + 1000],
        ['.sub.platform.example.com', 'child', '/', 'C', nowSeconds + 1000],
      ]);
      final before = tempCopies();
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        requiredNames: ['sid', 'token'],
        browsers: [BrowserKind.firefox],
        homeDir: home.path,
        environment: _Env(BrowserCookieOs.macos),
      );
      expect(result.problem, isNull);
      expect(result.browser, BrowserKind.firefox);
      expect(result.profile, 'abc.default-release');
      expect(result.header, anyOf('sid=S1; token=T1', 'token=T1; sid=S1'));
      expect(tempCopies(), before);
    });

    test('a missing required cookie is reported without leaking values', () async {
      await firefoxDb('.mozilla/firefox', 'p.default', [
        ['.example.com', 'sid', '/', 'SECRETVALUE', 0],
      ]);
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        requiredNames: ['sid', 'token'],
        browsers: [BrowserKind.firefox],
        homeDir: home.path,
        environment: _Env(BrowserCookieOs.linux),
      );
      expect(result.header, isNull);
      expect(result.problem, contains('token'));
      expect(result.problem, isNot(contains('SECRETVALUE')));
    });

    test('profiles.ini puts the default profile first', () {
      final paths = parseFirefoxProfilesIni('''
[Profile0]
Name=old
IsRelative=1
Path=Profiles/old.profile

[Profile1]
Name=main
IsRelative=1
Path=Profiles/main.default
Default=1

[Install4F96D1932A9F858E]
Default=Profiles/main.default
Locked=1
''');
      expect(paths.map((p) => p.path), ['Profiles/main.default', 'Profiles/old.profile']);
      expect(paths.every((p) => p.relative), isTrue);
    });

    test('no browser installed explains what was searched', () async {
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        browsers: [BrowserKind.firefox, BrowserKind.chrome],
        homeDir: home.path,
        environment: _Env(BrowserCookieOs.linux),
      );
      expect(result.header, isNull);
      expect(result.problem, allOf(contains('Firefox'), contains('Chrome')));
    });
  });

  group('Chromium', () {
    test('macOS: keychain password -> AES-128-CBC, host hash stripped (version 24)', () async {
      final key = deriveChromiumKey('synthetic-password', iterations: 1003);
      await _chromiumDb(home, 'Library/Application Support/Google/Chrome', [
        (
          host: '.example.com',
          name: 'sid',
          path: '/',
          value: '',
          blob: _chromiumBlob(BrowserCookieOs.macos, key, '.example.com', 'S-MAC', dbVersion: 24),
          expires: _futureExpiry,
        ),
        (
          host: 'platform.example.com',
          name: 'plain',
          path: '/',
          value: 'P1',
          blob: null,
          expires: 0,
        ),
        (
          host: '.example.com',
          name: 'expired',
          path: '/',
          value: 'gone',
          blob: null,
          expires: _pastExpiry,
        ),
        (
          host: '.unrelated.org',
          name: 'leak',
          path: '/',
          value: '',
          blob: _chromiumBlob(BrowserCookieOs.macos, key, '.unrelated.org', 'no', dbVersion: 24),
          expires: 0,
        ),
      ]);
      final env = _Env(
        BrowserCookieOs.macos,
        commands: {'/usr/bin/security': const ProcessOutput(0, 'synthetic-password\n', '')},
      );
      final before = tempCopies();
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        requiredNames: ['sid'],
        browsers: [BrowserKind.chrome],
        homeDir: home.path,
        environment: env,
      );
      expect(result.problem, isNull);
      expect(result.browser, BrowserKind.chrome);
      expect(result.profile, 'Default');
      expect(result.header, anyOf('sid=S-MAC; plain=P1', 'plain=P1; sid=S-MAC'));
      expect(env.ran.single, contains('Chrome Safe Storage'));
      expect(tempCopies(), before);
    });

    test('macOS: version < 24 has no host-hash prefix', () async {
      final key = deriveChromiumKey('pw', iterations: 1003);
      await _chromiumDb(home, 'Library/Application Support/BraveSoftware/Brave-Browser', [
        (
          host: '.example.com',
          name: 'sid',
          path: '/',
          value: '',
          blob: _chromiumBlob(BrowserCookieOs.macos, key, '.example.com', 'OLD', dbVersion: 23),
          expires: 0,
        ),
      ], version: 23);
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        browsers: [BrowserKind.brave],
        homeDir: home.path,
        environment: _Env(
          BrowserCookieOs.macos,
          commands: {'/usr/bin/security': const ProcessOutput(0, 'pw\n', '')},
        ),
      );
      expect(result.header, 'sid=OLD');
    });

    test('macOS: a denied keychain is explained, not thrown', () async {
      final key = deriveChromiumKey('pw', iterations: 1003);
      await _chromiumDb(home, 'Library/Application Support/Google/Chrome', [
        (
          host: '.example.com',
          name: 'sid',
          path: '/',
          value: '',
          blob: _chromiumBlob(BrowserCookieOs.macos, key, '.example.com', 'x', dbVersion: 24),
          expires: 0,
        ),
      ]);
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        browsers: [BrowserKind.chrome],
        homeDir: home.path,
        environment: _Env(
          BrowserCookieOs.macos,
          commands: {'/usr/bin/security': const ProcessOutput(51, '', 'denied')},
        ),
      );
      expect(result.header, isNull);
      expect(result.problem, contains('钥匙串'));
    });

    test('Linux: v10 uses "peanuts", v11 the libsecret password', () async {
      final peanuts = deriveChromiumKey('peanuts', iterations: 1);
      final secret = deriveChromiumKey('ring-password', iterations: 1);
      await _chromiumDb(home, '.config/google-chrome', [
        (
          host: '.example.com',
          name: 'a',
          path: '/',
          value: '',
          blob: _chromiumBlob(BrowserCookieOs.linux, peanuts, '.example.com', 'V10', dbVersion: 24),
          expires: 0,
        ),
        (
          host: '.example.com',
          name: 'b',
          path: '/',
          value: '',
          blob: _chromiumBlob(
            BrowserCookieOs.linux,
            secret,
            '.example.com',
            'V11',
            dbVersion: 24,
            prefix: 'v11',
          ),
          expires: 0,
        ),
      ]);
      final env = _Env(
        BrowserCookieOs.linux,
        commands: {'/usr/bin/secret-tool': const ProcessOutput(0, 'ring-password\n', '')},
      )..tools.add('secret-tool');
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        requiredNames: ['a', 'b'],
        browsers: [BrowserKind.chrome],
        homeDir: home.path,
        environment: env,
      );
      expect(result.problem, isNull);
      expect(result.header, anyOf('a=V10; b=V11', 'b=V11; a=V10'));
      expect(env.ran.single, contains('lookup application chrome'));
    });

    test('Windows: DPAPI-wrapped key -> AES-256-GCM (v10)', () async {
      final key = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      final wrapped = _bytes('pretend-dpapi-blob');
      final userData = 'AppData/Local/Microsoft/Edge/User Data';
      Directory('${home.path}/$userData').createSync(recursive: true);
      File('${home.path}/$userData/Local State').writeAsStringSync(
        jsonEncode({
          'os_crypt': {
            'encrypted_key': base64.encode([..._bytes('DPAPI'), ...wrapped]),
          },
        }),
      );
      await _chromiumDb(home, userData, [
        (
          host: '.example.com',
          name: 'sid',
          path: '/',
          value: '',
          blob: _chromiumBlob(BrowserCookieOs.windows, key, '.example.com', 'S-WIN', dbVersion: 24),
          expires: _futureExpiry,
        ),
      ]);
      final env = _Env(
        BrowserCookieOs.windows,
        commands: {'powershell.exe': ProcessOutput(0, '${base64.encode(key)}\r\n', '')},
      );
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        browsers: [BrowserKind.edge],
        homeDir: home.path,
        environment: env,
      );
      expect(result.problem, isNull);
      expect(result.header, 'sid=S-WIN');
      expect(result.browser, BrowserKind.edge);
      // Only the DPAPI payload (without the "DPAPI" tag) goes to PowerShell.
      expect(env.ran.single, contains(base64.encode(wrapped)));
      expect(env.ran.single, isNot(contains(base64.encode(key))));
    });

    test('Windows: v20 app-bound values are refused, never decrypted', () async {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final userData = 'AppData/Local/Google/Chrome/User Data';
      Directory('${home.path}/$userData').createSync(recursive: true);
      File('${home.path}/$userData/Local State').writeAsStringSync(
        jsonEncode({
          'os_crypt': {
            'encrypted_key': base64.encode([..._bytes('DPAPI'), 1, 2, 3]),
          },
        }),
      );
      await _chromiumDb(home, userData, [
        (
          host: '.example.com',
          name: 'sid',
          path: '/',
          value: '',
          // Even with a valid GCM body the v20 tag must stop us.
          blob: _chromiumBlob(
            BrowserCookieOs.windows,
            key,
            '.example.com',
            'S',
            dbVersion: 24,
            prefix: 'v20',
          ),
          expires: 0,
        ),
      ]);
      final env = _Env(
        BrowserCookieOs.windows,
        commands: {'powershell.exe': ProcessOutput(0, '${base64.encode(key)}\n', '')},
      );
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        browsers: [BrowserKind.chrome],
        homeDir: home.path,
        environment: env,
      );
      expect(result.header, isNull);
      expect(result.problem, allOf(contains('v20'), contains('Firefox')));
    });

    test('decryptChromiumValue reports v20 and missing keys', () {
      final blob = _concat([_bytes('v20'), List.filled(40, 1)]);
      expect(
        decryptChromiumValue(blob, os: BrowserCookieOs.windows, v10Key: Uint8List(32)).status,
        CookieDecryptStatus.appBound,
      );
      final v10 = _concat([_bytes('v10'), List.filled(32, 1)]);
      expect(
        decryptChromiumValue(v10, os: BrowserCookieOs.macos, v10Key: null).status,
        CookieDecryptStatus.noKey,
      );
      expect(
        decryptChromiumValue(
          v10,
          os: BrowserCookieOs.macos,
          v10Key: deriveChromiumKey('wrong', iterations: 1003),
        ).status,
        CookieDecryptStatus.failed,
      );
    });

    test('a locked database (copy impossible) is reported', () async {
      // A file SQLite cannot open stands in for a database the browser holds locked.
      Directory('${home.path}/.config/chromium/Default/Network').createSync(recursive: true);
      File('${home.path}/.config/chromium/Default/Network/Cookies')
          .writeAsStringSync('not a database' * 50);
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        browsers: [BrowserKind.chromium],
        homeDir: home.path,
        environment: _Env(BrowserCookieOs.linux),
      );
      expect(result.header, isNull);
      expect(result.problem, contains('Chromium'));
      expect(result.problem, contains('锁定'));
    });

    test('the original database is not modified', () async {
      final key = deriveChromiumKey('peanuts', iterations: 1);
      final path = await _chromiumDb(home, '.config/chromium', [
        (
          host: '.example.com',
          name: 'sid',
          path: '/',
          value: '',
          blob: _chromiumBlob(BrowserCookieOs.linux, key, '.example.com', 'V', dbVersion: 24),
          expires: 0,
        ),
      ]);
      final before = File(path).readAsBytesSync();
      final result = await readBrowserCookies(
        hosts: _hostsUnderTest,
        browsers: [BrowserKind.chromium],
        homeDir: home.path,
        environment: _Env(BrowserCookieOs.linux),
      );
      expect(result.header, 'sid=V');
      expect(File(path).readAsBytesSync(), before);
      expect(Directory(File(path).parent.path).listSync().length, 1); // no stray -wal / -shm
    });
  });

  test('searches the browsers in order and falls through to the next one', () async {
    final key = deriveChromiumKey('peanuts', iterations: 1);
    await _chromiumDb(home, '.config/google-chrome', [
      (
        host: '.example.com',
        name: 'sid',
        path: '/',
        value: '',
        blob: _chromiumBlob(BrowserCookieOs.linux, key, '.example.com', 'CHROME', dbVersion: 24),
        expires: 0,
      ),
    ]);
    // Firefox is installed but holds no matching cookie.
    final ff = Directory('${home.path}/.mozilla/firefox/x.default')..createSync(recursive: true);
    sqlite3.open('${ff.path}/cookies.sqlite')
      ..execute(
        'CREATE TABLE moz_cookies(host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER)',
      )
      ..close();
    final result = await readBrowserCookies(
      hosts: _hostsUnderTest,
      requiredNames: ['sid'],
      homeDir: home.path,
      environment: _Env(BrowserCookieOs.linux),
    );
    expect(result.browser, BrowserKind.chrome);
    expect(result.header, 'sid=CHROME');
  });
}
