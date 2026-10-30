import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:token_bar/app/theme.dart';
import 'package:token_bar/l10n/app_localizations.dart';
import 'package:token_bar/services/quota_alerts.dart';
import 'package:token_bar/state/settings.dart';
import 'package:token_bar/ui/format.dart';
import 'package:token_bar/ui/pages/accounts_page.dart';
import 'package:token_bar/ui/widgets/account_card.dart';
import 'package:token_bar/ui/widgets/window_row.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

const _zh = Locale('zh', 'CN');

/// Localized MaterialApp wrapper: the UI is Chinese by default in these tests.
MaterialApp _app({required Widget home, ThemeData? theme}) => MaterialApp(
  theme: theme,
  locale: _zh,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
  home: home,
);

void main() {
  final now = DateTime(2026, 10, 23, 12);
  final l = lookupAppLocalizations(_zh);

  UsageSnapshot snapshot({double session = 42, double weekly = 17, String? error}) => UsageSnapshot(
    accountId: 'a1',
    providerId: 'codex',
    accountLabel: '工作账户',
    fetchedAt: now.subtract(const Duration(minutes: 3)),
    plan: 'plus',
    email: 'dev@example.com',
    source: 'oauth',
    windows: [
      RateWindow(
        id: 'session',
        label: '5-hour',
        usedPercent: session,
        resetsAt: now.add(const Duration(hours: 2, minutes: 5)),
        windowMinutes: 300,
      ),
      RateWindow(
        id: 'weekly',
        label: 'Weekly',
        usedPercent: weekly,
        resetsAt: now.add(const Duration(days: 3)),
        windowMinutes: 10080,
      ),
    ],
    credits: const [Credits(id: 'codex-credits', label: 'Credits', balance: 12.5)],
    error: error,
  );

  testWidgets('account card shows remaining, countdown and plan', (tester) async {
    await tester.pumpWidget(
      _app(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountCard(snapshot: snapshot(), now: now),
          ),
        ),
      ),
    );
    expect(find.text('工作账户'), findsOneWidget);
    expect(find.text('Plus'), findsOneWidget);
    expect(find.text('58%'), findsOneWidget);
    expect(find.text('83%'), findsOneWidget);
    expect(find.textContaining('2小时5分后重置'), findsOneWidget);
    expect(find.text('Credits 余额'), findsOneWidget);
    expect(find.textContaining('3 分钟前'), findsOneWidget);
  });

  testWidgets('stale data is labelled when last fetch failed', (tester) async {
    await tester.pumpWidget(
      _app(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountCard(
              snapshot: snapshot(error: '网络错误'),
              now: now,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('显示的是上次数据'), findsOneWidget);
  });

  testWidgets('account card renders in English', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountCard(snapshot: snapshot(), now: now),
          ),
        ),
      ),
    );
    expect(find.text('工作账户'), findsOneWidget);
    expect(find.text('Credits balance'), findsOneWidget);
    expect(find.textContaining('Resets in 2h 5m'), findsOneWidget);
    expect(find.textContaining('Updated 3 minutes ago'), findsOneWidget);
    expect(find.textContaining('Weekly'), findsWidgets);
    expect(find.textContaining('5-hour'), findsWidgets);
  });

  group('quota alerts', () {
    test('fires once per threshold per period', () {
      final engine = QuotaAlertEngine({});
      List<QuotaAlert> run(double used) => engine.evaluate(
        snapshot(session: used, weekly: 0),
        thresholds: const [20, 5],
        notifyOnReset: true,
        providerName: 'Codex',
        l10n: l,
      );
      expect(run(50), isEmpty);
      expect(run(85).single.title, contains('额度不足'));
      expect(run(86), isEmpty);
      expect(run(96).single.body, contains('剩余 4%'));
      expect(run(97), isEmpty);
    });

    test('a reset time that drifts by seconds does not re-arm thresholds', () {
      // Providers that report "seconds until reset" yield fetch time + seconds, so the
      // reset time moves slightly on every refresh while the period stays the same.
      final engine = QuotaAlertEngine({});
      final reset = now.add(const Duration(hours: 2));
      List<QuotaAlert> run(Duration drift, {double used = 85}) => engine.evaluate(
        UsageSnapshot(
          accountId: 'a1',
          providerId: 'factory',
          fetchedAt: now,
          windows: [
            RateWindow(
              id: 'session',
              label: '5 小时',
              usedPercent: used,
              resetsAt: reset.add(drift),
              windowMinutes: 300,
            ),
          ],
        ),
        thresholds: const [20],
        notifyOnReset: true,
        providerName: 'Factory',
        l10n: l,
      );
      expect(run(Duration.zero), hasLength(1));
      expect(run(const Duration(milliseconds: 420)), isEmpty);
      expect(run(const Duration(seconds: 1, milliseconds: 80)), isEmpty);
      expect(run(const Duration(seconds: 1, milliseconds: 950)), isEmpty);
      // A real new period moves the reset by hours and re-arms the threshold.
      expect(run(const Duration(hours: 5)), hasLength(1));
    });

    test('reset notification after a new period starts', () {
      final state = <String, Object?>{};
      final engine = QuotaAlertEngine(state);
      final low = snapshot(session: 90, weekly: 0);
      engine.evaluate(
        low,
        thresholds: const [20],
        notifyOnReset: true,
        providerName: 'Codex',
        l10n: l,
      );
      final fresh = UsageSnapshot(
        accountId: 'a1',
        providerId: 'codex',
        fetchedAt: now,
        windows: [
          RateWindow(
            id: 'session',
            label: '5-hour',
            usedPercent: 0,
            resetsAt: now.add(const Duration(hours: 7)),
            windowMinutes: 300,
          ),
        ],
      );
      final alerts = engine.evaluate(
        fresh,
        thresholds: const [20],
        notifyOnReset: true,
        providerName: 'Codex',
        l10n: l,
      );
      expect(alerts.single.title, contains('已重置'));
    });
  });

  test('settings json roundtrip keeps token out of json', () {
    final s = AppSettings.defaults().copyWith(
      themeMode: ThemeMode.dark,
      language: AppLanguage.en,
      refreshMinutes: 10,
      syncMode: SyncMode.localPush,
      serverUrl: 'https://tb.example.com',
      serverToken: 'secret',
      thresholds: [30, 10],
      trayAccountId: 'acc-1',
    );
    final json = s.toJson();
    expect(json.containsKey('serverToken'), isFalse);
    final back = AppSettings.fromJson(json, token: 'secret');
    expect(back.themeMode, ThemeMode.dark);
    expect(back.language, AppLanguage.en);
    expect(back.syncMode, SyncMode.localPush);
    expect(back.thresholds, [30, 10]);
    expect(back.trayAccountId, 'acc-1');
    expect(AppSettings.fromJson(const {}).trayAccountId, isEmpty); // older files: auto
    expect(back.serverConfigured, isTrue);
  });

  Future<void> openEditor(WidgetTester tester, {AccountConfig? existing}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAccountEditor(context, existing: existing),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop editor offers Cursor local login and manual cookie', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await openEditor(tester);
      await tester.tap(find.byKey(const ValueKey('provider-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cursor').last);
      await tester.pumpAndSettle();
      expect(find.text('本机 Cursor 登录'), findsOneWidget);
      await tester.tap(find.text('手动粘贴 Cookie'));
      await tester.pumpAndSettle();
      expect(find.text('cursor.com Cookie'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone editor only offers providers usable without a desktop login', (tester) async {
    await openEditor(tester);
    expect(find.text('本机 Cursor 登录'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('provider-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'cursor');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cursor').last);
    await tester.pumpAndSettle();
    expect(find.text('cursor.com Cookie'), findsOneWidget);
    expect(availableProviders.map((p) => p.id), isNot(contains('codex')));
    expect(availableProviders.map((p) => p.id), isNot(contains('claude')));
  });

  testWidgets('selecting Copilot offers a concealed GitHub token and optional host', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('provider-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'copilot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitHub Copilot').last);
    await tester.pumpAndSettle();

    final tokenField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == 'GitHub Token',
      ),
    );
    expect(tokenField.obscureText, isTrue);
    expect(find.text(l.optionalField('GitHub Enterprise 主机')), findsOneWidget);
    expect(find.textContaining(l.storedInKeychain), findsOneWidget);
    expect(availableProviders.map((p) => p.id), contains('copilot'));
  });

  testWidgets('Copilot credits without an allowance remain a plain used counter', (tester) async {
    // Artificial display data, independent of any account response.
    await tester.pumpWidget(
      _app(
        home: Scaffold(
          body: AccountCard(
            snapshot: UsageSnapshot(
              accountId: 'copilot-test',
              providerId: 'copilot',
              fetchedAt: now,
              plan: 'Business',
              source: 'api-key',
              credits: const [Credits(id: 'copilot-seat-credits', label: 'Credits 已用', used: 360)],
            ),
            now: now,
          ),
        ),
      ),
    );

    expect(find.text('GitHub Copilot'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
    expect(find.text('Credits 已用'), findsOneWidget);
    expect(find.textContaining('360'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.byType(WindowRow), findsNothing);
  });

  testWidgets('selecting MiMo offers the platform Cookie field', (tester) async {
    await openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('provider-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'mimo');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xiaomi MiMo').last);
    await tester.pumpAndSettle();

    expect(find.text('platform.xiaomimimo.com Cookie'), findsOneWidget);
    expect(find.textContaining('api-platform_serviceToken'), findsWidgets);
    expect(find.textContaining(l.storedInKeychain), findsOneWidget);
    expect(availableProviders.map((p) => p.id), contains('mimo'));
  });

  testWidgets('editing MiMo never fills the saved Cookie into the text field', (tester) async {
    const cookie = 'api-platform_serviceToken=synthetic-session; userId=42';
    await openEditor(
      tester,
      existing: const AccountConfig(
        id: 'mimo-test',
        providerId: 'mimo',
        label: 'MiMo test',
        sourceType: SourceType.apiKey,
        secret: cookie,
      ),
    );

    final field = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'platform.xiaomimimo.com Cookie',
      ),
    );
    expect(field.controller!.text, isEmpty);
    expect(field.decoration!.hintText, l.savedKeepUnchanged);
    expect(find.textContaining('synthetic-session'), findsNothing);
  });

  testWidgets('expired MiMo session labels its cached balance as old data', (tester) async {
    const error = 'Xiaomi MiMo 登录已过期';
    const hint = '在 platform.xiaomimimo.com 重新登录后复制 Cookie';
    await tester.pumpWidget(
      _app(
        home: Scaffold(
          body: AccountCard(
            snapshot: UsageSnapshot(
              accountId: 'mimo-test',
              providerId: 'mimo',
              fetchedAt: now.subtract(const Duration(minutes: 3)),
              source: 'web',
              credits: const [
                Credits(id: 'mimo-balance', label: '余额', balance: 12.5, currency: 'CNY'),
              ],
              error: error,
              errorHint: hint,
            ),
            now: now,
          ),
        ),
      ),
    );

    expect(find.text('Xiaomi MiMo'), findsOneWidget);
    expect(find.textContaining('12.50'), findsOneWidget);
    expect(find.text(l.staleDataNotice(error)), findsOneWidget);
    expect(find.text(hint), findsOneWidget);
    expect(find.byType(WindowRow), findsNothing);
  });

  test('cursor labels', () {
    expect(
      windowLabel(l, const RateWindow(id: 'cursor-total', label: 'Monthly', usedPercent: 5)),
      '本月额度',
    );
    expect(creditsLabel(l, const Credits(id: 'cursor-plan', label: 'Plan usage')), '本月用量');
    expect(sourceTypeLabel(l, 'cursor', SourceType.apiKey), '手动粘贴 Cookie');
    expect(sourceTypeLabel(l, 'codex', SourceType.localCli), '本机 Codex CLI 登录');
  });

  test('chinese formatting', () {
    expect(countdownLabel(l, const Duration(days: 2, hours: 3)), '2天3小时');
    expect(countdownLabel(l, const Duration(minutes: 45)), '45分钟');
    expect(resetTimeLabel(l, DateTime(2026, 10, 23, 18, 5), now), '18:05');
    expect(resetTimeLabel(l, DateTime(2026, 10, 24, 9, 0), now), '明天 09:00');
  });
}
