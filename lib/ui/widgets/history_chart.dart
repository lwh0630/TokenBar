import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../chart_math.dart';
import '../format.dart';
import '../history_series.dart';
import 'stacked_bar_chart.dart';

/// Which breakdown the history card shows.
enum HistoryView {
  /// Newly consumed quota per window (from [UsagePoint.used]).
  quota,

  /// Tokens or cost per model (from [ModelUsageSeries]).
  models,

  /// Newly spent money per credits line (from [UsagePoint.spend]).
  spend,
}

/// Unit of the per-model view.
enum ModelMetric { tokens, cost }

/// Usage history of one account: a view switch, clickable legend chips, a
/// stacked bar chart and a share list. Views without data are not offered.
class HistoryChart extends StatefulWidget {
  const HistoryChart({
    super.key,
    required this.points,
    required this.windowLabels,
    required this.credits,
    required this.range,
    this.modelUsage,
    this.now,
  });

  final List<UsagePoint> points;

  /// Window id → display label.
  final Map<String, String> windowLabels;

  /// Credits id → credits (for labels and currency).
  final Map<String, Credits> credits;
  final Duration range;

  /// Per-model usage for [range]; null when the service has none.
  final ModelUsageSeries? modelUsage;

  /// Clock override for tests.
  final DateTime? now;

  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

/// The numbers behind one view, computed once per input change (not per frame).
class _ViewModel {
  const _ViewModel({
    required this.full,
    required this.colorOrder,
    required this.bucket,
    required this.starts,
  });

  /// Merged to at most [seriesPalette] length, "Other" last; hidden series included.
  final StackedHistory full;

  /// Stable ordering that decides each series' color.
  final List<String> colorOrder;
  final Duration bucket;
  final List<DateTime> starts;
}

class _HistoryChartState extends State<HistoryChart> {
  HistoryView? _preferredView;

  /// Cost is the default; [_effectiveMetric] falls back to tokens while the data
  /// has no cost (a provider without pricing, an unknown model).
  ModelMetric _modelMetric = ModelMetric.cost;
  final Map<String, Set<String>> _hidden = {};
  final Map<String, _ViewModel> _cache = {};
  late DateTime _now;
  late List<String> _quotaIds;
  late List<String> _spendIds;
  late bool _hasCost;

  @override
  void initState() {
    super.initState();
    _invalidate();
  }

  @override
  void didUpdateWidget(HistoryChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.points, widget.points) ||
        !identical(old.modelUsage, widget.modelUsage) ||
        old.range != widget.range ||
        old.now != widget.now ||
        !mapEquals(old.windowLabels, widget.windowLabels) ||
        !_sameCredits(old.credits, widget.credits)) {
      _invalidate();
    }
  }

  static bool _sameCredits(Map<String, Credits> a, Map<String, Credits> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final o = b[e.key];
      if (o == null || o.currency != e.value.currency || o.label != e.value.label) return false;
    }
    return true;
  }

  void _invalidate() {
    _cache.clear();
    _now = widget.now ?? DateTime.now();
    _quotaIds = <String>{for (final p in widget.points) ...p.used.keys}.toList()..sort();
    _spendIds = <String>{for (final p in widget.points) ...p.spend.keys}.toList()..sort();
    _hasCost =
        widget.modelUsage?.buckets.any((b) => b.usage.any((u) => (u.costUsd ?? 0) > 0)) ?? false;
  }

  bool get _hasModels => widget.modelUsage != null && !widget.modelUsage!.isEmpty;

  List<HistoryView> get _views => [
    if (_hasModels) HistoryView.models,
    if (widget.points.length >= 2 && _quotaIds.isNotEmpty) HistoryView.quota,
    if (widget.points.length >= 2 && _spendIds.isNotEmpty) HistoryView.spend,
  ];

  HistoryView? get _view {
    final views = _views;
    if (views.isEmpty) return null;
    return views.contains(_preferredView) ? _preferredView : views.first;
  }

  ModelMetric get _effectiveMetric => _hasCost ? _modelMetric : ModelMetric.tokens;

  String _key(HistoryView v) =>
      v == HistoryView.models ? 'models/${_effectiveMetric.name}' : v.name;

  _ViewModel _model(HistoryView view) => _cache.putIfAbsent(_key(view), () => _buildModel(view));

  _ViewModel _buildModel(HistoryView view) {
    final range = widget.range;
    if (view == HistoryView.models) {
      final series = widget.modelUsage!;
      final base = bucketFor(range);
      final bucket = series.bucket > base ? series.bucket : base;
      final starts = alignedBucketStarts(now: _now, range: range, bucket: bucket, minCount: 2);
      final raw = buildModelHistory(
        series: series,
        starts: starts,
        bucket: bucket,
        cost: _effectiveMetric == ModelMetric.cost,
      );
      return _ViewModel(
        full: mergeTailSeries(raw, maxSeries: seriesPalette.length),
        colorOrder: series.models,
        bucket: bucket,
        starts: starts,
      );
    }
    final bucket = bucketFor(range);
    final starts = alignedBucketStarts(now: _now, range: range, bucket: bucket);
    final ids = view == HistoryView.quota ? _quotaIds : _spendIds;
    final raw = buildStackedHistory(
      points: widget.points,
      read: view == HistoryView.quota ? (p) => p.used : (p) => p.spend,
      include: ids.toSet(),
      start: starts.first,
      end: _now.add(const Duration(minutes: 1)),
      bucket: bucket,
      alignedStarts: starts,
    );
    return _ViewModel(
      full: mergeTailSeries(raw, maxSeries: seriesPalette.length),
      colorOrder: ids,
      bucket: bucket,
      starts: starts,
    );
  }

  /// Series hidden by default: aggregate quota windows when components exist,
  /// and money lines in a different currency than the first.
  Set<String> _hiddenFor(HistoryView view, _ViewModel vm) {
    return _hidden.putIfAbsent(_key(view), () {
      final ids = vm.full.ids;
      switch (view) {
        case HistoryView.quota:
          final shown = defaultUsageSeries(ids);
          return {
            for (final id in ids)
              if (!shown.contains(id)) id,
          };
        case HistoryView.spend:
          if (ids.isEmpty) return <String>{};
          final currency = widget.credits[ids.first]?.currency;
          return {
            for (final id in ids)
              if (widget.credits[id]?.currency != currency) id,
          };
        case HistoryView.models:
          return <String>{};
      }
    });
  }

  Color _color(_ViewModel vm, String id) {
    if (id == otherSeriesId) return seriesOtherColor;
    final i = vm.colorOrder.indexOf(id);
    return seriesPalette[(i < 0 ? 0 : i) % seriesPalette.length];
  }

  String _label(AppLocalizations l, HistoryView view, String id) {
    if (id == otherSeriesId) return l.seriesOther;
    return switch (view) {
      HistoryView.quota => widget.windowLabels[id] ?? id,
      HistoryView.spend => widget.credits[id] == null ? id : creditsLabel(l, widget.credits[id]!),
      HistoryView.models => id,
    };
  }

  String? _currencyOf(HistoryView view, String id) => switch (view) {
    HistoryView.models => 'USD',
    HistoryView.spend => widget.credits[id]?.currency,
    HistoryView.quota => null,
  };

  String _value(HistoryView view, String id, double v) {
    switch (view) {
      case HistoryView.quota:
        return '+${formatPercent(v)}';
      case HistoryView.models:
        return _effectiveMetric == ModelMetric.cost ? formatMoney(v, 'USD') : abbreviateNumber(v);
      case HistoryView.spend:
        final currency = _currencyOf(view, id);
        return currency == null ? v.toStringAsFixed(2) : formatMoney(v, currency);
    }
  }

  String _axis(HistoryView view, List<String> visibleIds, double v) {
    switch (view) {
      case HistoryView.quota:
        return formatPercent(v);
      case HistoryView.models:
        return _effectiveMetric == ModelMetric.cost
            ? formatAxisMoney(v, 'USD')
            : abbreviateNumber(v);
      case HistoryView.spend:
        final currency = visibleIds.isEmpty ? null : _currencyOf(view, visibleIds.first);
        return formatAxisMoney(v, currency);
    }
  }

  String _modelSource(AppLocalizations l) {
    final s = (widget.modelUsage?.source ?? '').toLowerCase();
    if (s.contains('cursor')) return l.modelSourceCursor;
    if (s.contains('codex')) return l.modelSourceCodex;
    return l.modelSourceLocal;
  }

  String _viewName(AppLocalizations l, HistoryView v) => switch (v) {
    HistoryView.quota => l.viewQuotaWindows,
    HistoryView.models => l.viewModels,
    HistoryView.spend => l.viewSpend,
  };

  String _bucketTitle(AppLocalizations l, DateTime start, Duration bucket) {
    final day = l.monthDay(start.month, start.day);
    if (bucket >= const Duration(days: 1)) return day;
    final hours = math.max(1, bucket.inHours);
    final end = DateTime(start.year, start.month, start.day, start.hour + hours);
    return '$day ${two(start.hour)}:${two(start.minute)}–${two(end.hour)}:${two(end.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final view = _view;
    if (view == null) {
      final modelsEmpty = widget.modelUsage != null && widget.modelUsage!.isEmpty;
      return _EmptyState(
        title: l.historyEmptyTitle,
        body: modelsEmpty ? l.historyEmptyModelBody(_modelSource(l)) : l.historyEmptyBody,
      );
    }

    final vm = _model(view);
    final hidden = _hiddenFor(view, vm);
    final visible = filterSeries(vm.full, hidden);
    final legendIds = vm.full.ids;

    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 480;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _controls(l, view),
            if (legendIds.length > 1) ...[const SizedBox(height: 12), _legend(l, view, vm, hidden)],
            const SizedBox(height: 14),
            if (visible.isEmpty)
              _EmptyState(
                title: view == HistoryView.spend ? l.noCostChanges : l.noUsageChanges,
                body: null,
                height: compact ? 190 : 220,
              )
            else
              _chart(l, view, vm, hidden, visible, compact ? 200 : 230),
            if (!visible.isEmpty) ...[
              const SizedBox(height: 16),
              _summary(l, view, vm, visible, compact),
              const SizedBox(height: 10),
              _footnote(l, view),
            ],
          ],
        );
      },
    );
  }

  Widget _controls(AppLocalizations l, HistoryView view) {
    final views = _views;
    final showMetric = view == HistoryView.models;
    if (views.length < 2 && !showMetric) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (views.length > 1)
          SegmentedButton<HistoryView>(
            segments: [
              for (final v in views) ButtonSegment(value: v, label: Text(_viewName(l, v))),
            ],
            selected: {view},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => setState(() => _preferredView = s.first),
          ),
        if (showMetric)
          SegmentedButton<ModelMetric>(
            segments: [
              ButtonSegment(value: ModelMetric.tokens, label: Text(l.metricTokens)),
              ButtonSegment(value: ModelMetric.cost, label: Text(l.metricCost), enabled: _hasCost),
            ],
            selected: {_effectiveMetric},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => setState(() => _modelMetric = s.first),
          ),
      ],
    );
  }

  Widget _legend(AppLocalizations l, HistoryView view, _ViewModel vm, Set<String> hidden) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in vm.full.ids)
          _LegendChip(
            key: ValueKey('legend:$id'),
            label: _label(l, view, id),
            color: _color(vm, id),
            active: !hidden.contains(id),
            onTap: () => setState(() {
              _hidden[_key(view)] = toggleHidden(hidden, id, vm.full.ids);
            }),
          ),
      ],
    );
  }

  Widget _chart(
    AppLocalizations l,
    HistoryView view,
    _ViewModel vm,
    Set<String> hidden,
    StackedHistory visible,
    double height,
  ) {
    final ids = visible.ids;
    final values = [
      for (final b in visible.buckets) [for (final id in ids) b[id] ?? 0.0],
    ];
    final showTime = axisShowsTime(vm.starts, vm.bucket);
    String xLabel(int i) {
      final t = vm.starts[i];
      return showTime ? '${two(t.hour)}:00' : l.monthDay(t.month, t.day);
    }

    ChartTooltip tooltip(int i) {
      final bucket = visible.buckets[i];
      final sorted = [
        for (final id in ids)
          if ((bucket[id] ?? 0) > 0) id,
      ]..sort((a, b) => bucket[b]!.compareTo(bucket[a]!));
      const maxRows = 8;
      final rows = <ChartTooltipRow>[];
      var rest = 0.0;
      for (var k = 0; k < sorted.length; k++) {
        final id = sorted[k];
        if (k < maxRows - 1 || sorted.length <= maxRows) {
          rows.add(
            ChartTooltipRow(
              color: _color(vm, id),
              label: _label(l, view, id),
              value: _value(view, id, bucket[id]!),
            ),
          );
        } else {
          rest += bucket[id]!;
        }
      }
      if (rest > 0) {
        rows.add(
          ChartTooltipRow(
            color: seriesOtherColor,
            label: l.seriesOther,
            value: _value(view, ids.first, rest),
          ),
        );
      }
      return ChartTooltip(
        title: _bucketTitle(l, vm.starts[i], vm.bucket),
        totalLabel: l.historyTotal,
        total: _value(view, ids.first, visible.bucketTotal(i)),
        rows: rows,
      );
    }

    final sortedHidden = hidden.toList()..sort();
    return StackedBarChart(
      starts: vm.starts,
      bucket: vm.bucket,
      values: values,
      colors: [for (final id in ids) _color(vm, id)],
      axisLabel: (v) => _axis(view, ids, v),
      xLabel: xLabel,
      tooltipFor: tooltip,
      height: height,
      animationKey:
          '${_key(view)}|${sortedHidden.join(',')}|${widget.range.inMinutes}|${vm.hashCode}',
    );
  }

  Widget _summary(
    AppLocalizations l,
    HistoryView view,
    _ViewModel vm,
    StackedHistory visible,
    bool compact,
  ) {
    return _SummaryList(
      compact: compact,
      totalLabel: l.historyTotal,
      total: _value(view, visible.ids.first, visible.grandTotal),
      rows: [
        for (final id in visible.ids)
          _SummaryRowData(
            label: _label(l, view, id),
            color: _color(vm, id),
            value: _value(view, id, visible.totals[id]!),
            share: visible.share(id),
          ),
      ],
    );
  }

  Widget _footnote(AppLocalizations l, HistoryView view) {
    final text = switch (view) {
      HistoryView.quota => l.usageNote,
      HistoryView.models => l.modelNote(_modelSource(l)),
      HistoryView.spend => null,
    };
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// Friendly placeholder: icon, headline and an optional explanation.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.body, this.height = 200});

  final String title;
  final String? body;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      height: height,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bar_chart_rounded, size: 28, color: muted),
              ),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
              if (body != null) ...[
                const SizedBox(height: 4),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Toggle chip: color dot + name; tapping shows / hides the series.
class _LegendChip extends StatelessWidget {
  const _LegendChip({
    super.key,
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? color.withValues(alpha: 0.5) : scheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? color : Colors.transparent,
                      border: Border.all(color: active ? color : scheme.outline, width: 1.2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRowData {
  const _SummaryRowData({
    required this.label,
    required this.color,
    required this.value,
    required this.share,
  });

  final String label;
  final Color color;
  final String value;

  /// 0-100.
  final double share;
}

/// Total line plus one row per series: dot, name, share bar, value, share %.
class _SummaryList extends StatelessWidget {
  const _SummaryList({
    required this.rows,
    required this.total,
    required this.totalLabel,
    required this.compact,
  });

  final List<_SummaryRowData> rows;
  final String total;
  final String totalLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const figures = [FontFeature.tabularFigures()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  totalLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Text(total, style: theme.textTheme.titleSmall?.copyWith(fontFeatures: figures)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: compact ? _compactRow(theme, r) : _wideRow(theme, r),
          ),
      ],
    );
  }

  Widget _dot(_SummaryRowData r) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: r.color, borderRadius: BorderRadius.circular(3)),
  );

  Widget _name(ThemeData theme, _SummaryRowData r) => Tooltip(
    message: r.label,
    waitDuration: const Duration(milliseconds: 500),
    child: Text(
      r.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium,
    ),
  );

  Widget _valueText(ThemeData theme, _SummaryRowData r) => Text(
    r.value,
    textAlign: TextAlign.right,
    maxLines: 1,
    style: theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _shareText(ThemeData theme, _SummaryRowData r) => Text(
    formatPercent(r.share),
    textAlign: TextAlign.right,
    maxLines: 1,
    style: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _bar(ThemeData theme, _SummaryRowData r) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      height: 6,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
          ),
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (r.share / 100).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, f, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: f,
                  // Align gives loose constraints and a child-less DecoratedBox
                  // shrinks to nothing, so the height has to be forced.
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: r.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _wideRow(ThemeData theme, _SummaryRowData r) => Row(
    children: [
      _dot(r),
      const SizedBox(width: 10),
      SizedBox(width: 170, child: _name(theme, r)),
      const SizedBox(width: 12),
      Expanded(child: _bar(theme, r)),
      const SizedBox(width: 14),
      SizedBox(width: 78, child: _valueText(theme, r)),
      SizedBox(width: 56, child: _shareText(theme, r)),
    ],
  );

  Widget _compactRow(ThemeData theme, _SummaryRowData r) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          _dot(r),
          const SizedBox(width: 10),
          Expanded(child: _name(theme, r)),
          const SizedBox(width: 10),
          _valueText(theme, r),
          SizedBox(width: 50, child: _shareText(theme, r)),
        ],
      ),
      const SizedBox(height: 6),
      Padding(padding: const EdgeInsets.only(left: 20), child: _bar(theme, r)),
    ],
  );
}

/// Placeholder shown while history and model usage load: soft bars + a thin progress line.
class HistorySkeleton extends StatelessWidget {
  const HistorySkeleton({super.key, this.height = 260});

  final double height;

  static const _heights = [0.35, 0.55, 0.4, 0.7, 0.5, 0.85, 0.45, 0.6, 0.3, 0.75, 0.5, 0.65];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = scheme.onSurface.withValues(alpha: 0.06);
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            // Own layer: the indeterminate bar repaints every frame and must not drag
            // the surrounding glass card (and page) along with it.
            child: const RepaintBoundary(child: LinearProgressIndicator(minHeight: 2)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final w in const [70.0, 90.0, 80.0]) ...[
                Container(
                  width: w,
                  height: 26,
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(999)),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final f in _heights)
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: f,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 22),
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
