import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:token_bar/app/theme.dart';
import 'package:token_bar/l10n/app_localizations.dart';
import 'package:token_bar/services/desktop.dart';
import 'package:token_bar/services/history_store.dart';
import 'package:token_bar/services/home_widget_bridge.dart';
import 'package:token_bar/services/notifier.dart';
import 'package:token_bar/services/persistence.dart';
import 'package:token_bar/state/app_controller.dart';
import 'package:token_bar/state/codex_reset_credits_controller.dart';
import 'package:token_bar/state/settings.dart';
import 'package:token_bar/ui/pages/account_detail_page.dart';
import 'package:token_bar/ui/pages/dashboard_page.dart';
import 'package:token_bar/ui/widgets/account_card.dart';
import 'package:token_bar/ui/widgets/codex_reset_credits_card.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

void main() {
  final now = DateTime.now();
  final l = lookupAppLocalizations(const Locale('zh'));
  final expiry = now.add(const Duration(days: 7));

  MaterialApp app(Widget page, {bool dark = false}) => MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
    home: page,
  );

  Future<CodexResetCreditsController> render(WidgetTester tester, _AccountBackend rpc) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = CodexResetCreditsController(
      target: (home: 'fake-home', email: rpc.email),
      onQuotaChanged: () async {},
      service: _service({'fake-home': rpc}),
    );
    addTearDown(controller.dispose);
    unawaited(controller.refresh());
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CodexResetCreditsCard(
            controller: controller,
            accountLabel: 'Test account',
            now: now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('dashboard silently loads both accounts and uses only the selected card', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(960, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reply = Completer<void>();
    final rpcs = {
      'primary-home': _AccountBackend(expiry: expiry, count: 2, countOnly: true),
      'backup-home': _AccountBackend(
        email: 'backup@example.invalid',
        expiry: expiry,
        count: 1,
        waitForInventory: reply.future,
      ),
    };
    final persistence = await Persistence.openDemo();
    await persistence.saveSettings(AppSettings.defaults().copyWith(notificationsEnabled: false));
    await persistence.saveAccounts(const [
      AccountConfig(id: 'primary', providerId: 'codex', label: 'Primary', homeDir: 'primary-home'),
      AccountConfig(id: 'backup', providerId: 'codex', label: 'Backup', homeDir: 'backup-home'),
    ]);
    final provider = _CodexProvider(rpcs);
    final controller = AppController(
      persistence: persistence,
      historyStore: HistoryStore.demo(const []),
      desktop: DesktopIntegration(),
      notifier: Notifier(),
      homeWidget: HomeWidgetBridge(),
      providerLookup: (_) => provider,
      codexResetService: _service(rpcs),
    );
    try {
      await controller.init();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: app(const DashboardPage(), dark: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.refreshing, isFalse);
      expect(canUseLocalLogins, isTrue);
      expect(controller.snapshots, hasLength(2));
      expect(rpcs.values.map((backend) => backend.reads), [1, 1]);
      expect(find.text(l.codexResetCount(2)), findsOneWidget);
      expect(find.text(l.codexResetCount(0)), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(l.codexResetUse), findsNothing);

      reply.complete();
      await tester.pumpAndSettle();
      final backup = rpcs['backup-home']!;
      final card = find.ancestor(of: find.text('Backup'), matching: find.byType(AccountCard));
      final use = find.descendant(of: card, matching: find.text(l.codexResetUse));
      expect(find.descendant(of: card, matching: find.text(l.codexResetCount(1))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('到期')), findsOneWidget);
      await tester.tap(use);
      await tester.pumpAndSettle();
      expect(find.byType(AccountDetailPage), findsNothing);
      expect(find.text(l.codexResetUseBody(backup.email)), findsOneWidget);
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(backup.consumes, isEmpty);

      await tester.tap(use);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.codexResetUse).last);
      await tester.pumpAndSettle();
      expect(backup.consumes.single['credit_id'], 'saved-reset');
      expect(rpcs['primary-home']!.consumes, isEmpty);
      expect(provider.calls, 4); // Both quotas were refreshed after redemption.
      expect(find.descendant(of: card, matching: find.text(l.codexResetCount(0))), findsOneWidget);
      expect(find.text(l.codexResetCount(2)), findsOneWidget);
    } finally {
      if (!reply.isCompleted) reply.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('loads inventory silently and shows the count only once known', (tester) async {
    final reply = Completer<void>();
    final rpc = _AccountBackend(expiry: expiry, count: 1, waitForInventory: reply.future);
    final controller = await render(tester, rpc);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('正在查询'), findsNothing);
    expect(find.text(l.codexResetCount(0)), findsNothing);

    reply.complete();
    await tester.pumpAndSettle();
    expect(find.text(l.codexResetCount(1)), findsOneWidget);

    final refresh = Completer<void>();
    rpc.waitForInventory = refresh.future;
    final pending = controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text(l.codexResetCount(1)), findsOneWidget);
    refresh.completeError(StateError('temporary inventory failure'));
    await pending;
    await tester.pumpAndSettle();
    expect(find.text(l.codexResetCount(1)), findsOneWidget);
    expect(find.text(l.codexResetUnavailable), findsNothing);
  });

  testWidgets('keeps a count-only response distinct from an empty inventory', (tester) async {
    final rpc = _AccountBackend(expiry: null, count: 3, countOnly: true);
    await render(tester, rpc);
    expect(find.text(l.codexResetCount(3)), findsOneWidget);
    expect(find.text(l.codexResetDetailsMissing), findsOneWidget);
    expect(find.text(l.codexResetUse), findsNothing);
  });

  testWidgets('retries an unknown outcome with the same request ID and credit', (tester) async {
    final rpc = _AccountBackend(expiry: expiry, count: 1, failOnce: true);
    await render(tester, rpc);
    await tester.tap(find.text(l.codexResetUse));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.codexResetUse).last);
    await tester.pumpAndSettle();
    expect(find.text(l.codexResetUncertain), findsOneWidget);
    await tester.tap(find.text(l.codexResetRetry));
    await tester.pumpAndSettle();
    expect(rpc.consumes, hasLength(2));
    expect(rpc.consumes.last, rpc.consumes.first);
    expect(find.text(l.codexResetCount(0)), findsOneWidget);
  });
}

class _CodexProvider extends UsageProvider {
  _CodexProvider(this.rpcs);

  final Map<String, _AccountBackend> rpcs;
  int calls = 0;

  @override
  String get id => 'codex';
  @override
  String get displayName => 'Codex';
  @override
  int get brandColor => 0xFF10A37F;
  @override
  List<SourceType> get supportedSources => const [SourceType.localCli];
  @override
  String get setupHint => '';

  @override
  Future<UsageSnapshot> fetch(AccountConfig account, FetchContext ctx) async {
    calls++;
    return UsageSnapshot(
      accountId: account.id,
      providerId: id,
      fetchedAt: ctx.now(),
      email: rpcs[account.homeDir]!.email,
    );
  }
}

CodexResetService _service(Map<String, _AccountBackend> accounts) => CodexResetService(
  loadCredentials: (home) async {
    final account = accounts[home]!;
    return CodexCredentials(accessToken: 'test-$home', accountId: home, email: account.email);
  },
  createClient: () => MockClient((request) {
    final account = accounts[request.headers['ChatGPT-Account-Id']]!;
    return account.request(request);
  }),
);

class _AccountBackend {
  _AccountBackend({
    required this.expiry,
    required this.count,
    this.countOnly = false,
    this.failOnce = false,
    this.waitForInventory,
    this.email = 'test@example.invalid',
  });

  final DateTime? expiry;
  final String email;
  Future<void>? waitForInventory;
  final bool countOnly;
  final bool failOnce;
  int count;
  int reads = 0;
  final consumes = <Map<String, Object?>>[];

  Future<http.Response> request(http.Request request) async {
    if (request.method == 'POST') {
      consumes.add((jsonDecode(request.body) as Map).cast<String, Object?>());
      count = 0;
      if (failOnce && consumes.length == 1) throw StateError('lost reply');
      return http.Response(jsonEncode({'code': failOnce ? 'already_redeemed' : 'reset'}), 200);
    }
    reads++;
    await waitForInventory;
    return http.Response(
      jsonEncode({
        'available_count': count,
        'credits': countOnly
            ? null
            : [
                if (count > 0)
                  {
                    'id': 'saved-reset',
                    'title': 'Usage reset',
                    'reset_type': 'codex_rate_limits',
                    'status': 'available',
                    'expires_at': expiry?.toUtc().toIso8601String(),
                  },
              ],
      }),
      200,
    );
  }
}
