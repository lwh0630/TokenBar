import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:token_bar/l10n/app_localizations.dart';
import 'package:token_bar/services/update/app_version.dart';
import 'package:token_bar/services/update/release_assets.dart';
import 'package:token_bar/services/update/update_installer.dart';
import 'package:token_bar/services/update/update_installer_io.dart';
import 'package:token_bar/services/update/update_service.dart';
import 'package:token_bar/state/settings.dart';
import 'package:token_bar/state/update_controller.dart';
import 'package:token_bar/ui/update_dialog.dart';

const _base = 'https://github.com/lwh0630/TokenBar/releases/download/v1.3.0';

ReleaseAsset _asset(String name, {int size = 0}) =>
    ReleaseAsset(name: name, url: Uri.parse('$_base/$name'), size: size);

ReleaseInfo _release(List<ReleaseAsset> assets) => ReleaseInfo(
  tag: 'v1.3.0',
  version: const AppVersion(1, 3, 0),
  notes: 'Notes',
  pageUrl: Uri.parse('https://github.com/lwh0630/TokenBar/releases/tag/v1.3.0'),
  assets: assets,
);

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  group('release assets', () {
    final all = [
      for (final t in UpdateTarget.values) _asset('tokenbar-v1.3.0${t.suffix}'),
      _asset('SHA256SUMS.txt'),
    ];

    test('every target finds exactly its own file', () {
      for (final t in UpdateTarget.values) {
        expect(pickAsset(all, t)!.name, 'tokenbar-v1.3.0${t.suffix}');
      }
      expect(pickAsset(all.take(1), UpdateTarget.macosArm64), isNull);
      expect(pickChecksums(all)!.name, 'SHA256SUMS.txt');
      expect(pickChecksums(all.take(2)), isNull);
    });

    test('reads sha256sum lists in their usual spellings', () {
      final a = 'a' * 64, b = 'B' * 64, c = 'c' * 64;
      final sums =
          '$a  tokenbar-v1.3.0-linux-x64.tar.gz\r\n'
          '$b *./tokenbar-v1.3.0-windows-x64-setup.exe\n'
          'not a line\n'
          '$c  dist/tokenbar-v1.3.0-android-arm64-v8a.apk\n';
      expect(expectedSha256(sums, 'tokenbar-v1.3.0-linux-x64.tar.gz'), a);
      expect(expectedSha256(sums, 'tokenbar-v1.3.0-windows-x64-setup.exe'), 'b' * 64);
      expect(expectedSha256(sums, 'tokenbar-v1.3.0-android-arm64-v8a.apk'), c);
      expect(expectedSha256(sums, 'tokenbar-v1.3.0-macos-arm64.dmg'), isNull);
    });

    test('only this repository\'s release downloads are trusted', () {
      bool ok(String u) => isTrustedAssetUrl(Uri.parse(u));
      expect(ok('$_base/x.exe'), isTrue);
      expect(ok('http://github.com/lwh0630/TokenBar/releases/download/v1/x.exe'), isFalse);
      expect(ok('https://github.com/evil/TokenBar/releases/download/v1/x.exe'), isFalse);
      expect(ok('https://github.com.evil.io/lwh0630/TokenBar/releases/download/v1/x'), isFalse);
      expect(ok('https://github.com/lwh0630/TokenBar/archive/main.zip'), isFalse);
    });

    test('parseRelease keeps only trusted assets', () {
      final r = UpdateService.parseRelease({
        'tag_name': 'v1.3.0',
        'draft': false,
        'prerelease': false,
        'body': '',
        'html_url': 'https://github.com/lwh0630/TokenBar/releases/tag/v1.3.0',
        'assets': [
          {'name': 'good.exe', 'browser_download_url': '$_base/good.exe', 'size': 12},
          {'name': 'evil.exe', 'browser_download_url': 'https://evil.example/evil.exe'},
          {'name': 'no-url.exe'},
          'junk',
        ],
      })!;
      expect(r.assets.map((a) => a.name), ['good.exe']);
      expect(r.assets.single.size, 12);
    });
  });

  group('IoUpdateInstaller', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tokenbar_update_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    final payload = utf8.encode('pretend this is an installer' * 50);
    const name = 'tokenbar-v1.3.0-windows-x64-setup.exe';

    /// A client serving [payload] (or [served] instead) for the installer and [sums] for the list.
    MockClient client({List<int>? served, String? sums, int status = 200}) =>
        MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('SHA256SUMS.txt')) {
            final body = utf8.encode(sums ?? '${_sha(payload)}  $name\n');
            return http.StreamedResponse(Stream.value(body), status, contentLength: body.length);
          }
          final body = served ?? payload;
          return http.StreamedResponse(
            Stream.fromIterable([body.sublist(0, 100), body.sublist(100)]),
            status,
            contentLength: body.length,
          );
        });

    ReleaseInfo release() =>
        _release([_asset(name, size: payload.length), _asset('SHA256SUMS.txt')]);

    IoUpdateInstaller make(
      http.Client c, {
      UpdateTarget target = UpdateTarget.windowsX64,
      bool managed = true,
      void Function(File)? onWindows,
      Future<String> Function(String)? apk,
      Future<void> Function(String)? open,
    }) => IoUpdateInstaller(
      client: c,
      target: target,
      workDir: dir,
      managedWindowsInstall: managed,
      startWindowsInstaller: (f) async => onWindows?.call(f),
      installApk: apk,
      openPath: open,
    );

    test('downloads, verifies and starts the Windows installer', () async {
      File? started;
      final stages = <UpdateInstallStage>[];
      final progress = <double?>[];
      final out = await make(
        client(),
        onWindows: (f) => started = f,
      ).install(release(), onStage: stages.add, onProgress: progress.add);
      expect(out.kind, UpdateInstallKind.quitForInstaller);
      expect(started!.readAsBytesSync(), payload);
      expect(stages, [
        UpdateInstallStage.downloading,
        UpdateInstallStage.verifying,
        UpdateInstallStage.installing,
      ]);
      expect(progress.last, 1.0);
    });

    test('a corrupted or tampered file is discarded and never started', () async {
      var launched = false;
      final bad = [...payload]..[10] ^= 0xff;
      await expectLater(
        make(client(served: bad), onWindows: (_) => launched = true).install(release()),
        throwsA(isA<UpdateInstallException>().having((e) => e.code, 'code', 'checksum')),
      );
      expect(launched, isFalse);
      expect(File('${dir.path}/$name').existsSync(), isFalse);
    });

    test('a checksum list without the file fails before downloading it', () async {
      var downloads = 0;
      final c = MockClient.streaming((request, _) async {
        if (!request.url.path.endsWith('SHA256SUMS.txt')) downloads++;
        final body = utf8.encode('${'0' * 64}  something-else.exe\n');
        return http.StreamedResponse(Stream.value(body), 200);
      });
      await expectLater(
        make(c).install(release()),
        throwsA(isA<UpdateInstallException>().having((e) => e.code, 'code', 'checksum')),
      );
      expect(downloads, 0);
    });

    test('HTTP errors and a missing asset are reported', () async {
      await expectLater(
        make(client(status: 500)).install(release()),
        throwsA(isA<UpdateInstallException>().having((e) => e.code, 'code', 'network')),
      );
      await expectLater(
        make(client()).install(_release([_asset('SHA256SUMS.txt')])),
        throwsA(isA<UpdateInstallException>().having((e) => e.code, 'code', 'no_asset')),
      );
    });

    test('a cancelled download leaves nothing behind', () async {
      final token = UpdateCancelToken();
      await expectLater(
        make(client()).install(release(), cancel: token, onProgress: (_) => token.cancel()),
        throwsA(isA<UpdateInstallException>().having((e) => e.code, 'code', 'cancelled')),
      );
      expect(File('${dir.path}/$name').existsSync(), isFalse);
    });

    test('canInstall needs an asset, checksums, and a managed Windows install', () {
      final r = release();
      expect(make(client()).canInstall(r), isTrue);
      expect(make(client(), managed: false).canInstall(r), isFalse);
      expect(make(client()).canInstall(_release([_asset(name)])), isFalse); // no checksums
      expect(make(client(), target: UpdateTarget.macosArm64).canInstall(r), isFalse);
      expect(
        IoUpdateInstaller(client: client(), target: null).canInstall(r),
        isFalse,
        reason: 'iOS and anything else without a build',
      );
    });

    test('Android hands the APK to the system, or asks for the permission', () async {
      const apk = 'tokenbar-v1.3.0-android-arm64-v8a.apk';
      final c = MockClient.streaming((request, _) async {
        final body = request.url.path.endsWith('SHA256SUMS.txt')
            ? utf8.encode('${_sha(payload)}  $apk\n')
            : payload;
        return http.StreamedResponse(Stream.value(body), 200, contentLength: body.length);
      });
      final r = _release([_asset(apk), _asset('SHA256SUMS.txt')]);

      String? opened;
      final ok = await make(
        c,
        target: UpdateTarget.androidArm64,
        apk: (p) async {
          opened = p;
          return 'started';
        },
      ).install(r);
      expect(ok.kind, UpdateInstallKind.handedToSystem);
      expect(opened, endsWith(apk));

      await expectLater(
        make(c, target: UpdateTarget.androidArm64, apk: (_) async => 'needs_permission').install(r),
        throwsA(isA<UpdateInstallException>().having((e) => e.code, 'code', 'permission')),
      );
      await expectLater(
        make(c, target: UpdateTarget.androidArm64, apk: (_) async => 'failed').install(r),
        throwsA(isA<UpdateInstallException>().having((e) => e.code, 'code', 'launch')),
      );
    });

    test('macOS opens the dmg, Linux opens its folder', () async {
      Future<UpdateInstallOutcome> run(UpdateTarget t, String file, List<String> opened) {
        final c = MockClient.streaming((request, _) async {
          final body = request.url.path.endsWith('SHA256SUMS.txt')
              ? utf8.encode('${_sha(payload)}  $file\n')
              : payload;
          return http.StreamedResponse(Stream.value(body), 200, contentLength: body.length);
        });
        return make(
          c,
          target: t,
          open: (p) async => opened.add(p),
        ).install(_release([_asset(file), _asset('SHA256SUMS.txt')]));
      }

      final mac = <String>[];
      final m = await run(UpdateTarget.macosArm64, 'tokenbar-v1.3.0-macos-arm64.dmg', mac);
      expect(m.kind, UpdateInstallKind.savedFile);
      expect(mac.single, endsWith('.dmg'));
      expect(File(m.path!).existsSync(), isTrue);

      final linux = <String>[];
      await run(UpdateTarget.linuxX64, 'tokenbar-v1.3.0-linux-x64.tar.gz', linux);
      expect(linux.single, dir.path);
    });
  });

  group('UpdateController.install', () {
    late AppSettings settings;
    setUp(() => settings = AppSettings.defaults());

    UpdateController make(_FakeInstaller installer) => UpdateController(
      readSettings: () => settings,
      saveSettings: (s) async => settings = s,
      service: UpdateService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v1.3.0',
              'draft': false,
              'prerelease': false,
              'body': 'n',
              'html_url': 'https://github.com/lwh0630/TokenBar/releases/tag/v1.3.0',
            }),
            200,
          ),
        ),
      ),
      installer: installer,
      versionLoader: () async => '1.0.0',
    );

    test('reports progress and returns the outcome', () async {
      final fake = _FakeInstaller();
      final u = make(fake);
      await u.init();
      expect(u.canInstall, isTrue);

      final seen = <UpdateInstallStage?>[];
      u.addListener(() => seen.add(u.installStage));
      final outcome = await u.install();
      expect(outcome!.kind, UpdateInstallKind.handedToSystem);
      expect(u.installing, isFalse);
      expect(u.installErrorCode, isNull);
      expect(seen, contains(UpdateInstallStage.verifying));
      expect(u.installStage, isNull);
    });

    test('keeps the failure code, and a cancel is not a failure', () async {
      final fake = _FakeInstaller()..fail = 'checksum';
      final u = make(fake);
      await u.init();
      expect(await u.install(), isNull);
      expect(u.installErrorCode, 'checksum');

      fake.fail = 'cancelled';
      expect(await u.install(), isNull);
      expect(u.installErrorCode, isNull);
    });

    test('cancelInstall reaches the running install', () async {
      final fake = _FakeInstaller()..hold = Completer<void>();
      final u = make(fake);
      await u.init();
      final run = u.install();
      await Future<void>.delayed(Duration.zero);
      expect(u.installing, isTrue);
      expect(await u.install(), isNull, reason: 'a second install does not start');
      u.cancelInstall();
      fake.hold!.complete();
      await run;
      expect(fake.sawCancel, isTrue);
      expect(u.installing, isFalse);
    });
  });

  group('update dialog', () {
    Future<(UpdateController, ReleaseInfo)> boot(_FakeInstaller fake) async {
      var settings = AppSettings.defaults();
      final u = UpdateController(
        readSettings: () => settings,
        saveSettings: (s) async => settings = s,
        service: UpdateService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'tag_name': 'v1.3.0',
                'draft': false,
                'prerelease': false,
                'body': 'Faster',
                'html_url': 'https://github.com/lwh0630/TokenBar/releases/tag/v1.3.0',
              }),
              200,
            ),
          ),
        ),
        installer: fake,
        versionLoader: () async => '1.0.0',
      );
      await u.init();
      return (u, u.takePrompt()!);
    }

    Future<void> open(WidgetTester tester, UpdateController u, ReleaseInfo r) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpdateDialog(context, u, r),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers Update now where it can install, and shows a failure', (tester) async {
      final fake = _FakeInstaller()..fail = 'checksum';
      final (u, r) = await tester.runAsync(() => boot(fake)).then((v) => v!);
      await open(tester, u, r);

      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Open release page'), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('checksum'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget, reason: 'can be retried');
    });

    testWidgets('falls back to Download when the build cannot be installed', (tester) async {
      final fake = _FakeInstaller()..installable = false;
      final (u, r) = await tester.runAsync(() => boot(fake)).then((v) => v!);
      await open(tester, u, r);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Update now'), findsNothing);
    });

    testWidgets('shows progress while downloading and where a file was saved', (tester) async {
      final fake = _FakeInstaller()
        ..hold = Completer<void>()
        ..outcome = const UpdateInstallOutcome(UpdateInstallKind.savedFile, path: '/tmp/x.dmg');
      final (u, r) = await tester.runAsync(() => boot(fake)).then((v) => v!);
      await open(tester, u, r);

      await tester.tap(find.text('Update now'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.textContaining('Downloading'), findsOneWidget);

      fake.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('/tmp/x.dmg'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}

class _FakeInstaller implements UpdateInstaller {
  bool installable = true;
  String? fail;
  Completer<void>? hold;
  bool sawCancel = false;
  UpdateInstallOutcome outcome = const UpdateInstallOutcome(UpdateInstallKind.handedToSystem);

  @override
  bool canInstall(ReleaseInfo release) => installable;

  @override
  Future<UpdateInstallOutcome> install(
    ReleaseInfo release, {
    void Function(UpdateInstallStage stage)? onStage,
    void Function(double? fraction)? onProgress,
    UpdateCancelToken? cancel,
  }) async {
    onStage?.call(UpdateInstallStage.downloading);
    onProgress?.call(0.5);
    if (hold != null) await hold!.future;
    sawCancel = cancel?.cancelled ?? false;
    if (sawCancel) throw const UpdateInstallException('cancelled');
    final f = fail;
    if (f != null) throw UpdateInstallException(f);
    onStage?.call(UpdateInstallStage.verifying);
    return outcome;
  }
}
