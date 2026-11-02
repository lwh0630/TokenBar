import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:token_bar/app/app_shell.dart';
import 'package:token_bar/app/design/ambient_background.dart';
import 'package:token_bar/app/design/reveal.dart';
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

Future<(AppController, UpdateController)> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
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
        home: const AppShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller, updates);
}

Future<void> _dispose(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
}

int _shownPage(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack).first).index!;

void main() {
  testWidgets('wide layout shows the glass sidebar and switches pages', (tester) async {
    final (controller, _) = await _pump(tester, const Size(1200, 800));

    expect(find.text('Quota'), findsWidgets);
    expect(find.text('Accounts'), findsOneWidget);
    expect(_shownPage(tester), 0);

    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 1);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 2);

    expect(tester.takeException(), isNull);
    await _dispose(tester, controller);
  });

  testWidgets('narrow layout uses the floating bottom bar', (tester) async {
    final (controller, _) = await _pump(tester, const Size(400, 800));

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 2);

    expect(tester.takeException(), isNull);
    await _dispose(tester, controller);
  });

  testWidgets('dashboard cards fade in and settle fully visible', (tester) async {
    final (controller, _) = await _pump(tester, const Size(1200, 800));

    expect(find.byType(Reveal), findsWidgets);
    final opacities = tester.widgetList<Opacity>(
      find.descendant(of: find.byType(Reveal), matching: find.byType(Opacity)),
    );
    expect(opacities.every((o) => o.opacity == 1), isTrue);

    await _dispose(tester, controller);
  });

  testWidgets('reveal skips the animation when the platform disables animations', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Reveal(index: 5, child: Text('hi')),
        ),
      ),
    );
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 1);
  });

  testWidgets('ambient background does not keep the frame loop alive when frozen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const AmbientBackground(animate: false, child: Text('x')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('ambient background honors reduced motion', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AmbientBackground(child: Text('y')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('y'), findsOneWidget);
  });

  testWidgets('ambient background animates by default and disposes cleanly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const AmbientBackground(child: Text('z')),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
