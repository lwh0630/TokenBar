import 'package:flutter/material.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

import '../../app/design/glass.dart';
import '../../app/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../format.dart';
import 'provider_badge.dart';
import 'window_row.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.snapshot, required this.now, this.onTap});

  final UsageSnapshot snapshot;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = snapshot;
    final provider = ProviderRegistry.instance.byId(s.providerId);
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.accountLabel ?? provider?.displayName ?? s.providerId,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (s.plan != null) ...[
                          const SizedBox(width: 8),
                          GlassChip(planLabel(s.plan)),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final w in s.windows) ...[
            WindowRow(window: w, now: now),
            const SizedBox(height: 12),
          ],
          for (final c in s.credits) _CreditsRow(credits: c),
          if (s.hasError) _ErrorBox(error: s.error!, hint: s.errorHint, stale: s.hasData),
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
