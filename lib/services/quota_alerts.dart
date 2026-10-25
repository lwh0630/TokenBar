import 'package:tokenbar_core/tokenbar_core.dart';

import '../l10n/app_localizations.dart';
import '../ui/format.dart';

class QuotaAlert {
  const QuotaAlert(this.key, this.title, this.body);

  final String key;
  final String title;
  final String body;
}

/// Pure decision logic: which notifications a new snapshot should trigger.
///
/// [state] maps `accountId|windowId` to the lowest threshold already
/// notified in the current window period (and the period's reset time), so
/// each threshold fires once per period.
class QuotaAlertEngine {
  QuotaAlertEngine(this.state);

  /// Reset times this close together belong to the same period. Providers that only report
  /// the seconds left until a reset (Factory, OpenCode Go, Notion, ...) give a reset time that
  /// moves by a fraction of a second on every fetch; that is not a new period.
  static const resetTolerance = Duration(minutes: 2);

  final Map<String, Object?> state;

  List<QuotaAlert> evaluate(
    UsageSnapshot s, {
    required List<int> thresholds,
    required bool notifyOnReset,
    required String providerName,
    required AppLocalizations l10n,
  }) {
    if (s.hasError) return const [];
    final alerts = <QuotaAlert>[];
    final sorted = [...thresholds]..sort();
    final name = s.accountLabel ?? providerName;
    for (final w in s.windows) {
      final key = '${s.accountId}|${w.id}';
      final entry = (state[key] as Map?)?.cast<String, Object?>() ?? {};
      final prevReset = entry['reset'] as String?;
      final prevRemaining = (entry['remaining'] as num?)?.toDouble();
      var notified = (entry['level'] as num?)?.toInt();
      final reset = w.resetsAt?.toUtc().toIso8601String();

      final newPeriod =
          prevReset != null &&
          reset != null &&
          DateTime.parse(reset).difference(DateTime.parse(prevReset)) > resetTolerance;
      if (newPeriod) {
        if (notifyOnReset &&
            prevRemaining != null &&
            prevRemaining < 50 &&
            w.remainingPercent > prevRemaining + 20) {
          alerts.add(
            QuotaAlert(
              '$key|reset',
              l10n.quotaResetTitle(name, windowLabel(l10n, w)),
              l10n.quotaResetBody(formatPercent(w.remainingPercent)),
            ),
          );
        }
        notified = null;
      }

      // The lowest threshold the window is currently below.
      int? level;
      for (final t in sorted) {
        if (w.remainingPercent <= t) {
          level = t;
          break;
        }
      }
      if (level != null && (notified == null || level < notified)) {
        final remaining = formatPercent(w.remainingPercent);
        final until = w.resetsAt?.difference(DateTime.now());
        final body = until == null || until.inSeconds <= 0
            ? l10n.lowQuotaBody(remaining)
            : l10n.lowQuotaBodyWithReset(remaining, countdownLabel(l10n, until));
        alerts.add(QuotaAlert('$key|$level', l10n.lowQuotaTitle(name, windowLabel(l10n, w)), body));
        notified = level;
      } else if (level == null) {
        notified = null;
      }

      state[key] = {'reset': ?reset, 'remaining': w.remainingPercent, 'level': ?notified};
    }
    return alerts;
  }
}
