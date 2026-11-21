import 'dart:async';

import 'package:http/http.dart' as http;

import '../../platform/process_types.dart';
import '../../util/json_utils.dart';
import '../http_support.dart';
import '../provider.dart';
import 'codex_credentials.dart';

class CodexResetCredit {
  const CodexResetCredit({
    required this.id,
    required this.expiresAt,
    this.title,
    required this.isAvailable,
    required this.isSupported,
  });

  final String id;
  final DateTime? expiresAt;
  final String? title;
  final bool isAvailable;
  final bool isSupported;

  bool isRedeemableAt(DateTime now) =>
      isAvailable && isSupported && (expiresAt?.isAfter(now) ?? true);
}

class CodexResetCredits {
  const CodexResetCredits({required this.availableCount, this.credits});

  final int availableCount;

  /// Null is a count-only response. The server may return fewer rows than [availableCount].
  final List<CodexResetCredit>? credits;
}

class CodexResetAccount {
  const CodexResetAccount({this.accountId, this.email, this.userId, this.summary});

  final String? accountId;
  final String? email;
  final String? userId;
  final CodexResetCredits? summary;

  bool get hasIdentity =>
      _nonBlankString(accountId) != null ||
      _nonBlankString(email) != null ||
      _nonBlankString(userId) != null;
}

enum CodexResetOutcome { reset, nothingToReset, noCredit, alreadyRedeemed }

enum CodexResetFailure {
  signedOut,
  unsupportedAccount,
  identityUnavailable,
  accountChanged,
  creditUnavailable,
  invalidRequest,
  unavailable,
  redemptionUncertain,
}

class CodexResetException implements Exception {
  const CodexResetException(this.failure, {this.retryAttempt});

  final CodexResetFailure failure;
  final CodexResetAttempt? retryAttempt;

  @override
  String toString() => 'CodexResetException: ${failure.name}';
}

/// A verified redemption with an unknown outcome. Keep it in memory until its outcome is known.
final class CodexResetAttempt {
  const CodexResetAttempt._(this._account, this._creditId, this._idempotencyKey);

  final CodexResetAccount _account;
  final String _creditId;
  final String _idempotencyKey;
}

const _requestTimeout = Duration(seconds: 15);
const _creditsPath = '/backend-api/wham/rate-limit-reset-credits';

/// Uses the same account-scoped OAuth routes as the official Codex backend client.
/// https://github.com/openai/codex/blob/1af47ac084303b7bab777394e8b704a21f8e73c1/codex-rs/backend-client/src/client/rate_limit_resets.rs
class CodexResetService {
  const CodexResetService({
    this.loadCredentials = readCodexCredentials,
    this.createClient = http.Client.new,
  });

  final Future<CodexCredentials?> Function(String home) loadCredentials;
  final FutureOr<http.Client> Function() createClient;

  Future<CodexResetAccount> read(String home) => _withLogin(home, _inventory);

  Future<CodexResetOutcome> redeem(
    String home, {
    required CodexResetAccount expectedAccount,
    required String creditId,
    required String idempotencyKey,
    CodexResetAttempt? retryAttempt,
  }) => _withLogin(
    home,
    (context, credentials) => _redeemVerifiedCredit(
      readAccount: () => _inventory(context, credentials),
      send: () async {
        final result = await _request(
          context,
          credentials,
          '$_creditsPath/consume',
          body: {'credit_id': creditId, 'redeem_request_id': idempotencyKey},
        );
        return switch (result['code']) {
          'reset' => CodexResetOutcome.reset,
          'nothing_to_reset' => CodexResetOutcome.nothingToReset,
          'no_credit' => CodexResetOutcome.noCredit,
          'already_redeemed' => CodexResetOutcome.alreadyRedeemed,
          _ => throw const CodexResetException(CodexResetFailure.unavailable),
        };
      },
      expectedAccount: expectedAccount,
      creditId: creditId,
      idempotencyKey: idempotencyKey,
      retryAttempt: retryAttempt,
    ),
  );

  Future<T> _withLogin<T>(
    String home,
    Future<T> Function(FetchContext, CodexCredentials) operation,
  ) async {
    final credentials = await loadCredentials(home);
    if (credentials == null || credentials.isExpired(DateTime.now())) {
      throw const CodexResetException(CodexResetFailure.signedOut);
    }
    if (credentials.isApiKey) {
      throw const CodexResetException(CodexResetFailure.unsupportedAccount);
    }
    final context = FetchContext(client: await createClient(), userAgent: 'TokenBar/0.1');
    try {
      return await operation(context, credentials);
    } finally {
      context.client.close();
    }
  }

  Future<CodexResetAccount> _inventory(FetchContext context, CodexCredentials credentials) async {
    CodexResetCredits? summary;
    try {
      final data = await _request(context, credentials, _creditsPath);
      summary = _parseResetCredits(data, fromHttp: true);
    } on CodexResetException catch (error) {
      if (error.failure != CodexResetFailure.unavailable) rethrow;
    }
    if (summary == null) {
      final usage = await _request(context, credentials, '/backend-api/wham/usage');
      final reportedAccount = asString(usage['account_id']);
      if (reportedAccount != null &&
          credentials.accountId != null &&
          reportedAccount != credentials.accountId) {
        throw const CodexResetException(CodexResetFailure.accountChanged);
      }
      summary = _parseResetCredits(usage['rate_limit_reset_credits'], fromHttp: true);
    }
    return CodexResetAccount(
      accountId: credentials.accountId,
      email: credentials.email,
      userId: asString(decodeJwtPayload(credentials.accessToken)?['sub']),
      summary: summary,
    );
  }

  Future<Map<String, Object?>> _request(
    FetchContext context,
    CodexCredentials credentials,
    String path, {
    Map<String, String>? body,
  }) async {
    final HttpResult result;
    try {
      result = await sendRequest(
        context,
        'Codex',
        Uri.https('chatgpt.com', path),
        method: body == null ? 'GET' : 'POST',
        headers: {
          'Authorization': 'Bearer ${credentials.accessToken}',
          'User-Agent': context.userAgent,
          if (credentials.accountId != null) 'ChatGPT-Account-Id': credentials.accountId!,
        },
        body: body,
        timeout: _requestTimeout,
        followRedirects: false,
      );
    } catch (_) {
      throw const CodexResetException(CodexResetFailure.unavailable);
    }
    if (result.statusCode == 401) throw const CodexResetException(CodexResetFailure.signedOut);
    final data = result.ok ? asMap(result.json) : null;
    return data ?? (throw const CodexResetException(CodexResetFailure.unavailable));
  }
}

/// Reads the signed-in ChatGPT account and its earned reset inventory over initialized app-server
/// stdio. Older backends can return a count without details or omit the inventory altogether.
Future<CodexResetAccount> readCodexResetAccount(JsonRpcSession session) async {
  final accountResult = await _readResult(session, 'account/read', params: {'refreshToken': false});
  final account = asMap(accountResult['account']);
  if (accountResult['account'] == null) {
    throw const CodexResetException(CodexResetFailure.signedOut);
  }
  final accountType = account?['type'];
  if (accountType is! String) {
    throw const CodexResetException(CodexResetFailure.unavailable);
  }
  if (accountType != 'chatgpt') {
    throw const CodexResetException(CodexResetFailure.unsupportedAccount);
  }

  final limits = await _readResult(session, 'account/rateLimits/read');
  final workspaceRouting = asMap(accountResult['workspaceRouting']);
  final routedAccountId = _nonBlankString(workspaceRouting?['chatgptAccountId']);
  final usageAccountId = _nonBlankString(limits['accountId']);
  if (routedAccountId != null && usageAccountId != null && routedAccountId != usageAccountId) {
    throw const CodexResetException(CodexResetFailure.accountChanged);
  }
  return CodexResetAccount(
    accountId: usageAccountId ?? routedAccountId,
    email: _nonBlankString(account?['email']),
    userId: _nonBlankString(accountResult['userId']),
    summary: _parseResetCredits(limits['rateLimitResetCredits']),
  );
}

/// Consumes only the selected credit, after re-reading the account and inventory on [session].
/// Pass the same [idempotencyKey], [creditId] and returned [retryAttempt] when retrying an
/// uncertain redemption. A verified retry can recover an outcome after the credit disappears.
Future<CodexResetOutcome> redeemCodexResetCredit(
  JsonRpcSession session, {
  required CodexResetAccount expectedAccount,
  required String creditId,
  required String idempotencyKey,
  DateTime? now,
  CodexResetAttempt? retryAttempt,
}) => _redeemVerifiedCredit(
  readAccount: () => readCodexResetAccount(session),
  send: () async {
    final result = await session.request(
      'account/rateLimitResetCredit/consume',
      params: {'creditId': creditId, 'idempotencyKey': idempotencyKey},
      timeout: _requestTimeout,
    );
    return switch (asMap(result)?['outcome']) {
      'reset' => CodexResetOutcome.reset,
      'nothingToReset' => CodexResetOutcome.nothingToReset,
      'noCredit' => CodexResetOutcome.noCredit,
      'alreadyRedeemed' => CodexResetOutcome.alreadyRedeemed,
      _ => throw const CodexResetException(CodexResetFailure.unavailable),
    };
  },
  expectedAccount: expectedAccount,
  creditId: creditId,
  idempotencyKey: idempotencyKey,
  now: now,
  retryAttempt: retryAttempt,
);

Future<CodexResetOutcome> _redeemVerifiedCredit({
  required Future<CodexResetAccount> Function() readAccount,
  required Future<CodexResetOutcome> Function() send,
  required CodexResetAccount expectedAccount,
  required String creditId,
  required String idempotencyKey,
  DateTime? now,
  CodexResetAttempt? retryAttempt,
}) async {
  if (creditId.trim().isEmpty || idempotencyKey.trim().isEmpty) {
    throw const CodexResetException(CodexResetFailure.invalidRequest);
  }
  if (retryAttempt != null &&
      (retryAttempt._creditId != creditId || retryAttempt._idempotencyKey != idempotencyKey)) {
    throw const CodexResetException(CodexResetFailure.invalidRequest);
  }
  if (!expectedAccount.hasIdentity) {
    throw const CodexResetException(CodexResetFailure.identityUnavailable);
  }

  final currentAccount = await readAccount();
  if (!currentAccount.hasIdentity) {
    throw const CodexResetException(CodexResetFailure.identityUnavailable);
  }
  if (!_matchesAccount(expectedAccount, currentAccount) ||
      (retryAttempt != null && !_matchesAccount(retryAttempt._account, currentAccount))) {
    throw const CodexResetException(CodexResetFailure.accountChanged);
  }
  if (retryAttempt == null &&
      !_hasRedeemableCredit(currentAccount.summary, creditId, now ?? DateTime.now())) {
    throw const CodexResetException(CodexResetFailure.creditUnavailable);
  }

  final attempt = retryAttempt ?? CodexResetAttempt._(currentAccount, creditId, idempotencyKey);
  try {
    return await send();
  } catch (_) {
    throw CodexResetException(CodexResetFailure.redemptionUncertain, retryAttempt: attempt);
  }
}

bool _matchesAccount(CodexResetAccount expected, CodexResetAccount current) =>
    (expected.accountId == null || expected.accountId == current.accountId) &&
    (expected.email == null || expected.email == current.email) &&
    (expected.userId == null || expected.userId == current.userId);

bool _hasRedeemableCredit(CodexResetCredits? summary, String id, DateTime now) =>
    summary != null &&
    summary.availableCount > 0 &&
    (summary.credits?.any((credit) => credit.id == id && credit.isRedeemableAt(now)) ?? false);

Future<Map<String, Object?>> _readResult(
  JsonRpcSession session,
  String method, {
  Object? params,
}) async {
  final Object? result;
  try {
    result = await session.request(method, params: params, timeout: _requestTimeout);
  } catch (_) {
    throw const CodexResetException(CodexResetFailure.unavailable);
  }
  return asMap(result) ?? (throw const CodexResetException(CodexResetFailure.unavailable));
}

CodexResetCredits? _parseResetCredits(Object? rawSummary, {bool fromHttp = false}) {
  final summary = asMap(rawSummary);
  if (summary == null) return null;
  final count = summary[fromHttp ? 'available_count' : 'availableCount'];
  if (count is! int || count < 0) return null;

  final rawCredits = summary['credits'];
  final countOnly = CodexResetCredits(availableCount: count);
  if (rawCredits is! List) return countOnly;
  final credits = <CodexResetCredit>[];
  final ids = <String>{};
  for (final rawCredit in rawCredits) {
    final credit = _parseResetCredit(rawCredit, fromHttp: fromHttp);
    if (credit == null || !ids.add(credit.id)) return countOnly;
    credits.add(credit);
  }
  return CodexResetCredits(availableCount: count, credits: List.unmodifiable(credits));
}

CodexResetCredit? _parseResetCredit(Object? rawCredit, {required bool fromHttp}) {
  final data = asMap(rawCredit);
  if (data == null || (!fromHttp && !data.containsKey('expiresAt'))) return null;
  final id = _nonBlankString(data['id']);
  final type = _nonBlankString(data[fromHttp ? 'reset_type' : 'resetType']);
  final status = _nonBlankString(data['status']);
  if (id == null || type == null || status == null) return null;

  final rawExpiry = data[fromHttp ? 'expires_at' : 'expiresAt'];
  final expiry = switch (rawExpiry) {
    String text when fromHttp => DateTime.tryParse(text),
    int seconds when !fromHttp && seconds >= -8640000000000 && seconds <= 8640000000000 =>
      epochSeconds(seconds),
    _ => null,
  };
  if (rawExpiry != null && expiry?.isUtc != true) return null;
  return CodexResetCredit(
    id: id,
    expiresAt: expiry,
    title: asString(data['title']),
    isAvailable: status == 'available',
    isSupported: type == (fromHttp ? 'codex_rate_limits' : 'codexRateLimits'),
  );
}

String? _nonBlankString(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
