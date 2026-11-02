import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/design/glass.dart';
import '../l10n/app_localizations.dart';
import '../services/update/update_service.dart';
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

/// "A new version is available" dialog.
Future<void> showUpdateDialog(BuildContext context, UpdateController updates, ReleaseInfo release) {
  return showGlassDialog<void>(
    context: context,
    builder: (ctx) {
      final l = AppLocalizations.of(ctx);
      final theme = Theme.of(ctx);
      final notes = release.notes.isEmpty ? l.updateNoNotes : release.notes;
      return GlassDialog(
        width: 520,
        title: Text(l.newVersionAvailable(release.tag)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.currentVersion(updates.currentVersion),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(child: SingleChildScrollView(child: SelectableText(notes))),
            ],
          ),
        ),
        actions: [
          GlassButton(
            kind: GlassButtonKind.ghost,
            onPressed: () {
              updates.skip(release);
              Navigator.pop(ctx);
            },
            label: l.skipThisVersion,
          ),
          GlassButton(
            kind: GlassButtonKind.ghost,
            onPressed: () => Navigator.pop(ctx),
            label: l.later,
          ),
          GlassButton(
            kind: GlassButtonKind.primary,
            onPressed: () {
              openReleasePage(release.pageUrl);
              Navigator.pop(ctx);
            },
            label: l.goToDownload,
          ),
        ],
      );
    },
  );
}
