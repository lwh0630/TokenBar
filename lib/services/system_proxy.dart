import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// dart:io reads environment proxies. Desktop runners expose the current user's
// manual system proxy through this channel for apps launched from the GUI.
const _channel = MethodChannel('dev.tokenbar.app/system_proxy');
const _ttl = Duration(minutes: 10);
const _proxyEnvironmentKeys = {'http_proxy', 'https_proxy', 'all_proxy'};

Future<SystemProxyConfig?>? _configFuture;
DateTime? _cachedAt;

/// Each caller owns its client. Only the proxy configuration is cached.
Future<http.Client> createProviderClient() async {
  if (kIsWeb || (!Platform.isMacOS && !Platform.isWindows)) return http.Client();
  if (Platform.environment.entries.any(
    (entry) => _proxyEnvironmentKeys.contains(entry.key.toLowerCase()) && entry.value.isNotEmpty,
  )) {
    return http.Client();
  }
  final now = DateTime.now();
  if (_configFuture == null || now.difference(_cachedAt!) >= _ttl) {
    _cachedAt = now;
    _configFuture = _readConfig();
  }
  final config = await _configFuture;
  if (config == null) return http.Client();
  return IOClient(HttpClient()..findProxy = (url) => systemProxyFindProxy(url, config));
}

Future<SystemProxyConfig?> _readConfig() async {
  try {
    final raw = await _channel
        .invokeMapMethod<Object?, Object?>('get')
        .timeout(const Duration(seconds: 2));
    return Platform.isWindows ? SystemProxyConfig.parseWindows(raw) : SystemProxyConfig.parse(raw);
  } catch (_) {
    // Tests and older runners may lack the channel.
    return null;
  }
}

/// Parsed manual HTTP proxy configuration.
class SystemProxyConfig {
  const SystemProxyConfig({this.httpProxy, this.httpsProxy, this.exceptions = const []})
    : _windows = false;

  const SystemProxyConfig._windows({this.httpProxy, this.httpsProxy, required this.exceptions})
    : _windows = true;

  final bool _windows;

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

  /// WinHTTP exposes either a shared proxy or a list such as
  /// `http=proxy:80;https=proxy:8080`. Only HTTP proxies can carry CONNECT.
  static SystemProxyConfig? parseWindows(Map<Object?, Object?>? raw) {
    final proxy = raw?['proxy'];
    if (proxy is! String || proxy.trim().isEmpty) return null;
    String? shared;
    final byScheme = <String, String?>{};
    for (final entry in proxy.trim().split(RegExp(r'[;\s]+'))) {
      final separator = entry.indexOf('=');
      if (separator < 0) {
        shared ??= _httpProxyAddress(entry);
      } else {
        final scheme = entry.substring(0, separator).toLowerCase();
        if (scheme == 'http' || scheme == 'https') {
          byScheme[scheme] = _httpProxyAddress(entry.substring(separator + 1));
        }
      }
    }
    final httpProxy = byScheme.containsKey('http') ? byScheme['http'] : shared;
    final httpsProxy = byScheme.containsKey('https') ? byScheme['https'] : shared;
    if (httpProxy == null && httpsProxy == null) return null;
    final bypass = raw?['bypass'];
    return SystemProxyConfig._windows(
      httpProxy: httpProxy,
      httpsProxy: httpsProxy,
      exceptions: bypass is String ? bypass.split(RegExp(r'[;\s]+')) : const [],
    );
  }
}

String? _httpProxyAddress(String value) {
  if (value.isEmpty) return null;
  try {
    final uri = Uri.parse(value.contains('://') ? value : 'http://$value');
    if (uri.scheme != 'http' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return '$host:${uri.port}';
  } on FormatException {
    return null;
  }
}

/// dart:io `findProxy` callback: match the URL scheme to the proxy entries
/// and keep exception-listed hosts direct.
String systemProxyFindProxy(Uri url, SystemProxyConfig config) {
  final host = url.host.toLowerCase();
  if (config._windows) {
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        InternetAddress.tryParse(host)?.isLoopback == true) {
      return 'DIRECT';
    }
    for (final entry in config.exceptions) {
      final pattern = entry.toLowerCase();
      if (pattern == '<local>' && !host.contains('.') && !host.contains(':')) return 'DIRECT';
      if (pattern == host || (pattern.startsWith('*') && host.endsWith(pattern.substring(1)))) {
        return 'DIRECT';
      }
    }
  } else if (config.exceptions.any((pattern) => exceptionMatches(pattern, host))) {
    return 'DIRECT';
  }
  final proxy = url.scheme == 'https'
      ? config.httpsProxy ?? (config._windows ? null : config.httpProxy)
      : config.httpProxy;
  return proxy == null ? 'DIRECT' : 'PROXY $proxy';
}

bool exceptionMatches(String pattern, String host) {
  final p = pattern.trim();
  if (p == '*') return true;
  if (p.startsWith('*.')) return host == p.substring(2) || host.endsWith(p.substring(1));
  return host == p;
}
