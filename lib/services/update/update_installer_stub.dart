import 'update_installer_types.dart';
import 'update_service.dart';

/// Web: there is nothing to install; the update dialog only opens the release page.
UpdateInstaller createUpdateInstaller() => _NoUpdateInstaller();

class _NoUpdateInstaller implements UpdateInstaller {
  @override
  bool canInstall(ReleaseInfo release) => false;

  @override
  Future<UpdateInstallOutcome> install(
    ReleaseInfo release, {
    void Function(UpdateInstallStage stage)? onStage,
    void Function(double? fraction)? onProgress,
    UpdateCancelToken? cancel,
  }) => Future.error(const UpdateInstallException('unsupported'));
}
