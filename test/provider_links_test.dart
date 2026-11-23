import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:token_bar/l10n/app_localizations.dart';
import 'package:token_bar/ui/provider_links.dart';
import 'package:token_bar/ui/widgets/account_card.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

void main() {
  final now = DateTime(2026, 11, 23);
  UsageSnapshot snapshot(String providerId, {List<Credits> credits = const []}) => UsageSnapshot(
    accountId: 'demo-$providerId',
    providerId: providerId,
    fetchedAt: now,
    credits: credits,
  );

  test('every registered service has a credential-free HTTPS destination', () {
    for (final provider in ProviderRegistry.instance.all) {
      final url = providerOfficialUrl(snapshot(provider.id));
      expect(url, isNotNull, reason: provider.id);
      expect(url!.scheme, 'https', reason: provider.id);
      expect(url.host, isNotEmpty, reason: provider.id);
      expect(url.userInfo, isEmpty, reason: provider.id);
    }
  });

  test('Codex subscriptions and OpenAI API open their own usage overviews', () {
    expect(providerOfficialUrl(snapshot('codex')).toString(), 'https://chatgpt.com/settings/usage');
    expect(
      providerOfficialUrl(snapshot('openai')).toString(),
      'https://platform.openai.com/settings/organization/analytics/usage',
    );
  });

  test('OpenRouter and MiMo open their account usage dashboards', () {
    expect(
      providerOfficialUrl(snapshot('openrouter')).toString(),
      'https://openrouter.ai/activity',
    );
    expect(
      providerOfficialUrl(snapshot('mimo')).toString(),
      'https://platform.xiaomimimo.com/#/console/usage',
    );
  });

  for (final (id, region, url) in const [
    ('moonshot', 'china', 'https://platform.kimi.com/console/account'),
    ('moonshot', 'international', 'https://platform.kimi.ai/console/account'),
    ('kimi', 'china', 'https://www.kimi.com/code/console'),
    ('kimi', 'international', 'https://www.kimi.ai/code/console'),
    ('minimax', 'cn', 'https://platform.minimax.cn/console/home'),
    ('minimax', 'global', 'https://platform.minimax.io/console/home'),
    ('siliconflow', 'cn', 'https://cloud.siliconflow.cn/'),
    ('siliconflow', 'global', 'https://cloud.siliconflow.com/console'),
    ('zai', 'bigmodel-cn', 'https://bigmodel.cn/console/overview'),
    ('zai', 'global', 'https://z.ai/manage-apikey/apikey-list'),
  ]) {
    test('$id opens the configured $region account site', () {
      final data = snapshot(id);
      final account = AccountConfig(
        id: data.accountId,
        providerId: id,
        label: 'Demo',
        sourceType: SourceType.apiKey,
        options: {'region': region},
      );
      expect(providerOfficialUrl(data, account: account).toString(), url);
    });
  }

  test('synced balances preserve their regional console', () {
    const usd = Credits(id: 'moonshot-balance', label: 'Balance', currency: 'USD');
    const cny = Credits(id: 'siliconflow-balance', label: 'Balance', currency: 'CNY');
    expect(
      providerOfficialUrl(snapshot('moonshot', credits: [usd])).toString(),
      'https://platform.kimi.ai/console/account',
    );
    expect(
      providerOfficialUrl(snapshot('siliconflow', credits: [cny])).toString(),
      'https://cloud.siliconflow.cn/',
    );
  });

  test('configured gateway endpoints are independent of the official link', () {
    final data = snapshot('litellm');
    final account = AccountConfig(
      id: data.accountId,
      providerId: data.providerId,
      label: 'Demo',
      sourceType: SourceType.apiKey,
      options: const {'baseUrl': 'https://example.org/private/gateway'},
    );
    expect(
      providerOfficialUrl(data, account: account).toString(),
      'https://github.com/BerriAI/litellm',
    );
    expect(providerOfficialUrl(snapshot('unknown-service')), isNull);
  });

  testWidgets('a self-hosted card labels its official destination as Project', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: AccountCard(snapshot: snapshot('litellm'), now: now),
        ),
      ),
    );
    final link = find.byTooltip('Open LiteLLM website');
    expect(find.descendant(of: link, matching: find.text('Project')), findsOneWidget);
    expect(find.text('Account'), findsNothing);
  });

  testWidgets('the labeled account button opens DeepSeek usage without opening details', (
    tester,
  ) async {
    final launchCalls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    var launchSucceeds = true;
    messenger.setMockMethodCallHandler(launcher, (call) async {
      launchCalls.add(call);
      return launchSucceeds;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));

    var cardTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: AccountCard(
              snapshot: UsageSnapshot(
                accountId: 'demo-deepseek',
                providerId: 'deepseek',
                fetchedAt: now,
                source: 'api-key',
                accountLabel: '一个名字很长的 DeepSeek 测试账户',
                plan: 'Long Demo Organization Subscription',
                credits: const [Credits(id: 'balance', label: '余额', balance: 12, currency: 'CNY')],
              ),
              now: now,
              onTap: () => cardTaps++,
            ),
          ),
        ),
      ),
    );

    final link = find.byTooltip('打开 DeepSeek 账户总览');
    expect(link, findsOneWidget);
    expect(find.descendant(of: link, matching: find.text('账户')), findsOneWidget);
    expect(tester.getCenter(link).dx, greaterThan(220));
    await tester.tap(link);
    await tester.pump();
    expect(launchCalls.single.method, 'launch');
    expect(launchCalls.single.arguments['url'], 'https://platform.deepseek.com/usage');
    expect(launchCalls.single.arguments['useWebView'], isFalse);
    expect(cardTaps, 0);

    await tester.tap(find.text('一个名字很长的 DeepSeek 测试账户'));
    await tester.pump();
    expect(cardTaps, 1);
    expect(launchCalls, hasLength(1));

    launchSucceeds = false;
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('无法打开网页，请重试。'), findsOneWidget);
    expect(cardTaps, 1);
    expect(tester.takeException(), isNull);
  });
}
