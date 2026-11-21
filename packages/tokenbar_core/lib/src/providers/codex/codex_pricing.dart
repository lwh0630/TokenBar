/// API-equivalent price estimates for Codex session tokens.
///
/// The table is copied from CodexBar's bundled `CostUsagePricing.codex` (and
/// `codexHistoricalPricing`) in
/// `third_party/CodexBar/Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift`.
/// Models that are not listed get no price (`null`) — nothing is invented. These are public
/// API list prices, not what a ChatGPT subscription is charged. Fast / priority-tier
/// multipliers and cache-write rates are not applied (the session logs do not let us tell
/// them apart reliably), so the estimate is the Standard rate.
library;

/// USD per token for one model. `*Long` rates apply to a whole request whose input exceeds
/// [thresholdTokens].
class CodexPrice {
  const CodexPrice({
    required this.input,
    required this.output,
    this.cachedInput,
    this.thresholdTokens,
    this.inputLong,
    this.outputLong,
    this.cachedInputLong,
  });

  /// Long-context pricing as CodexBar's `longContextPricing`: input and cached input are
  /// doubled above 272K input tokens, output uses [outputLong].
  const CodexPrice.longContext({
    required double input,
    double? cached,
    required double output,
    required double outputLong,
  }) : this(
         input: input,
         output: output,
         cachedInput: cached,
         thresholdTokens: 272000,
         inputLong: input * 2,
         outputLong: outputLong,
         cachedInputLong: cached == null ? null : cached * 2,
       );

  final double input;
  final double output;
  final double? cachedInput;
  final int? thresholdTokens;
  final double? inputLong;
  final double? outputLong;
  final double? cachedInputLong;

  /// CodexBar's `codexCostUSD`: `input` is the whole prompt with cached reads as a subset.
  double costUsd({required int input, required int cached, required int output}) {
    final totalInput = input < 0 ? 0 : input;
    final cachedTokens = cached.clamp(0, totalInput);
    final nonCached = totalInput - cachedTokens;
    final threshold = thresholdTokens;
    final long = threshold != null && totalInput > threshold;
    final inputRate = long ? (inputLong ?? this.input) : this.input;
    final cachedRate = long
        ? (cachedInputLong ?? cachedInput ?? inputRate)
        : (cachedInput ?? this.input);
    final outputRate = long ? (outputLong ?? this.output) : this.output;
    return nonCached * inputRate +
        cachedTokens * cachedRate +
        (output < 0 ? 0 : output) * outputRate;
  }
}

const _codexPrices = <String, CodexPrice>{
  'gpt-5': CodexPrice(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
  'gpt-5-codex': CodexPrice(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
  'gpt-5-mini': CodexPrice(input: 2.5e-7, output: 2e-6, cachedInput: 2.5e-8),
  'gpt-5-nano': CodexPrice(input: 5e-8, output: 4e-7, cachedInput: 5e-9),
  'gpt-5-pro': CodexPrice(input: 1.5e-5, output: 1.2e-4),
  'gpt-5.1': CodexPrice(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
  'gpt-5.1-codex': CodexPrice(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
  'gpt-5.1-codex-max': CodexPrice(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
  'gpt-5.1-codex-mini': CodexPrice(input: 2.5e-7, output: 2e-6, cachedInput: 2.5e-8),
  'gpt-5.2': CodexPrice(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
  'gpt-5.2-codex': CodexPrice(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
  'gpt-5.2-pro': CodexPrice(input: 2.1e-5, output: 1.68e-4),
  'gpt-5.3-codex': CodexPrice(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
  // Research preview: CodexBar prices it at zero.
  'gpt-5.3-codex-spark': CodexPrice(input: 0, output: 0, cachedInput: 0),
  'gpt-5.4': CodexPrice.longContext(
    input: 2.5e-6,
    cached: 2.5e-7,
    output: 1.5e-5,
    outputLong: 2.25e-5,
  ),
  'gpt-5.4-mini': CodexPrice(input: 7.5e-7, output: 4.5e-6, cachedInput: 7.5e-8),
  'gpt-5.4-nano': CodexPrice(input: 2e-7, output: 1.25e-6, cachedInput: 2e-8),
  'gpt-5.4-pro': CodexPrice.longContext(input: 3e-5, output: 1.8e-4, outputLong: 2.7e-4),
  'gpt-5.5': CodexPrice.longContext(input: 5e-6, cached: 5e-7, output: 3e-5, outputLong: 4.5e-5),
  'gpt-5.5-pro': CodexPrice.longContext(input: 3e-5, output: 1.8e-4, outputLong: 2.7e-4),
  'gpt-6-astra': CodexPrice.longContext(
    input: 1e-5,
    cached: 1e-6,
    output: 5e-5,
    outputLong: 7.5e-5,
  ),
  'gpt-6.1-sol': CodexPrice.longContext(
    input: 2e-6,
    cached: 1e-7,
    output: 1e-5,
    outputLong: 1.5e-5,
  ),
  'gpt-6-sol': CodexPrice.longContext(input: 2e-6, cached: 2e-7, output: 1e-5, outputLong: 1.5e-5),
  'gpt-6.1-terra': CodexPrice.longContext(
    input: 1e-6,
    cached: 5e-8,
    output: 5e-6,
    outputLong: 7.5e-6,
  ),
  'gpt-6.2-astra': CodexPrice.longContext(
    input: 8e-6,
    cached: 4e-7,
    output: 4e-5,
    outputLong: 6e-5,
  ),
  'gpt-6.2-sol': CodexPrice.longContext(
    input: 2e-6,
    cached: 1e-7,
    output: 1e-5,
    outputLong: 1.5e-5,
  ),
  'gpt-6-luna': CodexPrice.longContext(input: 1e-7, cached: 1e-8, output: 5e-7, outputLong: 7.5e-7),
  // Sol was repriced from $5/$30 to $4/$20 on 2026-08-21 (see [_historicalCodexPrices]).
  'gpt-5.6-sol': CodexPrice.longContext(input: 4e-6, cached: 4e-7, output: 2e-5, outputLong: 3e-5),
  'gpt-5.6-terra': CodexPrice.longContext(
    input: 2e-6,
    cached: 2e-7,
    output: 1.2e-5,
    outputLong: 1.8e-5,
  ),
  'gpt-5.6-luna': CodexPrice.longContext(
    input: 2e-7,
    cached: 2e-8,
    output: 1.2e-6,
    outputLong: 1.8e-6,
  ),
  'gpt-5.6-cyber': CodexPrice(input: 1.25e-5, output: 7.5e-5, cachedInput: 1.25e-6),
  'gpt-5.5-cyber': CodexPrice(input: 1.25e-5, output: 7.5e-5, cachedInput: 1.25e-6),
};

/// Rates in force before a repricing: usage dated before `cutoff` uses `price`.
final _historicalCodexPrices = <String, ({DateTime cutoff, CodexPrice price})>{
  // 2026-08-21 UTC (Unix 1787270400).
  'gpt-5.6-sol': (
    cutoff: DateTime.fromMillisecondsSinceEpoch(1787270400 * 1000, isUtc: true),
    price: CodexPrice.longContext(input: 5e-6, cached: 5e-7, output: 3e-5, outputLong: 4.5e-5),
  ),
  // 2026-07-30 UTC (Unix 1785369600).
  'gpt-5.6-terra': (
    cutoff: DateTime.fromMillisecondsSinceEpoch(1785369600 * 1000, isUtc: true),
    price: CodexPrice.longContext(
      input: 2.5e-6,
      cached: 2.5e-7,
      output: 1.5e-5,
      outputLong: 2.25e-5,
    ),
  ),
  'gpt-5.6-luna': (
    cutoff: DateTime.fromMillisecondsSinceEpoch(1785369600 * 1000, isUtc: true),
    price: CodexPrice.longContext(input: 1e-6, cached: 1e-7, output: 6e-6, outputLong: 9e-6),
  ),
};

/// CodexBar's `CostUsagePricing.normalizeCodexModel`: strips `openai/`, maps the
/// `gpt-5.6` / `gpt-reserve` / Daybreak aliases and drops a trailing `-YYYY-MM-DD`.
String normalizeCodexModel(String raw) {
  var model = raw.trim();
  if (model.startsWith('openai/')) model = model.substring('openai/'.length);
  switch (model) {
    case 'gpt-5.6':
    case 'gpt-daybreak-blue-latest':
      return 'gpt-5.6-sol';
    case 'gpt-reserve':
      return 'gpt-5.6-luna';
    case 'gpt-daybreak-red-latest':
      return 'gpt-5.6-cyber';
  }
  if (_codexPrices.containsKey(model)) return model;
  final dated = RegExp(r'-\d{4}-\d{2}-\d{2}$').firstMatch(model);
  if (dated != null) {
    final base = model.substring(0, dated.start);
    if (_codexPrices.containsKey(base)) return base;
  }
  return model;
}

/// Price of [model] for usage dated [at], or null when CodexBar has no price for it.
CodexPrice? codexPriceFor(String model, DateTime at) {
  final key = normalizeCodexModel(model);
  final historical = _historicalCodexPrices[key];
  if (historical != null && at.toUtc().isBefore(historical.cutoff)) return historical.price;
  return _codexPrices[key];
}

/// Estimated API-equivalent cost of one request's token deltas, or null for unpriced models.
double? codexCostUsd(
  String model,
  DateTime at, {
  required int input,
  required int cached,
  required int output,
}) => codexPriceFor(model, at)?.costUsd(input: input, cached: cached, output: output);
