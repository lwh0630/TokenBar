<div align="center">

<img src="assets/icon/tokenbar.png" alt="TokenBar logo" width="96" height="96">

# TokenBar

**所有 AI 额度，一眼看清。**
开源、跨平台的 AI 额度监控：剩余额度、余额、重置倒计时和使用节奏。
支持 **Windows、macOS、Linux、Android 和 iOS**。

[English](README.md) | 简体中文

[![CI](https://github.com/lwh0630/TokenBar/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/lwh0630/TokenBar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/lwh0630/TokenBar?display_name=tag&sort=semver)](https://github.com/lwh0630/TokenBar/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Windows%20%C2%B7%20Android%20%C2%B7%20macOS%20%C2%B7%20Linux%20%C2%B7%20iOS-2ea44f)
![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)
![Providers](https://img.shields.io/badge/providers-52-8A63D2)

</div>

> 灵感来自 macOS 上的 [CodexBar](https://github.com/steipete/CodexBar)。TokenBar 把同样的思路带到 Windows、Android、Linux 和 iOS（也提供 macOS 版本），并支持 52 个服务。

## 为什么用 TokenBar

- **一处看全部。** Codex、Claude、Cursor、OpenRouter、DeepSeek、z.ai 等 52 个服务：剩余额度、余额、重置倒计时，以及你消耗得是否比匀速更快。
- **中间没有第三方。** 应用在你的设备上直接请求各服务商自己的接口。可选的同步服务器只接收额度*快照*，从不接触凭证。
- **复用你已有的登录。** 桌面端只读取官方 CLI / 客户端已保存的登录状态，其他场景粘贴 API Key 或 Cookie。TokenBar 不索要密码，也不替你登录。
- **桌面原生体验。** 托盘图标的双进度条跟随最紧张的额度，点击弹出托盘小面板，列出所有账户。

## 截图

> **截图中的数据均为虚构的演示数据。**

**桌面端**

<p align="center">
  <img src="docs/screenshots/zh/windows-dashboard.png" alt="Windows 上的额度总览" width="49%">
  <img src="docs/screenshots/zh/windows-history.png" alt="Windows 上的堆叠式使用历史" width="49%">
</p>
<p align="center">
  <img src="docs/screenshots/zh/windows-tray-panel.png" alt="托盘小面板" width="26%">
</p>

**移动端**

<p align="center">
  <img src="docs/screenshots/zh/android-dashboard.png" alt="Android 额度总览" width="26%">
  <img src="docs/screenshots/zh/android-detail.png" alt="Android 账户详情" width="26%">
  <img src="docs/screenshots/zh/android-history.png" alt="Android 使用历史" width="26%">
</p>

## 功能

| | |
| --- | --- |
| **额度窗口** | 5 小时、每周、每月和分模型窗口，显示剩余百分比、重置倒计时、本地重置时间和节奏标记（快于 / 慢于匀速、重置时预计用量）。 |
| **余额与花费** | 以服务商自己的货币或积分单位显示余额、花费和上限。 |
| **托盘图标与小面板**（桌面） | 双进度条托盘图标跟随最紧张的窗口，点击弹出面板查看所有账户，右键仍是菜单。主窗口同时充当托盘面板。 |
| **使用历史** | 按时间段堆叠的柱状图（24 小时 / 7 天 / 30 天），按额度窗口或费用项分项，显示每一项的占比和合计。 |
| **通知** | 剩余额度低于你设定的阈值时提醒，额度较低后重置时再提醒。 |
| **界面语言** | 简体中文与 English，在**设置 → 语言**中切换，默认跟随系统语言（中文系统用中文，其他语言用英文）。 |
| **浅色 / 深色主题** | 跟随系统或手动选择。 |
| **手机小组件** | Android 原生桌面小组件。iOS WidgetKit 源码已包含，尚未验证。 |
| **检查更新** | 启动时（可关闭）或手动检查 GitHub 上是否有新版本，见[更新](#更新)。 |
| **可选同步服务器** | 自建。在电脑上推送快照，在手机或浏览器里查看。 |
| **命令行** | `tokenbar usage` 在终端或以 JSON 输出同样的数据。 |

## 支持的服务（共 52 个）

读取方式：

- **本机登录**：只读复用本机官方客户端已有的登录状态，仅桌面端可用。
- **API Key / 令牌**：在账户页手动粘贴，桌面、手机和网页都能用。桌面端留空时会回退到对应的环境变量。
- **Cookie**：登录网站后，从浏览器开发者工具复制请求的 Cookie 请求头。这类接口不公开，可能随网站变动。

### 订阅类（本机登录）

| 服务 | 读取方式 | 额度 |
| --- | --- | --- |
| Codex（ChatGPT 订阅） | 本机 `~/.codex/auth.json`（先运行 `codex login`）；令牌过期时可走 `codex app-server` | 5 小时、每周、Credits |
| Claude（Pro / Max） | 本机 Claude Code 登录（`~/.claude/.credentials.json`，macOS 为钥匙串） | 5 小时、每周、Opus / Sonnet 每周、额外用量 |
| Cursor | 本机 Cursor 桌面端登录（只读 `state.vscdb`），或粘贴 cursor.com 的 Cookie | 本月额度、Auto / API 分项、按需用量 |

<details>
<summary><b>官方 API Key（23 个）</b></summary>

| 服务 | 额度 |
| --- | --- |
| OpenAI API | 近 30 天花费（需组织 Admin Key；普通 Key 尝试旧版余额接口） |
| DeepSeek | 账户余额 |
| Moonshot / Kimi 开放平台 | 账户余额 |
| xAI | 余额与花费（需管理密钥 + 团队 ID） |
| Venice | DIEM / USD 余额 |
| DeepInfra | 余额、本月花费、消费上限 |
| Fireworks AI | 近 30 天花费 |
| Hugging Face | 账单用量（需 Billing 读取权限的 Token，桌面端可读 `hf auth login` 保存的 Token） |
| ElevenLabs | 字符额度、声音槽位 |
| Vercel AI Gateway | 团队余额，或个人预算 |
| Atlas Cloud | 账户余额 |
| OpenRouter | Credits 余额、Key 限额 |
| Tavily | 套餐与 Key 的 credits 用量 |
| Linkup | 预付 credits 余额 |
| Exa | 指定 Key 的本月花费（需 Team Management 服务密钥） |
| fal | Credits 余额（需 billing 读取权限） |
| Soniox | 本月用量与预算（需组织 Key） |
| Poe | 剩余积分 |
| Neuralwatt | 订阅 kWh 额度、Key 限额、预付余额 |
| ZenMux | 5 小时 / 7 天额度、按量余额（需管理 Key） |
| Warp | AI 请求额度、附加 credits |
| Synthetic | 滚动额度、每周额度、搜索额度 |
| Chutes | 4 小时滚动额度、月度额度 |

</details>

<details>
<summary><b>编程套餐（8 个）</b></summary>

| 服务 | 额度 |
| --- | --- |
| z.ai / 智谱 GLM | 5 小时 / 每周额度、MCP 额度（国际站与国内站） |
| Kimi Code | 每周 / 5 小时 / 月度额度（默认中国站，可切换区域） |
| MiniMax | 区间与每周额度（默认中国站，可切换区域） |
| v0 | 账单余额、API 速率限制 |
| DevPass | 套餐 credits、每周 premium 额度、Key 花费 |
| xKiro | 每日免费 token 额度（UTC 0 点重置） |
| ai& | 近 30 天花费 |
| Groq | 最近 5 分钟的请求与 token 速率（Groq 不公开额度余量） |

</details>

<details>
<summary><b>自建网关（6 个）</b></summary>

| 服务 | 额度 |
| --- | --- |
| LiteLLM | 个人 / 团队预算与花费（虚拟 Key） |
| sub2api | 日 / 周 / 月额度与限流窗口 |
| Bifrost | 预算用量 |
| LLM Proxy | quota-stats（剩余最少的分组） |
| ClawRouter | 月度预算 |
| Aixy | 适用于该 Key 的预算 |

</details>

<details>
<summary><b>其他账户类 API（12 个）</b></summary>

| 服务 | 额度 |
| --- | --- |
| Aerostack | 本月 AI token 额度（账户 JWT） |
| Cosmic AI | 项目的输入 / 输出 token 额度 |
| FLORA | 可用余额、本月花费 |
| Future AGI | 本计费周期 AI credits、网关请求额度 |
| GitKraken AI | 每周 AI credits |
| Sail Research | 组织 credits 余额、近期花费 |
| Munito | 每日 / 每月花费限额 |
| Sofya | 可用 / 套餐 / 购买 credits |
| Chatbox AI | 套餐 / 奖励 / 加油包 / 图片额度（License Key） |
| IBM Bob | 各团队 Bobcoin 预算 |
| GitHub Copilot | GitHub 返回的计量额度和 credits 用量（GitHub 令牌） |
| Xiaomi MiMo | 账户余额、Token Plan 用量（手动粘贴平台 Cookie） |

**GitHub Copilot**：在**账户 → 添加账户 → GitHub Copilot** 中粘贴有权查询该账户 Copilot 用量的 GitHub 令牌。[CodexBar 接入](https://github.com/steipete/CodexBar/blob/5f93dc3068b3bee3f8753f3772614cc2949c335d/Sources/CodexBarCore/Providers/Copilot/CopilotUsageFetcher.swift)使用 GitHub OAuth 令牌本体（`gho_...`），而非 Copilot 的短期服务令牌。桌面端也可使用 `COPILOT_API_TOKEN`；可选的 Enterprise 主机用于指定对应账户的 API 主机。TokenBar 不提供设备码登录，也不会自动查找其他客户端保存的 Copilot 登录。

Copilot 用量来自非公开的 `/copilot_internal/user` 接口，能否访问取决于令牌权限。GitHub 返回计量额度时按真实值显示；若只返回 `credits_used`，则仅显示已用 credits，不推算剩余额度或百分比。无限额度或占位数据不会显示为剩余 100% 的进度条；本接入不包含 GitHub 网页账单预算和手动设置的每席 credits 上限。

**Xiaomi MiMo**：登录 `platform.xiaomimimo.com`，在浏览器开发者工具中复制请求的 `Cookie` 请求头，需包含 `api-platform_serviceToken` 和 `userId`，然后粘贴到**账户 → 添加账户 → Xiaomi MiMo**。应用使用此会话 Cookie 读取平台的非公开余额与 Token Plan 接口；MiMo 接入不支持推理 API Key 或自动导入浏览器 Cookie。平台登录过期后需更新 Cookie；仅在平台返回套餐用量时显示额度窗口，只有余额的账户不会显示虚构的套餐额度。

</details>

<details>
<summary><b>暂不支持及原因</b></summary>

| 服务 | 原因 |
| --- | --- |
| Doubao（豆包 / 火山方舟） | API Key 方式要发真实对话请求来探测额度，会消耗 token；AK/SK 方式需要火山引擎请求签名 |
| AWS Bedrock | 需要 AWS SigV4 请求签名 |
| Vertex AI | 需要 Google Cloud 服务账号 / gcloud 凭证与签名 |
| Azure OpenAI | 需要 Azure 订阅管理凭证 |
| Muse（Meta Muse Code） | 唯一的额度接口会在账户上创建推理 Key，不是只读操作 |
| Antigravity、Grok、Wayfinder、Pi、CodeRabbit | 依赖浏览器 Cookie 库解密、macOS 钥匙串或非公开登录流程 |

</details>

各服务读取的都是 CodexBar 研究中记录的公开或已被逆向记录的接口，没有虚构：无法追溯来源的接口不会接入。

## 隐私与安全

- **凭证只留在你的设备上**，保存在系统安全存储（`flutter_secure_storage`）。不会写入日志、快照或同步服务器，也不会出现在任何导出的 JSON 里。
- **默认只读。** TokenBar 不刷新、不改写其他工具的令牌（刷新会轮换 refresh token，可能让官方客户端掉线）。刷新 Claude 令牌是显式开关，默认关闭。
- **不要密码，不做模拟登录。** 只用本机已有的登录，或你主动粘贴的 Key / Cookie。
- **同步服务器是可选的**，只接收额度快照。
- **检查更新只发一次匿名请求**到 GitHub API，见[更新](#更新)。

## 安装

在 [**Releases**](https://github.com/lwh0630/TokenBar/releases/latest) 页面下载最新版本，并用 `SHA256SUMS.txt` 校验。

### Windows 10 / 11（x64 与 ARM64）

1. 下载 `tokenbar-<版本>-windows-x64-setup.exe`（Intel / AMD）或 `tokenbar-<版本>-windows-arm64-setup.exe`（Windows on ARM），运行安装程序。
2. 安装程序默认按当前用户安装（不需要管理员权限，装到 `%LOCALAPPDATA%\Programs\TokenBar`），权限提示框里也可以选择为所有用户安装。它会创建开始菜单项（可选桌面图标），支持原地升级，可以在**设置 → 应用**里卸载，并已自带 Visual C++ 运行库。静默安装可加 `/VERYSILENT`。

> 安装程序和应用都没有代码签名。SmartScreen 可能提示"Windows 已保护你的电脑"：点击**更多信息 → 仍要运行**。启用了智能应用控制（Smart App Control）或应用控制策略的系统可能直接拦截未签名程序，这时请[从源码构建](#从源码构建)。

### Android 7.0+（API 24+）

1. 下载适合你设备的 APK：几乎所有近年的手机用 `arm64-v8a`，旧的 32 位设备用 `armeabi-v7a`，模拟器用 `x86_64`。
2. 打开安装包，按 Android 提示允许浏览器或文件管理器安装应用。

APK 使用 TokenBar 发布密钥签名，可以这样校验：

```bash
apksigner verify --print-certs tokenbar-<版本>-android-arm64-v8a.apk
# certificate SHA-256 digest: c04373ec39a24dd04d6f6797ed984be27d172c01fc30833f957845bb5b622d27
```

### macOS 12+

1. 下载 `tokenbar-<版本>-macos-arm64.dmg`（Apple 芯片：M1 及以后）或 `tokenbar-<版本>-macos-x86_64.dmg`（Intel），打开后把 **TokenBar** 拖进**应用程序**。
2. 如果首次启动被 macOS 拦下，右键点击应用选择**打开**，或者执行：

```bash
xattr -dr com.apple.quarantine /Applications/TokenBar.app
```

### Linux x64 / ARM64 — 实验性

1. 下载 `tokenbar-<版本>-linux-x64.tar.gz`（Intel / AMD）或 `tokenbar-<版本>-linux-arm64.tar.gz`（ARM，例如树莓派 4/5、Asahi Linux）并解压。
2. 运行解压目录里的 `./token_bar`。

运行时依赖：GTK 3、`libsecret`（凭证存储，需要 GNOME Keyring 或 KWallet 之类的密钥环在运行）和 `libayatana-appindicator3`（托盘图标）。Debian / Ubuntu：`sudo apt install libgtk-3-0 libsecret-1-0 libayatana-appindicator3-1`。GNOME 桌面需要安装 AppIndicator 扩展才能显示托盘图标。Linux 的托盘图标只有菜单、没有点击事件，所以托盘小面板在 Linux 上不可用，请用菜单里的**打开 TokenBar**。

### iOS 15+ — 实验性，仅支持侧载

`tokenbar-<version>-ios-unsigned.ipa` **没有签名**，本项目也没有 Apple 开发者账号，所以不能直接安装。请用你自己的 Apple ID，通过 [AltStore](https://altstore.io) 或 [Sideloadly](https://sideloadly.io) 之类的侧载工具重新签名并安装（免费 Apple ID 每 7 天需要续签一次）。主屏幕小组件不包含在 IPA 里。

### 平台状态

| 平台 | 状态 |
| --- | --- |
| Windows x64 | 已支持。在 Windows 11 上构建并测试；CI 每次推送都会构建 release。 |
| Windows ARM64 | 实验性。CI 每次推送都会在 Windows ARM 构建机上原生构建；**尚未在真正的 ARM 设备上运行**。 |
| Android | 已支持。在 Android 模拟器（API 37）上测试；CI 每次推送都会构建，发布版本经过签名。 |
| Web | CI 会构建。适合配合同步服务器使用（浏览器无法直接访问大多数服务商接口）。 |
| macOS | 维护者实测可用；CI 每次推送都会构建。仅 ad-hoc 签名、未公证（见上面的安装说明）。Apple 芯片和 Intel 分开提供。 |
| Linux x64、ARM64 | 实验性。CI 每次推送都会在对应架构的构建机上原生构建，但**尚未在真机上运行验证**。托盘只有菜单（没有托盘小面板）。 |
| iOS | 实验性。CI 构建**未签名**的 IPA（仅支持侧载），**尚未在真机上运行**。WidgetKit 源码没有编进 IPA。 |

## 开始使用

1. 启动 TokenBar。桌面端会自动检测你已登录的服务（Codex、Claude、Cursor）并添加。
2. 在**账户 → 添加账户**中添加其他服务：选择服务（支持搜索），粘贴 Key 或 Cookie，保存。同一服务可以有多个账户（例如不同的 `CODEX_HOME` 目录）。
3. 总览页每隔几分钟自动刷新（可调整）。点账户可查看各窗口详情和历史。

**托盘小面板（桌面端）**：点击托盘图标弹出，列出每个账户最紧张的两个额度和重置倒计时，失去焦点自动收起；点**打开 TokenBar**回到主窗口。

**使用历史**：在账户页选择 24 小时、7 天或 30 天。每根柱子是一个时间段内新增的用量，按分项堆叠：

- 「额度用量」：各额度窗口新增的已用百分比。有分项窗口时默认只叠加分项（Cursor 的 Auto / API、Claude 的 Opus / Sonnet）；上方标签可以增减。
- 「费用」：各费用项新增的金额或积分。

服务商的接口大多不提供按模型的明细，所以这里的"模型"只是接口能区分的分项。历史从首次运行起在本地积累。

Cursor 与 Codex 还可以**按模型**查看堆叠柱状图（token 用量，已知价格时附带费用）。Cursor 读取控制台的用量事件（本机登录或 Cookie 均可，手机端也能用）；Codex 读取本机 `~/.codex/sessions` 会话日志，因此需要桌面端。日志只读，只取模型名和 token 数字，不读取提示词或文件内容。

## 更新

TokenBar 在启动时和你点**设置 → 关于 → 检查更新**时，会检查最新的 [GitHub Release](https://github.com/lwh0630/TokenBar/releases)。有新版本时显示更新说明，并打开发布页供你下载。可以关闭启动时的检查，也可以忽略某个版本。

检查只会向 `api.github.com` 发送一次匿名 `GET`，`User-Agent` 里带应用版本号。草稿和预发布版本会被忽略。TokenBar 不会自行下载或安装任何东西。

## 命令行

```bash
dart run packages/tokenbar_server/bin/tokenbar.dart --help            # 列出所有服务
dart run packages/tokenbar_server/bin/tokenbar.dart usage             # 本机所有已登录服务
dart run packages/tokenbar_server/bin/tokenbar.dart usage -p cursor   # 指定服务
dart run packages/tokenbar_server/bin/tokenbar.dart usage --json
```

## 可选：自建服务器同步

只有想在手机 / 浏览器里查看电脑上的额度时才需要。服务器只保存额度快照，不会收到任何服务商凭证。

```bash
# 服务器（同时托管网页版）
docker compose up -d          # 需在 .env 中设置 TOKENBAR_TOKEN（可选 TOKENBAR_READ_TOKEN）

# 或不用 Docker
flutter build web
(cd packages/tokenbar_server && dart build cli -o ../../build/server)
TOKENBAR_TOKEN=change-me build/server/bundle/bin/tokenbar serve --web build/web --port 8787
```

构建服务器要用 `dart build cli`，不要用 `dart compile exe`（会缺少 SQLite 动态库）。

电脑端：**设置 → 服务器同步 →「推送本机数据」**，填服务器地址和管理员令牌。手机端：**「查看服务器数据」**，填只读令牌。没有桌面界面的机器可以定时运行 `tokenbar collect --server URL --token TOKEN`。

## 从源码构建

环境：Flutter 3.47.7（Dart 3.13.5）。Android 另需 JDK 17 和 Android SDK；Windows 需要安装了「使用 C++ 的桌面开发」工作负载的 Visual Studio 2022。

```bash
git clone https://github.com/lwh0630/TokenBar.git
cd TokenBar
flutter pub get

flutter run -d windows        # 或 -d android、-d chrome
flutter build windows --release
flutter build apk --release   # 需要签名材料，见下
```

**Android 发布签名。** release 构建不会退回调试密钥。请提供 `android/key.properties`（已被 git 忽略）或环境变量：

```properties
storeFile=/你的/密钥库/绝对路径.jks
storePassword=...
keyPassword=...
keyAlias=...
```

```bash
# 生成你自己的密钥
keytool -genkeypair -keystore your.jks -alias tokenbar -keyalg RSA -keysize 4096 -validity 10000
```

调试构建（`flutter run`、`flutter build apk --debug`）不需要密钥。

**演示模式。** `flutter run --dart-define=TOKENBAR_DEMO=true`（加 `--dart-define=TOKENBAR_DEMO_LANG=en` 或 `zh` 可固定界面语言）使用虚构的账户和一个月的模拟历史启动。它使用内存存储，不发任何网络请求，也不会碰你真实的设置或凭证。上面的截图就是这样拍的。

### 测试

```bash
flutter analyze && flutter test
(cd packages/tokenbar_core && dart analyze && dart test)
(cd packages/tokenbar_server && dart analyze && dart test)
dart format --output=none --set-exit-if-changed lib test packages
```

### 目录结构

```
lib/                      Flutter 应用（provider + ChangeNotifier）
packages/tokenbar_core/   纯 Dart：模型、各服务实现、同步客户端、托盘图标渲染
packages/tokenbar_server/ 命令行（usage / collect / serve）与可选同步服务器（shelf + sqlite）
android/ ios/ windows/ …  平台工程、Android 小组件、iOS WidgetKit 源码
tool/gen_icons.py         重新生成各平台的应用图标
.github/workflows/        CI 与签名发布流水线
```

## 发布流程

发布由 [`release.yml`](.github/workflows/release.yml) 完成：推送 `vX.Y.Z` 标签（或手动运行工作流）。它会检查并构建，用存放在 `production` 环境中的密钥给各 ABI 的 Android APK 签名，构建 Windows x64 与 ARM64 安装程序、Linux x64 与 ARM64 压缩包、macOS（Apple 芯片与 Intel）磁盘映像和未签名的 iOS IPA，并创建带 `SHA256SUMS.txt` 的**草稿** Release。手动发布草稿之前不会公开任何内容。上传前会用预期的证书指纹校验 APK。

## 路线图

- 服务商模块提供的文字仍是中文：`packages/tokenbar_core` 中的配置提示、字段名、错误信息，以及较少见的额度和积分标签。应用界面本身已有简体中文和英文（`lib/l10n/`），之后可以在那里加入更多语言。
- 在真机上验证 Linux（x64、ARM64）、iOS 和 Windows ARM64 版本。
- 带代码签名的 Windows 版本，以及签名并公证的 macOS 版本（都需要付费证书）。
- 更多服务。新增一个服务工作量小、路径清晰：步骤和规则（只用有文档的接口、不虚构 API、不把凭证写进日志）见 [AGENTS.md](AGENTS.md)。

## 参与贡献

欢迎提交 Issue 和 Pull Request。提 PR 前请运行[测试](#测试)里的检查。新增服务需要实现代码、一份真实响应样本、一个 `MockClient` 测试，并补充到上面的表格。

## 许可证

[MIT](LICENSE)。服务接口的研究基于 [CodexBar](https://github.com/steipete/CodexBar)（MIT），见 [NOTICE.md](NOTICE.md)。

服务商图标位于 `assets/provider_icons/`，复制自 CodexBar（MIT）。logo 为各自所有者的商标，仅用于标识对应服务，见 [assets/provider_icons/README.md](assets/provider_icons/README.md)。

TokenBar 是独立项目，与其可监控的任何服务无隶属或背书关系。
