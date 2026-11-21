import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

typedef CodexResetTarget = ({String home, String? email});

typedef _Redemption = ({
  CodexResetAccount account,
  String id,
  String key,
  CodexResetAttempt? attempt,
});

/// The dashboard and account detail share the inventory and any pending redemption.
class CodexResetCreditsController extends ChangeNotifier {
  CodexResetCreditsController({
    required this.target,
    required this.onQuotaChanged,
    this.service = const CodexResetService(),
  });

  final CodexResetTarget target;
  final Future<void> Function() onQuotaChanged;
  final CodexResetService service;

  CodexResetAccount? _account;
  CodexResetOutcome? _outcome;
  Object? _actionError;
  Future<void>? _reading;
  _Redemption? _retry;
  bool _using = false;
  bool _disposed = false;

  CodexResetAccount? get account => _account;
  CodexResetOutcome? get outcome => _outcome;
  Object? get actionError => _actionError;
  bool get using => _using;
  bool get canRetry => _retry != null;

  Future<void> refresh() async {
    if (_disposed || _using || _reading != null || canRetry) return;
    final reading = _readInventory();
    _reading = reading;
    try {
      await reading;
    } finally {
      _reading = null;
    }
  }

  Future<void> _readInventory() async {
    final previous = _account;
    try {
      final account = await service.read(target.home);
      final expected = target.email;
      if (expected != null && account.email?.toLowerCase() != expected.toLowerCase()) {
        throw const CodexResetException(CodexResetFailure.accountChanged);
      }
      _account = account;
    } catch (error) {
      if (_invalidAccount(error)) _account = null;
    }
    if (!_disposed && !_using && _account != previous) notifyListeners();
  }

  Future<void> use(CodexResetAccount account, CodexResetCredit credit) async {
    if (canRetry || _using || _disposed) return;
    await _redeem((account: account, id: credit.id, key: _resetRequestId(), attempt: null));
  }

  Future<void> retry() async {
    if (_retry case final request?) await _redeem(request);
  }

  Future<void> _redeem(_Redemption request) async {
    if (_using || _disposed) return;
    _using = true;
    _outcome = null;
    _actionError = null;
    notifyListeners();
    var reload = false;
    var quotaChanged = false;
    try {
      // An older inventory read must finish before redeeming the credit.
      await _reading;
      if (_disposed) return;
      final outcome = await service.redeem(
        target.home,
        expectedAccount: request.account,
        creditId: request.id,
        idempotencyKey: request.key,
        retryAttempt: request.attempt,
      );
      if (_disposed) return;
      _outcome = outcome;
      _retry = null;
      quotaChanged =
          outcome == CodexResetOutcome.reset || outcome == CodexResetOutcome.alreadyRedeemed;
      if (quotaChanged || outcome == CodexResetOutcome.noCredit) _account = null;
      reload = true;
    } catch (error) {
      if (_disposed) return;
      _actionError = error;
      if (_invalidAccount(error)) {
        _account = null;
        _retry = null;
      } else if (error is CodexResetException) {
        if (error.retryAttempt case final attempt?) {
          _retry = (account: request.account, id: request.id, key: request.key, attempt: attempt);
        }
        if (error.failure == CodexResetFailure.creditUnavailable) {
          _account = null;
          reload = true;
        }
      }
    } finally {
      _using = false;
      if (!_disposed) notifyListeners();
    }
    if (reload) unawaited(refresh());
    if (quotaChanged && !_disposed) unawaited(onQuotaChanged());
  }

  static bool _invalidAccount(Object error) =>
      error is CodexResetException &&
      switch (error.failure) {
        CodexResetFailure.signedOut ||
        CodexResetFailure.unsupportedAccount ||
        CodexResetFailure.accountChanged ||
        CodexResetFailure.identityUnavailable => true,
        _ => false,
      };

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _resetRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
