import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'release_assets.dart';
import 'update_installer_types.dart';
import 'update_service.dart';

/// The real installer (every platform that has `dart:io`).
UpdateInstaller createUpdateInstaller() => IoUpdateInstaller();

/// Where this build runs, as far as the release files are concerned; `null` on iOS and
/// anything else that has no downloadable build.
UpdateTarget? detectUpdateTarget() {
  final abi = ffi.Abi.current();
  if (Platform.isWindows) {
    if (abi == ffi.Abi.windowsX64) return UpdateTarget.windowsX64;
    if (abi == ffi.Abi.windowsArm64) return UpdateTarget.windowsArm64;
  } else if (Platform.isAndroid) {
    if (abi == ffi.Abi.androidArm64) return UpdateTarget.androidArm64;
    if (abi == ffi.Abi.androidArm) return UpdateTarget.androidArm;
    if (abi == ffi.Abi.androidX64) return UpdateTarget.androidX64;
  } else if (Platform.isMacOS) {
    if (abi == ffi.Abi.macosArm64) return UpdateTarget.macosArm64;
    if (abi == ffi.Abi.macosX64) return UpdateTarget.macosX64;
  } else if (Platform.isLinux) {
    if (abi == ffi.Abi.linuxX64) return UpdateTarget.linuxX64;
    if (abi == ffi.Abi.linuxArm64) return UpdateTarget.linuxArm64;
  }
  return null;
}

/// Downloads the release file, checks its SHA-256 against the release's `SHA256SUMS.txt`,
/// then installs it the way each platform allows:
///
/// * Windows: runs the Inno Setup installer silently and asks the app to quit; the installer
///   replaces the files and starts the new version (only for installations made by that
///   installer, never for a loose build folder).
/// * Android: hands the APK to the system installer (the signature is checked by Android, which
///   refuses anything not signed with the key of the installed app).
/// * macOS / Linux: saves the file to Downloads and opens it (dmg) or its folder (tar.gz).
///
/// Credentials are never involved: only anonymous downloads from this repository's releases.
class IoUpdateInstaller implements UpdateInstaller {
  IoUpdateInstaller({
    http.Client? client,
    UpdateTarget? target,
    this._workDir,
    this._managedWindowsInstall,
    Future<void> Function(File installer)? startWindowsInstaller,
    Future<String> Function(String apkPath)? installApk,
    Future<void> Function(String path)? openPath,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _target = target ?? detectUpdateTarget(),
       _startWindowsInstaller = startWindowsInstaller ?? _launchWindowsInstaller,
       _installApk = installApk ?? _androidInstallApk,
       _openPath = openPath ?? _desktopOpen;

  final http.Client _client;
  final UpdateTarget? _target;
  final Directory? _workDir;
  final bool? _managedWindowsInstall;
  final Future<void> Function(File installer) _startWindowsInstaller;
  final Future<String> Function(String apkPath) _installApk;
  final Future<void> Function(String path) _openPath;

  /// Connection and per-chunk idle limit.
  final Duration timeout;

  static const _androidChannel = MethodChannel('tokenbar/installer');

  /// True when the running app sits in a folder created by the Inno Setup installer (it leaves
  /// `unins000.exe` next to the exe), so running the next installer really is an upgrade.
  static bool _isManagedWindowsInstall() {
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      return File('$dir${Platform.pathSeparator}unins000.exe').existsSync();
    } on Object {
      return false;
    }
  }

  @override
  bool canInstall(ReleaseInfo release) {
    final target = _target;
    if (target == null) return false;
    if (pickAsset(release.assets, target) == null) return false;
    if (pickChecksums(release.assets) == null) return false;
    if (target.isWindows && !(_managedWindowsInstall ?? _isManagedWindowsInstall())) return false;
    return true;
  }

  @override
  Future<UpdateInstallOutcome> install(
    ReleaseInfo release, {
    void Function(UpdateInstallStage stage)? onStage,
    void Function(double? fraction)? onProgress,
    UpdateCancelToken? cancel,
  }) async {
    final target = _target;
    if (target == null) throw const UpdateInstallException('unsupported');
    final asset = pickAsset(release.assets, target);
    final sums = pickChecksums(release.assets);
    if (asset == null || sums == null) throw const UpdateInstallException('no_asset');

    final dir = await _prepareDir(target);
    final file = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    try {
      onStage?.call(UpdateInstallStage.downloading);
      onProgress?.call(null);
      // The checksum list is tiny; fetch it first so a missing entry fails before the big download.
      final listed = expectedSha256(await _downloadText(sums.url), asset.name);
      if (listed == null) throw const UpdateInstallException('checksum');

      final actual = await _download(asset, file, onProgress: onProgress, cancel: cancel);
      onStage?.call(UpdateInstallStage.verifying);
      if (actual != listed) {
        await _delete(file);
        throw const UpdateInstallException('checksum');
      }
      if (cancel?.cancelled ?? false) throw const UpdateInstallException('cancelled');

      onStage?.call(UpdateInstallStage.installing);
      return await _launch(target, file);
    } on UpdateInstallException {
      rethrow;
    } on Object {
      throw const UpdateInstallException('network');
    }
  }

  Future<Directory> _prepareDir(UpdateTarget target) async {
    Directory dir;
    final custom = _workDir;
    if (custom != null) {
      dir = custom;
    } else if (!target.isWindows && !target.isAndroid) {
      // macOS / Linux: the user opens the file by hand, so it belongs in Downloads.
      dir = (await getDownloadsDirectory()) ?? await getTemporaryDirectory();
    } else {
      dir = Directory(
        '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
        'tokenbar-update',
      );
    }
    if (target.isWindows || target.isAndroid) {
      // Old downloads of earlier updates are garbage once a new one starts.
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } on Object {
          // A file still in use is not worth failing for.
        }
      }
    }
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _downloadText(Uri url) async {
    final res = await _send(url);
    final bytes = <int>[];
    await for (final chunk in res.stream.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > 1 << 20) throw const UpdateInstallException('checksum');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<http.StreamedResponse> _send(Uri url) async {
    final req = http.Request('GET', url)..headers['User-Agent'] = 'TokenBar-updater';
    final res = await _client.send(req).timeout(timeout);
    if (res.statusCode != 200) throw const UpdateInstallException('network');
    return res;
  }

  /// Streams [asset] into [dest] and returns the lower-case hex SHA-256 of what was written.
  Future<String> _download(
    ReleaseAsset asset,
    File dest, {
    void Function(double? fraction)? onProgress,
    UpdateCancelToken? cancel,
  }) async {
    final res = await _send(asset.url);
    final total = (res.contentLength ?? 0) > 0 ? res.contentLength! : asset.size;
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    final sink = dest.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream.timeout(timeout)) {
        if (cancel?.cancelled ?? false) throw const UpdateInstallException('cancelled');
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? (received / total).clamp(0.0, 1.0) : null);
      }
      hasher.close();
      await sink.flush();
      await sink.close();
    } on Object {
      hasher.close();
      try {
        await sink.close();
      } on Object {
        // Already failing; the original error is the one to report.
      }
      await _delete(dest);
      rethrow;
    }
    return digest.value.toString();
  }

  Future<void> _delete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on Object {
      // Best effort.
    }
  }

  Future<UpdateInstallOutcome> _launch(UpdateTarget target, File file) async {
    try {
      if (target.isWindows) {
        await _startWindowsInstaller(file);
        return const UpdateInstallOutcome(UpdateInstallKind.quitForInstaller);
      }
      if (target.isAndroid) {
        final result = await _installApk(file.path);
        if (result == 'needs_permission') throw const UpdateInstallException('permission');
        if (result != 'started') throw const UpdateInstallException('launch');
        return const UpdateInstallOutcome(UpdateInstallKind.handedToSystem);
      }
      // dmg: mounts and shows in Finder. tar.gz: show the folder it is in.
      await _openPath(
        target == UpdateTarget.linuxX64 || target == UpdateTarget.linuxArm64
            ? file.parent.path
            : file.path,
      );
      return UpdateInstallOutcome(UpdateInstallKind.savedFile, path: file.path);
    } on UpdateInstallException {
      rethrow;
    } on Object {
      throw const UpdateInstallException('launch');
    }
  }

  static Future<void> _launchWindowsInstaller(File installer) async {
    // /SILENT shows only a small progress window. `/relaunch=1` is read by tokenbar.iss, which then
    // starts the new version when it is done (the old process has quit by then).
    await Process.start(installer.path, const [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/relaunch=1',
    ], mode: ProcessStartMode.detached);
  }

  static Future<String> _androidInstallApk(String path) async {
    try {
      return await _androidChannel.invokeMethod<String>('installApk', path) ?? 'failed';
    } on MissingPluginException {
      return 'failed';
    }
  }

  static Future<void> _desktopOpen(String path) async {
    final command = Platform.isMacOS ? 'open' : 'xdg-open';
    final r = await Process.run(command, [path]);
    if (r.exitCode != 0) throw const UpdateInstallException('launch');
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
