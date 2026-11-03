import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/design/glass.dart';
import '../l10n/app_localizations.dart';
import '../services/update/update_installer.dart';
import '../services/update/update_service.dart';
import '../state/app_controller.dart';
import '../state/update_controller.dart';

/// Opens a release page in the browser (github.com only).
Future<bool> openReleasePage(Uri url) async {
  if (!isTrustedReleaseUrl(url)) return false;
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// "A new version is available" dialog. Where the build can be installed from inside the app
/// (see [UpdateController.canInstall]) it offers "Update now"; everywhere else, and always as a
/// second choice, it opens the release page.
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateController updates,
  ReleaseInfo release,
) async {
  await showGlassDialog<void>(
    context: context,
    builder: (ctx) => _UpdateDialog(updates: updates, release: release),
  );
  // Closed (barrier tap / escape) while a download was running: stop it.
  updates.cancelInstall();
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.updates, required this.release});

  final UpdateController updates;
  final ReleaseInfo release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  /// Set when macOS / Linux saved the verified file and the user has to finish by hand.
  String? _savedPath;

  Future<void> _install() async {
    final outcome = await widget.updates.install();
    if (!mounted || outcome == null) return;
    switch (outcome.kind) {
      case UpdateInstallKind.quitForInstaller:
        // The installer is already running; it needs the app out of the way, then starts the new
        // version itself.
        final desktop = context.read<AppController>().desktop;
        Navigator.pop(context);
        await desktop.quit();
      case UpdateInstallKind.handedToSystem:
        Navigator.pop(context);
      case UpdateInstallKind.savedFile:
        setState(() => _savedPath = outcome.path);
    }
  }

  String _stageText(AppLocalizations l, UpdateController u) {
    switch (u.installStage) {
      case UpdateInstallStage.verifying:
        return l.updateVerifying;
      case UpdateInstallStage.installing:
        return l.updateInstalling;
      case UpdateInstallStage.downloading || null:
        final p = u.installProgress;
        return p == null ? l.updateDownloading : l.updateDownloadingPercent((p * 100).round());
    }
  }

  String? _errorText(AppLocalizations l, String? code) => switch (code) {
    null => null,
    'network' => l.updateFailedNetwork,
    'checksum' => l.updateFailedChecksum,
    'permission' => l.updateFailedPermission,
    _ => l.updateFailedLaunch,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final release = widget.release;
    return ListenableBuilder(
      listenable: widget.updates,
      builder: (context, _) {
        final updates = widget.updates;
        final notes = release.notes.isEmpty ? l.updateNoNotes : release.notes;
        final error = _errorText(l, updates.installErrorCode);
        final saved = _savedPath;
        final muted = theme.colorScheme.onSurfaceVariant;
        return GlassDialog(
          width: 520,
          title: Text(l.newVersionAvailable(release.tag)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.currentVersion(updates.currentVersion),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 12),
                Flexible(child: SingleChildScrollView(child: SelectableText(notes))),
                if (updates.installing) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: updates.installStage == UpdateInstallStage.downloading
                        ? updates.installProgress
                        : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 6),
                  Text(_stageText(l, updates), style: theme.textTheme.bodySmall),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                if (saved != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(l.updateSavedTo(saved), style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          actions: updates.installing
              ? [
                  GlassButton(
                    kind: GlassButtonKind.ghost,
                    onPressed: updates.cancelInstall,
                    label: l.cancel,
                  ),
                ]
              : saved != null
              ? [
                  GlassButton(
                    kind: GlassButtonKind.primary,
                    onPressed: () => Navigator.pop(context),
                    label: l.updateDone,
                  ),
                ]
              : [
                  GlassButton(
                    kind: GlassButtonKind.ghost,
                    onPressed: () {
                      updates.skip(release);
                      Navigator.pop(context);
                    },
                    label: l.skipThisVersion,
                  ),
                  GlassButton(
                    kind: GlassButtonKind.ghost,
                    onPressed: () => Navigator.pop(context),
                    label: l.later,
                  ),
                  if (updates.canInstall) ...[
                    GlassButton(
                      onPressed: () => openReleasePage(release.pageUrl),
                      label: l.openReleasePage,
                    ),
                    GlassButton(
                      kind: GlassButtonKind.primary,
                      onPressed: _install,
                      label: l.updateNow,
                    ),
                  ] else
                    GlassButton(
                      kind: GlassButtonKind.primary,
                      onPressed: () {
                        openReleasePage(release.pageUrl);
                        Navigator.pop(context);
                      },
                      label: l.goToDownload,
                    ),
                ],
        );
      },
    );
  }
}
