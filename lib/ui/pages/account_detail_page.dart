import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

import '../../app/design/glass.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../widgets/history_chart.dart';
import '../widgets/provider_badge.dart';
import '../widgets/quota_ring.dart';
import '../widgets/window_row.dart';

class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({super.key, required this.accountId});

  final String accountId;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  /// Range id → window length. Labels come from [_rangeLabel].
  static const _ranges = {
    'day': Duration(hours: 24),
    'week': Duration(days: 7),
    'month': Duration(days: 30),
  };
  String _range = 'week';
  Future<_ChartData>? _history;
  DateTime? _loadedFor;

  static String _rangeLabel(AppLocalizations l, String id) => switch (id) {
    'day' => l.rangeDay,
    'month' => l.rangeMonth,
    _ => l.rangeWeek,
  };

  void _load(AppController c) {
    _loadedFor = c.lastRefresh;
    _history = _fetch(c, DateTime.now().subtract(_ranges[_range]!));
  }

  /// Quota history and per-model usage for the same range, loaded together.
  /// Per-model usage failing only hides the model view; history errors surface.
  Future<_ChartData> _fetch(AppController c, DateTime since) async {
    Future<ModelUsageSeries?> models() async {
      try {
        return await c.modelUsage(widget.accountId, since);
      } catch (_) {
        return null;
      }
    }

    final pending = models();
    final points = await c.history(widget.accountId, since);
    return _ChartData(points, await pending);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<AppController>();
    if (_history == null || _loadedFor != c.lastRefresh) _load(c);
    final s =
        c.snapshots.where((x) => x.accountId == widget.accountId).firstOrNull ??
        c.snapshot(widget.accountId);
    final theme = Theme.of(context);

    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.accountNotFound)),
      );
    }
    final provider = ProviderRegistry.instance.byId(s.providerId);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ProviderBadge(providerId: s.providerId, size: 28),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                s.accountLabel ?? provider?.displayName ?? s.providerId,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: c.refreshing ? null : c.refresh,
            icon: const Icon(Icons.refresh),
            tooltip: l.refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: c.now,
        builder: (context, now, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (s.windows.isNotEmpty)
                      GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                          child: Wrap(
                            alignment: WrapAlignment.spaceEvenly,
                            spacing: 24,
                            runSpacing: 20,
                            children: [
                              for (final w in s.windows.take(4))
                                QuotaRing(
                                  remaining: w.remainingPercent,
                                  label: windowLabel(l, w),
                                  caption: w.resetsAt == null
                                      ? null
                                      : resetsInLabel(l, w.timeUntilReset(now)!),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    if (s.windows.isNotEmpty)
                      GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.allQuotas, style: theme.textTheme.titleMedium),
                              const SizedBox(height: 12),
                              for (final w in s.windows) ...[
                                WindowRow(window: w, now: now),
                                _Projection(window: w, now: now),
                                const SizedBox(height: 14),
                              ],
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(l.usageHistory, style: theme.textTheme.titleMedium),
                                ),
                                SegmentedButton<String>(
                                  segments: [
                                    for (final r in _ranges.keys)
                                      ButtonSegment(value: r, label: Text(_rangeLabel(l, r))),
                                  ],
                                  selected: {_range},
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                  onSelectionChanged: (v) => setState(() {
                                    _range = v.first;
                                    _load(c);
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            FutureBuilder<_ChartData>(
                              future: _history,
                              builder: (context, snap) {
                                if (snap.connectionState != ConnectionState.done) {
                                  return const HistorySkeleton();
                                }
                                if (snap.hasError) {
                                  return SizedBox(
                                    height: 120,
                                    child: Center(
                                      child: Text(l.historyLoadFailed('${snap.error}')),
                                    ),
                                  );
                                }
                                return HistoryChart(
                                  points: snap.data?.points ?? const [],
                                  modelUsage: snap.data?.models,
                                  range: _ranges[_range]!,
                                  windowLabels: {
                                    for (final w in s.windows) w.id: windowLabel(l, w),
                                  },
                                  credits: {for (final c in s.credits) c.id: c},
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GlassCard(
                      child: Column(
                        children: [
                          _info(context, l.infoService, provider?.displayName ?? s.providerId),
                          if (s.plan != null) _info(context, l.infoPlan, planLabel(s.plan)),
                          if (s.email != null) _info(context, l.infoAccount, s.email!),
                          if (s.source != null)
                            _info(context, l.infoSource, sourceLabel(l, s.source)),
                          if (s.origin != null) _info(context, l.infoDevice, s.origin!),
                          _info(
                            context,
                            l.infoUpdatedAt,
                            l.timeWithAgo(
                              resetTimeLabel(l, s.fetchedAt, now),
                              agoLabel(l, s.fetchedAt, now),
                            ),
                          ),
                          for (final c in s.credits)
                            _info(context, creditsLabel(l, c), creditsValue(l, c)),
                          for (final e in s.extras.entries) _info(context, e.key, e.value),
                          if (s.error != null)
                            _info(
                              context,
                              l.infoLastError,
                              [s.error, s.errorHint].whereType<String>().join('\n'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(BuildContext context, String label, String value) => ListTile(
    dense: true,
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SelectableText(
        value,
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class _ChartData {
  const _ChartData(this.points, this.models);

  final List<UsagePoint> points;
  final ModelUsageSeries? models;
}

class _Projection extends StatelessWidget {
  const _Projection({required this.window, required this.now});

  final RateWindow window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final projected = window.projectedUsedAtReset(now);
    final elapsed = window.elapsedFraction(now);
    if (projected == null || elapsed == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    String text;
    if (projected >= 100 && window.usedClamped < 100) {
      // Time at which the window runs out at the current average rate.
      final total = Duration(minutes: window.windowMinutes!);
      final elapsedTime = total * elapsed;
      final rate = window.usedClamped / elapsedTime.inSeconds;
      final secondsLeft = ((100 - window.usedClamped) / rate).round();
      text = l.projectionRunsOut(countdownLabel(l, Duration(seconds: secondsLeft)));
    } else if (window.usedClamped >= 100) {
      text = l.exhaustedWaitingReset;
    } else {
      text = l.projectedAtReset(formatPercent(projected));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
