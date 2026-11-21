import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:token_bar/app/theme.dart';
import 'package:token_bar/demo/demo_data.dart';
import 'package:token_bar/l10n/app_localizations.dart';
import 'package:token_bar/services/desktop.dart';
import 'package:token_bar/services/history_store.dart';
import 'package:token_bar/services/home_widget_bridge.dart';
import 'package:token_bar/services/notifier.dart';
import 'package:token_bar/services/persistence.dart';
import 'package:token_bar/state/app_controller.dart';
import 'package:token_bar/ui/tray_panel.dart';

void main() {
  testWidgets('shows the login email and saves a direct drag in the tray', (tester) async {
    final demo = DemoData(DateTime(2026, 10, 24, 12));
    demo.accounts.removeWhere((a) => a.id != 'demo-codex' && a.id != 'demo-claude');
    final persistence = await Persistence.openDemo();
    AppController createController() => AppController(
      persistence: persistence,
      historyStore: HistoryStore.demo(demo.history),
      desktop: DesktopIntegration(),
      notifier: Notifier(),
      homeWidget: HomeWidgetBridge(),
    )..initDemo(demo);

    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> show(AppController controller) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: const Scaffold(body: TrayPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final primary = find.text('demo.user@example.com');
    final secondary = find.text('alex.demo@example.com');
    final controller = createController();
    try {
      await show(controller);
      expect(primary, findsOneWidget);
      expect(secondary, findsOneWidget);
      expect(tester.getCenter(primary).dy, lessThan(tester.getCenter(secondary).dy));
      final handle = find.byIcon(Icons.drag_indicator).last;
      final start = tester.getCenter(handle);
      final end = tester.getCenter(primary).dy + 20;
      final drag = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await drag.moveBy(const Offset(0, -20));
      await tester.pump();
      await drag.moveTo(Offset(start.dx, end));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.getCenter(secondary).dy, lessThan(tester.getCenter(primary).dy));
      expect(controller.snapshots.first.accountId, 'demo-claude');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }

    final reopened = createController();
    try {
      await show(reopened);
      expect(tester.getCenter(secondary).dy, lessThan(tester.getCenter(primary).dy));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      reopened.dispose();
    }
  });

  testWidgets('tray panel renders above the navigator (it has its own Overlay)', (tester) async {
    tester.view.physicalSize = const Size(420 * 2, 700 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final demo = DemoData(DateTime(2026, 10, 24, 12));
    final controller = AppController(
      persistence: await Persistence.openDemo(),
      historyStore: HistoryStore.demo(demo.history),
      desktop: DesktopIntegration(),
      notifier: Notifier(),
      homeWidget: HomeWidgetBridge(),
    )..initDemo(demo);

    // Mirrors MaterialApp.builder in main.dart: the panel is a sibling of the
    // Navigator, so without its own Overlay the refresh button's Tooltip throws
    // "No Overlay widget found".
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          builder: (context, child) => Stack(
            children: [
              Offstage(child: child),
              Positioned.fill(
                child: Overlay(initialEntries: [OverlayEntry(builder: (_) => const TrayPanel())]),
              ),
            ],
          ),
          home: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(TrayPanel), findsOneWidget);
    expect(find.byType(Tooltip), findsWidgets);

    // Dispose inside the test so the controller's clock timer is gone before
    // the framework checks for pending timers.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('tray panel fits its estimated height and offers the footer actions', (tester) async {
    final demo = DemoData(DateTime(2026, 10, 24, 12));
    final height = TrayPanel.heightFor(demo.snapshots.values.toList());
    tester.view.physicalSize = Size(420 * 2, height * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final controller = AppController(
      persistence: await Persistence.openDemo(),
      historyStore: HistoryStore.demo(demo.history),
      desktop: DesktopIntegration(),
      notifier: Notifier(),
      homeWidget: HomeWidgetBridge(),
    )..initDemo(demo);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const Scaffold(body: TrayPanel()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Open TokenBar'), findsOneWidget);
    expect(find.text('Quit'), findsOneWidget);
    // The footer is pinned to the bottom edge of the panel.
    expect(tester.getBottomLeft(find.text('Quit')).dy, lessThanOrEqualTo(height));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
