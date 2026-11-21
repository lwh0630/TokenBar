import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/src/platform/browser_cookies.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

// Synthetic only: a throw-away "Firefox profile" in a temp home, no real browser involved.

class _Env extends BrowserCookieEnvironment {
  _Env(this._home);

  final String _home;
  int reads = 0;

  @override
  BrowserCookieOs get os => BrowserCookieOs.linux;

  @override
  String? get homeDir => _home;

  @override
  String? env(String name) => null;

  @override
  Future<List<List<Object?>>?> readRows(
    String path,
    String sql,
    List<Object?> params, {
    bool copy = false,
  }) {
    reads++;
    return super.readRows(path, sql, params, copy: copy);
  }
}

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<_Env> _firefoxHome({required bool withRequired}) async {
  final home = await Directory.systemTemp.createTemp('tokenbar_cookie_src');
  addTearDown(() => home.delete(recursive: true));
  final profile = Directory('${home.path}/.mozilla/firefox/x.default')..createSync(recursive: true);
  final db = sqlite3.open('${profile.path}/cookies.sqlite');
  db.execute(
    'CREATE TABLE moz_cookies(host TEXT, name TEXT, path TEXT, value TEXT, expiry INTEGER)',
  );
  const farFuture = 4102444800; // seconds
  void put(String host, String name, String value) => db.execute(
    'INSERT INTO moz_cookies VALUES(?, ?, ?, ?, ?)',
    [host, name, '/', value, farFuture],
  );
  put('platform.xiaomimimo.com', 'api-platform_serviceToken', 'browser-token');
  put('.example.com', 'unrelated', 'other-site');
  if (withRequired) put('.xiaomimimo.com', 'userId', 'browser-user');
  db.close();
  return _Env(home.path);
}

Future<(UsageSnapshot, List<http.Request>)> _mimo({
  BrowserCookieEnvironment? browser,
  String? secret,
  Map<String, String> options = const {},
}) async {
  final requests = <http.Request>[];
  final client = MockClient((r) async {
    requests.add(r);
    if (r.url.path == '/api/v1/balance') {
      return _json({
        'code': 0,
        'data': {'balance': 5.0, 'currency': 'CNY'},
      });
    }
    return _json({'code': 1});
  });
  final provider = ProviderRegistry.instance.byId('mimo')!;
  final s = await provider.fetchSafely(
    AccountConfig(
      id: 'a',
      providerId: 'mimo',
      label: 'mimo',
      sourceType: SourceType.apiKey,
      secret: secret,
      options: options,
    ),
    FetchContext(client: client, browserCookies: browser),
  );
  return (s, requests);
}

void main() {
  group('browser cookie source (MiMo)', () {
    test('an account with no pasted cookie uses the signed-in browser', () async {
      final env = await _firefoxHome(withRequired: true);
      final (s, requests) = await _mimo(browser: env);
      expect(s.error, isNull, reason: s.error);
      final cookie = requests.first.headers['Cookie']!;
      expect(cookie, contains('api-platform_serviceToken=browser-token'));
      expect(cookie, contains('userId=browser-user'));
      // Only this service's cookies are sent, never the rest of the jar.
      expect(cookie, isNot(contains('other-site')));
    });

    test('the browser wins over a stale pasted copy', () async {
      final env = await _firefoxHome(withRequired: true);
      final (_, requests) = await _mimo(
        browser: env,
        secret: 'api-platform_serviceToken=stale; userId=stale-user',
      );
      expect(requests.first.headers['Cookie'], contains('browser-token'));
    });

    test('manual mode never reads a browser', () async {
      final env = await _firefoxHome(withRequired: true);
      final (s, requests) = await _mimo(
        browser: env,
        secret: 'api-platform_serviceToken=pasted; userId=pasted-user',
        options: {'cookieSource': 'manual'},
      );
      expect(s.error, isNull, reason: s.error);
      expect(env.reads, 0);
      expect(requests.first.headers['Cookie'], contains('pasted-user'));
    });

    test('without browser access in the context a browser is never touched', () async {
      final (s, requests) = await _mimo();
      expect(s.error, contains('未填写'));
      expect(requests, isEmpty);
    });

    test('a signed-out browser falls back to the pasted cookie, else explains', () async {
      final env = await _firefoxHome(withRequired: false);
      final (ok, requests) = await _mimo(
        browser: env,
        secret: 'api-platform_serviceToken=pasted; userId=pasted-user',
      );
      expect(ok.error, isNull, reason: ok.error);
      expect(requests.first.headers['Cookie'], contains('pasted-user'));

      final (bad, none) = await _mimo(browser: env);
      expect(bad.error, isNotNull);
      expect(bad.errorHint, contains('Cookie 来源'));
      expect(none, isEmpty);
    });

    test('a tp- Token Plan key never needs a browser', () async {
      final env = await _firefoxHome(withRequired: true);
      final (_, requests) = await _mimo(browser: env, secret: 'tp-abc');
      expect(env.reads, 0);
      expect(requests.single.url.host, startsWith('token-plan-'));
    });

    test('validation lets an empty field through only while automatic is on', () {
      final mimo = ProviderRegistry.instance.byId('mimo')!;
      FieldValues values(Map<String, String> v) => FieldValues(mimo.displayName, mimo.fields, v);
      final auto = mimo.validateManual(values({}));
      final manual = mimo.validateManual(values({'cookieSource': 'manual'}));
      // Automatic is only available on a desktop; on other hosts the field is required.
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        expect(auto, isNull);
      }
      expect(manual, isNotNull);
    });
  });
}
