import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app_info.dart';
import 'app_version.dart';
import 'release_assets.dart';

/// A published GitHub release.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.assets = const [],
  });

  /// e.g. `v1.2.0`.
  final String tag;
  final AppVersion version;

  /// Release notes (Markdown, shown as plain text); may be empty.
  final String notes;

  /// The release page on github.com (where the user downloads the build).
  final Uri pageUrl;

  /// The release's files (only trusted GitHub download URLs are kept).
  final List<ReleaseAsset> assets;
}

/// A failed update check. [code] is `network`, `rate_limit` or `bad_response`.
class UpdateException implements Exception {
  const UpdateException(this.code);
  final String code;

  @override
  String toString() => 'UpdateException($code)';
}

const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Only HTTPS pages on github.com may be opened from the update dialog.
bool isTrustedReleaseUrl(Uri uri) =>
    uri.scheme == 'https' && (uri.host == 'github.com' || uri.host.endsWith('.github.com'));

/// Looks up the newest published release of TokenBar on GitHub.
///
/// The only request is an anonymous `GET` of `releases/latest`; nothing but a
/// `User-Agent` with the app version (GitHub requires one) is sent. Drafts and
/// pre-releases are never offered.
class UpdateService {
  UpdateService({http.Client? client, Uri? latestUrl, this.timeout = const Duration(seconds: 15)})
    : _client = client ?? http.Client(),
      latestUrl =
          latestUrl ?? Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest');

  final http.Client _client;
  final Uri latestUrl;
  final Duration timeout;

  /// Parses GitHub's "release" JSON. `null` for drafts, pre-releases and
  /// anything without a valid `vX.Y.Z` tag.
  static ReleaseInfo? parseRelease(Object? json) {
    if (json is! Map) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    if (tag is! String) return null;
    final version = AppVersion.tryParse(tag);
    if (version == null || version.isPreRelease) return null;
    final html = json['html_url'];
    var page = html is String ? Uri.tryParse(html) : null;
    if (page == null || !isTrustedReleaseUrl(page)) page = Uri.parse('$kReleasesUrl/tag/$tag');
    final body = json['body'];
    return ReleaseInfo(
      tag: tag,
      version: version,
      notes: body is String ? body.trim() : '',
      pageUrl: page,
      assets: _parseAssets(json['assets']),
    );
  }

  static List<ReleaseAsset> _parseAssets(Object? json) {
    if (json is! List) return const [];
    final out = <ReleaseAsset>[];
    for (final a in json) {
      if (a is! Map) continue;
      final name = a['name'];
      final url = a['browser_download_url'];
      if (name is! String || url is! String) continue;
      final uri = Uri.tryParse(url);
      if (uri == null || !isTrustedAssetUrl(uri)) continue;
      final size = a['size'];
      out.add(ReleaseAsset(name: name, url: uri, size: size is int ? size : 0));
    }
    return out;
  }

  /// The latest published release, or `null` when the repository has none yet.
  Future<ReleaseInfo?> fetchLatest({required String currentVersion}) async {
    final http.Response res;
    try {
      res = await _client
          .get(
            latestUrl,
            headers: {
              'Accept': 'application/vnd.github+json',
              // Browsers refuse to set User-Agent; GitHub accepts the request anyway.
              if (!_isWeb) 'User-Agent': 'TokenBar/$currentVersion',
            },
          )
          .timeout(timeout);
    } on Object {
      throw const UpdateException('network');
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode == 403 || res.statusCode == 429) throw const UpdateException('rate_limit');
    if (res.statusCode != 200) throw const UpdateException('bad_response');
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map) throw const UpdateException('bad_response');
      return parseRelease(json);
    } on FormatException {
      throw const UpdateException('bad_response');
    }
  }

  void close() => _client.close();
}
