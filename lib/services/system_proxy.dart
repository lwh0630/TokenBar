import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// dart:io's HttpClient only honors http_proxy/https_proxy environment
// variables (the default `findProxyFromEnvironment`), which a GUI-launched
// app does not have. Browsers and URLSession follow the macOS system proxy,
// so read that configuration through a method channel and route dart:io
// through it. See MainFlutterWindow.swift for the native side.

const _channel = MethodChannel('dev.tokenbar.app/system_proxy');
const _ttl = Duration(minutes: 10);

Future<http.Client?>? _clientFuture;
DateTime? _cachedAt;

/// A client that routes through the macOS system proxy, or null when none is
/// configured / usable (the caller then keeps dart:io's default behavior).
/// Re-checked at most every [_ttl] so toggling the system proxy takes effect
/// without an app restart.
Future<http.Client?> systemProxyClient() {
  final now = DateTime.now();
  if (_clientFuture == null || now.difference(_cachedAt!) >= _ttl) {
    _cachedAt = now;
    _clientFuture = _build();
  }
  return _clientFuture!;
}

Future<http.Client?> _build() async {
  if (!Platform.isMacOS) return null;
  // Environment variables already cover the proxy case; keep dart:io's
  // default lookup in that setup instead of overriding it.
  const envKeys = ['https_proxy', 'http_proxy', 'all_proxy'];
  if (envKeys.any((k) => (Platform.environment[k] ?? '').isNotEmpty)) return null;
  try {
    final raw = await _channel.invokeMethod<Object?>('get');
    final config = SystemProxyConfig.parse(raw is Map ? raw : null);
    if (config == null) return null;
    return IOClient(HttpClient()..findProxy = (url) => systemProxyFindProxy(url, config));
  } catch (_) {
    // Channel not implemented (tests, older bundle) — dart:io defaults apply.
    return null;
  }
}

/// Parsed macOS system proxy settings (the `CFNetworkCopySystemProxySettings`
/// dictionary keys).
class SystemProxyConfig {
  const SystemProxyConfig({this.httpProxy, this.httpsProxy, this.exceptions = const []});

  /// `host:port`, null when the scheme is disabled or incomplete.
  final String? httpProxy;
  final String? httpsProxy;
  final List<String> exceptions;

  /// dart:io's HttpClient speaks HTTP CONNECT only: a SOCKS-only or PAC-only
  /// setup is not usable and parses to null.
  static SystemProxyConfig? parse(Map<Object?, Object?>? raw) {
    if (raw == null) return null;
    String? proxy(String enableKey, String hostKey, String portKey) {
      final enabled = raw[enableKey];
      if (enabled is! num || enabled.toInt() != 1) return null;
      final host = raw[hostKey];
      if (host is! String || host.isEmpty) return null;
      final port = raw[portKey];
      final value = port is num ? port.toInt() : int.tryParse('$port');
      if (value == null || value <= 0 || value > 65535) return null;
      return '$host:$value';
    }

    final httpEntry = proxy('HTTPEnable', 'HTTPProxy', 'HTTPPort');
    final httpsEntry = proxy('HTTPSEnable', 'HTTPSProxy', 'HTTPSPort');
    if (httpEntry == null && httpsEntry == null) return null;
    final list = raw['ExceptionsList'];
    return SystemProxyConfig(
      httpProxy: httpEntry,
      httpsProxy: httpsEntry,
      exceptions: [
        if (list is List<Object?>)
          for (final e in list)
            if (e is String) e,
      ],
    );
  }
}

/// dart:io `findProxy` callback: match the URL scheme to the proxy entries
/// and keep exception-listed hosts direct.
String systemProxyFindProxy(Uri url, SystemProxyConfig config) {
  for (final pattern in config.exceptions) {
    if (exceptionMatches(pattern, url.host)) return 'DIRECT';
  }
  final proxy = url.scheme == 'https' ? (config.httpsProxy ?? config.httpProxy) : config.httpProxy;
  return proxy == null ? 'DIRECT' : 'PROXY $proxy';
}

bool exceptionMatches(String pattern, String host) {
  final p = pattern.trim();
  if (p == '*') return true;
  if (p.startsWith('*.')) return host == p.substring(2) || host.endsWith(p.substring(1));
  return host == p;
}
