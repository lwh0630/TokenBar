import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tokenbar_core/tokenbar_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/design/glass.dart';
import '../../app/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/codex_login_home.dart';

Future<({String home, String? email})?> showCodexSignIn(BuildContext context) =>
    showGlassDialog<({String home, String? email})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CodexSignInDialog(),
    );

class _CodexSignInDialog extends StatefulWidget {
  const _CodexSignInDialog();

  @override
  State<_CodexSignInDialog> createState() => _CodexSignInDialogState();
}

class _CodexSignInDialogState extends State<_CodexSignInDialog> {
  JsonRpcSession? _session;
  Uri? _url;
  String? _error;
  bool _browserFailed = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_signIn());
    });
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    ({String path, Future<void> Function() discard})? home;
    var keepHome = false;
    try {
      home = await createCodexLoginHome();
      if (!mounted) return;
      _session = await openCodexAppServer(home.path, officialAccount: true);
      if (!mounted) return;
      await signInToCodex(_session!, _openBrowser);
      final credentials = await readCodexCredentials(home.path);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (credentials == null || credentials.isApiKey) {
        setState(() => _error = l.codexSignInFailed);
        return;
      }
      keepHome = true;
      Navigator.pop(context, (home: home.path, email: credentials.email));
    } on CodexCliNotFound {
      if (mounted) setState(() => _error = l.codexCliMissing);
    } on TimeoutException {
      if (mounted) setState(() => _error = l.codexSignInTimedOut);
    } catch (_) {
      if (mounted) setState(() => _error = l.codexSignInFailed);
    } finally {
      final session = _session;
      _session = null;
      try {
        await session?.close();
      } finally {
        if (!keepHome && home != null) {
          try {
            await home.discard();
          } catch (_) {
            // A canceled sign-in must not affect another Codex home.
          }
        }
      }
    }
  }

  Future<void> _openBrowser(Uri url) async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    setState(() => _url = url);
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The same link can be opened in a different browser profile.
    }
    if (!opened && mounted) setState(() => _browserFailed = true);
  }

  Future<void> _copyLink() async {
    final url = _url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (mounted) setState(() => _copied = true);
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) unawaited(session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final error = _error;
    return GlassDialog(
      width: 480,
      title: Text(l.codexSignIn),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error == null) ...[const LinearProgressIndicator(), const SizedBox(height: Sp.x4)],
          Text(error ?? (_url == null ? l.codexSignInPreparing : l.codexSignInWaiting)),
          if (_browserFailed && error == null) ...[
            const SizedBox(height: Sp.x2),
            Text(l.codexSignInBrowserFailed),
          ],
        ],
      ),
      actions: [
        if (_url != null && error == null)
          GlassButton(
            kind: GlassButtonKind.secondary,
            onPressed: _copyLink,
            label: _copied ? l.codexSignInLinkCopied : l.codexSignInCopyLink,
          ),
        GlassButton(
          kind: GlassButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
          label: error == null ? l.cancel : MaterialLocalizations.of(context).closeButtonLabel,
        ),
      ],
    );
  }
}
