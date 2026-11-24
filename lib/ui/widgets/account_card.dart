import 'package:flutter/material.dart';
import 'package:tokenbar_core/tokenbar_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/design/glass.dart';
import '../../app/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/codex_reset_credits_controller.dart';
import '../format.dart';
import '../provider_links.dart';
import 'codex_reset_credits_card.dart';
import 'provider_badge.dart';
import 'window_row.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.snapshot,
    required this.now,
    this.account,
    this.onTap,
    this.resetCredits,
  });

  final UsageSnapshot snapshot;
  final DateTime now;
  final AccountConfig? account;
  final VoidCallback? onTap;
  final CodexResetCreditsController? resetCredits;

  Future<void> _openWebsite(BuildContext context, Uri url) async {
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } on Object {
      // The platform can throw if it cannot hand the URL to a browser.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).openProviderWebsiteFailed)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = snapshot;
    final providerName = ProviderRegistry.instance.byId(s.providerId)?.displayName ?? s.providerId;
    final website = providerOfficialUrl(s, account: account);
    final projectLink = providerLinkIsProject(s.providerId);
    final muted = theme.colorScheme.onSurfaceVariant;
    final subtitle = [
      s.email,
      if (s.origin != null) l.fromDevice(s.origin!),
    ].whereType<String>().join(' · ');

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(Sp.x4 + 2, Sp.x4, Sp.x4 + 2, Sp.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProviderBadge(providerId: s.providerId),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Sp.x2,
                      runSpacing: Sp.x1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          s.accountLabel ?? providerName,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (s.plan != null) GlassChip(planLabel(s.plan)),
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (website != null) ...[
                const SizedBox(width: Sp.x1),
                Tooltip(
                  message: projectLink
                      ? l.openProviderWebsite(providerName)
                      : l.openProviderAccountOverview(providerName),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      textStyle: theme.textTheme.labelLarge,
                      minimumSize: const Size(72, 30),
                      padding: const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x1),
                      shape: const StadiumBorder(),
                      iconSize: Sp.x3 + 2,
                      tapTargetSize: MaterialTapTargetSize.padded,
                      visualDensity: VisualDensity.standard,
                      animationDuration: Motion.of(context, Motion.fast),
                    ),
                    icon: const Icon(Icons.north_east_rounded),
                    iconAlignment: IconAlignment.end,
                    label: Text(projectLink ? l.providerProjectLink : l.providerAccountLink),
                    onPressed: () => _openWebsite(context, website),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          for (final w in s.windows) ...[
            WindowRow(window: w, now: now),
            const SizedBox(height: 12),
          ],
          for (final c in s.credits) _CreditsRow(credits: c),
          if (s.hasError) _ErrorBox(error: s.error!, hint: s.errorHint, stale: s.hasData),
          if (resetCredits case final controller?)
            CodexResetCreditsCard(
              inline: true,
              controller: controller,
              accountLabel: s.accountLabel ?? providerName,
              now: now,
            ),
          const SizedBox(height: 4),
          Text(
            [
              l.updatedAgo(agoLabel(l, s.fetchedAt, now)),
              if (s.source != null) sourceLabel(l, s.source),
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(color: muted.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

class _CreditsRow extends StatelessWidget {
  const _CreditsRow({required this.credits});

  final Credits credits;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final percent = credits.usedPercent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              creditsLabel(l, credits),
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              creditsValue(l, credits) + (percent == null ? '' : '  (${formatPercent(percent)})'),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error, this.hint, required this.stale});

  final String error;
  final String? hint;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = stale ? theme.colorScheme.tertiary : theme.colorScheme.error;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(stale ? Icons.history_toggle_off : Icons.error_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stale ? l.staleDataNotice(error) : error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hint != null) SelectableText(hint!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
