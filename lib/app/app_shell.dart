import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_controller.dart';
import '../state/update_controller.dart';
import '../ui/pages/accounts_page.dart';
import '../ui/pages/dashboard_page.dart';
import '../ui/pages/settings_page.dart';
import '../ui/update_dialog.dart';
import 'design/glass.dart';
import 'design/tokens.dart';

typedef _Destination = (IconData outlined, IconData filled, String label);

/// A floating glass bottom bar on phones, a glass sidebar on wide screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  UpdateController? _updates;

  @override
  void initState() {
    super.initState();
    _updates = context.read<UpdateController>()..addListener(_promptForUpdate);
    // The launch-time check may already have finished.
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptForUpdate());
  }

  @override
  void dispose() {
    _updates?.removeListener(_promptForUpdate);
    super.dispose();
  }

  void _promptForUpdate() {
    final updates = _updates;
    if (updates == null || !mounted) return;
    final release = updates.takePrompt();
    if (release != null) showUpdateDialog(context, updates, release);
  }

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final List<_Destination> destinations = [
      (Icons.speed_outlined, Icons.speed, l.navQuota),
      (Icons.people_outline, Icons.people, l.navAccounts),
      (Icons.settings_outlined, Icons.settings, l.navSettings),
    ];
    final pages = [
      DashboardPage(onOpenSettings: () => _go(2), onOpenAccounts: () => _go(1)),
      const AccountsPage(),
      const SettingsPage(),
    ];
    final body = IndexedStack(index: _index, children: pages);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    if (wide) {
      // The unified title bar already shows the app icon and name.
      final showBrand = !context.read<AppController>().desktop.hasCustomChrome;
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              index: _index,
              onSelect: _go,
              destinations: destinations,
              showBrand: showBrand,
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: _BottomBar(index: _index, onSelect: _go, destinations: destinations),
    );
  }
}

const double _itemHeight = 40;
const double _itemGap = 4;

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.destinations,
    required this.showBrand,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<_Destination> destinations;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 212,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x1, 0, Sp.x3),
        child: GlassSurface(
          radius: Rd.lg,
          padding: const EdgeInsets.all(Sp.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBrand)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x4),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Rd.sm),
                        child: Image.asset(
                          'assets/icon/tokenbar.png',
                          width: 28,
                          height: 28,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      const SizedBox(width: Sp.x2 + 2),
                      Text(
                        'TokenBar',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              _SelectionStack(
                index: index,
                count: destinations.length,
                child: Column(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == destinations.length - 1 ? 0 : _itemGap,
                        ),
                        child: _SidebarItem(
                          icon: index == i ? destinations[i].$2 : destinations[i].$1,
                          label: destinations[i].$3,
                          selected: index == i,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays an animated "selection pill" behind a fixed-height list of items.
class _SelectionStack extends StatelessWidget {
  const _SelectionStack({required this.index, required this.count, required this.child});

  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final accent = Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: count * _itemHeight + (count - 1) * _itemGap,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: Motion.of(context, Motion.base),
            curve: Motion.curve,
            top: index * (_itemHeight + _itemGap),
            left: 0,
            right: 0,
            height: _itemHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Rd.md),
                color: accent.withValues(alpha: dark ? 0.24 : 0.14),
                border: Border.all(color: g.edgeLight.withValues(alpha: dark ? 0.12 : 0.55)),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hovered, pressed, focused) {
        final color = selected ? accent : onSurface.withValues(alpha: hovered ? 1 : 0.78);
        return AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          height: _itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.md),
            color: hovered && !selected ? onSurface.withValues(alpha: 0.06) : Colors.transparent,
            border: focused ? Border.all(color: accent.withValues(alpha: 0.7), width: 1.5) : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: Sp.x3),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect, required this.destinations});

  final int index;
  final ValueChanged<int> onSelect;
  final List<_Destination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final g = context.glass;
    final dark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x1, Sp.x4, Sp.x3),
        child: GlassSurface(
          radius: Rd.xl,
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            height: 52,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth / destinations.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: Motion.of(context, Motion.base),
                      curve: Motion.curve,
                      left: index * w,
                      top: 0,
                      bottom: 0,
                      width: w,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Rd.lg),
                          color: accent.withValues(alpha: dark ? 0.24 : 0.14),
                          border: Border.all(
                            color: g.edgeLight.withValues(alpha: dark ? 0.12 : 0.55),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          Expanded(
                            child: Pressable(
                              onTap: () => onSelect(i),
                              semanticLabel: destinations[i].$3,
                              builder: (context, hovered, pressed, focused) {
                                final selected = index == i;
                                final color = selected
                                    ? accent
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.7);
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      selected ? destinations[i].$2 : destinations[i].$1,
                                      size: 22,
                                      color: color,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      destinations[i].$3,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: color,
                                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
