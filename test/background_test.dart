import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:token_bar/app/design/ambient_background.dart';
import 'package:token_bar/app/design/background.dart';
import 'package:token_bar/app/design/tokens.dart';
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
import 'package:token_bar/ui/widgets/background_picker.dart';

/// A valid 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  group('AppSettings background', () {
    test('defaults to the aurora gradient and round-trips', () {
      final d = AppSettings.defaults();
      expect(d.background, BackgroundStyle.aurora);
      expect(d.backgroundImage, isEmpty);

      final s = d.copyWith(
        background: BackgroundStyle.image,
        backgroundImage: '/data/bg.png',
        backgroundDim: 0.6,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.background, BackgroundStyle.image);
      expect(back.backgroundImage, '/data/bg.png');
      expect(back.backgroundDim, 0.6);
    });

    test('older files and bad values fall back safely', () {
      expect(AppSettings.fromJson(const {}).background, BackgroundStyle.aurora);
      expect(
        AppSettings.fromJson(const {'background': 'plaid'}).background,
        BackgroundStyle.aurora,
      );
      expect(AppSettings.fromJson(const {'backgroundDim': 5}).backgroundDim, 0.85);
      expect(AppSettings.fromJson(const {'backgroundDim': 'x'}).backgroundDim, 0.45);
    });
  });

  group('AmbientBackground', () {
    Widget host(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

    testWidgets('image style paints the picture under a veil', (tester) async {
      await tester.pumpWidget(
        host(
          AmbientBackground(
            animate: false,
            style: BackgroundStyle.image,
            image: MemoryImage(_png),
            dim: 0.5,
            child: const Text('x'),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('x'), findsOneWidget);
    });

    testWidgets('image style without a picture shows the gradient', (tester) async {
      await tester.pumpWidget(
        host(
          const AmbientBackground(animate: false, style: BackgroundStyle.image, child: Text('x')),
        ),
      );
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a picture does not keep the frame loop running', (tester) async {
      await tester.pumpWidget(
        host(
          AmbientBackground(
            style: BackgroundStyle.image,
            image: MemoryImage(_png),
            child: const Text('x'),
          ),
        ),
      );
      // pumpAndSettle would time out if the drift ticker were still scheduling frames.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('every preset has distinct light and dark palettes', () {
      for (final style in BackgroundStyle.values.where((b) => b.isPreset)) {
        final light = BackgroundPalette.of(style, GlassColors.light);
        final dark = BackgroundPalette.of(style, GlassColors.dark);
        expect(light, isNot(dark), reason: '$style');
      }
    });
  });

  testWidgets('settings page picks a gradient preset', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600) * 2;
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
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackgroundPicker), findsOneWidget);
    expect(controller.settings.background, BackgroundStyle.aurora);
    // No picture yet: the image-only controls stay hidden.
    expect(find.text('Overlay strength'), findsNothing);

    await tester.tap(find.text('Sunset'));
    await tester.pumpAndSettle();
    expect(controller.settings.background, BackgroundStyle.sunset);

    // With a stored picture selected the veil slider appears.
    await controller.updateSettings(
      controller.settings.copyWith(background: BackgroundStyle.image, backgroundImage: '/x.png'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overlay strength'), findsOneWidget);
    expect(find.text('Remove image'), findsOneWidget);

    await tester.tap(find.text('Remove image'));
    await tester.pumpAndSettle();
    expect(controller.settings.background, BackgroundStyle.aurora);
    expect(controller.settings.backgroundImage, isEmpty);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
