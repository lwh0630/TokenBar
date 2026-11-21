/// Read-only access to the cookies of locally installed desktop browsers.
///
/// Used by cookie-based providers so the user does not have to copy a Cookie header out of the
/// developer tools by hand. Rules this file keeps:
///
/// * Strictly read-only: a Chromium cookie store is copied to a private temp file first (the
///   running browser locks it), a Firefox store is opened read-only; nothing is ever written
///   back, and the temp copy is deleted again.
/// * Only cookies whose domain matches the requested hosts are selected by the SQL query, so
///   unrelated cookies are never even loaded. Cookie values are never logged and never appear
///   in [BrowserCookieResult.problem].
/// * Chromium encryption is decrypted with the browser's own OS secret (macOS keychain,
///   Linux libsecret, Windows DPAPI). App-bound `v20` values (Chrome 127+ on Windows) are
///   deliberately **not** attempted: they are reported through [BrowserCookieResult.problem].
/// * Nothing here refreshes, rewrites or stores anything; the caller decides what to do with
///   the returned header.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'platform.dart' as platform;

/// Browsers whose cookie store can be read.
enum BrowserKind {
  firefox('Firefox'),
  chrome('Chrome'),
  edge('Edge'),
  brave('Brave'),
  chromium('Chromium'),
  vivaldi('Vivaldi'),
  opera('Opera'),
  arc('Arc');

  const BrowserKind(this.label);

  final String label;

  bool get isChromium => this != firefox;
}

/// Outcome of [readBrowserCookies]: either a [header] ready for a `Cookie:` request header,
/// or a Chinese user-facing [problem]. [browser] / [profile] only say where it came from.
class BrowserCookieResult {
  const BrowserCookieResult({this.header, this.browser, this.profile, this.problem});

  final String? header;
  final BrowserKind? browser;
  final String? profile;
  final String? problem;

  bool get found => header != null;
}

enum BrowserCookieOs { windows, macos, linux }

/// Everything [readBrowserCookies] touches outside the process: the file system, SQLite,
/// environment variables and child processes. The default talks to the real machine; tests
/// subclass it so no real browser is needed.
class BrowserCookieEnvironment {
  const BrowserCookieEnvironment();

  bool get supported => platform.localAccessSupported;

  BrowserCookieOs get os => platform.isWindows
      ? BrowserCookieOs.windows
      : platform.isMacOS
      ? BrowserCookieOs.macos
      : BrowserCookieOs.linux;

  String? env(String name) => platform.envVar(name);

  String? get homeDir => platform.homeDirectory();

  String join(String a, String b, [String? c, String? d]) => platform.joinPath(a, b, c, d);

  Future<List<platform.LocalFileEntry>> list(String path) => platform.listDirectory(path);

  Future<String?> readText(String path) => platform.readTextFile(path);

  /// Rows of [sql] from the SQLite file at [path], or null when it is missing, locked or
  /// unreadable. With [copy] the file is read from a throw-away copy.
  Future<List<List<Object?>>?> readRows(
    String path,
    String sql,
    List<Object?> params, {
    bool copy = false,
  }) => platform.readSqliteRowsOrNull(path, sql, params, copy);

  Future<platform.ProcessOutput?> run(String executable, List<String> args) =>
      platform.runProcess(executable, args);

  Future<String?> findExecutable(String name) => platform.findExecutable(name);

  DateTime now() => DateTime.now();
}

/// Reads the cookies for [hosts] from the first browser / profile that holds a usable
/// session and returns them as a `name=value; ...` header.
///
/// [hosts] are the request hosts the cookies must be valid for (`platform.example.com`): a
/// cookie matches when its host-only domain equals a host, or its domain cookie is that host
/// or a parent of it (RFC 6265 domain matching). [requiredNames], when given, must all be
/// present, otherwise that profile is skipped (e.g. the browser is not signed in). [browsers]
/// restricts and orders the search; the default tries Firefox first (no encryption, no
/// prompts) and then the Chromium family. [homeDir] overrides the user's home directory.
Future<BrowserCookieResult> readBrowserCookies({
  required List<String> hosts,
  List<String> requiredNames = const [],
  List<BrowserKind>? browsers,
  String? homeDir,
  BrowserCookieEnvironment environment = const BrowserCookieEnvironment(),
}) async {
  if (!environment.supported) {
    return const BrowserCookieResult(problem: '当前平台不支持读取浏览器 Cookie');
  }
  final wanted = _normalizeHosts(hosts);
  if (wanted.isEmpty) return const BrowserCookieResult(problem: '没有指定要读取 Cookie 的网站');
  final home = homeDir ?? environment.homeDir;
  if (home == null) return const BrowserCookieResult(problem: '找不到用户主目录，无法定位浏览器');
  final reader = _Reader(
    environment,
    _Roots.of(environment, home, explicit: homeDir != null),
    wanted,
    requiredNames,
  );
  final order = browsers ?? BrowserKind.values;
  for (final kind in order) {
    final found = kind == BrowserKind.firefox
        ? await reader.firefox()
        : await reader.chromium(kind);
    if (found != null) return found;
  }
  return BrowserCookieResult(
    problem: reader.problem ?? '没有找到可读取的浏览器 Cookie（已查找：${order.map((b) => b.label).join('、')}）',
  );
}

// ------------------------------------------------------------------- matching

List<String> _normalizeHosts(List<String> hosts) => {
  for (final h in hosts)
    if (h.trim().isNotEmpty) h.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), ''),
}.toList();

/// Every cookie `host` value that could match one of [hosts], with and without the leading
/// dot, so the SQL query can select by exact match instead of reading all cookies.
List<String> candidateCookieHosts(List<String> hosts) {
  final out = <String>{};
  for (final host in hosts) {
    final labels = host.split('.');
    if (labels.length == 1) {
      out.add(host);
      continue;
    }
    // A single label ("com") is a public suffix and can never be a cookie domain.
    for (var i = 0; i < labels.length - 1; i++) {
      final suffix = labels.sublist(i).join('.');
      out
        ..add(suffix)
        ..add('.$suffix');
    }
  }
  return out.toList();
}

/// RFC 6265 domain match of a stored cookie `host` (leading dot = domain cookie) against the
/// request [hosts].
bool cookieDomainMatches(String cookieHost, List<String> hosts) {
  final domainCookie = cookieHost.startsWith('.');
  final domain = (domainCookie ? cookieHost.substring(1) : cookieHost).toLowerCase();
  if (domain.isEmpty) return false;
  for (final host in hosts) {
    if (host == domain) return true;
    if (domainCookie && domain.contains('.') && host.endsWith('.$domain')) return true;
  }
  return false;
}

class _Cookie {
  _Cookie(this.domain, this.name, this.path, this.value);

  final String domain;
  final String name;
  final String path;
  final String value;
}

/// Builds the header from [cookies]: more specific domain first, then longer path; the first
/// cookie of a name wins.
Map<String, String> _pairs(List<_Cookie> cookies) {
  final sorted = [...cookies]
    ..sort((a, b) {
      final byDomain = b.domain.length.compareTo(a.domain.length);
      return byDomain != 0 ? byDomain : b.path.length.compareTo(a.path.length);
    });
  final pairs = <String, String>{};
  for (final c in sorted) {
    pairs.putIfAbsent(c.name, () => c.value);
  }
  return pairs;
}

// ---------------------------------------------------------------- decryption

enum CookieDecryptStatus { ok, appBound, noKey, failed, unknownFormat }

class CookieDecryption {
  const CookieDecryption(this.status, [this.value]);

  final CookieDecryptStatus status;
  final String? value;
}

/// AES key for the Chromium `v10` / `v11` scheme on macOS and Linux:
/// PBKDF2-HMAC-SHA1(password, "saltysalt", [iterations], 16 bytes).
Uint8List deriveChromiumKey(String password, {required int iterations}) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(utf8.encode('saltysalt')), iterations, 16));
  return derivator.process(Uint8List.fromList(utf8.encode(password)));
}

/// Decrypts one Chromium `encrypted_value`.
///
/// * macOS / Linux: `v10` / `v11` + AES-128-CBC (IV = 16 spaces, PKCS7).
/// * Windows: `v10` + 12-byte nonce + AES-256-GCM ciphertext and 16-byte tag.
/// * `v20` (app-bound encryption) is never attempted: [CookieDecryptStatus.appBound].
///
/// With [dbVersion] >= 24 the plaintext starts with SHA-256 of the cookie host, which is
/// dropped. [v10Key] / [v11Key] are the browser's keys; null means "could not be obtained".
CookieDecryption decryptChromiumValue(
  Uint8List encrypted, {
  required BrowserCookieOs os,
  required Uint8List? v10Key,
  Uint8List? v11Key,
  int dbVersion = 0,
}) {
  if (encrypted.length < 4) return const CookieDecryption(CookieDecryptStatus.unknownFormat);
  final prefix = String.fromCharCodes(encrypted.sublist(0, 3));
  if (prefix == 'v20') return const CookieDecryption(CookieDecryptStatus.appBound);
  if (prefix != 'v10' && prefix != 'v11') {
    return const CookieDecryption(CookieDecryptStatus.unknownFormat);
  }
  final key = prefix == 'v11' ? v11Key : v10Key;
  if (key == null) return const CookieDecryption(CookieDecryptStatus.noKey);
  try {
    final Uint8List plain;
    if (os == BrowserCookieOs.windows) {
      if (prefix != 'v10' || encrypted.length < 3 + 12 + 16) {
        return const CookieDecryption(CookieDecryptStatus.unknownFormat);
      }
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), 128, encrypted.sublist(3, 15), Uint8List(0)),
        );
      plain = cipher.process(encrypted.sublist(15));
    } else {
      final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
        ..init(
          false,
          PaddedBlockCipherParameters(
            ParametersWithIV(KeyParameter(key), Uint8List(16)..fillRange(0, 16, 0x20)),
            null,
          ),
        );
      plain = cipher.process(encrypted.sublist(3));
    }
    final body = dbVersion >= 24 && plain.length >= 32 ? plain.sublist(32) : plain;
    return CookieDecryption(CookieDecryptStatus.ok, utf8.decode(body));
  } catch (_) {
    // Wrong key, corrupt data or invalid UTF-8: all end up as "cannot decrypt".
    return const CookieDecryption(CookieDecryptStatus.failed);
  }
}

class _Keys {
  _Keys({this.v10, this.v11, this.problem});

  final Uint8List? v10;
  final Uint8List? v11;

  /// Why a key is missing (Chinese), shown when nothing could be decrypted.
  final String? problem;
}

// -------------------------------------------------------------------- reader

class _Roots {
  _Roots({required this.home, required this.local, required this.roaming});

  factory _Roots.of(BrowserCookieEnvironment env, String home, {required bool explicit}) {
    // With an explicit home the Windows app-data folders are derived from it, so a
    // sandboxed / test home never leaks into the real %LOCALAPPDATA%.
    String pick(String name, String fallback) => explicit ? fallback : (env.env(name) ?? fallback);
    return _Roots(
      home: home,
      local: pick('LOCALAPPDATA', env.join(home, 'AppData', 'Local')),
      roaming: pick('APPDATA', env.join(home, 'AppData', 'Roaming')),
    );
  }

  final String home;
  final String local;
  final String roaming;
}

/// Ranks what to tell the user when nothing was found; the highest rank wins.
enum _Issue { noCookies, missingRequired, locked, keyDenied, appBound }

class _Reader {
  _Reader(this.env, this.roots, this.hosts, this.requiredNames);

  final BrowserCookieEnvironment env;
  final _Roots roots;
  final List<String> hosts;
  final List<String> requiredNames;

  _Issue? _issue;
  String? _issueText;

  String? get problem => _issueText;

  void _report(_Issue issue, String text) {
    final current = _issue;
    if (current == null || issue.index > current.index) {
      _issue = issue;
      _issueText = text;
    }
  }

  /// Header for [cookies] when it satisfies [requiredNames], else null (and records why).
  String? _header(List<_Cookie> cookies, BrowserKind kind) {
    if (cookies.isEmpty) {
      _report(_Issue.noCookies, '在 ${kind.label} 中没有找到 ${hosts.join('、')} 的 Cookie，请先在该浏览器登录');
      return null;
    }
    final pairs = _pairs(cookies);
    final missing = [
      for (final n in requiredNames)
        if (!pairs.containsKey(n)) n,
    ];
    if (missing.isNotEmpty) {
      _report(
        _Issue.missingRequired,
        '在 ${kind.label} 中找到了 ${hosts.join('、')} 的 Cookie，但缺少 ${missing.join('、')}，可能尚未登录或登录已过期',
      );
      return null;
    }
    return pairs.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  String _marks(int n) => List.filled(n, '?').join(', ');

  // ---------------------------------------------------------------- Firefox

  Future<BrowserCookieResult?> firefox() async {
    final roots = <String, String>{}; // root -> directory that holds the profile folders
    switch (env.os) {
      case BrowserCookieOs.macos:
        final root = env.join(this.roots.home, 'Library', 'Application Support', 'Firefox');
        roots[root] = env.join(root, 'Profiles');
      case BrowserCookieOs.windows:
        final root = env.join(this.roots.roaming, 'Mozilla', 'Firefox');
        roots[root] = env.join(root, 'Profiles');
      case BrowserCookieOs.linux:
        for (final root in [
          env.join(this.roots.home, '.mozilla', 'firefox'),
          env.join(env.join(this.roots.home, 'snap', 'firefox', 'common'), '.mozilla', 'firefox'),
          env.join(
            env.join(this.roots.home, '.var', 'app', 'org.mozilla.firefox'),
            '.mozilla',
            'firefox',
          ),
        ]) {
          roots[root] = root;
        }
    }
    final candidates = candidateCookieHosts(hosts);
    for (final entry in roots.entries) {
      final profiles = await _firefoxProfiles(entry.key, entry.value);
      for (final profile in profiles) {
        final files = await env.list(profile);
        if (!files.any((f) => !f.isDirectory && f.name == 'cookies.sqlite')) continue;
        final db = env.join(profile, 'cookies.sqlite');
        final sql =
            'SELECT host, name, path, value, expiry FROM moz_cookies '
            'WHERE host IN (${_marks(candidates.length)})';
        // A live Firefox is read in place (read-only); a copy covers a locked database.
        final rows =
            await env.readRows(db, sql, candidates) ??
            await env.readRows(db, sql, candidates, copy: true);
        final name = _lastSegment(profile);
        if (rows == null) {
          _report(_Issue.locked, '无法读取 Firefox 的 Cookie 数据库（配置文件 $name），请关闭 Firefox 后重试');
          continue;
        }
        final now = env.now();
        final cookies = <_Cookie>[];
        for (final row in rows) {
          if (row.length < 5) continue;
          final host = row[0];
          final cookieName = row[1];
          final path = row[2];
          final value = row[3];
          if (host is! String || cookieName is! String || value is! String) continue;
          if (value.isEmpty || !cookieDomainMatches(host, hosts)) continue;
          if (_firefoxExpired(row[4], now)) continue;
          cookies.add(_Cookie(host, cookieName, path is String ? path : '/', value));
        }
        final header = _header(cookies, BrowserKind.firefox);
        if (header != null) {
          return BrowserCookieResult(header: header, browser: BrowserKind.firefox, profile: name);
        }
      }
    }
    return null;
  }

  bool _firefoxExpired(Object? expiry, DateTime now) {
    if (expiry is! int || expiry <= 0) return false;
    // Seconds in current Firefox, milliseconds in some older stores.
    final ms = expiry > 100000000000 ? expiry : expiry * 1000;
    return ms <= now.millisecondsSinceEpoch;
  }

  /// Profile directories in the order Firefox itself prefers them: the install default,
  /// profiles flagged `Default=1`, the rest of `profiles.ini`, then any other folder.
  Future<List<String>> _firefoxProfiles(String root, String profilesDir) async {
    final ordered = <String>[];
    void add(String path) {
      if (!ordered.contains(path)) ordered.add(path);
    }

    final ini = await env.readText(env.join(root, 'profiles.ini'));
    if (ini != null) {
      for (final path in parseFirefoxProfilesIni(ini)) {
        add(path.relative ? env.join(root, path.path) : path.path);
      }
    }
    for (final entry in await env.list(profilesDir)) {
      if (entry.isDirectory) add(entry.path);
    }
    return ordered;
  }

  // --------------------------------------------------------------- Chromium

  Future<BrowserCookieResult?> chromium(BrowserKind kind) async {
    final userData = _chromiumUserData(kind);
    if (userData == null) return null;
    final top = await env.list(userData);
    if (top.isEmpty) return null;
    // Opera keeps its profile in the root folder; the others use Default / Profile N.
    final profiles = <String>[];
    if (kind == BrowserKind.opera) {
      profiles.add(userData);
    } else {
      final dirs = top
          .where((e) => e.isDirectory && (e.name == 'Default' || e.name.startsWith('Profile ')))
          .toList();
      int rank(String name) =>
          name == 'Default' ? 0 : (int.tryParse(name.substring('Profile '.length)) ?? 9999) + 1;
      dirs.sort((a, b) => rank(a.name).compareTo(rank(b.name)));
      profiles.addAll(dirs.map((d) => d.path));
    }
    final candidates = candidateCookieHosts(hosts);
    Future<_Keys>? keys;
    Future<_Keys> loadKeys() => keys ??= _chromiumKeys(kind, userData);
    for (final profile in profiles) {
      final db = await _chromiumCookieFile(profile);
      if (db == null) continue;
      final name = profile == userData ? 'Default' : _lastSegment(profile);
      final rows = await env.readRows(
        db,
        'SELECT host_key, name, path, value, encrypted_value, expires_utc, '
        "(SELECT value FROM meta WHERE key = 'version') FROM cookies "
        'WHERE host_key IN (${_marks(candidates.length)})',
        candidates,
        copy: true,
      );
      if (rows == null) {
        _report(
          _Issue.locked,
          '无法读取 ${kind.label} 的 Cookie 数据库（${kind.label} 运行时可能锁定了该文件）。'
          '请关闭 ${kind.label} 后重试，或改用 Firefox / 手动粘贴 Cookie',
        );
        continue;
      }
      final now = env.now();
      final cookies = <_Cookie>[];
      var appBound = false;
      var undecryptable = false;
      String? keyProblem;
      for (final row in rows) {
        if (row.length < 7) continue;
        final host = row[0];
        final cookieName = row[1];
        final path = row[2];
        if (host is! String || cookieName is! String || !cookieDomainMatches(host, hosts)) {
          continue;
        }
        if (_chromiumExpired(row[5], now)) continue;
        String? value;
        final plain = row[3];
        final blob = row[4];
        if (plain is String && plain.isNotEmpty) {
          value = plain;
        } else if (blob is List<int> && blob.isNotEmpty) {
          final encrypted = blob is Uint8List ? blob : Uint8List.fromList(blob);
          final k = await loadKeys();
          final result = decryptChromiumValue(
            encrypted,
            os: env.os,
            v10Key: k.v10,
            v11Key: k.v11,
            dbVersion: _asInt(row[6]) ?? 0,
          );
          switch (result.status) {
            case CookieDecryptStatus.ok:
              value = result.value;
            case CookieDecryptStatus.appBound:
              appBound = true;
            case CookieDecryptStatus.noKey:
              keyProblem = k.problem;
            case CookieDecryptStatus.failed:
            case CookieDecryptStatus.unknownFormat:
              undecryptable = true;
          }
        }
        if (value == null || value.isEmpty) continue;
        cookies.add(_Cookie(host, cookieName, path is String ? path : '/', value));
      }
      final header = _header(cookies, kind);
      if (header != null) {
        return BrowserCookieResult(header: header, browser: kind, profile: name);
      }
      if (appBound) {
        _report(
          _Issue.appBound,
          '${kind.label} 使用了应用绑定加密（v20），TokenBar 不会尝试解密这类 Cookie。'
          '请改用 Firefox 登录后读取，或手动粘贴 Cookie',
        );
      } else if (keyProblem != null) {
        _report(_Issue.keyDenied, keyProblem);
      } else if (undecryptable) {
        _report(
          _Issue.keyDenied,
          '无法解密 ${kind.label} 的 Cookie（格式不受支持或密钥不匹配），请改用 Firefox 或手动粘贴 Cookie',
        );
      }
    }
    return null;
  }

  Future<String?> _chromiumCookieFile(String profile) async {
    final network = env.join(profile, 'Network');
    if ((await env.list(network)).any((f) => !f.isDirectory && f.name == 'Cookies')) {
      return env.join(network, 'Cookies');
    }
    if ((await env.list(profile)).any((f) => !f.isDirectory && f.name == 'Cookies')) {
      return env.join(profile, 'Cookies');
    }
    return null;
  }

  bool _chromiumExpired(Object? expiresUtc, DateTime now) {
    final v = _asInt(expiresUtc);
    if (v == null || v <= 0) return false; // 0 = session cookie
    // Microseconds since 1601-01-01.
    return v - 11644473600000000 <= now.microsecondsSinceEpoch;
  }

  String? _chromiumUserData(BrowserKind kind) {
    switch (env.os) {
      case BrowserCookieOs.windows:
        return switch (kind) {
          BrowserKind.chrome => env.join(roots.local, 'Google', 'Chrome', 'User Data'),
          BrowserKind.edge => env.join(roots.local, 'Microsoft', 'Edge', 'User Data'),
          BrowserKind.brave => env.join(roots.local, 'BraveSoftware', 'Brave-Browser', 'User Data'),
          BrowserKind.chromium => env.join(roots.local, 'Chromium', 'User Data'),
          BrowserKind.vivaldi => env.join(roots.local, 'Vivaldi', 'User Data'),
          BrowserKind.opera => env.join(roots.roaming, 'Opera Software', 'Opera Stable'),
          _ => null,
        };
      case BrowserCookieOs.macos:
        final support = env.join(roots.home, 'Library', 'Application Support');
        return switch (kind) {
          BrowserKind.chrome => env.join(support, 'Google', 'Chrome'),
          BrowserKind.edge => env.join(support, 'Microsoft Edge'),
          BrowserKind.brave => env.join(support, 'BraveSoftware', 'Brave-Browser'),
          BrowserKind.chromium => env.join(support, 'Chromium'),
          BrowserKind.vivaldi => env.join(support, 'Vivaldi'),
          BrowserKind.opera => env.join(support, 'com.operasoftware.Opera'),
          BrowserKind.arc => env.join(support, 'Arc', 'User Data'),
          _ => null,
        };
      case BrowserCookieOs.linux:
        final config = env.join(roots.home, '.config');
        return switch (kind) {
          BrowserKind.chrome => env.join(config, 'google-chrome'),
          BrowserKind.edge => env.join(config, 'microsoft-edge'),
          BrowserKind.brave => env.join(config, 'BraveSoftware', 'Brave-Browser'),
          BrowserKind.chromium => env.join(config, 'chromium'),
          BrowserKind.vivaldi => env.join(config, 'vivaldi'),
          BrowserKind.opera => env.join(config, 'opera'),
          _ => null,
        };
    }
  }

  // ------------------------------------------------------------- Chromium keys

  /// Fetches the browser's cookie keys. Only called once an encrypted value matching the
  /// requested hosts was found, so no keychain prompt appears for browsers without a session.
  Future<_Keys> _chromiumKeys(BrowserKind kind, String userData) async {
    switch (env.os) {
      case BrowserCookieOs.macos:
        final (service, account) = switch (kind) {
          BrowserKind.chrome => ('Chrome Safe Storage', 'Chrome'),
          BrowserKind.edge => ('Microsoft Edge Safe Storage', 'Microsoft Edge'),
          BrowserKind.brave => ('Brave Safe Storage', 'Brave'),
          BrowserKind.vivaldi => ('Vivaldi Safe Storage', 'Vivaldi'),
          BrowserKind.opera => ('Opera Safe Storage', 'Opera'),
          BrowserKind.arc => ('Arc Safe Storage', 'Arc'),
          _ => ('Chromium Safe Storage', 'Chromium'),
        };
        final out = await env.run('/usr/bin/security', [
          'find-generic-password',
          '-w',
          '-a',
          account,
          '-s',
          service,
        ]);
        final password = out == null || out.exitCode != 0 ? null : out.stdout.trim();
        if (password == null || password.isEmpty) {
          return _Keys(
            problem:
                '无法从钥匙串读取「$service」（访问可能被拒绝）。'
                '请在系统弹窗中允许访问，或改用 Firefox / 手动粘贴 Cookie',
          );
        }
        return _Keys(v10: deriveChromiumKey(password, iterations: 1003));
      case BrowserCookieOs.linux:
        // v10 always uses the fixed password "peanuts"; v11 uses the libsecret keyring.
        final v10 = deriveChromiumKey('peanuts', iterations: 1);
        final application = switch (kind) {
          BrowserKind.chrome || BrowserKind.vivaldi => 'chrome',
          BrowserKind.brave => 'brave',
          BrowserKind.chromium => 'chromium',
          _ => 'chromium',
        };
        Uint8List? v11;
        final tool = await env.findExecutable('secret-tool');
        if (tool != null) {
          final out = await env.run(tool, ['lookup', 'application', application]);
          final password = out == null || out.exitCode != 0 ? '' : out.stdout.trim();
          if (password.isNotEmpty) v11 = deriveChromiumKey(password, iterations: 1);
        }
        return _Keys(
          v10: v10,
          v11: v11,
          problem:
              '无法从系统钥匙环读取 ${kind.label} 的 Cookie 密钥（需要 secret-tool 与已解锁的钥匙环），请改用 Firefox 或手动粘贴 Cookie',
        );
      case BrowserCookieOs.windows:
        final state = await env.readText(env.join(userData, 'Local State'));
        final b64 = _osCryptKey(state);
        if (b64 == null) {
          return _Keys(
            problem: '找不到 ${kind.label} 的 Cookie 密钥（Local State 中没有 os_crypt.encrypted_key）',
          );
        }
        final bytes = base64.decode(b64);
        // The key is wrapped by DPAPI; the stored value starts with the literal "DPAPI".
        if (bytes.length <= 5 || String.fromCharCodes(bytes.sublist(0, 5)) != 'DPAPI') {
          return _Keys(problem: '${kind.label} 的 Cookie 密钥格式不受支持');
        }
        final wrapped = base64.encode(bytes.sublist(5));
        final out = await env.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Add-Type -AssemblyName System.Security; '
              '[Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Unprotect('
              "[Convert]::FromBase64String('$wrapped'), \$null, "
              '[System.Security.Cryptography.DataProtectionScope]::CurrentUser))',
        ]);
        final plain = out == null || out.exitCode != 0 ? null : out.stdout.trim();
        if (plain == null || !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(plain)) {
          return _Keys(
            problem: '无法通过 Windows DPAPI 解开 ${kind.label} 的 Cookie 密钥，请改用 Firefox 或手动粘贴 Cookie',
          );
        }
        final key = Uint8List.fromList(base64.decode(plain));
        return key.length == 32 ? _Keys(v10: key) : _Keys(problem: '${kind.label} 的 Cookie 密钥长度异常');
    }
  }

  String? _osCryptKey(String? localState) {
    if (localState == null) return null;
    try {
      final json = jsonDecode(localState);
      final osCrypt = json is Map ? json['os_crypt'] : null;
      final key = osCrypt is Map ? osCrypt['encrypted_key'] : null;
      if (key is String && RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(key)) return key;
    } on FormatException {
      return null;
    }
    return null;
  }
}

int? _asInt(Object? v) => switch (v) {
  int n => n,
  String s => int.tryParse(s),
  _ => null,
};

String _lastSegment(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// One profile entry of Firefox's `profiles.ini`.
typedef FirefoxProfilePath = ({String path, bool relative});

/// Profile paths from `profiles.ini` text, best first: the `[Install…]` default, profiles
/// flagged `Default=1`, then the others in file order. Duplicates are dropped.
List<FirefoxProfilePath> parseFirefoxProfilesIni(String text) {
  final sections = <String, Map<String, String>>{};
  Map<String, String>? current;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      current = sections.putIfAbsent(line.substring(1, line.length - 1), () => {});
    } else if (current != null && line.contains('=') && !line.startsWith(';')) {
      final i = line.indexOf('=');
      current[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
  }
  final out = <FirefoxProfilePath>[];
  void add(String? path, {required bool relative}) {
    if (path == null || path.isEmpty) return;
    if (!out.any((p) => p.path == path)) out.add((path: path, relative: relative));
  }

  for (final e in sections.entries) {
    if (e.key.startsWith('Install')) add(e.value['Default'], relative: true);
  }
  final profiles = sections.entries.where((e) => e.key.startsWith('Profile')).toList();
  for (final e in profiles) {
    if (e.value['Default'] == '1') add(e.value['Path'], relative: e.value['IsRelative'] != '0');
  }
  for (final e in profiles) {
    add(e.value['Path'], relative: e.value['IsRelative'] != '0');
  }
  return out;
}
