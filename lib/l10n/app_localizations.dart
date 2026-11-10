import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('zh')];

  /// No description provided for @navQuota.
  ///
  /// In zh, this message translates to:
  /// **'额度'**
  String get navQuota;

  /// No description provided for @navAccounts.
  ///
  /// In zh, this message translates to:
  /// **'账户'**
  String get navAccounts;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @refreshNow.
  ///
  /// In zh, this message translates to:
  /// **'立即刷新'**
  String get refreshNow;

  /// No description provided for @openTokenBar.
  ///
  /// In zh, this message translates to:
  /// **'打开 TokenBar'**
  String get openTokenBar;

  /// No description provided for @quit.
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get quit;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @later.
  ///
  /// In zh, this message translates to:
  /// **'稍后'**
  String get later;

  /// No description provided for @addAccount.
  ///
  /// In zh, this message translates to:
  /// **'添加账户'**
  String get addAccount;

  /// No description provided for @systemDefault.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get systemDefault;

  /// No description provided for @languageZh.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @justNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 分钟前'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 小时前'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{count} 天前'**
  String daysAgo(int count);

  /// No description provided for @resetImminent.
  ///
  /// In zh, this message translates to:
  /// **'即将重置'**
  String get resetImminent;

  /// No description provided for @lessThanMinute.
  ///
  /// In zh, this message translates to:
  /// **'不到 1 分钟'**
  String get lessThanMinute;

  /// No description provided for @countdownDaysHours.
  ///
  /// In zh, this message translates to:
  /// **'{days}天{hours}小时'**
  String countdownDaysHours(int days, int hours);

  /// No description provided for @countdownDays.
  ///
  /// In zh, this message translates to:
  /// **'{days}天'**
  String countdownDays(int days);

  /// No description provided for @countdownHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{hours}小时{minutes}分'**
  String countdownHoursMinutes(int hours, int minutes);

  /// No description provided for @countdownHours.
  ///
  /// In zh, this message translates to:
  /// **'{hours}小时'**
  String countdownHours(int hours);

  /// No description provided for @countdownMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes}分钟'**
  String countdownMinutes(int minutes);

  /// No description provided for @resetsIn.
  ///
  /// In zh, this message translates to:
  /// **'{countdown}后重置'**
  String resetsIn(String countdown);

  /// No description provided for @resetTomorrow.
  ///
  /// In zh, this message translates to:
  /// **'明天 {time}'**
  String resetTomorrow(String time);

  /// No description provided for @resetWeekday.
  ///
  /// In zh, this message translates to:
  /// **'{weekday} {time}'**
  String resetWeekday(String weekday, String time);

  /// No description provided for @resetDate.
  ///
  /// In zh, this message translates to:
  /// **'{date} {time}'**
  String resetDate(String date, String time);

  /// No description provided for @monthDay.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日'**
  String monthDay(int month, int day);

  /// No description provided for @weekdayMon.
  ///
  /// In zh, this message translates to:
  /// **'周一'**
  String get weekdayMon;

  /// No description provided for @weekdayTue.
  ///
  /// In zh, this message translates to:
  /// **'周二'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In zh, this message translates to:
  /// **'周三'**
  String get weekdayWed;

  /// No description provided for @weekdayThu.
  ///
  /// In zh, this message translates to:
  /// **'周四'**
  String get weekdayThu;

  /// No description provided for @weekdayFri.
  ///
  /// In zh, this message translates to:
  /// **'周五'**
  String get weekdayFri;

  /// No description provided for @weekdaySat.
  ///
  /// In zh, this message translates to:
  /// **'周六'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In zh, this message translates to:
  /// **'周日'**
  String get weekdaySun;

  /// No description provided for @timeWithAgo.
  ///
  /// In zh, this message translates to:
  /// **'{time}（{ago}）'**
  String timeWithAgo(String time, String ago);

  /// No description provided for @updatedAgo.
  ///
  /// In zh, this message translates to:
  /// **'更新于 {time}'**
  String updatedAgo(String time);

  /// No description provided for @listSeparator.
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get listSeparator;

  /// No description provided for @sentenceJoin.
  ///
  /// In zh, this message translates to:
  /// **'。'**
  String get sentenceJoin;

  /// No description provided for @labelWeekly.
  ///
  /// In zh, this message translates to:
  /// **'每周'**
  String get labelWeekly;

  /// No description provided for @labelMonthly.
  ///
  /// In zh, this message translates to:
  /// **'每月'**
  String get labelMonthly;

  /// No description provided for @labelDaily.
  ///
  /// In zh, this message translates to:
  /// **'每日'**
  String get labelDaily;

  /// No description provided for @labelFiveHour.
  ///
  /// In zh, this message translates to:
  /// **'5 小时'**
  String get labelFiveHour;

  /// No description provided for @labelThisMonth.
  ///
  /// In zh, this message translates to:
  /// **'本月'**
  String get labelThisMonth;

  /// No description provided for @labelToday.
  ///
  /// In zh, this message translates to:
  /// **'今日'**
  String get labelToday;

  /// No description provided for @labelQuota.
  ///
  /// In zh, this message translates to:
  /// **'额度'**
  String get labelQuota;

  /// No description provided for @labelHours.
  ///
  /// In zh, this message translates to:
  /// **'{count} 小时'**
  String labelHours(int count);

  /// No description provided for @labelDays.
  ///
  /// In zh, this message translates to:
  /// **'{count} 天'**
  String labelDays(int count);

  /// No description provided for @cursorMonthlyQuota.
  ///
  /// In zh, this message translates to:
  /// **'本月额度'**
  String get cursorMonthlyQuota;

  /// No description provided for @cursorApiModels.
  ///
  /// In zh, this message translates to:
  /// **'API 模型'**
  String get cursorApiModels;

  /// No description provided for @windowOpusWeekly.
  ///
  /// In zh, this message translates to:
  /// **'Opus 每周'**
  String get windowOpusWeekly;

  /// No description provided for @windowSonnetWeekly.
  ///
  /// In zh, this message translates to:
  /// **'Sonnet 每周'**
  String get windowSonnetWeekly;

  /// No description provided for @unlimited.
  ///
  /// In zh, this message translates to:
  /// **'无限'**
  String get unlimited;

  /// No description provided for @creditsBalance.
  ///
  /// In zh, this message translates to:
  /// **'Credits 余额'**
  String get creditsBalance;

  /// No description provided for @creditsSpendLimit.
  ///
  /// In zh, this message translates to:
  /// **'月度 Credits 上限'**
  String get creditsSpendLimit;

  /// No description provided for @extraUsage.
  ///
  /// In zh, this message translates to:
  /// **'额外用量'**
  String get extraUsage;

  /// No description provided for @cursorPlanUsage.
  ///
  /// In zh, this message translates to:
  /// **'本月用量'**
  String get cursorPlanUsage;

  /// No description provided for @cursorOnDemand.
  ///
  /// In zh, this message translates to:
  /// **'按需用量'**
  String get cursorOnDemand;

  /// No description provided for @cursorTeamOnDemand.
  ///
  /// In zh, this message translates to:
  /// **'团队按需用量'**
  String get cursorTeamOnDemand;

  /// No description provided for @sourceCursorLocal.
  ///
  /// In zh, this message translates to:
  /// **'Cursor 本机登录'**
  String get sourceCursorLocal;

  /// No description provided for @sourceServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get sourceServer;

  /// No description provided for @localLogin.
  ///
  /// In zh, this message translates to:
  /// **'本机登录'**
  String get localLogin;

  /// No description provided for @remainingSuffix.
  ///
  /// In zh, this message translates to:
  /// **'剩余'**
  String get remainingSuffix;

  /// No description provided for @usedPercent.
  ///
  /// In zh, this message translates to:
  /// **'已用 {value}'**
  String usedPercent(String value);

  /// No description provided for @paceAhead.
  ///
  /// In zh, this message translates to:
  /// **'快于节奏 {percent}%'**
  String paceAhead(int percent);

  /// No description provided for @paceBehind.
  ///
  /// In zh, this message translates to:
  /// **'低于节奏 {percent}%'**
  String paceBehind(int percent);

  /// No description provided for @paceTooltip.
  ///
  /// In zh, this message translates to:
  /// **'线性消耗下应剩余 {percent}%'**
  String paceTooltip(int percent);

  /// No description provided for @noData.
  ///
  /// In zh, this message translates to:
  /// **'无数据'**
  String get noData;

  /// No description provided for @staleDataNotice.
  ///
  /// In zh, this message translates to:
  /// **'显示的是上次数据：{error}'**
  String staleDataNotice(String error);

  /// No description provided for @fromDevice.
  ///
  /// In zh, this message translates to:
  /// **'来自 {origin}'**
  String fromDevice(String origin);

  /// No description provided for @syncNeedsServerConfig.
  ///
  /// In zh, this message translates to:
  /// **'请先在设置中配置服务器地址和令牌'**
  String get syncNeedsServerConfig;

  /// No description provided for @syncFailed.
  ///
  /// In zh, this message translates to:
  /// **'同步失败：{error}'**
  String syncFailed(String error);

  /// No description provided for @unsupportedProvider.
  ///
  /// In zh, this message translates to:
  /// **'不支持的服务：{providerId}'**
  String unsupportedProvider(String providerId);

  /// No description provided for @serverTokenInvalid.
  ///
  /// In zh, this message translates to:
  /// **'已连接，但令牌无效'**
  String get serverTokenInvalid;

  /// No description provided for @syncModeOff.
  ///
  /// In zh, this message translates to:
  /// **'不使用'**
  String get syncModeOff;

  /// No description provided for @syncModeServerView.
  ///
  /// In zh, this message translates to:
  /// **'查看服务器数据'**
  String get syncModeServerView;

  /// No description provided for @syncModePush.
  ///
  /// In zh, this message translates to:
  /// **'推送本机数据'**
  String get syncModePush;

  /// No description provided for @quotaLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取额度…'**
  String get quotaLoading;

  /// No description provided for @noAccountsYetPanel.
  ///
  /// In zh, this message translates to:
  /// **'还没有账户\n打开 TokenBar 添加服务'**
  String get noAccountsYetPanel;

  /// No description provided for @noQuotaDataYet.
  ///
  /// In zh, this message translates to:
  /// **'还没有额度数据'**
  String get noQuotaDataYet;

  /// No description provided for @webEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'还没有设备推送数据。\n在电脑上的 TokenBar 开启“推送本机数据”，或运行 tokenbar collect。'**
  String get webEmptyMessage;

  /// No description provided for @desktopEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'添加 Codex、Claude 或 Cursor 账户。\nTokenBar 会直接读取本机登录状态，向官方查询额度。'**
  String get desktopEmptyMessage;

  /// No description provided for @mobileEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'添加 Cursor 账户（粘贴 cursor.com Cookie）即可直接查看额度。\nCodex / Claude 的登录在电脑上，可选用服务器同步到手机。'**
  String get mobileEmptyMessage;

  /// No description provided for @serverSettings.
  ///
  /// In zh, this message translates to:
  /// **'服务器设置'**
  String get serverSettings;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get settingsTheme;

  /// No description provided for @settingsBackground.
  ///
  /// In zh, this message translates to:
  /// **'背景'**
  String get settingsBackground;

  /// No description provided for @backgroundAurora.
  ///
  /// In zh, this message translates to:
  /// **'极光'**
  String get backgroundAurora;

  /// No description provided for @backgroundSunset.
  ///
  /// In zh, this message translates to:
  /// **'日落'**
  String get backgroundSunset;

  /// No description provided for @backgroundOcean.
  ///
  /// In zh, this message translates to:
  /// **'海洋'**
  String get backgroundOcean;

  /// No description provided for @backgroundForest.
  ///
  /// In zh, this message translates to:
  /// **'森林'**
  String get backgroundForest;

  /// No description provided for @backgroundGraphite.
  ///
  /// In zh, this message translates to:
  /// **'石墨'**
  String get backgroundGraphite;

  /// No description provided for @backgroundImage.
  ///
  /// In zh, this message translates to:
  /// **'自定义图片'**
  String get backgroundImage;

  /// No description provided for @backgroundChooseImage.
  ///
  /// In zh, this message translates to:
  /// **'选择图片'**
  String get backgroundChooseImage;

  /// No description provided for @backgroundChangeImage.
  ///
  /// In zh, this message translates to:
  /// **'更换图片'**
  String get backgroundChangeImage;

  /// No description provided for @backgroundRemoveImage.
  ///
  /// In zh, this message translates to:
  /// **'移除图片'**
  String get backgroundRemoveImage;

  /// No description provided for @backgroundDim.
  ///
  /// In zh, this message translates to:
  /// **'遮罩强度'**
  String get backgroundDim;

  /// No description provided for @backgroundDimHint.
  ///
  /// In zh, this message translates to:
  /// **'遮罩越强，文字越清晰；越弱，图片越明显。'**
  String get backgroundDimHint;

  /// No description provided for @backgroundImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法使用这张图片'**
  String get backgroundImageFailed;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @sectionRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get sectionRefresh;

  /// No description provided for @autoRefreshInterval.
  ///
  /// In zh, this message translates to:
  /// **'自动刷新间隔'**
  String get autoRefreshInterval;

  /// No description provided for @autoRefreshIntervalHint.
  ///
  /// In zh, this message translates to:
  /// **'连续失败时会自动退避，最长 30 分钟'**
  String get autoRefreshIntervalHint;

  /// No description provided for @refreshMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String refreshMinutes(int minutes);

  /// No description provided for @sectionNotifications.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get sectionNotifications;

  /// No description provided for @lowQuotaAlerts.
  ///
  /// In zh, this message translates to:
  /// **'低额度提醒'**
  String get lowQuotaAlerts;

  /// No description provided for @alertThresholds.
  ///
  /// In zh, this message translates to:
  /// **'提醒阈值（剩余）'**
  String get alertThresholds;

  /// No description provided for @resetAlerts.
  ///
  /// In zh, this message translates to:
  /// **'额度重置提醒'**
  String get resetAlerts;

  /// No description provided for @resetAlertsHint.
  ///
  /// In zh, this message translates to:
  /// **'额度较低时重置后通知'**
  String get resetAlertsHint;

  /// No description provided for @sectionSyncOptional.
  ///
  /// In zh, this message translates to:
  /// **'服务器同步（可选）'**
  String get sectionSyncOptional;

  /// No description provided for @sectionServer.
  ///
  /// In zh, this message translates to:
  /// **'服务器'**
  String get sectionServer;

  /// No description provided for @syncEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用：{mode}'**
  String syncEnabled(String mode);

  /// No description provided for @syncDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get syncDisabled;

  /// No description provided for @syncOptionalHint.
  ///
  /// In zh, this message translates to:
  /// **'不需要服务器也能使用。只有想在手机或网页上查看电脑上的额度时，才需要自建 TokenBar 服务器。'**
  String get syncOptionalHint;

  /// No description provided for @syncDescLocal.
  ///
  /// In zh, this message translates to:
  /// **'所有账户都由本机直接向官方查询，不需要服务器。'**
  String get syncDescLocal;

  /// No description provided for @syncDescServerWeb.
  ///
  /// In zh, this message translates to:
  /// **'显示各设备推送到本服务器的额度数据。'**
  String get syncDescServerWeb;

  /// No description provided for @syncDescServerDesktop.
  ///
  /// In zh, this message translates to:
  /// **'在本机账户之外，再显示其他设备推送到自建服务器的账户（例如电脑上的 Codex / Claude）。'**
  String get syncDescServerDesktop;

  /// No description provided for @syncDescPush.
  ///
  /// In zh, this message translates to:
  /// **'把本机查询结果推送到自建服务器，供手机和网页查看；同时显示服务器上其他设备的账户。'**
  String get syncDescPush;

  /// No description provided for @serverUrl.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverUrl;

  /// No description provided for @accessToken.
  ///
  /// In zh, this message translates to:
  /// **'访问令牌'**
  String get accessToken;

  /// No description provided for @tokenHelperPush.
  ///
  /// In zh, this message translates to:
  /// **'推送需要管理员令牌 (TOKENBAR_TOKEN)'**
  String get tokenHelperPush;

  /// No description provided for @tokenHelperRead.
  ///
  /// In zh, this message translates to:
  /// **'只读令牌或管理员令牌'**
  String get tokenHelperRead;

  /// No description provided for @deviceName.
  ///
  /// In zh, this message translates to:
  /// **'设备名称'**
  String get deviceName;

  /// No description provided for @deviceNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：办公室电脑'**
  String get deviceNameHint;

  /// No description provided for @savedSyncSettings.
  ///
  /// In zh, this message translates to:
  /// **'已保存同步设置'**
  String get savedSyncSettings;

  /// No description provided for @testConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get testConnection;

  /// No description provided for @connectionOk.
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get connectionOk;

  /// No description provided for @connectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{error}'**
  String connectionFailed(String error);

  /// No description provided for @sectionDataSources.
  ///
  /// In zh, this message translates to:
  /// **'数据源'**
  String get sectionDataSources;

  /// No description provided for @allowCliFallback.
  ///
  /// In zh, this message translates to:
  /// **'允许调用 Codex CLI 兜底'**
  String get allowCliFallback;

  /// No description provided for @allowCliFallbackHint.
  ///
  /// In zh, this message translates to:
  /// **'OAuth 令牌过期时通过 `codex app-server` 读取额度（由 CLI 负责刷新登录）'**
  String get allowCliFallbackHint;

  /// No description provided for @allowClaudeRefresh.
  ///
  /// In zh, this message translates to:
  /// **'允许 TokenBar 刷新 Claude 令牌'**
  String get allowClaudeRefresh;

  /// No description provided for @allowClaudeRefreshHint.
  ///
  /// In zh, this message translates to:
  /// **'令牌过期时由 TokenBar 刷新并写回 ~/.claude/.credentials.json。刷新会轮换 refresh token，若 Claude Code 正在运行可能需要重新登录。默认关闭。'**
  String get allowClaudeRefreshHint;

  /// No description provided for @sectionDesktop.
  ///
  /// In zh, this message translates to:
  /// **'桌面'**
  String get sectionDesktop;

  /// No description provided for @launchAtStartup.
  ///
  /// In zh, this message translates to:
  /// **'开机自动启动'**
  String get launchAtStartup;

  /// No description provided for @minimizeToTray.
  ///
  /// In zh, this message translates to:
  /// **'关闭窗口时最小化到托盘'**
  String get minimizeToTray;

  /// No description provided for @hideDockIcon.
  ///
  /// In zh, this message translates to:
  /// **'仅在菜单栏显示（隐藏 Dock 图标）'**
  String get hideDockIcon;

  /// No description provided for @hideDockIconHint.
  ///
  /// In zh, this message translates to:
  /// **'隐藏后可从菜单栏图标打开窗口或退出；此时 ⌘Q 不可用。'**
  String get hideDockIconHint;

  /// No description provided for @trayDisplay.
  ///
  /// In zh, this message translates to:
  /// **'托盘显示'**
  String get trayDisplay;

  /// No description provided for @trayDisplayHint.
  ///
  /// In zh, this message translates to:
  /// **'托盘图标（以及 macOS 菜单栏文字）显示哪个账户的剩余额度。'**
  String get trayDisplayHint;

  /// No description provided for @trayDisplayAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动（最紧张的账户）'**
  String get trayDisplayAuto;

  /// No description provided for @sectionAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get sectionAbout;

  /// No description provided for @updateChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查…'**
  String get updateChecking;

  /// No description provided for @upToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get upToDate;

  /// No description provided for @newVersionAvailable.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本 {tag}'**
  String newVersionAvailable(String tag);

  /// No description provided for @checkFailedRateLimit.
  ///
  /// In zh, this message translates to:
  /// **'检查失败：请求过于频繁，请稍后再试'**
  String get checkFailedRateLimit;

  /// No description provided for @checkFailedNetwork.
  ///
  /// In zh, this message translates to:
  /// **'检查失败：无法连接 GitHub'**
  String get checkFailedNetwork;

  /// No description provided for @checkFailedFormat.
  ///
  /// In zh, this message translates to:
  /// **'检查失败：GitHub 返回了无法识别的数据'**
  String get checkFailedFormat;

  /// No description provided for @viewUpdate.
  ///
  /// In zh, this message translates to:
  /// **'查看更新'**
  String get viewUpdate;

  /// No description provided for @checkForUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkForUpdates;

  /// No description provided for @autoCheckUpdates.
  ///
  /// In zh, this message translates to:
  /// **'启动时自动检查更新'**
  String get autoCheckUpdates;

  /// No description provided for @autoCheckUpdatesHint.
  ///
  /// In zh, this message translates to:
  /// **'仅向 GitHub 请求最新版本号，不发送任何账号或使用数据'**
  String get autoCheckUpdatesHint;

  /// No description provided for @projectHome.
  ///
  /// In zh, this message translates to:
  /// **'项目主页'**
  String get projectHome;

  /// No description provided for @aboutBlurb.
  ///
  /// In zh, this message translates to:
  /// **'开源跨平台 AI 额度监控（MIT）。数据获取方式参考 steipete/CodexBar。直接向各服务商官方接口查询，复用本机客户端的登录状态（只读），不收集账号密码；可选的自建服务器只保存额度快照，不保存令牌。'**
  String get aboutBlurb;

  /// No description provided for @updateNoNotes.
  ///
  /// In zh, this message translates to:
  /// **'此版本未提供更新说明。'**
  String get updateNoNotes;

  /// No description provided for @currentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本 {version}'**
  String currentVersion(String version);

  /// No description provided for @skipThisVersion.
  ///
  /// In zh, this message translates to:
  /// **'忽略此版本'**
  String get skipThisVersion;

  /// No description provided for @goToDownload.
  ///
  /// In zh, this message translates to:
  /// **'前往下载'**
  String get goToDownload;

  /// No description provided for @updateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get updateNow;

  /// No description provided for @updateDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get updateDone;

  /// No description provided for @openReleasePage.
  ///
  /// In zh, this message translates to:
  /// **'打开发布页'**
  String get openReleasePage;

  /// No description provided for @updateDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载…'**
  String get updateDownloading;

  /// No description provided for @updateDownloadingPercent.
  ///
  /// In zh, this message translates to:
  /// **'正在下载 {percent}%'**
  String updateDownloadingPercent(int percent);

  /// No description provided for @updateVerifying.
  ///
  /// In zh, this message translates to:
  /// **'正在校验文件…'**
  String get updateVerifying;

  /// No description provided for @updateInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在启动安装…'**
  String get updateInstalling;

  /// No description provided for @updateFailedNetwork.
  ///
  /// In zh, this message translates to:
  /// **'下载失败，请检查网络后重试。'**
  String get updateFailedNetwork;

  /// No description provided for @updateFailedChecksum.
  ///
  /// In zh, this message translates to:
  /// **'文件校验失败，已丢弃下载内容。请重试，或前往发布页手动下载。'**
  String get updateFailedChecksum;

  /// No description provided for @updateFailedPermission.
  ///
  /// In zh, this message translates to:
  /// **'请在系统设置中允许 TokenBar 安装应用，然后回到这里重试。'**
  String get updateFailedPermission;

  /// No description provided for @updateFailedLaunch.
  ///
  /// In zh, this message translates to:
  /// **'无法启动安装程序，请前往发布页手动下载。'**
  String get updateFailedLaunch;

  /// No description provided for @updateSavedTo.
  ///
  /// In zh, this message translates to:
  /// **'已下载并通过校验：{path}\n请手动完成安装。'**
  String updateSavedTo(String path);

  /// No description provided for @usageNote.
  ///
  /// In zh, this message translates to:
  /// **'用量为各额度窗口在该时段内新增的已用百分比；不同窗口可能统计同一批请求，可用上方标签选择要叠加的项。'**
  String get usageNote;

  /// No description provided for @historyNotEnough.
  ///
  /// In zh, this message translates to:
  /// **'历史数据不足，自动刷新后会逐渐积累'**
  String get historyNotEnough;

  /// No description provided for @metricUsage.
  ///
  /// In zh, this message translates to:
  /// **'额度用量'**
  String get metricUsage;

  /// No description provided for @metricCost.
  ///
  /// In zh, this message translates to:
  /// **'费用'**
  String get metricCost;

  /// No description provided for @selectAtLeastOne.
  ///
  /// In zh, this message translates to:
  /// **'请至少选择一项'**
  String get selectAtLeastOne;

  /// No description provided for @noUsageChanges.
  ///
  /// In zh, this message translates to:
  /// **'这段时间内没有用量变化'**
  String get noUsageChanges;

  /// No description provided for @noCostChanges.
  ///
  /// In zh, this message translates to:
  /// **'这段时间内没有费用变化'**
  String get noCostChanges;

  /// No description provided for @viewQuotaWindows.
  ///
  /// In zh, this message translates to:
  /// **'额度窗口'**
  String get viewQuotaWindows;

  /// No description provided for @viewModels.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get viewModels;

  /// No description provided for @viewSpend.
  ///
  /// In zh, this message translates to:
  /// **'花费'**
  String get viewSpend;

  /// No description provided for @metricTokens.
  ///
  /// In zh, this message translates to:
  /// **'Tokens'**
  String get metricTokens;

  /// No description provided for @seriesOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get seriesOther;

  /// No description provided for @historyTotal.
  ///
  /// In zh, this message translates to:
  /// **'总计'**
  String get historyTotal;

  /// No description provided for @historyEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史数据'**
  String get historyEmptyTitle;

  /// No description provided for @historyEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'历史需要多次刷新才会积累，保持应用运行一段时间后再来看看。'**
  String get historyEmptyBody;

  /// No description provided for @historyEmptyModelBody.
  ///
  /// In zh, this message translates to:
  /// **'按模型的统计读取自{source}，所选时间范围内没有记录。'**
  String historyEmptyModelBody(String source);

  /// No description provided for @modelNote.
  ///
  /// In zh, this message translates to:
  /// **'按模型的统计读取自{source}；tokens 含输入、输出与缓存，各服务的计量方式可能不同。'**
  String modelNote(String source);

  /// No description provided for @modelSourceCursor.
  ///
  /// In zh, this message translates to:
  /// **'Cursor 用量记录'**
  String get modelSourceCursor;

  /// No description provided for @modelSourceCodex.
  ///
  /// In zh, this message translates to:
  /// **'Codex 本机日志'**
  String get modelSourceCodex;

  /// No description provided for @modelSourceLocal.
  ///
  /// In zh, this message translates to:
  /// **'本机用量记录'**
  String get modelSourceLocal;

  /// No description provided for @rangeDay.
  ///
  /// In zh, this message translates to:
  /// **'24 小时'**
  String get rangeDay;

  /// No description provided for @rangeWeek.
  ///
  /// In zh, this message translates to:
  /// **'7 天'**
  String get rangeWeek;

  /// No description provided for @rangeMonth.
  ///
  /// In zh, this message translates to:
  /// **'30 天'**
  String get rangeMonth;

  /// No description provided for @accountNotFound.
  ///
  /// In zh, this message translates to:
  /// **'账户不存在'**
  String get accountNotFound;

  /// No description provided for @allQuotas.
  ///
  /// In zh, this message translates to:
  /// **'全部额度'**
  String get allQuotas;

  /// No description provided for @usageHistory.
  ///
  /// In zh, this message translates to:
  /// **'使用历史'**
  String get usageHistory;

  /// No description provided for @historyLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载历史失败：{error}'**
  String historyLoadFailed(String error);

  /// No description provided for @infoService.
  ///
  /// In zh, this message translates to:
  /// **'服务'**
  String get infoService;

  /// No description provided for @infoPlan.
  ///
  /// In zh, this message translates to:
  /// **'套餐'**
  String get infoPlan;

  /// No description provided for @infoAccount.
  ///
  /// In zh, this message translates to:
  /// **'账户'**
  String get infoAccount;

  /// No description provided for @infoSource.
  ///
  /// In zh, this message translates to:
  /// **'数据来源'**
  String get infoSource;

  /// No description provided for @infoDevice.
  ///
  /// In zh, this message translates to:
  /// **'采集设备'**
  String get infoDevice;

  /// No description provided for @infoUpdatedAt.
  ///
  /// In zh, this message translates to:
  /// **'更新时间'**
  String get infoUpdatedAt;

  /// No description provided for @infoLastError.
  ///
  /// In zh, this message translates to:
  /// **'最近错误'**
  String get infoLastError;

  /// No description provided for @projectionRunsOut.
  ///
  /// In zh, this message translates to:
  /// **'按当前速度约 {countdown}后用完（早于重置）'**
  String projectionRunsOut(String countdown);

  /// No description provided for @exhaustedWaitingReset.
  ///
  /// In zh, this message translates to:
  /// **'已用完，等待重置'**
  String get exhaustedWaitingReset;

  /// No description provided for @projectedAtReset.
  ///
  /// In zh, this message translates to:
  /// **'按当前速度，重置时预计用掉 {percent}'**
  String projectedAtReset(String percent);

  /// No description provided for @myAccounts.
  ///
  /// In zh, this message translates to:
  /// **'我的账户'**
  String get myAccounts;

  /// No description provided for @dragToReorder.
  ///
  /// In zh, this message translates to:
  /// **'拖动排序'**
  String get dragToReorder;

  /// No description provided for @detectLocalLogins.
  ///
  /// In zh, this message translates to:
  /// **'检测本机已登录的服务'**
  String get detectLocalLogins;

  /// No description provided for @noNewLocalLogins.
  ///
  /// In zh, this message translates to:
  /// **'没有发现新的本机登录'**
  String get noNewLocalLogins;

  /// No description provided for @addedAccounts.
  ///
  /// In zh, this message translates to:
  /// **'已添加：{names}'**
  String addedAccounts(String names);

  /// No description provided for @noAccountsList.
  ///
  /// In zh, this message translates to:
  /// **'还没有账户'**
  String get noAccountsList;

  /// No description provided for @serverAccounts.
  ///
  /// In zh, this message translates to:
  /// **'服务器上的账户'**
  String get serverAccounts;

  /// No description provided for @serverNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置服务器'**
  String get serverNotConfigured;

  /// No description provided for @noRemoteAccounts.
  ///
  /// In zh, this message translates to:
  /// **'服务器上暂无其他设备推送的账户。'**
  String get noRemoteAccounts;

  /// No description provided for @mobileAccountsHint.
  ///
  /// In zh, this message translates to:
  /// **'填写 API Key 或粘贴 Cookie 的服务可以直接在手机上查询。Codex / Claude 等只在电脑上登录的服务，想在手机上看，可在设置里开启可选的服务器同步。'**
  String get mobileAccountsHint;

  /// No description provided for @defaultLogin.
  ///
  /// In zh, this message translates to:
  /// **'默认登录'**
  String get defaultLogin;

  /// No description provided for @defaultLoginAt.
  ///
  /// In zh, this message translates to:
  /// **'默认登录（{home}）'**
  String defaultLoginAt(String home);

  /// No description provided for @deleteAccountTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除账户'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除“{label}”？本地历史记录也会被删除，CLI 登录不受影响。'**
  String deleteAccountBody(String label);

  /// No description provided for @chooseService.
  ///
  /// In zh, this message translates to:
  /// **'选择服务'**
  String get chooseService;

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// No description provided for @serviceField.
  ///
  /// In zh, this message translates to:
  /// **'服务'**
  String get serviceField;

  /// No description provided for @displayName.
  ///
  /// In zh, this message translates to:
  /// **'显示名称'**
  String get displayName;

  /// No description provided for @editAccount.
  ///
  /// In zh, this message translates to:
  /// **'编辑账户'**
  String get editAccount;

  /// No description provided for @fillField.
  ///
  /// In zh, this message translates to:
  /// **'请填写 {label}'**
  String fillField(String label);

  /// No description provided for @optionalField.
  ///
  /// In zh, this message translates to:
  /// **'{label}（可选）'**
  String optionalField(String label);

  /// No description provided for @cursorDataDirField.
  ///
  /// In zh, this message translates to:
  /// **'Cursor 数据目录（可选）'**
  String get cursorDataDirField;

  /// No description provided for @configDirField.
  ///
  /// In zh, this message translates to:
  /// **'配置目录（可选）'**
  String get configDirField;

  /// No description provided for @homeDirHelper.
  ///
  /// In zh, this message translates to:
  /// **'留空使用默认目录；多账户时为每个账户指定不同目录'**
  String get homeDirHelper;

  /// No description provided for @envDetected.
  ///
  /// In zh, this message translates to:
  /// **'已检测到环境变量 {names}，可留空'**
  String envDetected(String names);

  /// No description provided for @storedInKeychain.
  ///
  /// In zh, this message translates to:
  /// **'保存在系统安全存储中'**
  String get storedInKeychain;

  /// No description provided for @savedKeepUnchanged.
  ///
  /// In zh, this message translates to:
  /// **'已保存，留空保持不变'**
  String get savedKeepUnchanged;

  /// No description provided for @quotaResetTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} · {window}额度已重置'**
  String quotaResetTitle(String name, String window);

  /// No description provided for @quotaResetBody.
  ///
  /// In zh, this message translates to:
  /// **'当前剩余 {remaining}'**
  String quotaResetBody(String remaining);

  /// No description provided for @lowQuotaTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} · {window}额度不足'**
  String lowQuotaTitle(String name, String window);

  /// No description provided for @lowQuotaBody.
  ///
  /// In zh, this message translates to:
  /// **'剩余 {remaining}'**
  String lowQuotaBody(String remaining);

  /// No description provided for @lowQuotaBodyWithReset.
  ///
  /// In zh, this message translates to:
  /// **'剩余 {remaining}，{countdown}后重置'**
  String lowQuotaBodyWithReset(String remaining, String countdown);

  /// No description provided for @notificationChannelName.
  ///
  /// In zh, this message translates to:
  /// **'额度提醒'**
  String get notificationChannelName;

  /// No description provided for @notificationChannelDescription.
  ///
  /// In zh, this message translates to:
  /// **'低额度和额度重置提醒'**
  String get notificationChannelDescription;

  /// No description provided for @widgetUpdatedAt.
  ///
  /// In zh, this message translates to:
  /// **'{time} 更新'**
  String widgetUpdatedAt(String time);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
