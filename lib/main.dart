import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app/app_shell.dart';
import 'app/app_background.dart';
import 'app/design/glass.dart' show GlassResizeTracker;
import 'app/semantics_guard.dart';
import 'app/theme.dart';
import 'demo/demo_data.dart';
import 'l10n/app_locale.dart';
import 'l10n/app_localizations.dart';
import 'services/desktop.dart';
import 'services/history_store.dart';
import 'services/home_widget_bridge.dart';
import 'services/notifier.dart';
import 'services/persistence.dart';
import 'state/app_controller.dart';
import 'state/settings.dart';
import 'state/update_controller.dart';
import 'ui/tray_panel.dart';
import 'ui/window_chrome.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final demoData = kDemoMode ? DemoData(DateTime.now()) : null;
  final persistence = demoData == null ? await Persistence.open() : await Persistence.openDemo();
  final settings = demoData == null
      ? await persistence.loadSettings()
      : (await persistence.loadSettings()).copyWith(language: demoLanguage);
  final desktop = DesktopIntegration();
  final notifier = Notifier();
  final homeWidget = HomeWidgetBridge();
  // Used for the tray menu and the first notification setup; later changes
  // reach the services through the controller.
  final l10n = lookupAppLocalizations(
    resolveAppLocale(settings.language, WidgetsBinding.instance.platformDispatcher.locales),
  );

  final controller = AppController(
    persistence: persistence,
    historyStore: demoData == null
        ? await HistoryStore.open()
        : HistoryStore.demo(demoData.history),
    desktop: desktop,
    notifier: notifier,
    homeWidget: homeWidget,
  );

  await desktop.init(
    onRefresh: controller.refresh,
    minimizeToTray: settings.minimizeToTray,
    hideDockIcon: settings.hideDockIcon,
    l10n: l10n,
    trayAccountId: settings.trayAccountId,
    onSelectTrayAccount: (id) =>
        controller.updateSettings(controller.settings.copyWith(trayAccountId: id)),
  );
  await notifier.init(l10n);
  await homeWidget.init();
  if (demoData == null) {
    await controller.init();
  } else {
    controller.initDemo(demoData);
  }

  final updates = UpdateController(
    readSettings: () => controller.settings,
    saveSettings: controller.updateSettings,
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: updates),
      ],
      child: const TokenBarApp(),
    ),
  );
  unawaited(updates.init());
  if (controller.settings.notificationsEnabled) unawaited(notifier.requestPermission());
  // `token_bar.exe --panel` opens straight into the tray panel (handy for testing).
  if (args.contains('--panel') || const bool.fromEnvironment('TOKENBAR_PANEL')) {
    unawaited(desktop.showPanel());
  }
}

class TokenBarApp extends StatefulWidget {
  const TokenBarApp({super.key});

  @override
  State<TokenBarApp> createState() => _TokenBarAppState();
}

class _TokenBarAppState extends State<TokenBarApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // With the "System" language, the UI follows the device language live.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final language = context.select<AppController, AppLanguage>((c) => c.settings.language);
    final themeMode = context.select<AppController, ThemeMode>((c) => c.settings.themeMode);
    final desktop = context.read<AppController>().desktop;
    return MaterialApp(
      title: 'TokenBar',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const GlassScrollBehavior(),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Always set (also for English): the locale makes the engine pick the
      // right glyph variants for Han text, and AppTheme adds the CJK fallback.
      locale: resolveAppLocale(language, WidgetsBinding.instance.platformDispatcher.locales),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      // The same window doubles as the tray panel. The main UI (navigator, pages, background)
      // is only mounted while the full window is on screen: a window hidden to the tray, or
      // showing the small panel, must not keep a whole widget tree and its GPU layers alive.
      builder: (context, child) => SemanticsGuard(
        child: GlassResizeTracker(
          child: AnimatedBuilder(
            animation: Listenable.merge([desktop.panelMode, desktop.uiSuspended]),
            builder: (context, _) {
              final panel = desktop.panelMode.value;
              return Stack(
                children: [
                  if (!panel && !desktop.uiSuspended.value)
                    // Pages are transparent: the ambient glow sits under the Navigator.
                    AppBackground(
                      child: WindowChrome(
                        desktop: desktop,
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  // The panel has no Overlay of its own; tooltips (and anything else that
                  // floats) need one.
                  if (panel)
                    Positioned.fill(
                      child: Overlay(
                        initialEntries: [OverlayEntry(builder: (_) => const TrayPanel())],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
