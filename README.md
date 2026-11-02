<div align="center">

<img src="assets/icon/tokenbar.png" alt="TokenBar logo" width="96" height="96">

# TokenBar

**Every AI quota, one glance away.**
An open-source, cross-platform monitor for AI usage limits, balances and reset times.
Runs on **Windows, macOS, Linux, Android and iOS**.

English | [简体中文](README.zh-CN.md)

[![CI](https://github.com/lwh0630/TokenBar/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/lwh0630/TokenBar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/lwh0630/TokenBar?display_name=tag&sort=semver)](https://github.com/lwh0630/TokenBar/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Windows%20%C2%B7%20Android%20%C2%B7%20macOS%20%C2%B7%20Linux%20%C2%B7%20iOS-2ea44f)
![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)
![Providers](https://img.shields.io/badge/providers-52-8A63D2)

</div>

> Inspired by [CodexBar](https://github.com/steipete/CodexBar) for macOS. TokenBar brings the same idea to Windows, Android, Linux and iOS (and ships a macOS build too), and covers 52 services.

## Why TokenBar

- **See everything in one place.** Codex, Claude, Cursor, OpenRouter, DeepSeek, z.ai and 46 more: remaining quota, balance, reset countdown and whether you are burning through it faster than a linear pace.
- **Nothing sits in the middle.** The app queries each provider's own endpoint from your device. The optional sync server only ever receives usage *snapshots*, never credentials.
- **Reuses what you already have.** On desktop it reads the login your official CLI or app already stored (read-only). Elsewhere you paste an API key or cookie. TokenBar never asks for a password and never logs in on your behalf.
- **Native desktop feel.** A tray icon whose two bars follow your tightest quota, and a compact tray panel that lists every account.

## Screenshots

> **The screenshots use fictional demo data.**

**Desktop**

<p align="center">
  <img src="docs/screenshots/windows-dashboard.png" alt="TokenBar dashboard on Windows" width="49%">
  <img src="docs/screenshots/windows-history.png" alt="TokenBar stacked usage history on Windows" width="49%">
</p>
<p align="center">
  <img src="docs/screenshots/windows-tray-panel.png" alt="Tray panel" width="26%">
</p>

**Mobile**

<p align="center">
  <img src="docs/screenshots/android-dashboard.png" alt="Dashboard on Android" width="26%">
  <img src="docs/screenshots/android-detail.png" alt="Account detail on Android" width="26%">
  <img src="docs/screenshots/android-history.png" alt="Usage history on Android" width="26%">
</p>

> The app interface is available in Simplified Chinese and English. Switch in **Settings → Language**; the default follows your system language (Chinese systems get Chinese, everything else gets English). Text that comes from the provider integrations (setup hints, some field names and error messages) is still Chinese for now, see the [roadmap](#roadmap). Provider names, plan names and numbers are shown as the providers report them.

## Features

| | |
| --- | --- |
| **Quota windows** | 5-hour, weekly, monthly and per-model windows, with percent left, reset countdown, local reset time and a pace marker ("ahead of / behind a linear pace", projected usage at reset). |
| **Balances and spend** | Credit balances, spend and caps in the provider's own currency or credit unit. |
| **Tray icon and panel** *(desktop)* | A two-bar tray icon driven by the tightest window, a click-to-open panel for all accounts, right-click menu. The same window doubles as the panel. |
| **Usage history** | Stacked bars per time slot (24 h / 7 d / 30 d), broken down by quota window or by cost item, with each item's share and total. |
| **Notifications** | Low-quota alerts at thresholds you choose and an alert when a low quota resets. |
| **Languages** | Simplified Chinese and English. Choose in **Settings → Language**; defaults to the system language. |
| **Light and dark themes** | Follows the system or set manually. |
| **Phone widgets** | Native Android home-screen widget. iOS WidgetKit sources are included but unverified. |
| **Update check** | Looks for a newer GitHub release at launch (can be turned off) or on demand. See [Updates](#updates). |
| **Optional sync server** | Self-hosted. Push snapshots from your PC, view them on your phone or in the browser. |
| **CLI** | `tokenbar usage` prints the same data in a terminal or as JSON. |

## Supported services

Three ways to read a service:

- **Local login**: reuses the login of the official client already on the machine (read-only). Desktop only.
- **API key / token**: paste it once. Works on desktop, phone and web. On desktop, an empty field falls back to the provider's usual environment variable.
- **Cookie**: copy the `Cookie` request header from your browser's developer tools. These endpoints are not public and may change without notice.

### Subscriptions (local login)

| Service | How it is read | What you see |
| --- | --- | --- |
| Codex (ChatGPT) | `~/.codex/auth.json` (run `codex login` first); falls back to `codex app-server` when the token expired | 5-hour, weekly, credits |
| Claude (Pro / Max) | Claude Code login (`~/.claude/.credentials.json`, Keychain on macOS) | 5-hour, weekly, Opus / Sonnet weekly, extra usage |
| Cursor | Cursor desktop login (read-only `state.vscdb`) or a pasted cursor.com cookie | Monthly quota, Auto / API split, on-demand usage |

<details>
<summary><b>Official API keys (23)</b></summary>

| Service | What you see |
| --- | --- |
| OpenAI API | Spend over the last 30 days (organization admin key; other keys try the legacy balance endpoint) |
| DeepSeek | Account balance |
| Moonshot / Kimi platform | Account balance |
| xAI | Balance and spend (management key + team ID) |
| Venice | DIEM / USD balance |
| DeepInfra | Balance, month-to-date spend, spend limit |
| Fireworks AI | Spend over the last 30 days |
| Hugging Face | Billing usage (token with billing read access; desktop can read the token saved by `hf auth login`) |
| ElevenLabs | Character quota, voice slots |
| Vercel AI Gateway | Team credits or personal budget |
| Atlas Cloud | Account balance |
| OpenRouter | Credit balance, key limit |
| Tavily | Plan and key credit usage |
| Linkup | Prepaid credit balance |
| Exa | Month-to-date spend of a key (Team Management service key) |
| fal | Credit balance (billing read access) |
| Soniox | Month-to-date usage and budget (organization key) |
| Poe | Remaining points |
| Neuralwatt | Subscription kWh quota, key limit, prepaid balance |
| ZenMux | 5-hour / 7-day quota, pay-as-you-go balance (management key) |
| Warp | AI request quota, bonus credits |
| Synthetic | Rolling, weekly and search quotas |
| Chutes | 4-hour rolling and monthly quotas |

</details>

<details>
<summary><b>Coding plans (8)</b></summary>

| Service | What you see |
| --- | --- |
| z.ai / Zhipu GLM | 5-hour and weekly quota, MCP quota (international and China sites) |
| Kimi Code | Weekly / 5-hour / monthly quota (China site by default, region selectable) |
| MiniMax | Interval and weekly quota (China site by default, region selectable) |
| v0 | Billing balance, API rate limits |
| DevPass | Plan credits, weekly premium quota, key spend |
| xKiro | Daily free token quota (resets at 00:00 UTC) |
| ai& | Spend over the last 30 days |
| Groq | Request and token rate over the last 5 minutes (Groq does not publish remaining quota) |

</details>

<details>
<summary><b>Self-hosted gateways (6)</b></summary>

| Service | What you see |
| --- | --- |
| LiteLLM | Personal / team budget and spend (virtual key) |
| sub2api | Daily / weekly / monthly quota and rate-limit windows |
| Bifrost | Budget usage |
| LLM Proxy | `quota-stats` (the group with the least remaining) |
| ClawRouter | Monthly budget |
| Aixy | Budget applying to the key |

</details>

<details>
<summary><b>Other account APIs (12)</b></summary>

| Service | What you see |
| --- | --- |
| Aerostack | Monthly AI token quota (account JWT) |
| Cosmic AI | Input / output token quota of a project |
| FLORA | Available balance, month-to-date spend |
| Future AGI | AI credits of the billing period, gateway request quota |
| GitKraken AI | Weekly AI credits |
| Sail Research | Organization credit balance, recent spend |
| Munito | Daily / monthly spend limits |
| Sofya | Available / plan / purchased credits |
| Chatbox AI | Plan / bonus / top-up / image quota (license key) |
| IBM Bob | Bobcoin budget per team |
| GitHub Copilot | Metered quota and credits usage reported by GitHub (GitHub token) |
| Xiaomi MiMo | Account balance and Token Plan usage (pasted platform cookie) |

For **GitHub Copilot**, paste a GitHub token authorized for the account's Copilot usage in **Accounts → Add account → GitHub Copilot**. The [CodexBar integration](https://github.com/steipete/CodexBar/blob/5f93dc3068b3bee3f8753f3772614cc2949c335d/Sources/CodexBarCore/Providers/Copilot/CopilotUsageFetcher.swift) uses the GitHub OAuth token itself (`gho_...`), rather than a short-lived Copilot service token. Desktop users can also supply `COPILOT_API_TOKEN`; an optional Enterprise host selects that account's API host. TokenBar does not provide a device-login flow or automatically discover other clients' saved Copilot logins.

Copilot usage comes from the non-public `/copilot_internal/user` endpoint and depends on the token's access. When GitHub returns metered quota values, they are shown directly; if it returns only `credits_used`, TokenBar shows credits used without inventing a remaining amount or percentage. Unlimited or placeholder quotas do not become 100% remaining bars. GitHub web billing budgets and a user-entered seat allowance are not included in this integration.

For **Xiaomi MiMo**, sign in to `platform.xiaomimimo.com` and copy a request's `Cookie` header from your browser's developer tools. It must include `api-platform_serviceToken` and `userId`. Paste it in **Accounts → Add account → Xiaomi MiMo**. The app reads the platform's non-public balance and Token Plan endpoints using this session cookie; inference API keys and automatic browser-cookie import are not supported for MiMo. Replace the cookie when the platform session expires. Plan usage is shown only when returned by the platform; a balance-only account does not gain a synthetic quota window.

</details>

<details>
<summary><b>Not supported, and why</b></summary>

| Service | Reason |
| --- | --- |
| Doubao (Volcano Ark) | The API-key route would have to send a real chat request to probe the quota (it spends tokens); the AK/SK route needs Volcengine request signing |
| AWS Bedrock | Needs AWS SigV4 request signing |
| Vertex AI | Needs a Google Cloud service account / gcloud credentials and signing |
| Azure OpenAI | Needs Azure subscription management credentials |
| Muse (Meta Muse Code) | The only quota endpoint creates an inference key on the account, which is not a read-only operation |
| Antigravity, Grok, Wayfinder, Pi, CodeRabbit | Rely on decrypting browser cookie stores, the macOS keychain or non-public login flows |

</details>

Each provider reads documented or reverse-documented endpoints taken from CodexBar's research. Nothing is invented: if an endpoint cannot be traced to its source, it is not shipped.

## Privacy and security

- **Credentials stay on your device**, in the platform secure store (`flutter_secure_storage`). They never go into logs, snapshots or the sync server, and they are not part of any exported JSON.
- **Read-only by default.** TokenBar never refreshes or rewrites another tool's tokens (refreshing rotates the refresh token and can sign the official client out). Refreshing Claude's token is an explicit opt-in setting, off by default.
- **No passwords, no simulated logins.** Only an existing local login, or a key / cookie that you paste yourself.
- **The sync server is optional** and only receives usage snapshots.
- **The update check is one anonymous request** to the GitHub API. See [Updates](#updates).

## Install

Download the latest build from the [**Releases**](https://github.com/lwh0630/TokenBar/releases/latest) page and check it against `SHA256SUMS.txt`.

### Windows 10 / 11 (x64 and ARM64)

1. Download `tokenbar-<version>-windows-x64-setup.exe` (Intel / AMD) or `tokenbar-<version>-windows-arm64-setup.exe` (Windows on ARM) and run it.
2. The installer is per-user by default (no administrator rights, installs to `%LOCALAPPDATA%\Programs\TokenBar`); the privileges dialog lets you install for all users instead. It adds a Start menu entry (and an optional desktop icon), upgrades in place and can be removed from **Settings → Apps**. The Visual C++ runtime is bundled. For silent installs use `/VERYSILENT`.

> The installer and the app are not code-signed. SmartScreen may show "Windows protected your PC": choose **More info → Run anyway**. Systems that enforce Smart App Control or an application-control policy can block unsigned executables outright. In that case, [build from source](#build-from-source).

### Android 7.0+ (API 24+)

1. Download the APK for your device: `arm64-v8a` for almost every recent phone, `armeabi-v7a` for old 32-bit devices, `x86_64` for emulators.
2. Open it and allow installation from your browser or file manager when Android asks.

APKs are signed with the TokenBar release key. To verify:

```bash
apksigner verify --print-certs tokenbar-<version>-android-arm64-v8a.apk
# certificate SHA-256 digest: c04373ec39a24dd04d6f6797ed984be27d172c01fc30833f957845bb5b622d27
```

### macOS 12+

1. Download `tokenbar-<version>-macos-arm64.dmg` (Apple Silicon: M1 and later) or `tokenbar-<version>-macos-x86_64.dmg` (Intel), open it and drag **TokenBar** to **Applications**.
2. If macOS blocks the first launch, right-click the app and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/TokenBar.app
```

### Linux x64 / ARM64 — experimental

1. Download `tokenbar-<version>-linux-x64.tar.gz` (Intel / AMD) or `tokenbar-<version>-linux-arm64.tar.gz` (ARM, for example Raspberry Pi 4/5 or Asahi Linux) and extract it.
2. Run `./token_bar` inside the extracted folder.

Runtime libraries: GTK 3, `libsecret` (credential storage, with a running keyring such as GNOME Keyring or KWallet) and `libayatana-appindicator3` (tray icon). On Debian / Ubuntu: `sudo apt install libgtk-3-0 libsecret-1-0 libayatana-appindicator3-1`. On GNOME the tray icon needs the AppIndicator extension. Linux tray icons only offer a menu (no click event), so the compact tray panel is not available there: use the menu's **Open TokenBar**.

### iOS 15+ — experimental, sideload only

`tokenbar-<version>-ios-unsigned.ipa` is **not signed**, and there is no Apple Developer account behind this project, so the file cannot be installed as is. Re-sign and install it with your own Apple ID through a sideloading tool such as [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) (free Apple IDs have to renew the install every 7 days). The Home Screen widget is not part of the IPA.

### Platform status

| Platform | Status |
| --- | --- |
| Windows x64 | Supported. Built and tested on Windows 11; CI builds a release on every push. |
| Windows ARM64 | Experimental. Built natively on a Windows ARM runner by CI on every push; **not run on real ARM hardware**. |
| Android | Supported. Tested on an Android emulator (API 37); CI builds on every push and releases are signed. |
| Web | Builds in CI. Intended for use with the sync server (browsers cannot reach most provider endpoints directly). |
| macOS | Works in the maintainer's testing; CI builds it on every push. Ad-hoc signed and not notarized (see the install note above). Separate Apple Silicon and Intel images. |
| Linux x64, ARM64 | Experimental. CI builds both natively on every push, but they have **not been run on a real machine**. The tray is a menu only (no tray panel). |
| iOS | Experimental. CI builds an **unsigned** IPA (sideload only); it has **not been run on a device**. The WidgetKit sources are not built into it. |

## Getting started

1. Launch TokenBar. On desktop it detects the services you are already signed in to (Codex, Claude, Cursor) and adds them.
2. Open **Accounts → Add account** to add anything else: pick a service (the list is searchable), paste the key or cookie, save. Several accounts of the same service are fine (for example, different `CODEX_HOME` directories).
3. The dashboard refreshes every few minutes (configurable). Tap an account for per-window detail and history.

**Tray panel (desktop).** Click the tray icon to open it. It lists each account's two tightest windows with reset countdowns, closes when it loses focus, and **Open TokenBar** brings back the main window.

**Usage history.** On an account's page choose 24 hours, 7 days or 30 days. Each bar is the usage added in a time slot, stacked by item:

- *Quota usage*: the percentage points added to each quota window. When a service has component windows (Cursor Auto / API, Claude Opus / Sonnet) only those are stacked by default; the chips above the chart add or remove series.
- *Cost*: the money or credits spent per cost item.

Providers rarely report usage per model, so "models" here are the breakdowns the endpoint exposes. History is recorded locally from the first run on.

Cursor and Codex can additionally be viewed **per model** as a stacked bar chart (tokens, plus cost where it is known). Cursor reads its dashboard events feed (local login or cookie, so phones work too). Codex reads the local session logs under `~/.codex/sessions` and therefore needs the desktop app; the logs are read-only and only model names and token counts are taken from them, never prompt or file content.

## Updates

TokenBar checks the latest [GitHub release](https://github.com/lwh0630/TokenBar/releases) once at launch and whenever you press **Settings → About → Check for updates**. When a newer version exists it shows the release notes and opens the release page so you can download it. You can turn the launch check off, or skip a specific version.

The check sends one anonymous `GET` to `api.github.com` with the app version in the `User-Agent`. Drafts and pre-releases are ignored. TokenBar never downloads or installs anything by itself.

## Command line

```bash
dart run packages/tokenbar_server/bin/tokenbar.dart --help            # list providers
dart run packages/tokenbar_server/bin/tokenbar.dart usage             # all local logins
dart run packages/tokenbar_server/bin/tokenbar.dart usage -p cursor   # one provider
dart run packages/tokenbar_server/bin/tokenbar.dart usage --json
```

## Optional: self-hosted sync

Only needed if you want to see your PC's quotas on your phone or in a browser. The server stores usage snapshots and never receives provider credentials.

```bash
# Server (also serves the web app)
docker compose up -d          # set TOKENBAR_TOKEN (and optionally TOKENBAR_READ_TOKEN) in .env

# Or without Docker
flutter build web
(cd packages/tokenbar_server && dart build cli -o ../../build/server)
TOKENBAR_TOKEN=change-me build/server/bundle/bin/tokenbar serve --web build/web --port 8787
```

Use `dart build cli`, not `dart compile exe` (the SQLite native library would be missing).

On the PC: **Settings → Server sync → Push local data**, enter the server URL and the admin token. On the phone: **View server data** with the read-only token. A machine without a desktop UI can run `tokenbar collect --server URL --token TOKEN` on a schedule.

## Build from source

Requirements: Flutter 3.47.7 (Dart 3.13.5). For Android also JDK 17 and the Android SDK; for Windows, Visual Studio 2022 with the *Desktop development with C++* workload.

```bash
git clone https://github.com/lwh0630/TokenBar.git
cd TokenBar
flutter pub get

flutter run -d windows        # or: -d android, -d chrome
flutter build windows --release
flutter build apk --release   # needs signing material, see below
```

**Android release signing.** Release builds never fall back to the debug key. Provide `android/key.properties` (git-ignored) or environment variables:

```properties
storeFile=/absolute/path/to/your.jks
storePassword=...
keyPassword=...
keyAlias=...
```

```bash
# create your own key
keytool -genkeypair -keystore your.jks -alias tokenbar -keyalg RSA -keysize 4096 -validity 10000
```

Debug builds (`flutter run`, `flutter build apk --debug`) need no key.

**Demo mode.** `flutter run --dart-define=TOKENBAR_DEMO=true` (add `--dart-define=TOKENBAR_DEMO_LANG=en` or `zh` to pin the UI language) starts with fictional accounts and a simulated month of history. It uses in-memory storage, makes no network requests and never touches your real settings or credentials. It is what the screenshots above were taken with.

### Tests

```bash
flutter analyze && flutter test
(cd packages/tokenbar_core && dart analyze && dart test)
(cd packages/tokenbar_server && dart analyze && dart test)
dart format --output=none --set-exit-if-changed lib test packages
```

### Project layout

```
lib/                      Flutter app (provider + ChangeNotifier)
packages/tokenbar_core/   Pure Dart: models, provider implementations, sync client, tray icon renderer
packages/tokenbar_server/ CLI (usage / collect / serve) and the optional sync server (shelf + sqlite)
android/ ios/ windows/ …  Platform projects, Android widget, iOS WidgetKit sources
tool/gen_icons.py         Regenerates the app icons for every platform
.github/workflows/        CI and signed release pipeline
```

## Releasing

Releases are cut by [`release.yml`](.github/workflows/release.yml): push a `vX.Y.Z` tag (or run the workflow by hand). It checks, builds and signs per-ABI Android APKs with the key stored in the `production` environment, builds the Windows x64 and ARM64 installers, the Linux x64 and ARM64 tarballs, the macOS Apple Silicon and Intel disk images and the unsigned iOS IPA, and creates a **draft** release with `SHA256SUMS.txt`. Nothing goes public until the draft is published by hand. APKs are verified against the expected certificate fingerprint before upload.

## Roadmap

- Provider-supplied text is still Chinese: setup hints, field labels and error messages in `packages/tokenbar_core`, plus the less common quota and credit labels. The app UI itself is translated (`lib/l10n/`); more UI languages can be added there.
- Verify the Linux (x64, ARM64), iOS and Windows ARM64 builds on real devices.
- Code-signed Windows build and a signed, notarized macOS build (both need paid certificates).
- More providers. Adding one is small and well-trodden: see [AGENTS.md](AGENTS.md) for the steps and the rules (documented endpoints only, no invented APIs, no credentials in logs).

## Contributing

Issues and pull requests are welcome. Before opening a PR run the checks in [Tests](#tests). For a new provider, add the implementation, a fixture of a real response and a `MockClient` test, then list it in the tables above.

## License

[MIT](LICENSE). Provider research is based on [CodexBar](https://github.com/steipete/CodexBar) (MIT); see [NOTICE.md](NOTICE.md).

Provider logos in `assets/provider_icons/` are copied from CodexBar (MIT). They are trademarks of their respective owners, used only to identify the services; see [assets/provider_icons/README.md](assets/provider_icons/README.md).

TokenBar is an independent project and is not affiliated with or endorsed by any of the services it can monitor.
