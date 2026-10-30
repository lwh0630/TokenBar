# TokenBar — Agent Guide

TokenBar is an open-source, cross-platform AI quota monitor inspired by [CodexBar](https://github.com/steipete/CodexBar), built with Flutter + Dart.
It supports Windows, macOS, Linux, Android and iOS (plus a Web build, meant to be used with the sync server).
Users add a service in the client (local login / API key / cookie) and the client queries the provider directly for quota. The server is an optional component, used only to sync snapshots across devices.

- Repository: <https://github.com/lwh0630/TokenBar> (public, MIT, default branch `main`).
- **Reply to the user in Simplified Chinese.** Code comments, the main README and commit messages are in English (except `README.zh-CN.md` and the Chinese strings inside the app).
- This file is the single source of conventions; `CLAUDE.md` is only an `@AGENTS.md` reference. Change conventions in this file only, and keep it consistent with the code.
- Order of work on a task: read this file → read the relevant code and tests → make the change → self-check with the "Checklist for finishing a change" → commit and push → wait for CI.

## Layout

```
lib/                            Flutter app (provider + ChangeNotifier)
  main.dart                     Startup, MaterialApp, mount point of the tray panel (the panel brings its own Overlay)
  app/                          app_shell.dart (navigation: side rail on wide screens / bottom bar on narrow ones), theme.dart (theme, font fallback, seriesPalette)
  app_info.dart                 Constants such as the repository name and project homepage
  demo/demo_data.dart           Fictional accounts / snapshots / history / per-model usage for demo mode (used for screenshots)
  l10n/                         app_zh.arb (template), app_en.arb, generated app_localizations*.dart (committed), app_locale.dart
  state/app_controller.dart     Accounts, refresh, sync, auto-detection of local logins, modelUsage, updateSettings
  state/settings.dart           AppSettings, SyncMode, AppLanguage, platform checks (canUseLocalLogins)
  state/update_controller.dart  Update-check state
  services/                     persistence (secure storage), desktop_io/desktop_stub (tray / window, conditional import),
                                notifier, quota_alerts, home_widget_bridge, history_*, update/ (reads GitHub releases)
  ui/pages/                     dashboard / accounts (the editor is generated from ProviderField) / account_detail / settings
  ui/widgets/                   account_card, quota_ring, usage_bar, history_chart, stacked_bar_chart, provider_badge ...
  ui/tray_panel.dart            Small desktop tray panel
  ui/format.dart                Formatting with AppLocalizations (countdowns, percentages, money, window labels)
  ui/chart_math.dart, history_series.dart   Pure functions for the charts (unit tested)
packages/tokenbar_core/         Pure Dart: models, per-service fetching, sync client, tray icon rendering
  lib/src/models/               AccountConfig, UsageSnapshot, RateWindow, Credits, UsagePoint, ModelUsageSeries
  lib/src/providers/            provider.dart (base class), fields.dart, http_support.dart, common.dart, registry.dart
    api/                        Simple services (files grouped by category, several services per file)
    codex/ claude/ cursor/      Services with complex logic such as reading local credentials or per-model usage
  lib/src/platform/             platform_io.dart / platform_stub.dart (conditional import; web has no dart:io)
  test/                         Unit tests + fixtures/ (real response samples; log-style fixtures must be synthetic)
packages/tokenbar_server/       CLI (usage / collect / serve) and the optional sync server (shelf + sqlite)
test/                           App tests (widget, controller, charts, i18n, tray panel, demo data)
assets/provider_icons/          51 service logos (SVG, from CodexBar and Win-CodexBar; attribution in NOTICE.md)
assets/icon/                    Source image of the app icon
tool/gen_icons.py               Generates the app icons for every platform (never edit icon files by hand)
tool/build_windows_installer.ps1 Windows installer build + smoke test (shared by CI and release)
windows/installer/              Inno Setup script tokenbar.iss + ChineseSimplified.isl
android/ ios/ macos/ linux/ windows/ web/   Platform projects; Android native widget, iOS WidgetKit sources
.github/workflows/              ci.yml (checks + per-platform builds), release.yml (tag → draft release)
docs/screenshots/               README screenshots: English at the root, Chinese in zh/
README.md / README.zh-CN.md     English main doc / Chinese doc (keep the structure identical)
NOTICE.md                       Third-party attribution (CodexBar MIT, Inno Setup language file, ...)
third_party/CodexBar/           Reference source (.gitignore, not committed)
third_party/provider_specs/     API specs extracted from CodexBar (not committed; consult when implementing a new service)
HANDOFF.md                      Local handoff notes (.gitignore, not committed, may be stale; the code and this file win)
```

## Common commands

```bash
flutter pub get
flutter gen-l10n                 # After editing the ARB files (generated files must be committed)
flutter analyze                  # Repo root, covers the app
flutter test                     # App tests
cd packages/tokenbar_core && dart analyze && dart test
cd packages/tokenbar_server && dart test
dart format lib test packages    # CI checks formatting (line width 100, see analysis_options.yaml): dart format --output=none --set-exit-if-changed lib test packages
dart run packages/tokenbar_server/bin/tokenbar.dart usage -p cursor --json   # Verify with a real fetch
flutter run -d windows           # Local debugging; -d emulator-5554 / -d chrome also work
flutter build windows | web | apk
cd packages/tokenbar_server && dart build cli -o ../../build/server          # Do not use dart compile exe
```

Demo mode (fictional data only, in-memory storage, never touches real credentials, makes no network requests):

```bash
flutter run -d windows --dart-define=TOKENBAR_DEMO=true
  --dart-define=TOKENBAR_DEMO_LANG=en|zh     # Pin the UI language (follows the system by default)
  --dart-entrypoint-args=--panel             # Open the tray panel directly (--dart-define=TOKENBAR_PANEL=true does the same)
```

## Checklist for finishing a change

1. `dart format lib test packages` (line width 100) → `flutter analyze` → `flutter test`; if you touched `packages/*`, also run `dart analyze && dart test` in each of them. **All three places must be green.**
2. New / changed user-facing text: edit `app_zh.arb` and `app_en.arb` together, run `flutter gen-l10n`, and commit the generated files.
3. Pair new logic with tests: unit tests for pure functions; widget tests for UI (note that `MaterialApp` in tests needs a locale and delegates); for a bug fix, write a test that reproduces it first and confirm it fails once the fix is removed.
4. If you changed behavior or structure, or hit a new pitfall: update this file (the relevant section); for user-visible changes also update `README.md` and `README.zh-CN.md`.
5. Visible UI change: retake the affected images per the "Screenshots" section.
6. Do not introduce credentials, personal e-mail addresses or local paths (see "Security rules").
7. Commit and push, then wait for CI to go fully green (see the next section).

## Commit and push

- **Commit identity** must be the GitHub noreply address: `git config user.email` should be `79432134+lwh0630@users.noreply.github.com` and `user.name` should be `lwh0630`. Check `git config user.email` before committing; do not use a personal e-mail, and do not change the global config — set it in this repository only.
- Push with the logged-in `gh` (account `lwh0630`, https): `git push origin main`. `gh` occasionally reports `unexpected EOF`; just retry (use a retry loop in scripts).
- Commit message: English, a one-line summary (imperative mood, within ~70 characters) + a blank line + a bullet list explaining "why / what changed". One commit does one kind of thing.
- Before committing, glance at `git status` and make sure `build/`, `*.jks`, `key.properties`, `third_party/`, `HANDOFF.md`, `.dart_tool/` (all already in `.gitignore`) and temporary scripts / screenshot drafts are not included.
- Push directly to `main` by default (personal project); for large or risky changes open a branch first and use `gh pr create`.
- After pushing, watch CI: `gh run list --repo lwh0630/TokenBar --workflow CI --limit 1 --json status,conclusion,headSha`, polling until `completed`; investigate failures with `gh run view <id> --log-failed`. CI builds every platform on GitHub — **do not build release packages locally** (locally, only run analyze / test / `flutter run` debugging and screenshots).
- When parallel sub-agents / several tasks edit files at the same time, `git add` only the files you changed; never `git add -A` and sweep in someone else's half-written work.

## Release

All release artifacts are built by GitHub Actions. The Release is first created as a **draft**, and the maintainer publishes it manually after testing it.

1. Make sure CI on the latest commit of `main` is green, the working tree is clean, and the README download table / platform status match reality.
2. Push a tag to trigger `release.yml`: `git tag vX.Y.Z && git push origin vX.Y.Z` (you can also trigger `workflow_dispatch` on the Actions page and enter the version).
3. Wait for the Release workflow to finish (`gh run list --workflow Release`), then check the draft: `gh release view vX.Y.Z --repo lwh0630/TokenBar --json isDraft,assets`. It should contain:
   - Android: three signed APKs — `arm64-v8a`, `armeabi-v7a`, `x86_64`
   - Windows: `-setup.exe` for x64 / arm64
   - macOS: `.dmg` for arm64 / x86_64
   - Linux: `.tar.gz` for x64 / arm64
   - iOS: `-ios-unsigned.ipa`
   - `SHA256SUMS.txt`
4. **To re-cut the same version** (the tag points at an old commit): `gh release delete vX.Y.Z --repo lwh0630/TokenBar --cleanup-tag --yes` → `git tag -d vX.Y.Z` → re-run `git tag vX.Y.Z && git push origin vX.Y.Z` on the latest commit. Never do this for a version that is already published (not a draft); ship a new patch version instead.
5. Leave the draft as a draft and tell the user to test it (especially the macOS dmg, the Windows installer and upgrading an installed Android app); publish only after the user confirms: `gh release edit vX.Y.Z --draft=false` (or click Publish on the web page).
6. Version numbers: `version` in `pubspec.yaml` is only a development default; CI overrides `--build-name` with the tag, and `--build-number` is `github.run_number`. The in-app "Check for updates" reads `releases/latest` (ignoring drafts / pre-releases).

Upgrading the Flutter version: change `FLUTTER_VERSION` and `FLUTTER_COMMIT` (the full commit of that tag) in `ci.yml` and `release.yml` together, and update the README badge / build notes. Pin every third-party Action to a full commit SHA (put the tag in a comment).

## Screenshots (for the README)

- Always take them in demo mode, with **fictional data only**: no real e-mail addresses, local paths or personal account information.
- Retake them whenever the UI visibly changes; English ones go in `docs/screenshots/`, Chinese ones in `docs/screenshots/zh/` (`README.zh-CN.md` references `zh/`). File names: `windows-dashboard.png`, `windows-history.png`, `windows-tray-panel.png`, `android-dashboard.png`, `android-detail.png`, `android-history.png`. Light theme only.
- Windows: `flutter run -d windows --dart-define=TOKENBAR_DEMO=true --dart-define=TOKENBAR_DEMO_LANG=en`, window about 1400×1400 physical pixels (wide layout); use Pillow to scale to 1100 px wide and crop 12 px off the bottom and 2 px off each side. For the tray panel add `--dart-entrypoint-args=--panel` and scale to 420 px wide.
- Android: emulator `flutter run -d emulator-5554 ...`, navigate with `adb shell screencap` + `adb shell input swipe/tap`, scale to 540 px wide.
- Pitfall: Flutter desktop / the emulator does not repaint without input, so the capture may be the previous frame; after scrolling, wiggle the mouse (or capture again) before taking the image. Wheel events are delayed, so scroll in small steps.
- The demo per-model usage lives in `DemoData.modelUsage` (only Cursor / Codex; deterministic, generated from an hourly seed).

## Core concepts

- `UsageProvider` (`provider.dart`): `id`, `displayName`, `brandColor`, `supportedSources`, `setupHint`, `fields`, `fetch()`, and optionally `fetchModelUsage()`.
  `fetchSafely()` turns a `ProviderException` into an error snapshot; the UI shows `message` + `hint` (in Chinese).
- `SourceType.localCli`: reads local files / runs a CLI (desktop only, `canUseLocalLogins`).
  `SourceType.apiKey`: fields the user fills in by hand (API key, cookie, base URL, region, ...); also usable on phones / the web.
- `ProviderField` (`fields.dart`): declares a hand-filled field. The value of a `kind: secret` field is stored in `AccountConfig.secret`
  (the raw value when there is a single primary credential with `key == 'secret'`, JSON when there are several, see `SecretBundle`); everything else goes in `AccountConfig.options`.
  `envVars` is the fallback on desktop when the field is left empty (reusing CodexBar's environment variable names). Always read values through `FieldValues.of(this, account)`.
- `UsageSnapshot`: `windows` (`RateWindow`, usedPercent 0–100, `resetsAt`, `windowMinutes`) + `credits` (`Credits`, balance / used / limit / currency) + `plan` / `email` / `source` / `extras`.
  The tray and widgets use `tightestWindow` (the window with the least remaining).
- `SyncMode`: `local` (no server), `server` (view server data), `localPush` (push local data). Local accounts are always fetched locally on non-web platforms.

## Adding a service

1. First read `third_party/provider_specs/<id>.md` (if it does not exist, check `third_party/CodexBar/Sources/CodexBarCore/Providers/<Name>/` and `docs/<id>.md`).
   **Endpoints, request headers, field names and units must come from CodexBar's source or the official docs — do not guess.**
2. Put simple services in a category-grouped file under `packages/tokenbar_core/lib/src/providers/api/` (one file may hold several services,
   e.g. `account_api_providers.dart`, `coding_plan_providers.dart`, `cookie_*_providers.dart`);
   put services with complex logic such as reading local credentials in `providers/<id>/`.
   - Write parsing as pure functions (`parseXxx(Map json) -> ...`) so it is easy to test with fixtures.
   - For HTTP use `fetchJsonObject` / `sendRequest` + `checkStatus` from `http_support.dart` (uniform timeout and Chinese errors for 401/403/429);
     shared helpers are in `common.dart` (`pct`, `quotaWindow`, `balanceRow`, `spendRow`, `gatewayBaseUrl`) and `flex_quota.dart`.
   - Window ids use an `<id>-xxx` prefix and labels are written directly in Chinese (e.g. `每月`, `每日`); money uses `Credits` with `currency` set to an ISO code, and non-monetary credits use null.
   - The `source` field: `api-key`, `web` (cookie), `local`, `admin-api`, etc.
3. Register it in `registry.dart`; only `show`-export a symbol from `tokenbar_core.dart` if tests or the UI need it.
4. Put real response samples in `test/fixtures/` (taken from CodexBar's tests) and write `MockClient` fetch tests in `test/`
   (use the `_run(providerId, {URL substring: response body or status code})` helper in `api_providers_test.dart`).
5. Update the service table and the service count (badge, numbers in the text) in `README.md` and `README.zh-CN.md`.
6. Service logo: if CodexBar has a matching `ProviderIcon-<name>.svg`, copy it to `assets/provider_icons/<id>.svg` as described in `assets/provider_icons/README.md`, and add the id to `providerIconIds` in `provider_badge.dart` (add colored logos to `providerColoredIconIds` as well); `test/provider_icons_test.dart` checks that the assets and the sets agree. Services without a logo fall back to an initial-letter square.

- MiMo uses a manually supplied Cookie header; there is no browser cookie extraction. Preserve balance when optional plan endpoints fail, suppress expired or incomplete plan windows, and disable redirects to sign-in pages.
- Copilot uses a manually supplied GitHub OAuth token or `COPILOT_API_TOKEN`, not a short-lived Copilot service token. Keep premium, completion and chat quotas separate, ignore `has_quota: false` placeholders, and never infer a remaining allowance from `credits_used` alone or sum shared counters. Provider tests must use synthetic account data.

## Internationalization (i18n)

- The app UI supports Simplified Chinese (template `lib/l10n/app_zh.arb`) and English (`lib/l10n/app_en.arb`); Flutter gen-l10n generates `lib/l10n/app_localizations*.dart` (configured in the root `l10n.yaml`, with `generate: true` in `pubspec.yaml`). The generated files must be committed (Flutter removed `synthetic-package`, and `.gitignore` does not ignore them); do not edit them by hand — after changing an ARB file run `flutter gen-l10n` (or `flutter pub get`).
- **New or changed user-facing text must be written in both `app_zh.arb` and `app_en.arb`** (`test/i18n_test.dart` checks that both sides have the same keys). Use placeholders for parameterized text and declare `@key.placeholders` in the template; use ICU `plural` for English plurals; single quotes must be written as `''` in ARB.
- The language setting is `AppSettings.language` (`AppLanguage.system / zh / en`, following the system by default: a Chinese system gets Chinese, every other language gets English), resolved by `resolveAppLocale` in `lib/l10n/app_locale.dart`. `MaterialApp` always sets an explicit `locale` (zh_CN or en_US); the CJK font fallback for Chinese is still in `AppTheme.fonts`.
- Getting text: in widgets use `AppLocalizations.of(context)`; code outside the widget tree (service layer, controller, tray) receives `AppLocalizations` as a parameter (a `l10n` getter on the controller) — do not use global mutable state. The formatting functions in `lib/ui/format.dart` all take an `AppLocalizations l` parameter.
- Error messages, `setupHint` and `ProviderField` labels in `packages/tokenbar_core` (the providers) are still in Chinese for now and are outside the UI translation scope. The UI-layer `windowLabel` only translates common window words (每周 / 每月 / 每日 / 5 小时 / 本月 / 今日 / 额度); add new common words in `_coreLabel` in `format.dart`.
- `MaterialApp` in tests needs `locale`, `supportedLocales` and `localizationsDelegates` (see `test/widget_test.dart`), otherwise `AppLocalizations.of` throws.

## Security rules (mandatory)

- Do not invent APIs; a non-public endpoint must have a basis in CodexBar's source, and its authorization method and limitations must be noted.
- Do not ask for or store account passwords; no simulated logins. Only use: logins that the official local client already has (read-only), and API keys / cookies / tokens the user pastes in on purpose.
- By default, do not refresh or rewrite other tools' tokens (refreshing rotates the refresh token and may sign the official client out). Claude refresh is an explicit switch, off by default.
- Credentials live only in the system secure storage (`flutter_secure_storage`); `AccountConfig.toJson()` does not output `secret`; never write credentials to logs, snapshots or the server.
- The server only receives quota snapshots, never any provider credentials.
- When reading local usage logs (such as Codex sessions), take only model names and numbers; do not read, store or output prompts, paths or session content; log fixtures used in tests must be synthetic.
- Never commit signing keystores (`*.jks`, `android/key.properties`); CI uses the secrets of the `production` Environment (`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`). `EXPECTED_CERT_SHA256` in `release.yml` is the public certificate fingerprint; changing the key would make installed APKs impossible to upgrade.
- Use the GitHub noreply address as the commit e-mail in the public repository, never a personal e-mail; screenshots must not contain real e-mail addresses, local paths or account information.

## Platform and release details

- CI / release matrix: `ci.yml` only checks and builds (format, analyze, tests, web build, Android debug, Windows x64/arm64 + installer smoke test, Linux x64/arm64, macOS, iOS); `release.yml` produces a **draft** Release. The `production` Environment holds the Android signing secrets.
- There is no Apple developer account for macOS / iOS: macOS only has an ad-hoc signature (not notarized), and iOS is built with `--no-codesign` and then packaged by hand from `Payload/Runner.app` into an ipa, so it can only be sideloaded. macOS has been tested by the maintainer; Linux, iOS and Windows arm64 are **not verified on real devices**, and the README and Release notes must keep saying so. Linux builds need `libgtk-3-dev libsecret-1-dev libayatana-appindicator3-dev` and more (see the workflow).
- The macOS arm64 / x86_64 dmgs are obtained from Flutter's universal build by thinning each Mach-O with `lipo -thin` and re-signing ad hoc (Flutter can only build a universal package).
- Windows installer: `windows/installer/tokenbar.iss` (Inno Setup, per-user install by default; never change the `AppId` GUID, otherwise upgrades cannot find the old installation; the Simplified Chinese language file `ChineseSimplified.isl` comes from the official Inno Setup repository, `is-6_5_4`). The build, bundling of the VC++ runtime, and the silent install / uninstall smoke test are all in `tool/build_windows_installer.ps1`, shared by CI and release.
- Windows / Linux arm64: Flutter does not publish arm64 SDK archives for these two platforms, so on the `windows-11-arm` / `ubuntu-24.04-arm` runners Flutter is cloned from source at a pinned commit (`FLUTTER_COMMIT`) and bootstraps the arm64 Dart itself. Using the x64 SDK would produce an x64 target, so the workflows verify the exe's PE machine type / the ELF architecture.
- Update check: `lib/services/update/` (`UpdateService` reads `releases/latest`, ignores drafts / pre-releases, trusts only github.com links) + `state/update_controller.dart`. It only opens the release page and never downloads or installs automatically. The repository-name constant is in `lib/app_info.dart`.
- Maintain the repository description and topics with `gh repo edit lwh0630/TokenBar --description ... --add-topic ...`; the description must state the supported platforms. Do not put absolute claims like "No server required" back into the README tagline.

## Pitfalls

- Linux CI and release builds use Ubuntu 24.04 to match the ARM64 baseline: `tray_manager` 0.5.x fails its `-Werror` build on Ubuntu 26.04 because `app_indicator_new` is deprecated there.
- The web build must not import `dart:io` / sqlite: always go through the conditional import in `platform/platform.dart` for local access.
- Android also has `dart:io`; to decide "can local logins be read" use `canUseLocalLogins` (= desktop platforms), not `localAccessSupported`.
- `sqlite3` 3.x uses build hooks: build the CLI with `dart build cli`; open Cursor's `state.vscdb` read-only (it can be read even while Cursor is running).
- `tray_manager` is pinned to `^0.5.0` (0.8 is an incompatible rewrite). On macOS it reads icons with `rootBundle.load(iconPath)`, which only supports assets bundled into the app; a tray icon generated at runtime has to bypass it and pass `base64Icon` directly through `MethodChannel('tray_manager')` (see `_setMacIcon` in `desktop_io.dart`). Linux's AppIndicator has no click events, so the tray panel is unavailable there — only the menu.
- Android: `flutter_local_notifications` needs core library desugaring; when the project and the pub cache are on different drive letters, `kotlin.incremental=false` is required (already configured).
- Request the notification permission after `runApp`, otherwise startup hangs.
- Widget tests default to the Android platform; to test desktop behavior set `debugDefaultTargetPlatformOverride`.
- An `AppController` created in a test (including `initDemo`) must be `dispose`d inside the test body, otherwise its 15-second timer fails the test with "Pending timers".
- When writing files with PowerShell on Windows, avoid a UTF-8 BOM; backticks in PowerShell double-quoted strings become control characters and Chinese quotation marks break parsing, so prefer the edit tools or single-quoted here-strings for writing files. Line endings in the repository follow `.gitattributes` (git warns about LF/CRLF conversion; no action needed).
- Windows application control policies may block unsigned release exes (the debug build from `flutter run` can run).
- `dart format` splits a single-line `if (x) y;`, after which `curly_braces_in_flow_control_structures` reports an info: use `dart fix --apply` to add the braces.
- Dart's `String.replaceFirst` does not support `$1` back-references; use `replaceFirstMapped`.
- A `FractionallySizedBox` inside an `Align` whose child is a `DecoratedBox` without a child collapses to height 0; set `heightFactor: 1` (the share bars were once invisible because of this).
- App icons are generated uniformly by `python tool/gen_icons.py` (Pillow, 4x supersampling; change the design only in that one file); the tray icon is drawn by `TrayIconRenderer`, also anti-aliased by supersampling. Never edit the per-platform icon files by hand.
- Chinese fonts: Flutter's default font on Windows, Segoe UI, has no Han characters, so a CJK fallback (Microsoft YaHei) must be written explicitly in `AppTheme.fonts`, and `MaterialApp` must always set `locale` (zh_CN for Chinese, en_US for English, see the "Internationalization" section; `flutter_localizations` is required), otherwise it falls back to odd fonts.
- The tray panel and the main window are the same window: when `DesktopIntegration.panelMode` is true, `MaterialApp.builder` shows `TrayPanel` and the main UI is kept alive with `Offstage`; the window hides automatically when it loses focus. The panel height is estimated by `TrayPanel.heightFor`, so change it together with the panel layout. The panel sits above the Navigator and has no `Overlay` of its own, so `main.dart` must wrap it in an `Overlay`, otherwise `Tooltip` throws "No Overlay widget found" (`test/tray_panel_test.dart` guards this). `token_bar.exe --panel` (or `flutter run -d windows --dart-entrypoint-args=--panel`) opens the panel directly for debugging.
- Which account the tray icon / macOS menu-bar text follows is decided by `AppSettings.trayAccountId` (empty = automatically the account with the least remaining; both the dropdown on the settings page and the "Tray display" submenu of the tray right-click menu can change it, and the menu item key is `tray:<accountId>`). On macOS, `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` must return `false`, otherwise closing the window quits the app instead of leaving it in the menu bar (a real quit goes through `DesktopIntegration.quit`). When changing the signature of `DesktopIntegration`, change `desktop_io.dart` and `desktop_stub.dart` together.
- The history chart (`lib/ui/widgets/history_chart.dart`) has three views and shows only those with data: "Model" (the `ModelUsageSeries` returned by `AppController.modelUsage`; it does not appear when null or empty; tokens / cost are mutually exclusive, and cost is available only when there is `costUsd`), "Quota windows" (`UsagePoint.used`) and "Spend" (`UsagePoint.spend`); the default priority is model > quota windows > spend. Quota / spend take per-bucket deltas, and a value that decreases is treated as a window reset (`lib/ui/history_series.dart`). The pure functions are in `lib/ui/chart_math.dart`: `alignedBucketStarts` (buckets aligned to local whole hours / 0·6·12·18 o'clock / local midnight; the x-axis always spans the full range and empty buckets are kept), `buildModelHistory`, `mergeTailSeries` (small items beyond the `seriesPalette` palette are merged into a trailing "Other"), `filterSeries` / `toggleHidden` (hiding via the legend; hiding everything restores everything), `niceScale`, `abbreviateNumber`, `pickAxisLabels`; all are unit tested (`test/chart_math_test.dart`).
- The bar chart `lib/ui/widgets/stacked_bar_chart.dart` is a hand-drawn `CustomPainter` (it no longer depends on fl_chart): bar width ≤ 28 px, 1.8 px gaps between segments, only the topmost segment has rounded top corners, and the entrance animation replays when `animationKey` changes; the tooltip card shown on hover (mouse) / tap (touch, tap again to dismiss) is placed beside the bar with `CustomSingleChildLayout` (flipping to the left near the right edge) and never covers the bar or leaves the chart. Colors are fixed by `colorOrder` (models sorted by tokens over the full range, window / spend lines sorted by id), so the same item has the same color in the legend / list / tooltip; to change the palette, edit only `seriesPalette` / `seriesOtherColor` in `lib/app/theme.dart`. The summary list, legend chips and empty state are all in `history_chart.dart`; the widget tests are in `test/history_chart_test.dart` (use `HistoryChart.now` to pin the clock, and sweep the mouse hover with `PointerDeviceKind.mouse` gestures).
- Per-model usage (the stacked bar chart on the history page): the `UsageProvider.fetchModelUsage()` hook (default null) → `ModelUsageSeries` (model × time bucket); `AppController.modelUsage()` only answers for local accounts (demo mode answers with `DemoData.modelUsage`), has a 2-minute in-memory cache, and always returns null on failure. The bucket width is decided by `modelUsageBucketWidth`: a range ≤ 36 hours uses 1-hour buckets, otherwise 1-day buckets, aligned to the local time zone (`ModelUsageAggregator`).
  - Cursor: reuses `get-filtered-usage-events` from `cursor_usage_events.dart` (works with both local login and cookie, at most 20 pages, returns null if it cannot gather enough).
  - Codex: only on desktop (`localAccessSupported` + `canUseLocalLogins`), reads `<CODEX_HOME or AccountConfig.homeDir>/sessions/YYYY/MM/DD/*.jsonl` and `archived_sessions/*.jsonl`, parsing line by line as a stream, with semantics matching CodexBar's `CostUsageScanner` (`last_token_usage` / `total_token_usage` of `token_count`; the model is the most recent `turn_context`). **Read-only; take only model names and numbers.** Cost is only estimated from `codex_pricing.dart` (copied from CodexBar's price table); models missing from the table get a null `costUsd` — never invent prices.
- Services that are not integrated (they need request signing, decryption of a browser cookie database, the macOS keychain, or sending a real inference request to probe quota) are listed under "Not supported, and why" in the README; check it before adding one.
