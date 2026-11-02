import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tokenbar_core/icon.dart';
import 'package:tokenbar_core/tokenbar_core.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../ui/format.dart';
import '../ui/tray_panel.dart';

/// System tray + window behaviour on Windows / macOS / Linux.
class DesktopIntegration with TrayListener, WindowListener {
  bool get supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  void Function()? _onRefresh;
  void Function(String accountId)? _onSelectTrayAccount;

  /// Account the tray icon follows; empty = the most constrained one.
  String _trayAccountId = '';
  List<UsageSnapshot> _lastSnapshots = const [];
  AppLocalizations? _l10n;
  bool _minimizeToTray = true;
  bool _trayReady = false;
  bool _quitting = false;
  String? _lastIconKey;
  int _iconGeneration = 0;

  /// True while the single window is acting as the small tray panel
  /// (frameless, always on top, anchored to the tray icon).
  final ValueNotifier<bool> panelMode = ValueNotifier(false);

  static const panelWidth = 392.0;

  /// Height of the panel for the current content; refreshed by [update].
  double _panelHeight = 280;
  Offset? _anchor;
  static const _mainSize = Size(1080, 760);
  static const _mainMinSize = Size(380, 520);

  Rect? _mainBounds;
  bool _panelBusy = false;
  DateTime _panelHiddenAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init({
    required void Function() onRefresh,
    required bool minimizeToTray,
    required AppLocalizations l10n,
    void Function(String accountId)? onSelectTrayAccount,
    String trayAccountId = '',
  }) async {
    if (!supported) return;
    _onRefresh = onRefresh;
    _onSelectTrayAccount = onSelectTrayAccount;
    _trayAccountId = trayAccountId;
    _l10n = l10n;
    _minimizeToTray = minimizeToTray;

    // A second launch (Windows) or a Dock-icon reopen (macOS) asks the running
    // instance to come forward; the native side calls this channel.
    _instanceChannel.setMethodCallHandler((call) async {
      if (call.method == 'activate' && !_quitting) await showMainWindow();
      return null;
    });

    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: _mainSize,
      minimumSize: _mainMinSize,
      center: true,
      title: 'TokenBar',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    try {
      trayManager.addListener(this);
      await _setIcon(null, null, false);
      await trayManager.setToolTip('TokenBar');
      await _setMenu(l10n, const []);
      _trayReady = true;
    } catch (e) {
      // Some Linux desktops have no tray; the window still works.
      debugPrint('tray unavailable: $e');
    }

    try {
      launchAtStartup.setup(
        appName: 'TokenBar',
        appPath: Platform.resolvedExecutable,
        packageName: 'dev.tokenbar.app',
      );
    } catch (e) {
      debugPrint('launch at startup unavailable: $e');
    }
  }

  Future<void> update(List<UsageSnapshot> snapshots, AppLocalizations l10n) async {
    if (!supported || !_trayReady) return;
    _lastSnapshots = snapshots;
    _l10n = l10n;
    final height = TrayPanel.heightFor(snapshots);
    if (height != _panelHeight) {
      _panelHeight = height;
      if (panelMode.value && !_panelBusy && _anchor != null && await windowManager.isVisible()) {
        await _layoutPanel();
      }
    }
    final withData = snapshots.where((s) => s.windows.isNotEmpty).toList();
    // The icon follows the account the user picked; "auto" (or a picked account
    // that has no data right now) falls back to the most constrained one.
    UsageSnapshot? focus;
    if (_trayAccountId.isNotEmpty) {
      for (final s in withData) {
        if (s.accountId == _trayAccountId) focus = s;
      }
    }
    if (focus == null) {
      for (final s in withData) {
        final t = s.tightestWindow!;
        if (focus == null || t.remainingPercent < focus.tightestWindow!.remainingPercent) {
          focus = s;
        }
      }
    }
    final top = focus?.session?.remainingPercent ?? focus?.tightestWindow?.remainingPercent;
    final bottom = focus?.weekly?.remainingPercent;
    final hasError = snapshots.any((s) => s.hasError);
    await _setIcon(top, bottom, hasError);

    final now = DateTime.now();
    final lines = <String>[];
    for (final s in snapshots) {
      final name = s.accountLabel ?? s.providerId;
      if (s.windows.isEmpty) {
        lines.add('$name: ${s.error ?? l10n.noData}');
        continue;
      }
      final parts = s.windows.take(2).map((w) {
        final reset = w.timeUntilReset(now);
        return '${windowLabel(l10n, w)} ${formatPercent(w.remainingPercent)}'
            '${reset == null ? '' : ' (${countdownLabel(l10n, reset)})'}';
      });
      lines.add('$name: ${parts.join(' · ')}');
    }
    // Windows caps tooltips at 128 chars.
    var tooltip = ['TokenBar', ...lines].join('\n');
    if (Platform.isWindows && tooltip.length > 127) tooltip = '${tooltip.substring(0, 126)}…';
    await trayManager.setToolTip(tooltip);
    if (Platform.isMacOS) {
      await trayManager.setTitle(
        focus == null ? '' : formatPercent(focus.tightestWindow!.remainingPercent),
      );
    }
    await _setMenu(l10n, lines, snapshots);
  }

  /// Settings page / tray menu changed the account the tray icon follows.
  Future<void> setTrayAccount(String accountId) async {
    if (_trayAccountId == accountId) return;
    _trayAccountId = accountId;
    final l10n = _l10n;
    if (l10n != null) await update(_lastSnapshots, l10n);
  }

  Future<void> _setIcon(double? top, double? bottom, bool error) async {
    final key = '${top?.round()}|${bottom?.round()}|$error';
    if (key == _lastIconKey) return;
    _lastIconKey = key;
    if (Platform.isMacOS) {
      await _setMacIcon(top, bottom, error);
      return;
    }
    final png = TrayIconRenderer.renderPng(top: top, bottom: bottom, error: error);
    final dir = await getTemporaryDirectory();
    // A fresh file name per change: some platforms cache icons by path.
    final gen = _iconGeneration++;
    final ext = Platform.isWindows ? 'ico' : 'png';
    final file = File('${dir.path}${Platform.pathSeparator}tokenbar_tray_$gen.$ext');
    await file.writeAsBytes(Platform.isWindows ? TrayIconRenderer.wrapIco(png) : png);
    await trayManager.setIcon(file.path);
    if (gen > 0) {
      final old = File('${dir.path}${Platform.pathSeparator}tokenbar_tray_${gen - 1}.$ext');
      if (await old.exists()) await old.delete().catchError((_) => old);
    }
  }

  /// tray_manager's macOS `setIcon` reads the icon with `rootBundle.load`, so it
  /// only accepts assets bundled in the app and throws for the generated icon
  /// (which made the whole tray unavailable on macOS). The native side only needs
  /// the PNG bytes as base64, so talk to the plugin's channel directly.
  Future<void> _setMacIcon(double? top, double? bottom, bool error) async {
    // Drawn at 64 px and shown at 18 pt, so it stays sharp on Retina menu bars.
    final png = TrayIconRenderer.renderPng(top: top, bottom: bottom, error: error, size: 64);
    await _trayChannel.invokeMethod<void>('setIcon', <String, Object>{
      'id': 'tokenbar-tray',
      'iconPath': '',
      'base64Icon': base64Encode(png),
      'isTemplate': false, // keep the colours; a template icon would be monochrome
      'iconPosition': 'left',
      'iconSize': 18,
    });
  }

  static const _trayChannel = MethodChannel('tray_manager');

  /// Native -> Dart: "another launch wants the window" (see `windows/runner`
  /// and `macos/Runner/AppDelegate.swift`).
  static const _instanceChannel = MethodChannel('tokenbar/instance');

  /// Menu keys of the "show in tray" choices: `tray:` (auto) or `tray:<accountId>`.
  static const _trayKeyPrefix = 'tray:';

  Future<void> _setMenu(
    AppLocalizations l10n,
    List<String> lines, [
    List<UsageSnapshot> snapshots = const [],
  ]) => trayManager.setContextMenu(
    Menu(
      items: [
        for (final line in lines) MenuItem(label: line, disabled: true),
        if (lines.isNotEmpty) MenuItem.separator(),
        if (snapshots.isNotEmpty) ...[
          MenuItem.submenu(
            label: l10n.trayDisplay,
            submenu: Menu(
              items: [
                MenuItem.checkbox(
                  key: _trayKeyPrefix,
                  label: l10n.trayDisplayAuto,
                  checked: !snapshots.any((s) => s.accountId == _trayAccountId),
                ),
                MenuItem.separator(),
                for (final s in snapshots)
                  MenuItem.checkbox(
                    key: '$_trayKeyPrefix${s.accountId}',
                    label: s.accountLabel ?? s.providerId,
                    checked: s.accountId == _trayAccountId,
                  ),
              ],
            ),
          ),
          MenuItem.separator(),
        ],
        MenuItem(key: 'show', label: l10n.openTokenBar),
        MenuItem(key: 'refresh', label: l10n.refreshNow),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: l10n.quit),
      ],
    ),
  );

  Future<void> setMinimizeToTray(bool value) async => _minimizeToTray = value;

  Future<void> setLaunchAtStartup(bool value) async {
    if (!supported) return;
    try {
      value ? await launchAtStartup.enable() : await launchAtStartup.disable();
    } catch (e) {
      debugPrint('launch at startup failed: $e');
    }
  }

  Future<void> showWindow() async {
    if (!supported) return;
    await showMainWindow();
  }

  /// Leaves panel mode (if needed) and brings the full window forward.
  Future<void> showMainWindow() async {
    if (!supported) return;
    _panelBusy = true;
    try {
      if (panelMode.value) {
        panelMode.value = false;
        await windowManager.hide();
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setSkipTaskbar(false);
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setResizable(true);
        await windowManager.setMinimumSize(_mainMinSize);
        final b = _mainBounds;
        if (b != null) {
          await windowManager.setBounds(b);
        } else {
          await windowManager.setSize(_mainSize);
          await windowManager.center();
        }
      }
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } finally {
      _panelBusy = false;
    }
  }

  /// Tray icon click: toggle the panel (or focus the main window if it is open).
  Future<void> _onTrayClick() async {
    if (_panelBusy) return;
    final visible = await windowManager.isVisible();
    if (visible && !panelMode.value) {
      await showMainWindow();
      return;
    }
    if (visible && panelMode.value) {
      await hidePanel();
      return;
    }
    // Clicking the tray icon blurs (and hides) the panel just before this
    // handler runs; ignore that click so the panel does not instantly reopen.
    if (DateTime.now().difference(_panelHiddenAt) < const Duration(milliseconds: 350)) return;
    await showPanel();
  }

  Future<void> showPanel() async {
    if (!supported || !_trayReady) return;
    _panelBusy = true;
    try {
      if (!panelMode.value) {
        _mainBounds = await windowManager.getBounds();
        panelMode.value = true;
        await windowManager.setMinimumSize(const Size(panelWidth, 120));
        await windowManager.setAsFrameless();
        await windowManager.setResizable(false);
        await windowManager.setSkipTaskbar(true);
        await windowManager.setAlwaysOnTop(true);
      }
      _anchor = await screenRetriever.getCursorScreenPoint();
      await _layoutPanel();
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('show panel failed: $e');
    } finally {
      _panelBusy = false;
    }
  }

  Future<void> hidePanel() async {
    _panelHiddenAt = DateTime.now();
    await windowManager.hide();
  }

  /// Top-left corner for the panel: centred on the cursor (which is over the
  /// tray icon), above a bottom taskbar or below a top menu bar, kept on screen.
  Future<void> _layoutPanel() async {
    final origin = await _panelOrigin(_anchor!);
    await windowManager.setBounds(origin & Size(panelWidth, _panelHeight));
  }

  Future<Offset> _panelOrigin(Offset cursor) async {
    const margin = 8.0;
    final displays = await screenRetriever.getAllDisplays();
    Rect area = Rect.fromLTWH(0, 0, 1920, 1080);
    for (final d in displays) {
      final pos = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      final r = pos & size;
      if (r.inflate(80).contains(cursor)) {
        area = r;
        break;
      }
      if (d == displays.first) area = r;
    }
    final x = (cursor.dx - panelWidth / 2).clamp(
      area.left + margin,
      area.right - panelWidth - margin,
    );
    _panelHeight = _panelHeight.clamp(120, area.height - margin * 2).toDouble();
    final height = _panelHeight;
    final below = cursor.dy < area.center.dy;
    final y = below ? area.top + margin : area.bottom - height - margin;
    return Offset(x.toDouble(), y);
  }

  Future<void> quit() => _quit();

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    // Hide first: tearing the engine down takes a moment, and a visible window
    // that no longer repaints looks like a hang. Each step is bounded so a
    // misbehaving plugin cannot block the exit.
    const limit = Duration(seconds: 2);
    try {
      await windowManager.hide().timeout(limit);
    } catch (e) {
      debugPrint('hide on quit failed: $e');
    }
    if (_trayReady) {
      try {
        await trayManager.destroy().timeout(limit);
      } catch (e) {
        debugPrint('tray destroy failed: $e');
      }
    }
    try {
      await windowManager.setPreventClose(false).timeout(limit);
    } catch (e) {
      debugPrint('setPreventClose failed: $e');
    }
    await windowManager.destroy();
  }

  @override
  void onTrayIconMouseDown() => _onTrayClick();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key != null && key.startsWith(_trayKeyPrefix)) {
      _onSelectTrayAccount?.call(key.substring(_trayKeyPrefix.length));
      return;
    }
    switch (key) {
      case 'show':
        showWindow();
      case 'refresh':
        _onRefresh?.call();
      case 'quit':
        _quit();
    }
  }

  @override
  void onWindowBlur() {
    if (panelMode.value && !_panelBusy) hidePanel();
  }

  @override
  void onWindowClose() async {
    if (_quitting) return;
    if (_minimizeToTray && _trayReady) {
      await windowManager.hide();
    } else {
      await _quit();
    }
  }
}
