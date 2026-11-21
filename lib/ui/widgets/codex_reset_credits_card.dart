import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tokenbar_core/tokenbar_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/design/glass.dart';
import '../../app/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/codex_reset_credits_controller.dart';

class CodexResetCreditsCard extends StatefulWidget {
  const CodexResetCreditsCard({
    super.key,
    required this.controller,
    required this.accountLabel,
    required this.now,
    this.inline = false,
  });

  final CodexResetCreditsController controller;
  final String accountLabel;
  final DateTime now;
  final bool inline;

  @override
  State<CodexResetCreditsCard> createState() => _CodexResetCreditsCardState();
}

class _CodexResetCreditsCardState extends State<CodexResetCreditsCard> {
  bool _confirming = false;
  bool _browserFailed = false;

  Future<void> _confirm(CodexResetAccount account, CodexResetCredit credit) async {
    final controller = widget.controller;
    if (_confirming || controller.using) return;
    _confirming = true;
    final l = AppLocalizations.of(context);
    final accountName = account.email ?? widget.accountLabel;
    final expiry = _expiryLabel(l, credit);
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => GlassDialog(
        width: 440,
        title: Text(l.codexResetUseTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.codexResetUseBody(accountName)),
            const SizedBox(height: Sp.x2),
            Text(expiry),
          ],
        ),
        actions: [
          GlassButton(
            kind: GlassButtonKind.ghost,
            onPressed: () => Navigator.pop(dialogContext, false),
            label: l.cancel,
          ),
          GlassButton(
            kind: GlassButtonKind.primary,
            onPressed: () => Navigator.pop(dialogContext, true),
            label: l.codexResetUse,
          ),
        ],
      ),
    );
    _confirming = false;
    if (mounted && confirmed == true && identical(controller, widget.controller)) {
      await controller.use(account, credit);
    }
  }

  Future<void> _openUsageSettings() async {
    final uri = Uri.https('chatgpt.com', '/settings/usage');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Report the failure without including account details.
    }
    if (mounted) setState(() => _browserFailed = !opened);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _buildInventory(context),
  );

  Widget _buildInventory(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = widget.controller;
    final account = controller.account;
    final summary = account?.summary;
    final credits = summary?.credits ?? const <CodexResetCredit>[];
    final missingDetails = summary != null && summary.availableCount > credits.length;
    final status = _actionStatus(l, controller);
    if (summary == null && status == null) return const SizedBox.shrink();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(l.codexResetCredits, style: theme.textTheme.titleSmall)),
            if (summary != null) ...[
              const SizedBox(width: Sp.x2),
              Flexible(
                child: Text(l.codexResetCount(summary.availableCount), textAlign: TextAlign.end),
              ),
            ],
          ],
        ),
        for (final credit in credits)
          Padding(
            padding: const EdgeInsets.only(top: Sp.x2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.inline && credit.title != null) Text(credit.title!),
                      Text(_expiryLabel(l, credit), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.x2),
                GlassButton(
                  compact: widget.inline,
                  onPressed:
                      !controller.using &&
                          !controller.canRetry &&
                          account?.hasIdentity == true &&
                          summary!.availableCount > 0 &&
                          credit.isRedeemableAt(widget.now)
                      ? () => _confirm(account!, credit)
                      : null,
                  label: l.codexResetUse,
                ),
              ],
            ),
          ),
        if (missingDetails) ...[
          const SizedBox(height: Sp.x2),
          Text(l.codexResetDetailsMissing, style: theme.textTheme.bodySmall),
          if (!widget.inline)
            TextButton(onPressed: _openUsageSettings, child: Text(l.codexResetUsageSettings)),
        ],
        if (status != null) ...[
          const SizedBox(height: Sp.x2),
          Semantics(liveRegion: true, child: Text(status, style: theme.textTheme.bodySmall)),
        ],
        if (controller.canRetry) ...[
          const SizedBox(height: Sp.x2),
          GlassButton(
            onPressed: controller.using ? null : controller.retry,
            label: l.codexResetRetry,
          ),
        ],
      ],
    );
    if (widget.inline) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Sp.x2),
        child: Column(
          children: [
            Divider(height: Sp.x4, color: theme.colorScheme.outlineVariant),
            content,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x4),
      child: GlassCard(padding: const EdgeInsets.all(Sp.x4), child: content),
    );
  }

  String? _actionStatus(AppLocalizations l, CodexResetCreditsController controller) {
    if (controller.using) return l.codexResetUsing;
    if (_browserFailed) return l.codexResetBrowserFailed;
    final error = controller.actionError;
    if (error is CodexResetException) {
      return switch (error.failure) {
        CodexResetFailure.signedOut ||
        CodexResetFailure.unsupportedAccount => l.codexResetSignedOut,
        CodexResetFailure.accountChanged ||
        CodexResetFailure.identityUnavailable => l.codexResetAccountChanged,
        CodexResetFailure.creditUnavailable => l.codexResetCreditUnavailable,
        CodexResetFailure.redemptionUncertain => l.codexResetUncertain,
        _ => l.codexResetUnavailable,
      };
    }
    if (error != null) return l.codexResetUnavailable;
    return switch (controller.outcome) {
      CodexResetOutcome.reset || CodexResetOutcome.alreadyRedeemed => l.codexResetUsed,
      CodexResetOutcome.nothingToReset => l.codexResetNothingToReset,
      CodexResetOutcome.noCredit => l.codexResetCreditUnavailable,
      null => null,
    };
  }

  String _expiryLabel(AppLocalizations l, CodexResetCredit credit) {
    final expiry = credit.expiresAt;
    if (expiry == null) return l.codexResetNoExpiry;
    final date = DateFormat.yMMMd(l.localeName).add_jm().format(expiry.toLocal());
    final label = l.codexResetExpiry(date);
    return expiry.isAfter(widget.now) ? label : '$label · ${l.codexResetExpired}';
  }
}
