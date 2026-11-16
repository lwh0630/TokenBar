import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:tokenbar_core/src/providers/api/local_auth_a_providers.dart';
import 'package:tokenbar_core/tokenbar_core.dart';

String _fx(String name) => File('test/fixtures/$name').readAsStringSync();

Map<String, Object?> _fxJson(String name) => jsonDecode(_fx(name)) as Map<String, Object?>;

final _now = DateTime.utc(2026, 10, 24, 12);

FetchContext _ctx(http.Client client) => FetchContext(client: client, clock: () => _now);

AccountConfig _acct(
  String providerId, {
  SourceType source = SourceType.apiKey,
  String? secret,
  Map<String, String> options = const {},
  String? homeDir,
}) => AccountConfig(
  id: 'a',
  providerId: providerId,
  label: providerId,
  sourceType: source,
  secret: secret,
  options: options,
  homeDir: homeDir,
);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

RateWindow _w(UsageSnapshot s, String id) => s.window(id)!;

void main() {
  test('registers the seven providers with expected ids', () {
    expect(localAuthAProviders.map((p) => p.id), [
      'copilot',
      'gemini',
      'kiro',
      'jetbrains',
      'amp',
      'kilo',
      'hyper',
    ]);
  });

  group('copilot', () {
    test('metered plan maps premium and chat windows', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response(_fx('copilot_user_metered.json'), 200);
      });
      final s = await CopilotProvider().fetchSafely(
        _acct('copilot', secret: 'gho_x'),
        _ctx(client),
      );
      expect(s.error, isNull);
      expect(seen.url.toString(), 'https://api.github.com/copilot_internal/user');
      expect(seen.headers['Authorization'], 'token gho_x');
      expect(seen.headers['Editor-Version'], 'vscode/1.96.2');
      expect(s.plan, 'Free');
      expect(_w(s, 'copilot-premium').usedPercent, closeTo(10, 1e-9));
      expect(_w(s, 'copilot-chat').usedPercent, closeTo(50, 1e-9));
      expect(_w(s, 'copilot-premium').resetsAt, DateTime.utc(2025, 2, 1));
      expect(s.credits, isEmpty);
    });

    test('token-billed business seat has no windows and shows credits', () {
      final u = parseCopilotUsage(_fxJson('copilot_user_business_token_billing.json'));
      expect(u.plan, 'Business');
      expect(u.windows, isEmpty);
      expect(u.credits.single.id, 'copilot-seat-credits');
      expect(u.credits.single.used, 31);
    });

    test('enterprise host normalization', () {
      expect(normalizeCopilotHost('https://OctoCorp.ghe.com/login'), 'octocorp.ghe.com');
      expect(copilotApiHost('octocorp.ghe.com'), 'api.octocorp.ghe.com');
      expect(copilotApiHost('api.octocorp.ghe.com'), 'api.octocorp.ghe.com');
      expect(copilotApiHost(normalizeCopilotHost('')), 'api.github.com');
    });

    test('401 surfaces a clear token hint', () async {
      final client = MockClient((_) async => http.Response('{"message":"Bad credentials"}', 401));
      final s = await CopilotProvider().fetchSafely(_acct('copilot', secret: 'bad'), _ctx(client));
      expect(s.error, contains('拒绝了凭证'));
      expect(s.errorHint, contains('Token'));
    });
  });

  group('gemini', () {
    test('quota buckets map to pro, flash and flash-lite windows', () {
      final windows = parseGeminiQuotaBuckets(_fxJson('gemini_retrieveUserQuota.json'));
      expect(windows.map((w) => w.id), ['gemini-pro', 'gemini-flash', 'gemini-flash-lite']);
      expect(windows[0].usedPercent, closeTo(40, 1e-6));
      expect(windows[1].usedPercent, closeTo(10, 1e-6));
      expect(windows[2].usedPercent, closeTo(20, 1e-6));
      expect(windows.every((w) => w.windowMinutes == 1440), isTrue);
    });

    test('standard tier code assist reports Paid and project', () {
      final a = parseGeminiCodeAssist({
        'currentTier': {'id': 'standard-tier'},
        'cloudaicompanionProject': 'proj-1',
      });
      expect(a.project, 'proj-1');
      expect(a.plan(null), 'Paid');
    });

    test('UNSUPPORTED_CLIENT without a tier is reported as consumer shutdown', () {
      expect(
        () => parseGeminiCodeAssist(_fxJson('gemini_loadCodeAssist_unsupported_client.json')),
        throwsA(
          isA<ProviderException>().having((e) => e.message, 'message', contains('Gemini CLI')),
        ),
      );
    });

    test('web usage parses the GXU pools', () {
      final u = parseGeminiWebUsage(_fx('gemini_web_usage.txt'));
      expect(u.plan, 'Pro');
      final session = u.windows.firstWhere((w) => w.id == RateWindow.sessionId);
      expect(session.usedPercent, closeTo(24, 1e-6));
      expect(session.windowMinutes, 300);
      final weekly = u.windows.firstWhere((w) => w.id == RateWindow.weeklyId);
      expect(weekly.usedPercent, closeTo(1.786011, 1e-6));
      expect(weekly.windowMinutes, 10080);
    });

    test('web viewer null means the pasted cookie was rejected', () {
      expect(
        () => parseGeminiWebUsage(')]}\'\n[{"data":{"viewer":null}}]'),
        throwsA(isA<ProviderException>().having((e) => e.message, 'message', contains('会话已失效'))),
      );
    });

    test('local credentials: api-key auth rejected, expiry detected, never refreshed', () {
      expect(
        () => parseGeminiLocalCredentials(
          oauthJson: '{"access_token":"ya29.x"}',
          settingsJson: '{"security":{"auth":{"selectedType":"api-key"}}}',
        ),
        throwsA(isA<ProviderException>()),
      );
      final expired = parseGeminiLocalCredentials(
        oauthJson: '{"access_token":"ya29.x","refresh_token":"r","expiry_date":1000}',
      )!;
      expect(expired.isExpired(_now), isTrue);
      final fresh = parseGeminiLocalCredentials(
        oauthJson:
            '{"access_token":"ya29.x","expiry_date":${_now.add(const Duration(hours: 1)).millisecondsSinceEpoch}}',
      )!;
      expect(fresh.isExpired(_now), isFalse);
      expect(parseGeminiLocalCredentials(oauthJson: '{}'), isNull);
    });

    test('pasted OAuth token runs code assist, project lookup and quota', () async {
      final bodies = <String>[];
      final client = MockClient((r) async {
        final url = r.url.toString();
        if (url.contains('loadCodeAssist')) {
          return _json({
            'currentTier': {'id': 'standard-tier'},
            'cloudaicompanionProject': 'proj-1',
          });
        }
        if (url.contains('retrieveUserQuota')) {
          bodies.add(r.body);
          return http.Response(_fx('gemini_retrieveUserQuota.json'), 200);
        }
        return _json({'projects': []});
      });
      final s = await GeminiProvider().fetchSafely(
        _acct('gemini', secret: 'ya29.abc'),
        _ctx(client),
      );
      expect(s.error, isNull);
      expect(s.plan, 'Paid');
      expect(s.source, 'api-key');
      expect(s.windows, hasLength(3));
      expect(bodies.single, contains('proj-1'));
    });

    test('pasted cookie uses the Gemini app usage endpoint', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response(_fx('gemini_web_usage.txt'), 200);
      });
      final s = await GeminiProvider().fetchSafely(
        _acct('gemini', secret: 'Cookie: SID=abc; __Secure-1PSID=xyz'),
        _ctx(client),
      );
      expect(s.error, isNull);
      expect(seen.url.host, 'gemini.google.com');
      expect(seen.headers['Cookie'], 'SID=abc; __Secure-1PSID=xyz');
      expect(s.source, 'web');
      expect(s.plan, 'Pro');
    });

    test('signature discovery helpers find the bundle and the query id', () {
      const html =
          '<script src="https://www.gstatic.com/bg3/boq-bard-web/islands/assets/'
          r'@messages/assets/UsagePageLoading-aB3cD-ef4.js"></script>';
      expect(findGeminiLoadingBundle(html), 'UsagePageLoading-aB3cD-ef4.js');
      expect(findGeminiLoadingBundle('<html>no import map here</html>'), isNull);
      const js = r'x={id:`2/fresh-sig=`,metadata:{},name:`UsagePageQuery`};';
      expect(findGeminiQueryId(js), '2/fresh-sig=');
      expect(findGeminiQueryId('no query here'), isNull);
    });

    test('rejected query re-derives the signature and retries once', () async {
      final executeQuerySignatures = <String?>[];
      final client = MockClient((r) async {
        if (r.url.host == 'gemini.google.com' && r.url.path.endsWith('/app')) {
          return http.Response('import "@messages/assets/UsagePageLoading-t1.js";', 200);
        }
        if (r.url.host == 'www.gstatic.com') {
          return http.Response(r'x={id:`2/fresh-sig=`,metadata:{},name:`UsagePageQuery`};', 200);
        }
        if (r.url.path.endsWith('executeQuery')) {
          executeQuerySignatures.add(r.url.queryParameters['query_signature']);
          if (r.url.queryParameters['query_signature'] == '2/fresh-sig=') {
            return http.Response(_fx('gemini_web_usage.txt'), 200);
          }
          return http.Response(')]}\'\n[{"errors":[{"message":"Unknown query"}]}]', 200);
        }
        return http.Response('unexpected ${r.url}', 404);
      });
      final s = await GeminiProvider().fetchSafely(
        _acct('gemini', secret: 'Cookie: SID=abc; __Secure-1PSID=xyz'),
        _ctx(client),
      );
      expect(s.error, isNull, reason: s.error);
      expect(executeQuerySignatures, [
        '2/dWbCvkVB0X16r9NPnxifeOAAqdCqMf0xeWvau9yPy7g=',
        '2/fresh-sig=',
      ]);
      expect(s.source, 'web');
      expect(s.plan, 'Pro');
    });

    test('query rejected and discovery unavailable keeps the rejection error', () async {
      final client = MockClient((r) async {
        if (r.url.path.endsWith('executeQuery')) {
          return http.Response(')]}\'\n[{"errors":[{"message":"Unknown query"}]}]', 200);
        }
        return http.Response('<html>no bundle</html>', 200);
      });
      final s = await GeminiProvider().fetchSafely(
        _acct('gemini', secret: 'Cookie: SID=abc; __Secure-1PSID=xyz'),
        _ctx(client),
      );
      expect(s.error, contains('查询签名'));
    });

    test('validateManual demands a session cookie field for cookie-shaped input', () {
      final p = GeminiProvider();
      FieldValues fv(String secret) => FieldValues('Gemini', p.fields, {'secret': secret});
      // Cookie without any of __Secure-1PSID / __Secure-3PSID / SID: rejected.
      expect(
        p.validateManual(fv('SEARCH_SAMESITE=x; NID=y; __Secure-1PSIDTS=t')),
        contains('登录会话字段'),
      );
      // A real session cookie passes.
      expect(p.validateManual(fv('NID=y; __Secure-1PSID=abc; __Secure-1PSIDTS=t')), isNull);
      // Bare OAuth tokens are not cookie-shaped and stay untouched.
      expect(p.validateManual(fv('ya29.a0Abc')), isNull);
      // Truncated paste surfaces the truncation message, not a crash.
      expect(p.validateManual(fv('a=1; b=2\u2026c=3')), contains('截断'));
    });

    Directory firefoxHome(Directory home) {
      // Mirror the per-platform profile layout that
      // [firefoxGoogleCookieHeader] looks up.
      final base = Platform.isMacOS
          ? '${home.path}/Library/Application Support/Firefox/Profiles'
          : '${home.path}/.mozilla/firefox';
      return Directory(base);
    }

    test('firefox cookie store yields a live session header', () async {
      final home = await Directory.systemTemp.createTemp('tokenbar_ff_test');
      addTearDown(() => home.delete(recursive: true));
      final profile = Directory('${firefoxHome(home).path}${Platform.pathSeparator}abc.gemini');
      profile.createSync(recursive: true);
      final db = sqlite3.open('${profile.path}${Platform.pathSeparator}cookies.sqlite');
      db.execute('CREATE TABLE moz_cookies (name TEXT, value TEXT, host TEXT)');
      db.execute(
        "INSERT INTO moz_cookies VALUES ('NID', 'nid-gemini-host', 'gemini.google.com'),"
        "('NID', 'nid-main-host', '.google.com'),"
        "('__Secure-1PSID', 'sid-value', '.google.com'),"
        "('__Secure-1PSIDTS', 'ts-value', '.google.com'),"
        "('SAPISID', 'sapi-value', '.google.com'),"
        "('unrelated', 'x', 'accounts.google.com')",
      );
      db.close();

      final header = await firefoxGoogleCookieHeader(homeDir: home.path);
      expect(header, isNotNull);
      expect(header, contains('__Secure-1PSID=sid-value'));
      // gemini.google.com host wins over .google.com for duplicate names.
      expect(header, contains('NID=nid-gemini-host'));
      expect(header, isNot(contains('nid-main-host')));
      // Sub-domain-only cookies (accounts.google.com) are not carried.
      expect(header, isNot(contains('unrelated')));
    });

    test('profiles without a Gemini session yield null', () async {
      final home = await Directory.systemTemp.createTemp('tokenbar_ff_test');
      addTearDown(() => home.delete(recursive: true));
      final profile = Directory('${firefoxHome(home).path}${Platform.pathSeparator}x.default');
      profile.createSync(recursive: true);
      final db = sqlite3.open('${profile.path}${Platform.pathSeparator}cookies.sqlite');
      db.execute('CREATE TABLE moz_cookies (name TEXT, value TEXT, host TEXT)');
      db.execute("INSERT INTO moz_cookies VALUES ('NID', 'x', '.google.com')");
      db.close();
      expect(await firefoxGoogleCookieHeader(homeDir: home.path), isNull);
    });

    test('signed-out paste falls back to the live Firefox cookie store', () async {
      final home = await Directory.systemTemp.createTemp('tokenbar_ff_test');
      addTearDown(() => home.delete(recursive: true));
      final profile = Directory('${firefoxHome(home).path}${Platform.pathSeparator}abc.gemini');
      profile.createSync(recursive: true);
      final db = sqlite3.open('${profile.path}${Platform.pathSeparator}cookies.sqlite');
      db.execute('CREATE TABLE moz_cookies (name TEXT, value TEXT, host TEXT)');
      db.execute(
        "INSERT INTO moz_cookies VALUES ('__Secure-1PSID', 'fresh-sid', '.google.com'),"
        "('__Secure-1PSIDTS', 'fresh-ts', '.google.com')",
      );
      db.close();

      final cookieHeaders = <String?>[];
      final client = MockClient((r) async {
        cookieHeaders.add(r.headers['Cookie']);
        if (cookieHeaders.length == 1) {
          return http.Response(')]}\'\n[{"data":{"viewer":null}}]', 200);
        }
        return http.Response(_fx('gemini_web_usage.txt'), 200);
      });
      final s = await GeminiProvider().fetchSafely(
        _acct('gemini', secret: 'Cookie: __Secure-1PSID=stale', homeDir: home.path),
        _ctx(client),
      );
      expect(s.error, isNull, reason: s.error);
      expect(s.source, 'firefox');
      expect(cookieHeaders, hasLength(2));
      expect(cookieHeaders[0], contains('__Secure-1PSID=stale'));
      expect(cookieHeaders[1], contains('__Secure-1PSID=fresh-sid'));
    });
  });

  group('kiro', () {
    test('identity comes from the CLI database rows', () {
      final id = parseKiroIdentity(
        '{"access_token":"tok"}',
        '{"arn":"arn:aws:codewhisperer:us-east-1:123:profile/abc"}',
      );
      expect(id.accessToken, 'tok');
      expect(id.profileArn, 'arn:aws:codewhisperer:us-east-1:123:profile/abc');
      expect(() => parseKiroIdentity(null, null), throwsA(isA<ProviderException>()));
    });

    test('profile region selects the endpoint, unknown regions are skipped', () {
      expect(
        kiroUsageEndpoint('arn:aws:codewhisperer:us-east-1:123:profile/abc').toString(),
        'https://codewhisperer.us-east-1.amazonaws.com/',
      );
      expect(
        kiroUsageEndpoint('arn:aws:codewhisperer:eu-central-1:123:profile/abc').toString(),
        'https://q.eu-central-1.amazonaws.com/',
      );
      expect(
        () => kiroUsageEndpoint('arn:aws:codewhisperer:ap-south-1:123:profile/abc'),
        throwsA(isA<ProviderException>()),
      );
      expect(
        () => kiroUsageEndpoint('arn:aws:codewhisperer:us-east-1:123:profile/'),
        throwsA(isA<ProviderException>()),
      );
    });

    test('GetUsageLimits maps plan credits, overage and cost', () {
      final u = parseKiroUsageLimits(_fxJson('kiro_getUsageLimits.json'));
      expect(u.plan, 'Kiro Power');
      final credits = u.windows.firstWhere((w) => w.id == 'kiro-credits');
      expect(credits.usedPercent, closeTo(100, 1e-6));
      expect(credits.resetsAt, DateTime.utc(2026, 9, 1));
      final overage = u.windows.firstWhere((w) => w.id == 'kiro-overage');
      expect(overage.usedPercent, closeTo(36.0349, 1e-3));
      final cost = u.credits.firstWhere((c) => c.id == 'kiro-overage-cost');
      expect(cost.used, closeTo(144.139711109352, 1e-9));
      expect(cost.limit, closeTo(400, 1e-9));
      expect(cost.currency, 'USD');
    });
  });

  group('jetbrains', () {
    test('quota XML maps the monthly window and refill date', () {
      final u = parseJetBrainsQuotaXml(_fx('jetbrains_AIAssistantQuotaManager2.xml'));
      expect(u.type, 'Available');
      final w = u.windows.single;
      expect(w.id, 'jetbrains-monthly');
      expect(w.usedPercent, closeTo(7478.3 / 1000000 * 100, 1e-9));
      expect(w.resetsAt, DateTime.utc(2026, 1, 16, 14, 0, 54, 939));
      expect(w.windowMinutes, isNull);
      expect(u.credits, isEmpty);
    });

    test('top-up credits are reported as balance in 100000-unit credits', () {
      const xml = '''
<application><component name="AIAssistantQuotaManager2">
<option name="quotaInfo" value="{&quot;type&quot;:&quot;Available&quot;,&quot;current&quot;:&quot;0&quot;,&quot;maximum&quot;:&quot;1000&quot;,&quot;topUpQuota&quot;:{&quot;maximum&quot;:&quot;5000000&quot;,&quot;available&quot;:&quot;5489986.397&quot;}}"/>
</component></application>''';
      final u = parseJetBrainsQuotaXml(xml);
      expect(u.credits.single.id, 'jetbrains-topup');
      expect(u.credits.single.balance, closeTo(50, 1e-9));
    });

    test('IDE directory names map to display names', () {
      expect(jetBrainsIdeName('IntelliJIdea2025.3'), 'IntelliJ IDEA 2025.3');
      expect(jetBrainsIdeName('PyCharmCE2025.1'), 'PyCharm CE2025.1');
      expect(jetBrainsIdeName('Unknown'), isNull);
    });

    test('missing component is an explicit error', () {
      expect(() => parseJetBrainsQuotaXml('<application/>'), throwsA(isA<ProviderException>()));
    });

    test('no IDE directory configured asks for one', () async {
      final s = await JetBrainsProvider().fetchSafely(
        _acct('jetbrains', source: SourceType.localCli),
        _ctx(MockClient((_) async => http.Response('', 500))),
      );
      expect(s.error, contains('未指定'));
    });
  });

  group('amp', () {
    test('day subscription uses legacy remaining percentages', () {
      final u = parseAmpDisplayText(_fx('amp_cli_day_subscription.txt'), _now);
      expect(u.email, 'fixture@example.test');
      expect(u.plan, 'Megawatt');
      expect(_w(_snap(u), 'amp-agent').usedPercent, closeTo(3, 1e-9));
      expect(_w(_snap(u), 'amp-orb').usedPercent, closeTo(0, 1e-9));
      expect(_w(_snap(u), 'amp-agent').resetsAt, _now.add(const Duration(days: 29)));
    });

    test('monthly text yields free, subscription, individual and workspace rows', () {
      final u = parseAmpDisplayText(_fx('amp_cli_monthly_subscription.txt'), _now);
      final s = _snap(u);
      expect(_w(s, 'amp-free').usedPercent, closeTo(39, 1e-9));
      expect(_w(s, 'amp-free').windowMinutes, 1440);
      expect(_w(s, 'amp-agent').usedPercent, closeTo(27, 1e-9));
      expect(_w(s, 'amp-orb').usedPercent, closeTo(9, 1e-9));
      expect(s.credits.firstWhere((c) => c.id == 'amp-individual').balance, closeTo(17.23, 1e-9));
      expect(
        s.credits.firstWhere((c) => c.id == 'amp-workspace-meow').balance,
        closeTo(5.33, 1e-9),
      );
      expect(u.plan, 'Gigawatt');
    });

    test('tier text with agent dollars and orb hours uses the billing period', () {
      const text =
          'Amp Megawatt Tier: agent usage \$18.57 of \$20 remaining (93%), orb usage 732.8h of 750h '
          'a1.small orb hours remaining (98%) - period 2026-09-13 to 2026-10-13, resets upon renewal in 19 days';
      final s = _snap(parseAmpDisplayText(text, _now));
      expect(_w(s, 'amp-agent').usedPercent, closeTo(7.15, 1e-9));
      expect(_w(s, 'amp-agent').windowMinutes, 43200);
      expect(_w(s, 'amp-agent').resetsAt, DateTime.utc(2026, 10, 13));
      expect(_w(s, 'amp-orb').usedPercent, closeTo(2.2933, 1e-3));
    });

    test('unrecognised text is an explicit error', () {
      expect(
        () => parseAmpDisplayText('nothing useful here', _now),
        throwsA(isA<ProviderException>().having((e) => e.message, 'message', contains('没有可识别'))),
      );
    });

    test('API auth-required error becomes a token hint', () async {
      final client = MockClient(
        (_) async => _json({
          'ok': false,
          'error': {'code': 'auth-required', 'message': 'no'},
        }),
      );
      final s = await AmpProvider().fetchSafely(_acct('amp', secret: 'bad'), _ctx(client));
      expect(s.error, contains('无效或已过期'));
    });

    test('API success returns displayText windows', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return _json({
          'ok': true,
          'result': {'displayText': _fx('amp_cli_day_subscription.txt')},
        });
      });
      final s = await AmpProvider().fetchSafely(_acct('amp', secret: 'tok'), _ctx(client));
      expect(s.error, isNull);
      expect(seen.url.toString(), 'https://ampcode.com/api/internal?userDisplayBalanceInfo');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.body, contains('userDisplayBalanceInfo'));
      expect(s.plan, 'Megawatt');
    });
  });

  group('kilo', () {
    test('batch pass fixture maps credit block and pass plan', () {
      final entries = kiloEntries(jsonDecode(_fx('kilo_trpc_batch_pass.json')));
      final u = parseKiloUsage(entries);
      final credits = u.windows.firstWhere((w) => w.id == 'kilo-credits');
      expect(credits.usedPercent, closeTo(25, 1e-9));
      expect(u.plan, contains('Kilo Pass Pro'));
      expect(u.plan, contains('自动充值'));
      expect(u.credits.firstWhere((c) => c.id == 'kilo-balance').balance, closeTo(75, 1e-9));
    });

    test('micro-USD blocks and zero balance are converted', () {
      final blocks = kiloEntries([
        {
          'result': {
            'data': {
              'json': {
                'creditBlocks': [
                  {'amount_mUsd': 100000000, 'balance_mUsd': 19000000},
                ],
              },
            },
          },
        },
        {
          'result': {
            'data': {
              'json': {
                'plan': {'name': 'Kilo Pass'},
              },
            },
          },
        },
      ]);
      expect(parseKiloUsage(blocks).windows.single.usedPercent, closeTo(81, 1e-9));

      final empty = kiloEntries([
        {
          'result': {
            'data': {
              'json': {'totalBalance_mUsd': 0},
            },
          },
        },
        {
          'result': {
            'data': {'json': {}},
          },
        },
      ]);
      expect(parseKiloUsage(empty).windows.single.usedPercent, 100);
    });

    test('API key request sends bearer, batch url and org header', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response(_fx('kilo_trpc_batch_pass.json'), 200);
      });
      final s = await KiloProvider().fetchSafely(
        _acct('kilo', secret: 'kilo-key', options: {'orgId': 'org-9'}),
        _ctx(client),
      );
      expect(s.error, isNull);
      expect(
        seen.url.path,
        '/api/trpc/user.getCreditBlocks,kiloPass.getState,user.getAutoTopUpPaymentMethod',
      );
      expect(seen.url.queryParameters['batch'], '1');
      expect(seen.headers['Authorization'], 'Bearer kilo-key');
      expect(seen.headers['X-KILOCODE-ORGANIZATIONID'], 'org-9');
      expect(s.source, 'api-key');
    });

    test('401 gives an authentication failure', () async {
      final client = MockClient((_) async => http.Response('{}', 401));
      final s = await KiloProvider().fetchSafely(_acct('kilo', secret: 'bad'), _ctx(client));
      expect(s.error, contains('认证失败'));
    });
  });

  group('hyper', () {
    test('API key returns the HC balance', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response(_fx('hyper_credits.json'), 200);
      });
      final s = await HyperProvider().fetchSafely(_acct('hyper', secret: 'hk'), _ctx(client));
      expect(s.error, isNull);
      expect(seen.url.toString(), 'https://hyper.charm.land/v1/credits');
      expect(seen.headers['Authorization'], 'Bearer hk');
      expect(s.credits.single.balance, 42.5);
      expect(s.source, 'api-key');
    });

    test('pasted cookie reads the dashboard balance', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response.bytes(utf8.encode(_fx('hyper_dashboard.html')), 200);
      });
      final provider = HyperProvider();
      final account = AccountConfig(
        id: 'a',
        providerId: 'hyper',
        label: 'hyper',
        secret: SecretBundle.encode({'cookie': 'session=abc'}),
      );
      final s = await provider.fetchSafely(account, _ctx(client));
      expect(s.error, isNull);
      expect(seen.url.toString(), 'https://hyper.charm.land/');
      expect(seen.headers['Cookie'], 'session=abc');
      expect(s.credits.single.balance, 100);
      expect(s.source, 'web');
    });

    test('rejected cookie falls back to the API key', () async {
      final client = MockClient((r) async {
        if (r.url.path == '/') return http.Response('<html>sign in</html>', 200);
        return http.Response(_fx('hyper_credits.json'), 200);
      });
      final account = AccountConfig(
        id: 'a',
        providerId: 'hyper',
        label: 'hyper',
        secret: SecretBundle.encode({'secret': 'hk', 'cookie': 'session=old'}),
      );
      final s = await HyperProvider().fetchSafely(account, _ctx(client));
      expect(s.error, isNull);
      expect(s.source, 'api-key');
      expect(s.credits.single.balance, 42.5);
    });

    test('rejected cookie without a key reports an expired session', () async {
      final client = MockClient((_) async => http.Response('<html>sign in</html>', 200));
      final account = AccountConfig(
        id: 'a',
        providerId: 'hyper',
        label: 'hyper',
        secret: SecretBundle.encode({'cookie': 'session=old'}),
      );
      final s = await HyperProvider().fetchSafely(account, _ctx(client));
      expect(s.error, contains('会话已过期'));
    });

    test('invalid balance is rejected', () async {
      final client = MockClient((_) async => http.Response('{"balance":"invalid"}', 200));
      final s = await HyperProvider().fetchSafely(_acct('hyper', secret: 'hk'), _ctx(client));
      expect(s.error, contains('非负数字'));
    });

    test('dashboard numeric prefix with trailing junk does not match', () {
      expect(
        parseHyperSessionBalance(
          'Hypercredits Available</p><p class="text-5xl font-bold">100oops<',
        ),
        isNull,
      );
      expect(
        parseHyperSessionBalance(
          'Hypercredits Available</p><p class="text-5xl font-bold">1,250</p>',
        ),
        1250,
      );
    });
  });
}

/// Snapshot view of parsed Amp data, for window/credit lookups.
UsageSnapshot _snap(
  ({String? email, String? plan, List<RateWindow> windows, List<Credits> credits}) u,
) => UsageSnapshot(
  accountId: 'a',
  providerId: 'amp',
  fetchedAt: DateTime.utc(2026, 10, 24, 12),
  plan: u.plan,
  windows: u.windows,
  credits: u.credits,
);
