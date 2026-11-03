import '../../app_info.dart';

/// One downloadable file of a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.size});

  final String name;
  final Uri url;

  /// Size in bytes as reported by GitHub (0 when unknown).
  final int size;
}

/// Only files of this repository's own releases, over HTTPS, may be downloaded by the updater
/// (GitHub then redirects to its CDN, which is fine; the *starting* URL is what is trusted).
bool isTrustedAssetUrl(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'github.com' &&
    uri.path.startsWith('/$kUpdateRepo/releases/download/');

/// A build flavour of TokenBar that has its own release file.
enum UpdateTarget {
  windowsX64('-windows-x64-setup.exe'),
  windowsArm64('-windows-arm64-setup.exe'),
  androidArm64('-android-arm64-v8a.apk'),
  androidArm('-android-armeabi-v7a.apk'),
  androidX64('-android-x86_64.apk'),
  macosArm64('-macos-arm64.dmg'),
  macosX64('-macos-x86_64.dmg'),
  linuxX64('-linux-x64.tar.gz'),
  linuxArm64('-linux-arm64.tar.gz');

  const UpdateTarget(this.suffix);

  /// Tail of the file name, e.g. `tokenbar-v1.2.0` + `-windows-x64-setup.exe`.
  final String suffix;

  bool get isWindows => this == windowsX64 || this == windowsArm64;
  bool get isAndroid => this == androidArm64 || this == androidArm || this == androidX64;
}

/// Name of the checksum list every release carries.
const String kChecksumAssetName = 'SHA256SUMS.txt';

/// The release file for [target], or `null` when the release has none for it.
ReleaseAsset? pickAsset(Iterable<ReleaseAsset> assets, UpdateTarget target) {
  for (final a in assets) {
    if (a.name.startsWith('tokenbar-') && a.name.endsWith(target.suffix)) return a;
  }
  return null;
}

/// The checksum list of a release, if it has one.
ReleaseAsset? pickChecksums(Iterable<ReleaseAsset> assets) {
  for (final a in assets) {
    if (a.name == kChecksumAssetName) return a;
  }
  return null;
}

final RegExp _sha256Line = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$');

/// Looks up [fileName] in a `sha256sum`-style list (`<hex>  <name>` per line) and returns the
/// lower-case hex digest, or `null` when it is not listed.
String? expectedSha256(String sums, String fileName) {
  for (final line in sums.split(RegExp(r'\r?\n'))) {
    final m = _sha256Line.firstMatch(line);
    if (m == null) continue;
    // `sha256sum` writes `./name` or a bare name; keep only the file name.
    final name = m.group(2)!.split(RegExp(r'[\\/]')).last;
    if (name == fileName) return m.group(1)!.toLowerCase();
  }
  return null;
}
