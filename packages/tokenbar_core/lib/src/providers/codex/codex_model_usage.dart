import '../../models/model_usage.dart';
import '../../platform/platform.dart' as platform;
import '../model_usage_buckets.dart';
import 'codex_pricing.dart';
import 'codex_session_parser.dart';

/// How far back a session file may have started and still receive new events. CodexBar's
/// `codexActiveSessionLookbackDays` (a resumed session appends to its original file, which
/// lives in the partition of the day it started).
const codexSessionLookbackDays = 30;

/// Session files that can contain events in `[from, to]`, read-only.
///
/// Layout (CodexBar `CostUsageScanner.codexSessionsRoots` / `listCodexSessionFiles`):
/// * `<home>/sessions/YYYY/MM/DD/*.jsonl` — day partitions (local date);
///   partitions outside `[from - 30 days, to + 1 day]` are skipped without listing them;
/// * `*.jsonl` placed directly in `<home>/sessions/` (legacy flat layout);
/// * `<home>/archived_sessions/*.jsonl` — flat, included like CodexBar does.
///
/// A file whose modification time is before [from] cannot contain events in range and is
/// skipped. An archived file with the same name as an active one counts once.
/// Returns null when neither directory exists.
Future<List<String>?> listCodexSessionFiles(String home, DateTime from, DateTime to) async {
  final sessionsRoot = platform.joinPath(home, 'sessions');
  final archivedRoot = platform.joinPath(home, 'archived_sessions');
  final sessionsTop = await platform.listDirectory(sessionsRoot);
  final archivedTop = await platform.listDirectory(archivedRoot);
  if (sessionsTop.isEmpty && archivedTop.isEmpty) return null;

  final earliest = from.toLocal().subtract(const Duration(days: codexSessionLookbackDays));
  final latest = to.toLocal().add(const Duration(days: 1));
  final files = <String>[];
  final names = <String>{};

  bool wanted(platform.LocalFileEntry file) {
    if (!file.name.toLowerCase().endsWith('.jsonl')) return false;
    final modified = file.modified;
    return modified != null && !modified.isBefore(from);
  }

  void take(platform.LocalFileEntry file) {
    if (wanted(file) && names.add(file.name)) files.add(file.path);
  }

  bool overlaps(DateTime start, DateTime end) => end.isAfter(earliest) && !start.isAfter(latest);

  for (final entry in sessionsTop) {
    if (!entry.isDirectory) {
      take(entry);
      continue;
    }
    final year = _partition(entry.name, 4);
    if (year == null || !overlaps(DateTime(year), DateTime(year + 1))) continue;
    for (final monthDir in await platform.listDirectory(entry.path)) {
      final month = _partition(monthDir.name, 2);
      if (!monthDir.isDirectory || month == null || month < 1 || month > 12) continue;
      if (!overlaps(DateTime(year, month), DateTime(year, month + 1))) continue;
      for (final dayDir in await platform.listDirectory(monthDir.path)) {
        final day = _partition(dayDir.name, 2);
        if (!dayDir.isDirectory || day == null || day < 1 || day > 31) continue;
        if (!overlaps(DateTime(year, month, day), DateTime(year, month, day + 1))) continue;
        for (final file in await platform.listDirectory(dayDir.path)) {
          if (!file.isDirectory) take(file);
        }
      }
    }
  }
  for (final entry in archivedTop) {
    if (!entry.isDirectory) take(entry);
  }
  return files;
}

int? _partition(String name, int length) =>
    name.length == length && RegExp(r'^\d+$').hasMatch(name) ? int.parse(name) : null;

/// Per-model token usage from the local Codex session logs over `[from, to]`.
///
/// Streams every candidate file line by line (never the whole file in memory), keeps only
/// the numbers and the model name, and aggregates per time bucket × model. `costUsd` is an
/// API-equivalent estimate from CodexBar's price table ([codexCostUsd]) and stays null for
/// models without a known price. Returns null when no Codex log directory exists.
Future<ModelUsageSeries?> loadCodexModelUsage(String home, DateTime from, DateTime to) async {
  final files = await listCodexSessionFiles(home, from, to);
  if (files == null) return null;
  final aggregator = ModelUsageAggregator(from: from, to: to);
  for (final path in files) {
    try {
      await collectCodexFileUsage(platform.readLines(path), (delta) {
        aggregator.add(
          delta.time,
          delta.model,
          tokens: delta.tokens.toDouble(),
          costUsd: codexCostUsd(
            delta.model,
            delta.time,
            input: delta.input,
            cached: delta.cached,
            output: delta.output,
          ),
        );
      });
    } catch (_) {
      // A file that vanishes or becomes unreadable mid-scan only drops its own events.
      continue;
    }
  }
  return aggregator.build(source: 'codex-logs');
}

/// [loadCodexModelUsage] on a background isolate (the app calls this one): scanning a month
/// of session logs decodes a lot of JSON and would otherwise stall the UI thread. Only plain
/// values cross the isolate boundary.
Future<ModelUsageSeries?> loadCodexModelUsageInBackground(
  String home,
  DateTime from,
  DateTime to,
) => platform.runInBackground(() => loadCodexModelUsage(home, from, to));

/// Runs [lines] of one session file through a [CodexSessionParser] and reports each delta.
Future<void> collectCodexFileUsage(
  Stream<String> lines,
  void Function(CodexTokenDelta delta) onDelta,
) async {
  final parser = CodexSessionParser();
  await for (final line in lines) {
    final delta = parser.addLine(line);
    if (delta != null) onDelta(delta);
  }
}
