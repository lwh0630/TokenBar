import 'dart:async';

import 'package:test/test.dart';
import 'package:tokenbar_core/src/platform/process_types.dart';
import 'package:tokenbar_core/src/providers/codex/codex_app_server.dart';

void main() {
  late _Session session;

  setUp(() => session = _Session());
  tearDown(() => session.close());

  test('opens the official browser link and waits for the matching login', () async {
    final opened = Completer<Uri>();
    final signIn = signInToCodex(session, (uri) async => opened.complete(uri));
    expect((await opened.future).host, 'auth.openai.com');
    session.complete('another-login', success: false);
    session.complete('active-login', success: true);
    await signIn;
    expect(session.requests, ['account/login/start']);
  });

  test('rejects a non-OpenAI sign-in link and cancels the attempt', () async {
    session.authUrl = 'https://example.invalid/authorize';
    await expectLater(
      signInToCodex(session, (_) async => fail('opened link')),
      throwsFormatException,
    );
    expect(session.requests, ['account/login/start', 'account/login/cancel']);
    expect(session.cancelParams, {'loginId': 'active-login'});
  });

  test('cancels when Codex reports a failed browser login', () async {
    await expectLater(
      signInToCodex(session, (_) async => session.complete('active-login', success: false)),
      throwsA(isA<JsonRpcException>()),
    );
    expect(session.cancelParams, {'loginId': 'active-login'});
  });

  test('cancels an expired login attempt', () async {
    await expectLater(
      signInToCodex(session, (_) async {}, timeout: Duration.zero),
      throwsA(isA<TimeoutException>()),
    );
    expect(session.cancelParams, {'loginId': 'active-login'});
  });
}

class _Session implements JsonRpcSession {
  final _notifications = StreamController<JsonRpcNotification>.broadcast();
  final requests = <String>[];
  Object? cancelParams;
  String authUrl = 'https://auth.openai.com/oauth/authorize?state=fake';

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  void complete(String id, {required bool success}) => _notifications.add((
    method: 'account/login/completed',
    params: {'loginId': id, 'success': success},
  ));

  @override
  Future<Object?> request(String method, {Object? params, Duration? timeout}) async {
    requests.add(method);
    if (method == 'account/login/start') {
      expect(params, {'type': 'chatgpt'});
      return {'type': 'chatgpt', 'loginId': 'active-login', 'authUrl': authUrl};
    }
    expect(method, 'account/login/cancel');
    cancelParams = params;
    return {'status': 'canceled'};
  }

  @override
  void notify(String method, {Object? params}) {}

  @override
  Future<void> close() => _notifications.close();
}
