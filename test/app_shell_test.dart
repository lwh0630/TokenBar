import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:token_bar/app/app_shell.dart';
import 'package:token_bar/app/design/ambient_background.dart';
import 'package:token_bar/app/design/glass.dart';
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
import 'package:token_bar/ui/pages/account_detail_page.dart';
import 'package:token_bar/ui/widgets/history_chart.dart';

Future<(AppController, UpdateController)> _pump(
  WidgetTester tester,
  Size size, {
  double cardBlur = 0,
}) async {
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
        // Above the Navigator, like AppBackground in the real app.
        builder: (context, child) => GlassCardBlur(blur: cardBlur, child: child!),
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

/// Selected page: the IndexedStack index on wide layouts, the PageView page on phones.
int _shownPage(WidgetTester tester) {
  final pageView = find.byType(PageView);
  if (pageView.evaluate().isNotEmpty) {
    return tester.widget<PageView>(pageView).controller!.page!.round();
  }
  return tester.widget<IndexedStack>(find.byType(IndexedStack).first).index!;
}

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

  testWidgets('phones swipe between the pages and the bottom bar follows', (tester) async {
    final (controller, _) = await _pump(tester, const Size(400, 800));
    expect(_shownPage(tester), 0);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 1);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 2);

    // No page after Settings: it stays put.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 2);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 1);

    // Tapping a far tab animates straight there (it must not stop on page 1).
    await tester.tap(find.text('Quota').last);
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 0);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(_shownPage(tester), 2);

    expect(tester.takeException(), isNull);
    await _dispose(tester, controller);
  });

  testWidgets('wide layout does not page by swiping', (tester) async {
    final (controller, _) = await _pump(tester, const Size(1200, 800));
    expect(find.byType(PageView), findsNothing);
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

  testWidgets('detail page loads its history only after the push animation', (tester) async {
    // Tall window so the history card (lazily built list) is on screen.
    final (controller, _) = await _pump(tester, const Size(1200, 2400));

    await tester.tap(find.text('Codex').first);
    await tester.pump(); // route pushed, animation starts
    await tester.pump(const Duration(milliseconds: 100)); // mid-transition
    expect(find.byType(AccountDetailPage), findsOneWidget);
    expect(find.byType(HistorySkeleton), findsOneWidget);
    expect(find.byType(HistoryChart), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(HistorySkeleton), findsNothing);
    expect(find.byType(HistoryChart), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _dispose(tester, controller);
  });

  testWidgets('gradient backgrounds use no backdrop blur at all', (tester) async {
    final (controller, _) = await _pump(tester, const Size(1200, 800));
    // Cards and the sidebar are plain translucent fills: a blur pass per card is what
    // made the app slow and memory-hungry, and over a smooth gradient it shows nothing.
    expect(find.byType(BackdropFilter), findsNothing);
    await _dispose(tester, controller);
  });

  for (final (platform, suspended) in [
    (TargetPlatform.windows, true),
    (TargetPlatform.android, false),
  ]) {
    testWidgets('glass blur ${suspended ? 'is suspended only while' : 'stays on while'} a page '
        'transition runs on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final (controller, _) = await _pump(tester, const Size(1200, 800), cardBlur: 16);

      bool anyBlur() =>
          tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).any((f) => f.enabled);

      expect(anyBlur(), isTrue); // over a picture the glass blurs at rest

      await tester.tap(find.text('Codex').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Desktop: sliding gets fills only, no blur passes. Phones keep the blur.
      expect(anyBlur(), !suspended);

      await tester.pumpAndSettle();
      expect(anyBlur(), isTrue); // settled: blur is back

      await _dispose(tester, controller);
      debugDefaultTargetPlatformOverride = null; // before the test's invariants are checked
    });
  }

  testWidgets('overscroll does not wrap the glass in a stretch layer', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<void> pullDown(ScrollBehavior? behavior) async {
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: behavior,
          theme: AppTheme.light(),
          home: Scaffold(
            body: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [for (var i = 0; i < 3; i++) const GlassCard(blur: 16, child: Text('c'))],
            ),
          ),
        ),
      );
      // The stretch indicator is what an overscroll-pull builds around the list.
      await tester.drag(find.byType(ListView), const Offset(0, 120), warnIfMissed: false);
      await tester.pump();
    }

    await pullDown(null);
    expect(find.byType(StretchingOverscrollIndicator), findsOneWidget, reason: 'stock behaviour');

    await pullDown(const GlassScrollBehavior());
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
    debugDefaultTargetPlatformOverride = null; // before the test's invariants are checked
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
