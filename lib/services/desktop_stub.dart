import 'package:flutter/foundation.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

import '../l10n/app_localizations.dart';
import 'window_edge.dart';

/// Web build: no tray / window management.
class DesktopIntegration {
  bool get supported => false;

  final ValueNotifier<bool> panelMode = ValueNotifier(false);

  /// Whether the main UI is unmounted to save memory (hidden window); never on web.
  final ValueNotifier<bool> uiSuspended = ValueNotifier(false);

  /// Whether the tray panel window has rounded corners; never on web.
  final ValueNotifier<bool> panelRounded = ValueNotifier(false);

  /// True while the (custom-drawn) title bar is in use; never on web.
  bool get hasCustomChrome => false;

  /// True where TokenBar draws its own minimize / maximize / close buttons.
  bool get drawsWindowButtons => false;

  /// True where the window has no native resize border.
  bool get needsResizeEdges => false;

  final ValueNotifier<bool> maximized = ValueNotifier(false);

  /// Window focus; always true where there is no window management.
  final ValueNotifier<bool> focused = ValueNotifier(true);

  Future<void> startDragging() async {}

  Future<void> toggleMaximize() async {}

  Future<void> minimizeWindow() async {}

  Future<void> closeWindow() async {}

  Future<void> startResizing(WindowEdge edge) async {}

  Future<void> init({
    required void Function() onRefresh,
    required bool minimizeToTray,
    required AppLocalizations l10n,
    void Function(String accountId)? onSelectTrayAccount,
    String trayAccountId = '',
    bool hideDockIcon = false,
  }) async {}

  Future<void> update(List<UsageSnapshot> snapshots, AppLocalizations l10n) async {}

  Future<void> setTrayAccount(String accountId) async {}

  Future<void> setMinimizeToTray(bool value) async {}

  Future<void> setHideDockIcon(bool value) async {}

  Future<void> setLaunchAtStartup(bool value) async {}

  Future<void> showWindow() async {}

  Future<void> showMainWindow() async {}

  Future<void> showPanel() async {}

  Future<void> hidePanel() async {}

  Future<void> quit() async {}
}
