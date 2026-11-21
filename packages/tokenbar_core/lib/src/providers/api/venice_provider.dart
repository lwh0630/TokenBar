import '../../models/account.dart';
import '../../models/rate_window.dart';
import '../../models/usage_snapshot.dart';
import '../../util/json_utils.dart';
import '../common.dart';
import '../fields.dart';
import '../http_support.dart';
import '../provider.dart';

/// Venice `/billing/balance` -> one window describing what can still be spent.
({RateWindow window, String text}) parseVeniceBalance(Map<String, Object?> json) {
  final canConsume = json['canConsume'];
  final balances = asMap(json['balances']);
  if (canConsume is! bool || balances == null) throw ProviderException('Venice 返回数据格式无法识别');
  final currency = asString(json['consumptionCurrency'])?.toUpperCase();
  final diem = asDouble(balances['diem']);
  final usd = asDouble(balances['usd']);
  final allocation = asDouble(json['diemEpochAllocation']);
  RateWindow w(double used) => quotaWindow('venice-balance', '余额', usedPercent: used);
  String f(double v) => v.toStringAsFixed(2);
  if (!canConsume) {
    // Blocked for API calls, but the API still reports the balance: show it
    // (CodexBar venice.js) rather than a generic message.
    final knownUsd = usd != null && (currency == 'USD' || diem == null);
    return (
      window: w(100),
      text: knownUsd
          ? '\$${f(usd)} USD（API 调用已被限制）'
          : diem != null
          ? 'DIEM ${f(diem)}（API 调用已被限制）'
          : '余额暂不可用于 API 调用',
    );
  }
  if (currency == 'USD' && (usd ?? 0) > 0) return (window: w(0), text: '\$${f(usd!)} USD 剩余');
  if (currency != 'USD' && diem != null && (allocation ?? 0) > 0) {
    return (
      window: w(((allocation! - diem) / allocation * 100).clamp(0, 100).toDouble()),
      text: 'DIEM ${f(diem)} / ${f(allocation)}（本周期分配）',
    );
  }
  if ((diem ?? 0) > 0) return (window: w(0), text: 'DIEM ${f(diem!)} 剩余');
  if ((usd ?? 0) > 0) return (window: w(0), text: '\$${f(usd!)} USD 剩余');
  return (window: w(100), text: '没有可用的 Venice API 余额');
}

class VeniceProvider extends UsageProvider {
  @override
  String get id => 'venice';

  @override
  String get displayName => 'Venice';

  @override
  int get brandColor => 0xFF3C8FDD;

  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];

  @override
  String get setupHint => 'venice.ai 的 API Key，查询 DIEM / USD 余额。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(envVars: ['VENICE_API_KEY', 'VENICE_KEY']),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final key = FieldValues.of(this, account).secret;
    final result = parseVeniceBalance(
      await fetchJsonObject(
        ctx,
        displayName,
        Uri.parse('https://api.venice.ai/api/v1/billing/balance'),
        headers: {'Authorization': 'Bearer ${bareToken(key)}'},
      ),
    );
    return snapshot(
      account,
      ctx,
      source: 'api-key',
      windows: [result.window],
      extras: {'余额': result.text},
    );
  }
}
