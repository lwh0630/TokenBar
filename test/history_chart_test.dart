import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:token_bar/app/theme.dart';
import 'package:token_bar/l10n/app_localizations.dart';
import 'package:token_bar/ui/chart_math.dart' show otherSeriesId;
import 'package:token_bar/ui/widgets/history_chart.dart';
import 'package:token_bar/ui/widgets/stacked_bar_chart.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

const _zh = Locale('zh', 'CN');
const _en = Locale('en', 'US');

// Saturday 2026-10-24 17:30 local; the 7-day grid ends with the 12:00 bucket.
final _now = DateTime(2026, 10, 24, 17, 30);

ModelUsageSeries _series(
  Map<DateTime, Map<String, double>> data, {
  Map<String, double>? cost,
  String? source = 'cursor-events',
  Duration range = const Duration(days: 7),
}) => ModelUsageSeries(
  from: _now.subtract(range),
  to: _now,
  bucket: const Duration(hours: 1),
  source: source,
  buckets: [
    for (final e in data.entries)
      ModelUsageBucket(
        start: e.key,
        usage: [
          for (final m in e.value.entries)
            ModelUsage(
              model: m.key,
              tokens: m.value,
              costUsd: cost == null || cost[m.key] == null ? null : cost[m.key]! * m.value / 1e6,
              requests: 1,
            ),
        ],
      ),
  ],
);

final _threeModels = _series({
  DateTime(2026, 10, 17, 13): {'gpt-5': 400000, 'claude-opus': 500000, 'auto': 600000},
  DateTime(2026, 10, 21, 3): {'gpt-5': 1200000, 'auto': 300000},
  DateTime(2026, 10, 24, 13): {'gpt-5': 900000, 'claude-opus': 2500000, 'auto': 100000},
});

List<UsagePoint> _quotaPoints() => [
  UsagePoint(
    accountId: 'a',
    at: DateTime(2026, 10, 24, 6),
    used: const {'session': 10, 'weekly': 5},
  ),
  UsagePoint(
    accountId: 'a',
    at: DateTime(2026, 10, 24, 13),
    used: const {'session': 55, 'weekly': 9},
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required Widget chart,
  double width = 900,
  Locale locale = _zh,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: chart),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

HistoryChart _chart({
  List<UsagePoint> points = const [],
  ModelUsageSeries? models,
  Duration range = const Duration(days: 7),
}) => HistoryChart(
  points: points,
  windowLabels: const {'session': '5 小时', 'weekly': '每周'},
  credits: const {},
  range: range,
  modelUsage: models,
  now: _now,
);

/// Hovers along the chart row at [y] from the left or right edge and returns
/// the x of the first position that shows the card (null if never).
Future<double?> _scanForCard(
  WidgetTester tester, {
  required bool fromLeft,
  TestGesture? mouse,
}) async {
  final rect = tester.getRect(find.byType(StackedBarChart));
  final y = rect.top + rect.height / 2;
  if (mouse == null) {
    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(rect.left + 1, y));
    addTearDown(mouse.removePointer);
  } else {
    await mouse.addPointer(location: Offset(rect.left + 1, y));
  }
  final xs = [for (var x = rect.left + 2; x < rect.right - 2; x += 2) x];
  for (final x in fromLeft ? xs : xs.reversed) {
    await mouse.moveTo(Offset(x, y));
    await tester.pump();
    if (find.byKey(chartTooltipKey).evaluate().isNotEmpty) return x;
  }
  return null;
}

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('model view', () {
    testWidgets('renders legend, chart and share list without errors', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      expect(find.byType(StackedBarChart), findsOneWidget);
      for (final m in ['gpt-5', 'claude-opus', 'auto']) {
        expect(find.byKey(ValueKey('legend:$m')), findsOneWidget);
        // Legend chip + share row.
        expect(find.text(m), findsNWidgets(2));
      }
      expect(find.text(zh.historyTotal), findsOneWidget);
      // Only the model view has data, so there is no view switch; tokens only (no cost).
      expect(find.text(zh.viewQuotaWindows), findsNothing);
      expect(find.text(zh.metricTokens), findsOneWidget);
      expect(find.textContaining('Cursor'), findsOneWidget);
    });

    testWidgets('share bars are actually drawn (non-zero height and width)', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      await tester.pumpAndSettle();
      final bars = find.byWidgetPredicate(
        (w) => w is FractionallySizedBox && w.widthFactor != null,
      );
      expect(bars, findsNWidgets(3));
      for (final e in bars.evaluate()) {
        final size = tester.getSize(find.byWidget(e.widget));
        expect(size.height, greaterThan(0));
        expect(size.width, greaterThan(0));
      }
    });

    testWidgets('share list is sorted by total, biggest first', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      // Totals: claude-opus 3.0M, gpt-5 2.5M, auto 1.0M.
      final names = ['claude-opus', 'gpt-5', 'auto'];
      final ys = [for (final m in names) tester.getTopLeft(find.text(m).last).dy];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
    });

    testWidgets('tapping a legend chip hides the model, tapping all restores everything', (
      tester,
    ) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      await tester.tap(find.byKey(const ValueKey('legend:auto')));
      await tester.pumpAndSettle();
      // Gone from the share list, still in the legend.
      expect(find.text('auto'), findsOneWidget);
      expect(find.text('gpt-5'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('legend:gpt-5')));
      await tester.pumpAndSettle();
      expect(find.text('gpt-5'), findsOneWidget);
      expect(find.text('claude-opus'), findsNWidgets(2));

      // Hiding the last visible one brings everything back.
      await tester.tap(find.byKey(const ValueKey('legend:claude-opus')));
      await tester.pumpAndSettle();
      for (final m in ['gpt-5', 'claude-opus', 'auto']) {
        expect(find.text(m), findsNWidgets(2));
      }
    });

    testWidgets('cost toggle is disabled without cost and works with it', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      await tester.tap(find.text(zh.metricCost));
      await tester.pumpAndSettle();
      expect(find.textContaining(r'$'), findsNothing);

      final withCost = _series(
        {
          DateTime(2026, 10, 24, 13): {'gpt-5': 2000000, 'auto': 500000},
        },
        cost: {'gpt-5': 10, 'auto': 2},
      );
      await _pump(tester, chart: _chart(models: withCost));
      await tester.tap(find.text(zh.metricCost));
      await tester.pumpAndSettle();
      expect(find.textContaining(r'$'), findsWidgets);
      // 2M tokens at $10/M = $20.00 in the share list and total.
      expect(find.text(r'$20.00'), findsWidgets);
    });

    testWidgets('cost is the default metric when there is cost, tokens otherwise', (tester) async {
      final withCost = _series(
        {
          DateTime(2026, 10, 24, 13): {'gpt-5': 2000000, 'auto': 500000},
        },
        cost: {'gpt-5': 10, 'auto': 2},
      );
      await _pump(tester, chart: _chart(models: withCost));
      // No tap: the dollar totals are already showing.
      expect(find.text(r'$20.00'), findsWidgets);

      await _pump(tester, chart: _chart(models: _threeModels));
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('more models than colors fold into "other"', (tester) async {
      final many = _series({
        DateTime(2026, 10, 24, 13): {
          for (var i = 0; i < 14; i++) 'model-$i': 1000000.0 - i * 10000,
        },
      });
      await _pump(tester, chart: _chart(models: many));
      expect(find.byKey(ValueKey('legend:$otherSeriesId')), findsOneWidget);
      expect(find.text(zh.seriesOther), findsNWidgets(2));
      expect(find.byKey(const ValueKey('legend:model-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('legend:model-13')), findsNothing);
    });

    testWidgets('a single bucket still lays out', (tester) async {
      final one = _series({
        DateTime(2026, 10, 24, 13): {'gpt-5': 123456},
      });
      await _pump(tester, chart: _chart(models: one), width: 360);
      expect(find.byType(StackedBarChart), findsOneWidget);
      expect(find.text('123K'), findsWidgets);
    });

    for (final range in [
      const Duration(hours: 24),
      const Duration(days: 7),
      const Duration(days: 30),
    ]) {
      testWidgets('renders for ${range.inHours} h range', (tester) async {
        final s = _series({
          DateTime(2026, 10, 24, 13): {'gpt-5': 900000, 'auto': 100000},
          DateTime(2026, 10, 24, 9): {'gpt-5': 100000},
        }, range: range);
        await _pump(
          tester,
          chart: _chart(models: s, range: range),
        );
        expect(find.byType(StackedBarChart), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('views', () {
    testWidgets('default is models when available and the switch offers each view', (tester) async {
      await _pump(
        tester,
        chart: _chart(points: _quotaPoints(), models: _threeModels),
      );
      expect(find.text(zh.viewModels), findsOneWidget);
      expect(find.text(zh.viewQuotaWindows), findsOneWidget);
      expect(find.text(zh.viewSpend), findsNothing);
      // Model view is selected: model legend visible.
      expect(find.byKey(const ValueKey('legend:gpt-5')), findsOneWidget);

      await tester.tap(find.text(zh.viewQuotaWindows));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('legend:gpt-5')), findsNothing);
      expect(find.text(zh.usageNote), findsOneWidget);
      expect(find.text('+45%'), findsWidgets);
    });

    testWidgets('without model data the quota view is the default and has no switch', (
      tester,
    ) async {
      await _pump(tester, chart: _chart(points: _quotaPoints()));
      expect(find.byType(SegmentedButton<HistoryView>), findsNothing);
      expect(find.byType(StackedBarChart), findsOneWidget);
      // session + weekly: both aggregate windows, shown together.
      expect(find.byKey(const ValueKey('legend:session')), findsOneWidget);
      expect(find.text('+45%'), findsWidgets);
    });

    testWidgets('spend is the fallback when only spend history exists', (tester) async {
      final points = <UsagePoint>[
        UsagePoint(
          accountId: 'a',
          at: DateTime(2026, 10, 24, 6),
          used: const {},
          spend: const {'c': 1.0},
        ),
        UsagePoint(
          accountId: 'a',
          at: DateTime(2026, 10, 24, 13),
          used: const {},
          spend: const {'c': 3.5},
        ),
      ];
      await _pump(
        tester,
        chart: HistoryChart(
          points: points,
          windowLabels: const {},
          credits: const {'c': Credits(id: 'c', label: 'On-demand', used: 3.5, currency: 'USD')},
          range: const Duration(days: 7),
          now: _now,
        ),
      );
      expect(find.byType(StackedBarChart), findsOneWidget);
      expect(find.text(r'$2.50'), findsWidgets);
    });

    testWidgets('a model series without data does not add a view', (tester) async {
      await _pump(
        tester,
        chart: _chart(points: _quotaPoints(), models: _series(const {})),
      );
      expect(find.byType(SegmentedButton<HistoryView>), findsNothing);
      expect(find.text(zh.viewModels), findsNothing);
    });
  });

  group('empty states', () {
    testWidgets('no data at all', (tester) async {
      await _pump(tester, chart: _chart());
      expect(find.text(zh.historyEmptyTitle), findsOneWidget);
      expect(find.text(zh.historyEmptyBody), findsOneWidget);
      expect(find.byType(StackedBarChart), findsNothing);
    });

    testWidgets('english', (tester) async {
      await _pump(tester, chart: _chart(), locale: _en);
      expect(find.text(en.historyEmptyTitle), findsOneWidget);
      expect(find.text('No history yet'), findsOneWidget);
    });

    testWidgets('empty model series explains where the data comes from', (tester) async {
      await _pump(tester, chart: _chart(models: _series(const {})));
      expect(find.text(zh.historyEmptyModelBody(zh.modelSourceCursor)), findsOneWidget);
      await _pump(
        tester,
        chart: _chart(models: _series(const {}, source: 'codex-logs')),
        locale: _en,
      );
      expect(find.text(en.historyEmptyModelBody(en.modelSourceCodex)), findsOneWidget);
    });

    testWidgets('a single quota point is not enough', (tester) async {
      await _pump(tester, chart: _chart(points: [_quotaPoints().first]));
      expect(find.text(zh.historyEmptyTitle), findsOneWidget);
    });
  });

  group('hover card', () {
    testWidgets('mouse hover shows a card beside the bar, never over it', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      final chartRect = tester.getRect(find.byType(StackedBarChart));
      final x = await _scanForCard(tester, fromLeft: true);
      expect(x, isNotNull);
      final card = tester.getRect(find.byKey(chartTooltipKey));
      // First populated bucket sits at the left: the card goes to its right.
      expect(card.left, greaterThan(x!));
      expect(chartRect.contains(card.topLeft), isTrue);
      expect(card.right, lessThanOrEqualTo(chartRect.right + 0.5));
      expect(card.bottom, lessThanOrEqualTo(chartRect.bottom + 0.5));
      // Total + models sorted largest first inside the card.
      final inCard = find.descendant(of: find.byKey(chartTooltipKey), matching: find.byType(Text));
      expect(inCard, findsWidgets);
      expect(
        find.descendant(of: find.byKey(chartTooltipKey), matching: find.text(zh.historyTotal)),
        findsOneWidget,
      );
    });

    testWidgets('near the right edge the card flips to the left', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      final chartRect = tester.getRect(find.byType(StackedBarChart));
      final x = await _scanForCard(tester, fromLeft: false);
      expect(x, isNotNull);
      expect(x, greaterThan(chartRect.right - 40));
      final card = tester.getRect(find.byKey(chartTooltipKey));
      expect(card.right, lessThan(x!));
      expect(card.left, greaterThanOrEqualTo(chartRect.left - 0.5));
    });

    testWidgets('moving off the bars hides the card', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final x = await _scanForCard(tester, fromLeft: false, mouse: mouse);
      expect(x, isNotNull);
      expect(find.byKey(chartTooltipKey), findsOneWidget);
      final rect = tester.getRect(find.byType(StackedBarChart));
      await mouse.moveTo(rect.topLeft + const Offset(0, -6));
      await tester.pump();
      expect(find.byKey(chartTooltipKey), findsNothing);
      await mouse.removePointer();
    });

    testWidgets('touch: tap shows the card, tapping again hides it', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels));
      final rect = tester.getRect(find.byType(StackedBarChart));
      // Rightmost slot (the 12:00 bucket of the last day has data).
      final pos = Offset(rect.right - 14, rect.center.dy);
      await tester.tapAt(pos);
      await tester.pump();
      expect(find.byKey(chartTooltipKey), findsOneWidget);
      await tester.tapAt(pos);
      await tester.pump();
      expect(find.byKey(chartTooltipKey), findsNothing);
    });
  });

  group('layout and theme', () {
    final manyLongNames = _series(
      {
        DateTime(2026, 10, 24, 13): {
          for (var i = 0; i < 14; i++)
            'a-very-long-model-name-that-keeps-going-and-going-$i': 900000.0 - i * 20000,
        },
        DateTime(2026, 10, 22, 7): {
          for (var i = 0; i < 14; i++)
            'a-very-long-model-name-that-keeps-going-and-going-$i': 100000.0 + i * 5000,
        },
      },
      cost: {
        for (var i = 0; i < 14; i++) 'a-very-long-model-name-that-keeps-going-and-going-$i': 3,
      },
    );

    for (final width in [360.0, 1000.0]) {
      for (final locale in [_zh, _en]) {
        testWidgets('${width.toInt()} px, ${locale.languageCode}: no overflow', (tester) async {
          await _pump(
            tester,
            chart: _chart(points: _quotaPoints(), models: manyLongNames),
            width: width,
            locale: locale,
          );
          expect(find.byType(StackedBarChart), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Tokens'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // Other views at the same width.
          final l = lookupAppLocalizations(locale);
          await tester.tap(find.text(l.viewQuotaWindows));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('dark theme renders and shows the card', (tester) async {
      await _pump(
        tester,
        chart: _chart(models: _threeModels),
        theme: AppTheme.dark(),
      );
      expect(find.byType(StackedBarChart), findsOneWidget);
      final x = await _scanForCard(tester, fromLeft: true);
      expect(x, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chart itself fills the width on a phone', (tester) async {
      await _pump(tester, chart: _chart(models: _threeModels), width: 360);
      final rect = tester.getRect(find.byType(StackedBarChart));
      expect(rect.width, closeTo(360 - 32, 0.5));
    });
  });

  testWidgets('skeleton renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HistorySkeleton())));
    expect(find.byType(HistorySkeleton), findsOneWidget);
  });
}
