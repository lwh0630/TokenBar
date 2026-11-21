import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

import '../app/app_background.dart';
import '../app/design/glass.dart';
import '../app/design/tokens.dart';
import '../app/theme.dart';
import '../l10n/app_localizations.dart';
import '../state/app_controller.dart';
import 'format.dart';
import 'widgets/provider_badge.dart';
import 'widgets/usage_bar.dart';

/// The compact popover shown when the tray icon is clicked: every account at a
/// glance, with the two tightest quota windows each, plus quick actions.
class TrayPanel extends StatelessWidget {
  const TrayPanel({super.key});

  /// Corner radius of the panel window on Windows 11 (DWM's "round" preference).
  static const cornerRadius = 8.0;

  /// Window height that fits [snapshots] without a scrollbar (capped; the list
  /// scrolls beyond that). Mirrors the layout below, measured on Windows.
  static double heightFor(List<UsageSnapshot> snapshots) {
    const header = 63.0, footer = 52.0, listPadding = 24.0, border = 2.0, gap = 10.0;
    if (snapshots.isEmpty) return 220;
    var tiles = 0.0;
    for (final s in snapshots) {
      final windows = s.windows.take(2).length;
      final credits = s.credits.take(windows == 0 ? 2 : 1).length;
      var h = 50.0 + windows * 59 + credits * 22;
      if (_trayLoginEmail(s) != null) h += 16;
      if (s.hasError) h += (windows == 0 && credits == 0) ? 42 : 22;
      tiles += h;
    }
    tiles += gap * (snapshots.length - 1);
    return (header + listPadding + tiles + footer + border).clamp(160, 640).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<AppController>();
    final theme = Theme.of(context);
    final snapshots = c.traySnapshots;

    void move(int oldIndex, int newIndex) {
      if (oldIndex == newIndex) return;
      unawaited(
        c.moveTrayAccount(
          snapshots[oldIndex].accountId,
          snapshots[newIndex].accountId,
          after: oldIndex < newIndex,
        ),
      );
    }

    // On Windows 11 the window itself has rounded corners (set natively); draw the
    // same radius so the outline follows them instead of being cut off at the corners.
    return Material(
      type: MaterialType.transparency,
      child: ValueListenableBuilder<bool>(
        valueListenable: c.desktop.panelRounded,
        builder: (context, rounded, child) {
          final radius = rounded ? BorderRadius.circular(cornerRadius) : BorderRadius.zero;
          return ClipRRect(
            borderRadius: radius,
            child: AppBackground(
              animate: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: context.glass.hairline),
                ),
                child: child,
              ),
            ),
          );
        },
        child: Column(
          children: [
            _Header(controller: c),
            Expanded(
              child: snapshots.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          c.refreshing ? l.quotaLoading : l.noAccountsYetPanel,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ValueListenableBuilder(
                      valueListenable: c.now,
                      builder: (context, now, _) => ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: snapshots.length,
                        buildDefaultDragHandles: false,
                        onReorderItem: move,
                        proxyDecorator: (child, _, _) => child,
                        itemBuilder: (_, i) {
                          final snapshot = snapshots[i];
                          return Padding(
                            key: ValueKey(snapshot.accountId),
                            padding: EdgeInsets.only(bottom: i + 1 < snapshots.length ? 10 : 0),
                            child: _AccountTile(
                              snapshot: snapshot,
                              now: now,
                              reorderHandle: snapshots.length == 1
                                  ? null
                                  : _ReorderHandle(
                                      index: i,
                                      onUp: i > 0 ? () => move(i, i - 1) : null,
                                      onDown: i + 1 < snapshots.length
                                          ? () => move(i, i + 1)
                                          : null,
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            _Footer(controller: c),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TokenBar',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (c.lastRefresh != null)
                  ValueListenableBuilder(
                    valueListenable: c.now,
                    builder: (_, now, _) => Text(
                      l.updatedAgo(agoLabel(l, c.lastRefresh!, now)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Tooltip(
            message: l.refresh,
            child: c.refreshing
                ? const Padding(
                    padding: EdgeInsets.all(Sp.x2),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : GlassButton(
                    kind: GlassButtonKind.ghost,
                    compact: true,
                    onPressed: c.refresh,
                    icon: Icons.refresh,
                  ),
          ),
        ],
      ),
    );
  }
}

String? _trayLoginEmail(UsageSnapshot snapshot) {
  final email = snapshot.email?.trim();
  if (email == null ||
      email.isEmpty ||
      email.toLowerCase() == snapshot.accountLabel?.trim().toLowerCase()) {
    return null;
  }
  return email;
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.snapshot, required this.now, this.reorderHandle});

  final UsageSnapshot snapshot;
  final DateTime now;
  final Widget? reorderHandle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = snapshot;
    final provider = ProviderRegistry.instance.byId(s.providerId);
    final loginEmail = _trayLoginEmail(s);
    final muted = theme.colorScheme.onSurfaceVariant;
    final windows = s.windows.take(2).toList();

    return GlassCard(
      blur: 0, // already sits on the panel's glass
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      radius: Rd.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProviderBadge(providerId: s.providerId, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.accountLabel ?? provider?.displayName ?? s.providerId,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (loginEmail != null)
                      Tooltip(
                        message: loginEmail,
                        excludeFromSemantics: true,
                        child: Text(
                          loginEmail,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (s.plan != null) ...[
                const SizedBox(width: Sp.x2),
                Text(planLabel(s.plan), style: theme.textTheme.labelSmall?.copyWith(color: muted)),
              ],
              if (reorderHandle case final handle?) ...[const SizedBox(width: Sp.x1), handle],
            ],
          ),
          if (s.hasError && windows.isEmpty && s.credits.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          for (final w in windows) ...[
            const SizedBox(height: 10),
            _CompactWindow(window: w, now: now),
          ],
          for (final credit in s.credits.take(windows.isEmpty ? 2 : 1)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    creditsLabel(l, credit),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                Text(
                  creditsValue(l, credit),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          if (s.hasError && (windows.isNotEmpty || s.credits.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l.staleDataNotice(s.error!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.tertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReorderHandle extends StatelessWidget {
  const _ReorderHandle({required this.index, this.onUp, this.onDown});

  final int index;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Tooltip(
      message: l.dragToReorder,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowUp): ?onUp,
          const SingleActivator(LogicalKeyboardKey.arrowDown): ?onDown,
        },
        child: Focus(
          child: Builder(
            builder: (context) {
              final colors = Theme.of(context).colorScheme;
              final focused = Focus.of(context).hasPrimaryFocus;
              return ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: SizedBox(
                    width: Sp.x8,
                    height: Sp.x6 + Sp.x1,
                    child: Icon(
                      Icons.drag_indicator,
                      size: Sp.x5,
                      color: focused ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompactWindow extends StatelessWidget {
  const _CompactWindow({required this.window, required this.now});

  final RateWindow window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final remaining = window.remainingPercent;
    final reset = window.timeUntilReset(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                windowLabel(l, window),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
            Text(
              formatPercent(remaining),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: quotaColor(remaining, theme.brightness),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        UsageBar(remaining: remaining, height: 6),
        if (reset != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              resetsInLabel(l, reset),
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final desktop = controller.desktop;
    // Fixed height so TrayPanel.heightFor stays exact.
    return SizedBox(
      height: 51,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            GlassButton(
              kind: GlassButtonKind.ghost,
              onPressed: desktop.showMainWindow,
              icon: Icons.open_in_new,
              label: l.openTokenBar,
            ),
            const Spacer(),
            GlassButton(kind: GlassButtonKind.ghost, onPressed: desktop.quit, label: l.quit),
          ],
        ),
      ),
    );
  }
}
