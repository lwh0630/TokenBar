// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get navQuota => '额度';

  @override
  String get navAccounts => '账户';

  @override
  String get navSettings => '设置';

  @override
  String get refresh => '刷新';

  @override
  String get refreshNow => '立即刷新';

  @override
  String get openTokenBar => '打开 TokenBar';

  @override
  String get quit => '退出';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get save => '保存';

  @override
  String get later => '稍后';

  @override
  String get addAccount => '添加账户';

  @override
  String get systemDefault => '跟随系统';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get resetImminent => '即将重置';

  @override
  String get lessThanMinute => '不到 1 分钟';

  @override
  String countdownDaysHours(int days, int hours) {
    return '$days天$hours小时';
  }

  @override
  String countdownDays(int days) {
    return '$days天';
  }

  @override
  String countdownHoursMinutes(int hours, int minutes) {
    return '$hours小时$minutes分';
  }

  @override
  String countdownHours(int hours) {
    return '$hours小时';
  }

  @override
  String countdownMinutes(int minutes) {
    return '$minutes分钟';
  }

  @override
  String resetsIn(String countdown) {
    return '$countdown后重置';
  }

  @override
  String resetTomorrow(String time) {
    return '明天 $time';
  }

  @override
  String resetWeekday(String weekday, String time) {
    return '$weekday $time';
  }

  @override
  String resetDate(String date, String time) {
    return '$date $time';
  }

  @override
  String monthDay(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get weekdayMon => '周一';

  @override
  String get weekdayTue => '周二';

  @override
  String get weekdayWed => '周三';

  @override
  String get weekdayThu => '周四';

  @override
  String get weekdayFri => '周五';

  @override
  String get weekdaySat => '周六';

  @override
  String get weekdaySun => '周日';

  @override
  String timeWithAgo(String time, String ago) {
    return '$time（$ago）';
  }

  @override
  String updatedAgo(String time) {
    return '更新于 $time';
  }

  @override
  String get listSeparator => '、';

  @override
  String get sentenceJoin => '。';

  @override
  String get labelWeekly => '每周';

  @override
  String get labelMonthly => '每月';

  @override
  String get labelDaily => '每日';

  @override
  String get labelFiveHour => '5 小时';

  @override
  String get labelThisMonth => '本月';

  @override
  String get labelToday => '今日';

  @override
  String get labelQuota => '额度';

  @override
  String labelHours(int count) {
    return '$count 小时';
  }

  @override
  String labelDays(int count) {
    return '$count 天';
  }

  @override
  String get cursorMonthlyQuota => '本月额度';

  @override
  String get cursorApiModels => 'API 模型';

  @override
  String get windowOpusWeekly => 'Opus 每周';

  @override
  String get windowSonnetWeekly => 'Sonnet 每周';

  @override
  String get unlimited => '无限';

  @override
  String get creditsBalance => 'Credits 余额';

  @override
  String get creditsSpendLimit => '月度 Credits 上限';

  @override
  String get extraUsage => '额外用量';

  @override
  String get cursorPlanUsage => '本月用量';

  @override
  String get cursorOnDemand => '按需用量';

  @override
  String get cursorTeamOnDemand => '团队按需用量';

  @override
  String get sourceCursorLocal => 'Cursor 本机登录';

  @override
  String get sourceServer => '服务器';

  @override
  String get localLogin => '本机登录';

  @override
  String get remainingSuffix => '剩余';

  @override
  String usedPercent(String value) {
    return '已用 $value';
  }

  @override
  String paceAhead(int percent) {
    return '快于节奏 $percent%';
  }

  @override
  String paceBehind(int percent) {
    return '低于节奏 $percent%';
  }

  @override
  String paceTooltip(int percent) {
    return '线性消耗下应剩余 $percent%';
  }

  @override
  String get noData => '无数据';

  @override
  String staleDataNotice(String error) {
    return '显示的是上次数据：$error';
  }

  @override
  String fromDevice(String origin) {
    return '来自 $origin';
  }

  @override
  String get syncNeedsServerConfig => '请先在设置中配置服务器地址和令牌';

  @override
  String syncFailed(String error) {
    return '同步失败：$error';
  }

  @override
  String unsupportedProvider(String providerId) {
    return '不支持的服务：$providerId';
  }

  @override
  String get serverTokenInvalid => '已连接，但令牌无效';

  @override
  String get syncModeOff => '不使用';

  @override
  String get syncModeServerView => '查看服务器数据';

  @override
  String get syncModePush => '推送本机数据';

  @override
  String get quotaLoading => '正在读取额度…';

  @override
  String get noAccountsYetPanel => '还没有账户\n打开 TokenBar 添加服务';

  @override
  String get noQuotaDataYet => '还没有额度数据';

  @override
  String get webEmptyMessage => '还没有设备推送数据。\n在电脑上的 TokenBar 开启“推送本机数据”，或运行 tokenbar collect。';

  @override
  String get desktopEmptyMessage => '添加 Codex、Claude 或 Cursor 账户。\nTokenBar 会直接读取本机登录状态，向官方查询额度。';

  @override
  String get mobileEmptyMessage =>
      '添加 Cursor 账户（粘贴 cursor.com Cookie）即可直接查看额度。\nCodex / Claude 的登录在电脑上，可选用服务器同步到手机。';

  @override
  String get serverSettings => '服务器设置';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsBackground => '背景';

  @override
  String get backgroundAurora => '极光';

  @override
  String get backgroundSunset => '日落';

  @override
  String get backgroundOcean => '海洋';

  @override
  String get backgroundForest => '森林';

  @override
  String get backgroundGraphite => '石墨';

  @override
  String get backgroundImage => '自定义图片';

  @override
  String get backgroundChooseImage => '选择图片';

  @override
  String get backgroundChangeImage => '更换图片';

  @override
  String get backgroundRemoveImage => '移除图片';

  @override
  String get backgroundDim => '遮罩强度';

  @override
  String get backgroundDimHint => '遮罩越强，文字越清晰；越弱，图片越明显。';

  @override
  String get backgroundImageFailed => '无法使用这张图片';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get settingsLanguage => '语言';

  @override
  String get sectionRefresh => '刷新';

  @override
  String get autoRefreshInterval => '自动刷新间隔';

  @override
  String get autoRefreshIntervalHint => '连续失败时会自动退避，最长 30 分钟';

  @override
  String refreshMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get sectionNotifications => '通知';

  @override
  String get lowQuotaAlerts => '低额度提醒';

  @override
  String get alertThresholds => '提醒阈值（剩余）';

  @override
  String get resetAlerts => '额度重置提醒';

  @override
  String get resetAlertsHint => '额度较低时重置后通知';

  @override
  String get sectionSyncOptional => '服务器同步（可选）';

  @override
  String get sectionServer => '服务器';

  @override
  String syncEnabled(String mode) {
    return '已启用：$mode';
  }

  @override
  String get syncDisabled => '未启用';

  @override
  String get syncOptionalHint => '不需要服务器也能使用。只有想在手机或网页上查看电脑上的额度时，才需要自建 TokenBar 服务器。';

  @override
  String get syncDescLocal => '所有账户都由本机直接向官方查询，不需要服务器。';

  @override
  String get syncDescServerWeb => '显示各设备推送到本服务器的额度数据。';

  @override
  String get syncDescServerDesktop => '在本机账户之外，再显示其他设备推送到自建服务器的账户（例如电脑上的 Codex / Claude）。';

  @override
  String get syncDescPush => '把本机查询结果推送到自建服务器，供手机和网页查看；同时显示服务器上其他设备的账户。';

  @override
  String get serverUrl => '服务器地址';

  @override
  String get accessToken => '访问令牌';

  @override
  String get tokenHelperPush => '推送需要管理员令牌 (TOKENBAR_TOKEN)';

  @override
  String get tokenHelperRead => '只读令牌或管理员令牌';

  @override
  String get deviceName => '设备名称';

  @override
  String get deviceNameHint => '例如：办公室电脑';

  @override
  String get savedSyncSettings => '已保存同步设置';

  @override
  String get testConnection => '测试连接';

  @override
  String get connectionOk => '连接成功';

  @override
  String connectionFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String get sectionDataSources => '数据源';

  @override
  String get allowCliFallback => '允许调用 Codex CLI 兜底';

  @override
  String get allowCliFallbackHint => 'OAuth 令牌过期时通过 `codex app-server` 读取额度（由 CLI 负责刷新登录）';

  @override
  String get allowClaudeRefresh => '允许 TokenBar 刷新 Claude 令牌';

  @override
  String get allowClaudeRefreshHint =>
      '令牌过期时由 TokenBar 刷新并写回 ~/.claude/.credentials.json。刷新会轮换 refresh token，若 Claude Code 正在运行可能需要重新登录。默认关闭。';

  @override
  String get sectionDesktop => '桌面';

  @override
  String get launchAtStartup => '开机自动启动';

  @override
  String get minimizeToTray => '关闭窗口时最小化到托盘';

  @override
  String get trayDisplay => '托盘显示';

  @override
  String get trayDisplayHint => '托盘图标（以及 macOS 菜单栏文字）显示哪个账户的剩余额度。';

  @override
  String get trayDisplayAuto => '自动（最紧张的账户）';

  @override
  String get sectionAbout => '关于';

  @override
  String get updateChecking => '正在检查…';

  @override
  String get upToDate => '已是最新版本';

  @override
  String newVersionAvailable(String tag) {
    return '发现新版本 $tag';
  }

  @override
  String get checkFailedRateLimit => '检查失败：请求过于频繁，请稍后再试';

  @override
  String get checkFailedNetwork => '检查失败：无法连接 GitHub';

  @override
  String get checkFailedFormat => '检查失败：GitHub 返回了无法识别的数据';

  @override
  String get viewUpdate => '查看更新';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get autoCheckUpdates => '启动时自动检查更新';

  @override
  String get autoCheckUpdatesHint => '仅向 GitHub 请求最新版本号，不发送任何账号或使用数据';

  @override
  String get projectHome => '项目主页';

  @override
  String get aboutBlurb =>
      '开源跨平台 AI 额度监控（MIT）。数据获取方式参考 steipete/CodexBar。直接向各服务商官方接口查询，复用本机客户端的登录状态（只读），不收集账号密码；可选的自建服务器只保存额度快照，不保存令牌。';

  @override
  String get updateNoNotes => '此版本未提供更新说明。';

  @override
  String currentVersion(String version) {
    return '当前版本 $version';
  }

  @override
  String get skipThisVersion => '忽略此版本';

  @override
  String get goToDownload => '前往下载';

  @override
  String get usageNote => '用量为各额度窗口在该时段内新增的已用百分比；不同窗口可能统计同一批请求，可用上方标签选择要叠加的项。';

  @override
  String get historyNotEnough => '历史数据不足，自动刷新后会逐渐积累';

  @override
  String get metricUsage => '额度用量';

  @override
  String get metricCost => '费用';

  @override
  String get selectAtLeastOne => '请至少选择一项';

  @override
  String get noUsageChanges => '这段时间内没有用量变化';

  @override
  String get noCostChanges => '这段时间内没有费用变化';

  @override
  String get viewQuotaWindows => '额度窗口';

  @override
  String get viewModels => '模型';

  @override
  String get viewSpend => '花费';

  @override
  String get metricTokens => 'Tokens';

  @override
  String get seriesOther => '其他';

  @override
  String get historyTotal => '总计';

  @override
  String get historyEmptyTitle => '暂无历史数据';

  @override
  String get historyEmptyBody => '历史需要多次刷新才会积累，保持应用运行一段时间后再来看看。';

  @override
  String historyEmptyModelBody(String source) {
    return '按模型的统计读取自$source，所选时间范围内没有记录。';
  }

  @override
  String modelNote(String source) {
    return '按模型的统计读取自$source；tokens 含输入、输出与缓存，各服务的计量方式可能不同。';
  }

  @override
  String get modelSourceCursor => 'Cursor 用量记录';

  @override
  String get modelSourceCodex => 'Codex 本机日志';

  @override
  String get modelSourceLocal => '本机用量记录';

  @override
  String get rangeDay => '24 小时';

  @override
  String get rangeWeek => '7 天';

  @override
  String get rangeMonth => '30 天';

  @override
  String get accountNotFound => '账户不存在';

  @override
  String get allQuotas => '全部额度';

  @override
  String get usageHistory => '使用历史';

  @override
  String historyLoadFailed(String error) {
    return '加载历史失败：$error';
  }

  @override
  String get infoService => '服务';

  @override
  String get infoPlan => '套餐';

  @override
  String get infoAccount => '账户';

  @override
  String get infoSource => '数据来源';

  @override
  String get infoDevice => '采集设备';

  @override
  String get infoUpdatedAt => '更新时间';

  @override
  String get infoLastError => '最近错误';

  @override
  String projectionRunsOut(String countdown) {
    return '按当前速度约 $countdown后用完（早于重置）';
  }

  @override
  String get exhaustedWaitingReset => '已用完，等待重置';

  @override
  String projectedAtReset(String percent) {
    return '按当前速度，重置时预计用掉 $percent';
  }

  @override
  String get myAccounts => '我的账户';

  @override
  String get dragToReorder => '拖动排序';

  @override
  String get detectLocalLogins => '检测本机已登录的服务';

  @override
  String get noNewLocalLogins => '没有发现新的本机登录';

  @override
  String addedAccounts(String names) {
    return '已添加：$names';
  }

  @override
  String get noAccountsList => '还没有账户';

  @override
  String get serverAccounts => '服务器上的账户';

  @override
  String get serverNotConfigured => '未配置服务器';

  @override
  String get noRemoteAccounts => '服务器上暂无其他设备推送的账户。';

  @override
  String get mobileAccountsHint =>
      '填写 API Key 或粘贴 Cookie 的服务可以直接在手机上查询。Codex / Claude 等只在电脑上登录的服务，想在手机上看，可在设置里开启可选的服务器同步。';

  @override
  String get defaultLogin => '默认登录';

  @override
  String defaultLoginAt(String home) {
    return '默认登录（$home）';
  }

  @override
  String get deleteAccountTitle => '删除账户';

  @override
  String deleteAccountBody(String label) {
    return '确定删除“$label”？本地历史记录也会被删除，CLI 登录不受影响。';
  }

  @override
  String get chooseService => '选择服务';

  @override
  String get search => '搜索';

  @override
  String get serviceField => '服务';

  @override
  String get displayName => '显示名称';

  @override
  String get editAccount => '编辑账户';

  @override
  String fillField(String label) {
    return '请填写 $label';
  }

  @override
  String optionalField(String label) {
    return '$label（可选）';
  }

  @override
  String get cursorDataDirField => 'Cursor 数据目录（可选）';

  @override
  String get configDirField => '配置目录（可选）';

  @override
  String get homeDirHelper => '留空使用默认目录；多账户时为每个账户指定不同目录';

  @override
  String envDetected(String names) {
    return '已检测到环境变量 $names，可留空';
  }

  @override
  String get storedInKeychain => '保存在系统安全存储中';

  @override
  String get savedKeepUnchanged => '已保存，留空保持不变';

  @override
  String quotaResetTitle(String name, String window) {
    return '$name · $window额度已重置';
  }

  @override
  String quotaResetBody(String remaining) {
    return '当前剩余 $remaining';
  }

  @override
  String lowQuotaTitle(String name, String window) {
    return '$name · $window额度不足';
  }

  @override
  String lowQuotaBody(String remaining) {
    return '剩余 $remaining';
  }

  @override
  String lowQuotaBodyWithReset(String remaining, String countdown) {
    return '剩余 $remaining，$countdown后重置';
  }

  @override
  String get notificationChannelName => '额度提醒';

  @override
  String get notificationChannelDescription => '低额度和额度重置提醒';

  @override
  String widgetUpdatedAt(String time) {
    return '$time 更新';
  }
}
