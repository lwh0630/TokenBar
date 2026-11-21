import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/src/platform/process_types.dart';
import 'package:tokenbar_core/src/providers/codex/codex_credentials.dart';
import 'package:tokenbar_core/src/providers/codex/codex_reset_credits.dart';

const _readAccount = 'account/read';
const _readLimits = 'account/rateLimits/read';
const _consume = 'account/rateLimitResetCredit/consume';
const _creditId = 'ResetCredit_1';
const _key = 'ac478270-25e1-4af7-a717-b91ebdce29b7';
final _now = DateTime.utc(2026, 11, 21);
final _futureExpiry = _now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
const _expected = CodexResetAccount(
  accountId: 'account-1',
  userId: 'user-1',
  email: 'reader@example.test',
);

void main() {
  group('CodexResetService', () {
    const listPath = '/backend-api/wham/rate-limit-reset-credits';
    const credentials = CodexCredentials(
      accessToken: 'synthetic-bearer',
      accountId: 'workspace-1',
      email: 'reader@example.test',
    );
    Map<String, Object?> inventory() => {
      'available_count': 3,
      'credits': [
        {
          'id': _creditId,
          'reset_type': 'codex_rate_limits',
          'status': 'available',
          'expires_at': '2099-11-22T08:00:00+08:00',
        },
        {'id': 'another-credit', 'reset_type': 'codex_rate_limits', 'status': 'available'},
      ],
    };

    test('reads expiry and confirms the selected credit for the current login', () async {
      var current = credentials;
      final requests = <http.Request>[];
      final service = CodexResetService(
        loadCredentials: (_) async => current,
        createClient: () => MockClient((request) async {
          requests.add(request);
          final payload = request.method == 'GET' ? inventory() : {'code': 'reset'};
          return http.Response(jsonEncode(payload), 200);
        }),
      );
      final account = await service.read('fake-home');
      final summary = account.summary!;
      expect(summary.availableCount, 3);
      expect(summary.credits!.first.expiresAt, DateTime.utc(2099, 11, 22));
      expect(summary.credits!.last.expiresAt, isNull);
      expect(
        await service.redeem(
          'fake-home',
          expectedAccount: account,
          creditId: _creditId,
          idempotencyKey: _key,
        ),
        CodexResetOutcome.reset,
      );
      expect(requests.map((request) => request.url.path), [
        listPath,
        listPath,
        '$listPath/consume',
      ]);
      expect(
        requests.every(
          (request) =>
              request.url.scheme == 'https' &&
              request.url.host == 'chatgpt.com' &&
              !request.followRedirects &&
              request.headers['authorization'] == 'Bearer synthetic-bearer' &&
              request.headers['chatgpt-account-id'] == 'workspace-1',
        ),
        isTrue,
      );
      expect(requests.last.method, 'POST');
      expect(requests.last.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(requests.last.body), {'credit_id': _creditId, 'redeem_request_id': _key});

      current = const CodexCredentials(
        accessToken: 'other-bearer',
        accountId: 'other-workspace',
        email: 'reader@example.test',
      );
      await expectLater(
        service.redeem(
          'fake-home',
          expectedAccount: account,
          creditId: _creditId,
          idempotencyKey: _key,
        ),
        throwsA(_failure(CodexResetFailure.accountChanged)),
      );
      expect(requests.where((request) => request.method == 'POST'), hasLength(1));
    });

    test('falls back to the usage count if the detail request is unavailable', () async {
      final service = CodexResetService(
        loadCredentials: (_) async => credentials,
        createClient: () => MockClient((request) async {
          if (request.url.path == listPath) return http.Response('', 503);
          expect(request.url, codexUsageUri(null));
          return http.Response('{"rate_limit_reset_credits":{"available_count":0}}', 200);
        }),
      );
      final summary = (await service.read('fake-home')).summary;
      expect(summary?.availableCount, 0);
      expect(summary?.credits, isNull);
    });
  });

  group('readCodexResetAccount', () {
    test('uses the authoritative count and decodes expiry in Unix seconds', () async {
      final session = _FakeSession([
        _account(),
        _limits(
          count: 4,
          credits: [
            _credit(expiresAt: _futureExpiry, title: 'Full reset'),
            _credit(id: 'ResetCredit_2'),
          ],
        ),
      ]);

      final account = await readCodexResetAccount(session);
      final summary = account.summary!;
      final credits = summary.credits!;
      expect(account.email, _expected.email);
      expect(account.userId, _expected.userId);
      expect(account.accountId, _expected.accountId);
      expect(summary.availableCount, 4);
      expect(credits.map((credit) => credit.id), [_creditId, 'ResetCredit_2']);
      expect(credits.first.expiresAt, _now.add(const Duration(days: 1)));
      expect(credits.first.title, 'Full reset');
      expect(credits.first.isAvailable, isTrue);
      expect(credits.first.isSupported, isTrue);
      expect(credits.last.expiresAt, isNull);
      expect(credits.last.isRedeemableAt(_now), isTrue);
      expect(session.methods, [_readAccount, _readLimits]);
      expect(session.requests.first.params, {'refreshToken': false});
    });

    test('distinguishes count-only, empty, and unavailable inventories', () async {
      final countOnly = await readCodexResetAccount(_FakeSession([_account(), _limits(count: 3)]));
      final empty = await readCodexResetAccount(
        _FakeSession([_account(), _limits(count: 0, credits: [])]),
      );
      final unavailable = await readCodexResetAccount(
        _FakeSession([
          _account(),
          {'rateLimits': <String, Object?>{}},
        ]),
      );

      expect(countOnly.summary!.availableCount, 3);
      expect(countOnly.summary!.credits, isNull);
      expect(empty.summary!.availableCount, 0);
      expect(empty.summary!.credits, isEmpty);
      expect(unavailable.summary, isNull);
    });

    test('keeps the count when a detail has an invalid expiration', () async {
      final session = _FakeSession([
        _account(),
        _limits(count: 1, credits: [_credit(expiresAt: 9223372036854775807)]),
      ]);

      final summary = (await readCodexResetAccount(session)).summary!;
      expect(summary.availableCount, 1);
      expect(summary.credits, isNull);
    });

    test('rejects a different workspace identity from the usage response', () async {
      final session = _FakeSession([
        {
          ..._account(),
          'workspaceRouting': {'chatgptAccountId': 'other-account'},
        },
        _limits(),
      ]);

      await expectLater(
        readCodexResetAccount(session),
        throwsA(_failure(CodexResetFailure.accountChanged)),
      );
    });

    test('distinguishes signed-out and API key sessions', () async {
      final signedOut = _FakeSession([
        {'account': null, 'requiresOpenaiAuth': true},
      ]);
      final apiKey = _FakeSession([
        {
          'account': {'type': 'apiKey'},
        },
      ]);

      await expectLater(
        readCodexResetAccount(signedOut),
        throwsA(_failure(CodexResetFailure.signedOut)),
      );
      await expectLater(
        readCodexResetAccount(apiKey),
        throwsA(_failure(CodexResetFailure.unsupportedAccount)),
      );
      expect(signedOut.methods, [_readAccount]);
      expect(apiKey.methods, [_readAccount]);
    });
  });

  group('redeemCodexResetCredit', () {
    for (final outcome in CodexResetOutcome.values) {
      test('returns ${outcome.name} after redeeming the selected credit only', () async {
        final session = _FakeSession([
          _account(),
          _limits(
            count: 2,
            credits: [
              _credit(id: 'ResetCredit_2'),
              _credit(expiresAt: _futureExpiry),
            ],
          ),
          {'outcome': outcome.name},
        ]);

        expect(await _redeem(session), outcome);
        expect(session.methods, [_readAccount, _readLimits, _consume]);
        expect(session.requests.last.params, {'creditId': _creditId, 'idempotencyKey': _key});
      });
    }

    test('does not send consume when account or person has changed', () async {
      final changedWorkspace = _FakeSession([
        _account(),
        _limits(accountId: 'other-account', credits: [_credit()]),
      ]);
      final changedPerson = _FakeSession([
        _account(userId: 'other-user'),
        _limits(credits: [_credit()]),
      ]);
      final changedEmail = _FakeSession([
        _account(email: 'other@example.test'),
        _limits(credits: [_credit()]),
      ]);

      for (final session in [changedWorkspace, changedPerson, changedEmail]) {
        await expectLater(_redeem(session), throwsA(_failure(CodexResetFailure.accountChanged)));
        expect(session.methods, isNot(contains(_consume)));
      }
    });

    test('does not send consume without evidence of the expected identity', () async {
      final session = _FakeSession([]);

      await expectLater(
        _redeem(session, expected: const CodexResetAccount()),
        throwsA(_failure(CodexResetFailure.identityUnavailable)),
      );
      expect(session.methods, isEmpty);
    });

    final rejectedDetails = <String, List<Map<String, Object?>>?>{
      'count only': null,
      'a different credit': [_credit(id: 'ResetCredit_2')],
      'an expired credit': [_credit(expiresAt: _now.millisecondsSinceEpoch ~/ 1000)],
      'a credit being redeemed': [_credit(status: 'redeeming')],
      'an unsupported reset type': [_credit(type: 'unknown')],
      'a duplicated credit ID': [_credit(), _credit()],
    };
    for (final entry in rejectedDetails.entries) {
      test('does not redeem ${entry.key}', () async {
        final session = _FakeSession([_account(), _limits(credits: entry.value)]);

        await expectLater(_redeem(session), throwsA(_failure(CodexResetFailure.creditUnavailable)));
        expect(session.methods, [_readAccount, _readLimits]);
      });
    }

    test('lets the same verified attempt retry after the credit disappears', () async {
      final attempt = await _uncertainAttempt();
      final session = _FakeSession([
        _account(),
        _limits(count: 0, credits: []),
        {'outcome': 'alreadyRedeemed'},
      ]);

      expect(await _redeem(session, retryAttempt: attempt), CodexResetOutcome.alreadyRedeemed);
      expect(session.methods, [_readAccount, _readLimits, _consume]);
      expect(session.requests.last.params, {'creditId': _creditId, 'idempotencyKey': _key});
    });

    test('rejects a retry with a different credit, key, or account', () async {
      final attempt = await _uncertainAttempt();
      final differentCredit = _FakeSession([]);
      final differentKey = _FakeSession([]);
      final differentAccount = _FakeSession([
        _account(userId: 'other-user'),
        _limits(accountId: 'other-account', count: 0, credits: []),
      ]);

      await expectLater(
        _redeem(differentCredit, creditId: 'ResetCredit_2', retryAttempt: attempt),
        throwsA(_failure(CodexResetFailure.invalidRequest)),
      );
      await expectLater(
        _redeem(differentKey, key: 'different-key', retryAttempt: attempt),
        throwsA(_failure(CodexResetFailure.invalidRequest)),
      );
      await expectLater(
        _redeem(
          differentAccount,
          expected: const CodexResetAccount(accountId: 'other-account', userId: 'other-user'),
          retryAttempt: attempt,
        ),
        throwsA(_failure(CodexResetFailure.accountChanged)),
      );
      expect(differentCredit.methods, isEmpty);
      expect(differentKey.methods, isEmpty);
      expect(differentAccount.methods, isNot(contains(_consume)));
    });

    test('a preflight RPC failure has no verified attempt or raw server details', () async {
      final session = _FakeSession([_account(), JsonRpcException('backend detail')]);

      await expectLater(
        _redeem(session),
        throwsA(
          _failure(CodexResetFailure.unavailable)
              .havingRetryAttempt(null)
              .havingNoRawError('backend detail'),
        ),
      );
      expect(session.methods, [_readAccount, _readLimits]);
    });
  });
}

Future<CodexResetAttempt> _uncertainAttempt() async {
  final session = _FakeSession([
    _account(),
    _limits(credits: [_credit(expiresAt: _futureExpiry)]),
    JsonRpcException('backend detail'),
  ]);
  try {
    await _redeem(session);
    fail('Expected an uncertain redemption');
  } on CodexResetException catch (error) {
    expect(error.failure, CodexResetFailure.redemptionUncertain);
    expect(error.toString(), isNot(contains('backend detail')));
    expect(session.methods, [_readAccount, _readLimits, _consume]);
    return error.retryAttempt!;
  }
}

Future<CodexResetOutcome> _redeem(
  _FakeSession session, {
  CodexResetAccount expected = _expected,
  String creditId = _creditId,
  String key = _key,
  CodexResetAttempt? retryAttempt,
}) => redeemCodexResetCredit(
  session,
  expectedAccount: expected,
  creditId: creditId,
  idempotencyKey: key,
  retryAttempt: retryAttempt,
  now: _now,
);

TypeMatcher<CodexResetException> _failure(CodexResetFailure failure) =>
    isA<CodexResetException>().having((error) => error.failure, 'failure', failure);

extension on TypeMatcher<CodexResetException> {
  TypeMatcher<CodexResetException> havingRetryAttempt(Object? matcher) =>
      having((error) => error.retryAttempt, 'retryAttempt', matcher);

  TypeMatcher<CodexResetException> havingNoRawError(String detail) =>
      having((error) => error.toString(), 'error message', isNot(contains(detail)));
}

Map<String, Object?> _account({String email = 'reader@example.test', String userId = 'user-1'}) => {
  'account': {'type': 'chatgpt', 'email': email, 'planType': 'plus'},
  'userId': userId,
};

Map<String, Object?> _limits({
  String accountId = 'account-1',
  int count = 1,
  List<Map<String, Object?>>? credits,
}) => {
  'accountId': accountId,
  'rateLimits': {
    'credits': {'hasCredits': true, 'balance': '12.5', 'unlimited': false},
  },
  'rateLimitResetCredits': {'availableCount': count, 'credits': credits},
};

Map<String, Object?> _credit({
  String id = _creditId,
  String type = 'codexRateLimits',
  String status = 'available',
  int? expiresAt,
  String? title,
}) => {
  'id': id,
  'resetType': type,
  'status': status,
  'grantedAt': 1781654400,
  'expiresAt': expiresAt,
  'title': title,
};

class _FakeSession implements JsonRpcSession {
  _FakeSession(this._results);

  final List<Object?> _results;
  final requests = <({String method, Object? params})>[];
  List<String> get methods => [for (final request in requests) request.method];

  @override
  Stream<JsonRpcNotification> get notifications => const Stream.empty();

  @override
  Future<Object?> request(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    requests.add((method: method, params: params));
    final result = _results[requests.length - 1];
    if (result is JsonRpcException) throw result;
    return result;
  }

  @override
  void notify(String method, {Object? params}) {}

  @override
  Future<void> close() async {}
}
