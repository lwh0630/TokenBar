import 'package:flutter/foundation.dart';
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
import 'package:token_bar/state/settings.dart';
import 'package:token_bar/state/update_controller.dart';
import 'package:token_bar/ui/pages/settings_page.dart';

class _SpyDesktop extends DesktopIntegration {
  final dockCalls = <bool>[];

  @override
  Future<void> setHideDockIcon(bool value) async => dockCalls.add(value);
}

void main() {
  test('hideDockIcon defaults to off, round-trips and tolerates older files', () {
    expect(AppSettings.defaults().hideDockIcon, isFalse);
    final on = AppSettings.defaults().copyWith(hideDockIcon: true);
    expect(AppSettings.fromJson(on.toJson()).hideDockIcon, isTrue);
    expect(AppSettings.fromJson(const {}).hideDockIcon, isFalse);
    expect(AppSettings.fromJson(const {'hideDockIcon': 'yes'}).hideDockIcon, isFalse);
  });

  Future<(AppController, _SpyDesktop)> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final demo = DemoData(DateTime(2026, 10, 24, 12));
    final desktop = _SpyDesktop();
    final controller = AppController(
      persistence: await Persistence.openDemo(),
      historyStore: HistoryStore.demo(demo.history),
      desktop: desktop,
      notifier: Notifier(),
      homeWidget: HomeWidgetBridge(),
    )..initDemo(demo);
    final updates = UpdateController(
      readSettings: AppSettings.defaults,
      saveSettings: (_) async {},
      versionLoader: () async => '1.0.0',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppController>.value(value: controller),
          ChangeNotifierProvider<UpdateController>.value(value: updates),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, desktop);
  }

  testWidgets('macOS settings can hide the Dock icon', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final (controller, desktop) = await pumpSettings(tester);

    final tile = find.text('Menu bar only (hide the Dock icon)');
    await tester.ensureVisible(tile);
    expect(controller.settings.hideDockIcon, isFalse);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(controller.settings.hideDockIcon, isTrue);
    expect(desktop.dockCalls, [true]);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(controller.settings.hideDockIcon, isFalse);
    expect(desktop.dockCalls, [true, false]);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('other platforms do not offer the Dock icon switch', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final (controller, _) = await pumpSettings(tester);

    expect(find.text('Minimize to tray when closing the window'), findsOneWidget);
    expect(find.text('Menu bar only (hide the Dock icon)'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
