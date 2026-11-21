import '../../models/account.dart';
import '../../models/usage_snapshot.dart';
import '../../util/json_utils.dart';
import '../common.dart';
import '../fields.dart';
import '../http_support.dart';
import '../provider.dart';

// Read-only balance / key-limit services: one bearer GET on a fixed origin, no
// inference request, no inferred reset dates. Endpoints and response shapes come
// from CodexBar's bundled plugins (abliteration.ts, trustedrouter.ts, tripo.ts,
// siliconflow.ts), which fail closed on missing or malformed amounts — so do we.

abstract class _BalanceProvider extends UsageProvider {
  List<String> get keyEnv;

  @override
  List<SourceType> get supportedSources => const [SourceType.apiKey];

  @override
  List<ProviderField> get fields => [ProviderField.apiKey(envVars: keyEnv)];

  String key(AccountConfig account) => bareToken(FieldValues.of(this, account).secret);
}

ProviderException _unrecognized(String provider) =>
    ProviderException('$provider 返回数据格式无法识别', hint: '接口可能已变更，请更新 TokenBar');

/// A finite non-negative number, else a parse failure.
double _amount(String provider, Object? v) {
  if (v is num && v.isFinite && v >= 0) return v.toDouble();
  throw _unrecognized(provider);
}

// ----------------------------------------------------------- abliteration.ai

UsageSnapshot parseAbliteration(UsageSnapshot base, Map<String, Object?> root) {
  const name = 'abliteration.ai';
  final data = asMap(root['data']) ?? (throw _unrecognized(name));
  final total = _amount(name, data['total_credits']);
  final used = _amount(name, data['total_usage']);
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    source: 'api-key',
    // Without a total there is nothing to take a percentage of; no reset is inferred.
    windows: [
      if (total > 0) quotaWindow('abliteration-credits', '额度', usedPercent: pct(used, total)),
    ],
    credits: [
      balanceRow(
        'abliteration-balance',
        (total - used).clamp(0, double.infinity).toDouble(),
        label: '余额',
      ),
    ],
    extras: {'已用': moneyText(used, 'USD'), '总额度': moneyText(total, 'USD')},
  );
}

class AbliterationProvider extends _BalanceProvider {
  @override
  String get id => 'abliteration';
  @override
  String get displayName => 'abliteration.ai';
  @override
  int get brandColor => 0xFF1B1B1B;
  @override
  List<String> get keyEnv => const ['ABLITERATION_API_KEY'];
  @override
  String get setupHint => 'abliteration.ai 的 API Key，查询预付 USD 额度与累计用量（只读，不会发起推理请求）。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('https://api.abliteration.ai/v1/credits'),
      headers: {'Authorization': 'Bearer ${key(account)}'},
      authHint: '检查 API Key 是否正确',
    );
    return parseAbliteration(snapshot(account, ctx), json);
  }
}

// ------------------------------------------------------------- TrustedRouter

/// Integer microdollars → USD; null stays null (an explicit `null` limit = unlimited).
double? _microdollars(Object? v, {bool nullable = false}) {
  if (v == null && nullable) return null;
  if (v is int && v >= 0 && v <= 9007199254740991) return v / 1000000;
  throw _unrecognized('TrustedRouter');
}

UsageSnapshot parseTrustedRouter(UsageSnapshot base, Map<String, Object?> root) {
  final data = asMap(root['data']) ?? (throw _unrecognized('TrustedRouter'));
  final total = _microdollars(data['usage_microdollars'])!;
  final daily = _microdollars(data['usage_daily_microdollars'])!;
  final weekly = _microdollars(data['usage_weekly_microdollars'])!;
  final monthly = _microdollars(data['usage_monthly_microdollars'])!;
  final limit = _microdollars(data['limit_microdollars'], nullable: true);
  final remaining = _microdollars(data['limit_remaining_microdollars'], nullable: true);
  // A limit without a remaining amount (or the reverse) cannot be trusted.
  if ((limit == null) != (remaining == null)) throw _unrecognized('TrustedRouter');
  // `limit_remaining` already excludes in-flight reservations: never recompute it from usage.
  final spent = limit == null ? 0.0 : (limit - remaining!).clamp(0, double.infinity).toDouble();
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    source: 'api-key',
    windows: [
      if (limit != null && limit > 0)
        quotaWindow('trustedrouter-key', 'Key 限额', usedPercent: pct(spent, limit)),
    ],
    credits: [
      if (remaining != null) balanceRow('trustedrouter-remaining', remaining, label: '剩余额度'),
      spendRow('trustedrouter-today', daily, label: '今日（UTC）'),
      spendRow('trustedrouter-month', monthly, label: '本月（UTC）'),
    ],
    extras: {
      if (limit != null) 'Key 限额': moneyText(limit, 'USD'),
      '本周（UTC）': moneyText(weekly, 'USD'),
      '累计': moneyText(total, 'USD'),
    },
  );
}

class TrustedRouterProvider extends _BalanceProvider {
  @override
  String get id => 'trustedrouter';
  @override
  String get displayName => 'TrustedRouter';
  @override
  int get brandColor => 0xFFA9CDB9;
  @override
  List<String> get keyEnv => const ['TRUSTEDROUTER_API_KEY'];
  @override
  String get setupHint => 'TrustedRouter 的推理 API Key，查询这个 Key 的剩余限额以及今日 / 本周 / 本月 / 累计花费。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('https://api.trustedrouter.com/v1/key'),
      headers: {'Authorization': 'Bearer ${key(account)}'},
      authHint: '检查 API Key 是否正确',
    );
    return parseTrustedRouter(snapshot(account, ctx), json);
  }
}

// --------------------------------------------------------------------- Tripo

UsageSnapshot parseTripo(UsageSnapshot base, Map<String, Object?> root) {
  final code = root['code'];
  if (code is! int) throw _unrecognized('Tripo');
  if (code != 0) throw ProviderException('Tripo 接口返回错误 (code $code)', hint: '稍后重试');
  final data = asMap(root['data']) ?? (throw _unrecognized('Tripo'));
  // `balance` is already the available amount: reservations are not subtracted again.
  final balance = _amount('Tripo', data['balance']);
  final frozen = _amount('Tripo', data['frozen']);
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    source: 'api-key',
    // Credits, not money: no currency, no inferred total or reset.
    credits: [balanceRow('tripo-balance', balance, label: '可用积分', currency: null)],
    extras: {'冻结积分': _trim(frozen)},
  );
}

String _trim(double v) {
  final text = v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  return text.endsWith('.') ? text.substring(0, text.length - 1) : text;
}

class TripoProvider extends _BalanceProvider {
  @override
  String get id => 'tripo';
  @override
  String get displayName => 'Tripo';
  @override
  int get brandColor => 0xFFF8CF00;
  @override
  List<String> get keyEnv => const ['TRIPO_API_KEY'];
  @override
  String get setupHint => 'Tripo（3D 生成）的 API Key，查询可用积分与任务冻结的积分（只读）。';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final json = await fetchJsonObject(
      ctx,
      displayName,
      Uri.parse('https://openapi.tripo3d.ai/v3/account/balance'),
      headers: {'Authorization': 'Bearer ${key(account)}'},
      authHint: '检查 API Key 是否正确',
    );
    return parseTripo(snapshot(account, ctx), json);
  }
}

// --------------------------------------------------------------- SiliconFlow

const _siliconFlowChinaRetired = 'SiliconFlow 国内站的余额接口已于 2026-08-14 下线（HTTP 410 / code 20092）';

/// Decimal amount as a JSON number or a plain numeric string.
double _siliconMoney(Object? v) {
  if (v is num && v.isFinite) return v.toDouble();
  if (v is String && RegExp(r'^-?(?:\d+|\d+\.\d+)$').hasMatch(v)) {
    final n = double.tryParse(v);
    if (n != null && n.isFinite) return n;
  }
  throw _unrecognized('SiliconFlow');
}

UsageSnapshot parseSiliconFlow(UsageSnapshot base, Map<String, Object?> root, String currency) {
  final code = root['code'];
  if (code is! int) throw _unrecognized('SiliconFlow');
  if (code == 20092) {
    throw ProviderException(
      _siliconFlowChinaRetired,
      hint: '国内站只能通过控制台页面查看余额；国际站（api.siliconflow.com）不受影响',
    );
  }
  if (code == 30014) {
    throw ProviderException('SiliconFlow 拒绝了凭证', hint: '检查 API Key 是否正确', statusCode: 401);
  }
  if (code != 20000 || root['status'] != true) throw _unrecognized('SiliconFlow');
  final data = asMap(root['data']) ?? (throw _unrecognized('SiliconFlow'));
  final total = _siliconMoney(data['totalBalance']);
  final charge = data['chargeBalance'];
  final bonus = data['balance'];
  final status = data['status'];
  if (status != null && (status is! String || !RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(status))) {
    throw _unrecognized('SiliconFlow');
  }
  return UsageSnapshot(
    accountId: base.accountId,
    providerId: base.providerId,
    fetchedAt: base.fetchedAt,
    source: 'api-key',
    credits: [balanceRow('siliconflow-balance', total, label: '余额', currency: currency)],
    extras: {
      if (charge != null) '充值余额': moneyText(_siliconMoney(charge), currency),
      if (bonus != null) '赠送余额': moneyText(_siliconMoney(bonus), currency),
      if (status != null && status != 'normal') '状态': status as String,
    },
  );
}

class SiliconFlowProvider extends _BalanceProvider {
  @override
  String get id => 'siliconflow';
  @override
  String get displayName => 'SiliconFlow';
  @override
  int get brandColor => 0xFF6E29F5;
  @override
  List<String> get keyEnv => const ['SILICONFLOW_API_KEY'];
  @override
  String get setupHint =>
      'SiliconFlow 国际站（api.siliconflow.com）的 API Key，查询 USD 余额。国内站的余额接口已下线，无法通过 API Key 查询。';

  @override
  List<ProviderField> get fields => const [
    ProviderField.apiKey(envVars: ['SILICONFLOW_API_KEY']),
    ProviderField(
      key: 'region',
      label: '区域',
      kind: FieldKind.choice,
      defaultValue: 'global',
      choices: [
        FieldChoice('global', '国际站 api.siliconflow.com（USD）'),
        FieldChoice('cn', '国内站 api.siliconflow.cn（CNY，接口已下线）'),
      ],
    ),
  ];

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    final v = FieldValues.of(this, account);
    final china = v['region'] == 'cn';
    final origin = china ? 'https://api.siliconflow.cn' : 'https://api.siliconflow.com';
    final result = await sendRequest(
      ctx,
      displayName,
      Uri.parse('$origin/v1/user/info'),
      headers: {'Authorization': 'Bearer ${bareToken(v.secret)}'},
    );
    if (result.statusCode == 410) {
      throw ProviderException(
        _siliconFlowChinaRetired,
        hint: '国内站只能通过控制台页面查看余额；国际站（api.siliconflow.com）不受影响',
        statusCode: 410,
      );
    }
    checkStatus(displayName, result, authHint: '检查 API Key 与所选区域是否一致');
    final root = asMap(result.json) ?? (throw _unrecognized(displayName));
    return parseSiliconFlow(snapshot(account, ctx), root, china ? 'CNY' : 'USD');
  }
}
