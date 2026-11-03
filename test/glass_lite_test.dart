import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:token_bar/app/design/glass.dart';
import 'package:token_bar/app/theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

bool _anyBlur(WidgetTester tester) =>
    tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).any((f) => f.enabled);

void main() {
  group('GlassCard backdrop blur', () {
    testWidgets('is off by default (smooth gradient behind)', (tester) async {
      await tester.pumpWidget(_host(const GlassCard(child: Text('x'))));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('follows GlassCardBlur (picture backgrounds)', (tester) async {
      await tester.pumpWidget(
        _host(const GlassCardBlur(blur: 16, child: GlassCard(child: Text('x')))),
      );
      expect(_anyBlur(tester), isTrue);
    });

    testWidgets('an explicit blur wins over the inherited one', (tester) async {
      await tester.pumpWidget(
        _host(const GlassCardBlur(blur: 16, child: GlassCard(blur: 0, child: Text('x')))),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('is suspended while GlassMotionScope.moving', (tester) async {
      await tester.pumpWidget(
        _host(
          const GlassCardBlur(
            blur: 16,
            child: GlassMotionScope(moving: true, child: GlassCard(child: Text('x'))),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(_anyBlur(tester), isFalse);
    });
  });

  group('GlassSurface', () {
    testWidgets('blur: 0 skips the backdrop filter', (tester) async {
      await tester.pumpWidget(_host(const GlassSurface(blur: 0, child: Text('x'))));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('blurs by default', (tester) async {
      await tester.pumpWidget(_host(const GlassSurface(child: Text('x'))));
      expect(_anyBlur(tester), isTrue);
    });
  });

  group('GlassResizeTracker', () {
    Widget app() => _host(
      const GlassResizeTracker(
        settle: Duration(milliseconds: 100),
        child: GlassCardBlur(blur: 16, child: GlassCard(child: Text('x'))),
      ),
    );

    testWidgets('goes lite while the window changes size and recovers afterwards', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      expect(_anyBlur(tester), isTrue); // at rest

      tester.view.physicalSize = const Size(1000, 700);
      await tester.pump();
      expect(_anyBlur(tester), isFalse); // dragging an edge: fills only

      tester.view.physicalSize = const Size(900, 650);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_anyBlur(tester), isFalse); // still moving, the settle timer restarted

      await tester.pump(const Duration(milliseconds: 150));
      expect(_anyBlur(tester), isTrue); // settled: the full glass look is back
    });

    testWidgets('stays untouched when the size does not change', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      expect(_anyBlur(tester), isTrue);
    });
  });
}
