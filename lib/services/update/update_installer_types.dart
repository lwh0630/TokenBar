import 'update_service.dart';

/// What the installer is busy with; drives the progress text of the update dialog.
enum UpdateInstallStage { downloading, verifying, installing }

/// How an install attempt ended (when it did not throw).
enum UpdateInstallKind {
  /// Windows: the installer is running on its own; the app must quit so it can replace the
  /// files, and the installer starts the new version afterwards.
  quitForInstaller,

  /// Android: the system installer screen is up; the user confirms there.
  handedToSystem,

  /// macOS / Linux: the file was downloaded, checked and opened (dmg) or revealed (tar.gz);
  /// the user finishes by hand.
  savedFile,
}

class UpdateInstallOutcome {
  const UpdateInstallOutcome(this.kind, {this.path});

  final UpdateInstallKind kind;

  /// Where the downloaded file is (for [UpdateInstallKind.savedFile]).
  final String? path;
}

/// A failed install. [code] is one of `unsupported`, `no_asset`, `network`, `checksum`,
/// `permission` (Android: installing from this app is not allowed yet), `launch` or `cancelled`.
class UpdateInstallException implements Exception {
  const UpdateInstallException(this.code);

  final String code;

  @override
  String toString() => 'UpdateInstallException($code)';
}

/// Lets the UI stop a download that is running.
class UpdateCancelToken {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Downloads the build of a [ReleaseInfo] for this device, verifies it against the release's
/// `SHA256SUMS.txt` and starts the platform's way of installing it.
abstract class UpdateInstaller {
  /// Whether [install] can be offered for [release] on this device. When it is false the UI
  /// falls back to opening the release page in the browser.
  bool canInstall(ReleaseInfo release);

  Future<UpdateInstallOutcome> install(
    ReleaseInfo release, {
    void Function(UpdateInstallStage stage)? onStage,

    /// 0..1 while downloading; `null` when the size is unknown.
    void Function(double? fraction)? onProgress,
    UpdateCancelToken? cancel,
  });
}
