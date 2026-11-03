import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:token_bar/app/semantics_guard.dart';

Widget _app({bool? exclude}) => MaterialApp(
  home: Scaffold(
    body: SemanticsGuard(
      exclude: exclude,
      child: Column(
        children: [
          const Text('Quota'),
          IconButton(tooltip: 'Refresh', onPressed: () {}, icon: const Icon(Icons.refresh)),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('excluded: the app publishes no semantics nodes below the guard', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(exclude: true));
    expect(find.bySemanticsLabel('Quota'), findsNothing);
    expect(find.bySemanticsLabel('Refresh'), findsNothing);
    handle.dispose();
  });

  testWidgets('not excluded: semantics are published as usual', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(exclude: false));
    expect(find.bySemanticsLabel('Quota'), findsOneWidget);
    handle.dispose();
  });

  test('only Windows skips semantics (Flutter engine crash on a null parent)', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final results = <TargetPlatform, bool>{};
    for (final p in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = p;
      results[p] = skipSemanticsOnThisPlatform;
    }
    debugDefaultTargetPlatformOverride = null;
    expect(results[TargetPlatform.windows], isTrue);
    expect(results.entries.where((e) => e.value).map((e) => e.key), [TargetPlatform.windows]);
  });
}
