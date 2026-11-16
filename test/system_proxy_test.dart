import 'package:flutter_test/flutter_test.dart';
import 'package:token_bar/services/system_proxy.dart';

SystemProxyConfig? parse(Map<Object?, Object?>? raw) => SystemProxyConfig.parse(raw);

void main() {
  group('SystemProxyConfig.parse', () {
    test('reads enabled http and https entries', () {
      final c = parse({
        'HTTPEnable': 1,
        'HTTPProxy': '127.0.0.1',
        'HTTPPort': 8899,
        'HTTPSEnable': 1,
        'HTTPSProxy': '127.0.0.1',
        'HTTPSPort': 8899,
        'ExceptionsList': ['*.local', '169.254/16'],
      })!;
      expect(c.httpProxy, '127.0.0.1:8899');
      expect(c.httpsProxy, '127.0.0.1:8899');
      expect(c.exceptions, ['*.local', '169.254/16']);
    });

    test('https falls back to parsing even when http is off', () {
      final c = parse({
        'HTTPEnable': 0,
        'HTTPSEnable': 1,
        'HTTPSProxy': 'proxy.lan',
        'HTTPSPort': 8443,
      })!;
      expect(c.httpProxy, isNull);
      expect(c.httpsProxy, 'proxy.lan:8443');
    });

    test('disabled, incomplete and socks/pac-only setups are unusable', () {
      expect(parse({'HTTPEnable': 0, 'HTTPProxy': 'h', 'HTTPPort': 1}), isNull);
      expect(parse({'HTTPEnable': 1, 'HTTPPort': 7890}), isNull);
      expect(parse({'HTTPEnable': 1, 'HTTPProxy': 'h'}), isNull);
      expect(
        parse({
          'HTTPEnable': 1,
          'HTTPProxy': 'h',
          'HTTPPort': 0,
          'HTTPSEnable': 1,
          'HTTPSProxy': 'h',
          'HTTPSPort': 99999,
        }),
        isNull,
      );
      expect(parse({'SOCKSEnable': 1, 'SOCKSProxy': 'h', 'SOCKSPort': 1080}), isNull);
      expect(parse(null), isNull);
    });
  });

  group('systemProxyFindProxy', () {
    final config = SystemProxyConfig(
      httpProxy: '10.0.0.2:7890',
      httpsProxy: '10.0.0.2:7890',
      exceptions: ['*.local', '192.168.1.5', '*.internal'],
    );

    test('routes by scheme, https falls back to the http proxy', () {
      expect(
        systemProxyFindProxy(Uri.parse('https://gemini.google.com/x'), config),
        'PROXY 10.0.0.2:7890',
      );
      expect(systemProxyFindProxy(Uri.parse('http://example.com/'), config), 'PROXY 10.0.0.2:7890');
    });

    test('exception list goes direct', () {
      expect(systemProxyFindProxy(Uri.parse('https://nas.local/api'), config), 'DIRECT');
      expect(systemProxyFindProxy(Uri.parse('https://192.168.1.5/'), config), 'DIRECT');
      final bare = SystemProxyConfig(httpProxy: 'p:1', exceptions: ['google.com']);
      expect(systemProxyFindProxy(Uri.parse('https://google.com/'), bare), 'DIRECT');
      expect(systemProxyFindProxy(Uri.parse('https://api.google.com/'), config), isNot('DIRECT'));
    });

    test('no usable entry for the scheme stays direct', () {
      final httpsOnly = SystemProxyConfig(httpsProxy: 'p:1');
      expect(systemProxyFindProxy(Uri.parse('http://example.com/'), httpsOnly), 'DIRECT');
      expect(systemProxyFindProxy(Uri.parse('https://example.com/'), httpsOnly), 'PROXY p:1');
    });
  });
}
