import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/design/glass.dart';
import '../../app/design/tokens.dart';
import '../../app_info.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_controller.dart';
import '../../state/settings.dart';
import '../../state/update_controller.dart';
import '../update_dialog.dart';
import '../widgets/background_picker.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<AppController>();
    final s = c.settings;
    void update(AppSettings next) => c.updateSettings(next);

    return Scaffold(
      appBar: AppBar(title: Text(l.navSettings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(l.settingsAppearance, [
                    ListTile(
                      title: Text(l.settingsTheme),
                      trailing: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: ThemeMode.system, label: Text(l.systemDefault)),
                          ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight)),
                          ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark)),
                        ],
                        selected: {s.themeMode},
                        onSelectionChanged: (v) => update(s.copyWith(themeMode: v.first)),
                      ),
                    ),
                    ListTile(
                      title: Text(l.settingsLanguage),
                      trailing: SegmentedButton<AppLanguage>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: AppLanguage.system, label: Text(l.systemDefault)),
                          ButtonSegment(value: AppLanguage.zh, label: Text(l.languageZh)),
                          ButtonSegment(value: AppLanguage.en, label: Text(l.languageEn)),
                        ],
                        selected: {s.language},
                        onSelectionChanged: (v) => update(s.copyWith(language: v.first)),
                      ),
                    ),
                    const BackgroundPicker(),
                  ]),
                  _Section(l.sectionRefresh, [
                    ListTile(
                      title: Text(l.autoRefreshInterval),
                      subtitle: Text(l.autoRefreshIntervalHint),
                      trailing: DropdownButton<int>(
                        value: s.refreshMinutes,
                        underline: const SizedBox.shrink(),
                        items: const [1, 2, 5, 10, 15, 30, 60]
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(l.refreshMinutes(m))),
                            )
                            .toList(),
                        onChanged: (v) => update(s.copyWith(refreshMinutes: v)),
                      ),
                    ),
                  ]),
                  _Section(l.sectionNotifications, [
                    SwitchListTile(
                      title: Text(l.lowQuotaAlerts),
                      value: s.notificationsEnabled,
                      onChanged: (v) => update(s.copyWith(notificationsEnabled: v)),
                    ),
                    ListTile(
                      enabled: s.notificationsEnabled,
                      title: Text(l.alertThresholds),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final t in const [50, 30, 20, 10, 5])
                              FilterChip(
                                label: Text('$t%'),
                                selected: s.thresholds.contains(t),
                                onSelected: !s.notificationsEnabled
                                    ? null
                                    : (on) {
                                        final next = {...s.thresholds};
                                        on ? next.add(t) : next.remove(t);
                                        update(s.copyWith(thresholds: next.toList()..sort()));
                                      },
                              ),
                          ],
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(l.resetAlerts),
                      subtitle: Text(l.resetAlertsHint),
                      value: s.notifyOnReset,
                      onChanged: s.notificationsEnabled
                          ? (v) => update(s.copyWith(notifyOnReset: v))
                          : null,
                    ),
                  ]),
                  const _SyncSection(),
                  if (isDesktopPlatform)
                    _Section(l.sectionDataSources, [
                      SwitchListTile(
                        title: Text(l.allowCliFallback),
                        subtitle: Text(l.allowCliFallbackHint),
                        value: s.allowCliFallback,
                        onChanged: (v) => update(s.copyWith(allowCliFallback: v)),
                      ),
                      SwitchListTile(
                        title: Text(l.allowClaudeRefresh),
                        subtitle: Text(l.allowClaudeRefreshHint),
                        value: s.allowClaudeRefresh,
                        onChanged: (v) => update(s.copyWith(allowClaudeRefresh: v)),
                      ),
                    ]),
                  if (isDesktopPlatform)
                    _Section(l.sectionDesktop, [
                      SwitchListTile(
                        title: Text(l.launchAtStartup),
                        value: s.launchAtStartup,
                        onChanged: (v) => update(s.copyWith(launchAtStartup: v)),
                      ),
                      SwitchListTile(
                        title: Text(l.minimizeToTray),
                        value: s.minimizeToTray,
                        onChanged: (v) => update(s.copyWith(minimizeToTray: v)),
                      ),
                      if (defaultTargetPlatform == TargetPlatform.macOS)
                        SwitchListTile(
                          title: Text(l.hideDockIcon),
                          subtitle: Text(l.hideDockIconHint),
                          value: s.hideDockIcon,
                          onChanged: (v) => update(s.copyWith(hideDockIcon: v)),
                        ),
                      ListTile(
                        title: Text(l.trayDisplay),
                        subtitle: Text(l.trayDisplayHint),
                        trailing: DropdownButton<String>(
                          // A removed account falls back to "auto".
                          value: c.accounts.any((a) => a.id == s.trayAccountId)
                              ? s.trayAccountId
                              : '',
                          underline: const SizedBox.shrink(),
                          items: [
                            DropdownMenuItem(value: '', child: Text(l.trayDisplayAuto)),
                            for (final a in c.accounts)
                              DropdownMenuItem(value: a.id, child: Text(a.label)),
                          ],
                          onChanged: (v) => update(s.copyWith(trayAccountId: v ?? '')),
                        ),
                      ),
                    ]),
                  const _AboutSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Version, update check and project links.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  static String _status(AppLocalizations l, UpdateController u) => switch (u.status) {
    UpdateStatus.idle => '',
    UpdateStatus.checking => l.updateChecking,
    UpdateStatus.upToDate => l.upToDate,
    UpdateStatus.available => l.newVersionAvailable(u.release?.tag ?? ''),
    UpdateStatus.error => switch (u.errorCode) {
      'rate_limit' => l.checkFailedRateLimit,
      'network' => l.checkFailedNetwork,
      _ => l.checkFailedFormat,
    },
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<AppController>();
    final u = context.watch<UpdateController>();
    final theme = Theme.of(context);
    final status = _status(l, u);
    final available = u.status == UpdateStatus.available && u.release != null;
    final version = u.currentVersion.isEmpty ? '' : ' ${u.currentVersion}';
    return _Section(l.sectionAbout, [
      ListTile(
        title: Text('TokenBar$version'),
        subtitle: status.isEmpty
            ? null
            : Text(
                status,
                style: TextStyle(
                  color: u.status == UpdateStatus.error
                      ? theme.colorScheme.error
                      : available
                      ? theme.colorScheme.primary
                      : null,
                ),
              ),
        trailing: available
            ? GlassButton(
                kind: GlassButtonKind.primary,
                compact: true,
                onPressed: () => showUpdateDialog(context, u, u.release!),
                label: l.viewUpdate,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (u.status == UpdateStatus.checking) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: Sp.x2),
                  ],
                  GlassButton(
                    compact: true,
                    onPressed: u.status == UpdateStatus.checking
                        ? null
                        : () => u.check(manual: true),
                    label: l.checkForUpdates,
                  ),
                ],
              ),
      ),
      SwitchListTile(
        title: Text(l.autoCheckUpdates),
        subtitle: Text(l.autoCheckUpdatesHint),
        value: c.settings.autoCheckUpdates,
        onChanged: (v) => c.updateSettings(c.settings.copyWith(autoCheckUpdates: v)),
      ),
      ListTile(
        title: Text(l.projectHome),
        subtitle: const Text('github.com/$kUpdateRepo'),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => openReleasePage(kRepoUrl),
      ),
      ListTile(subtitle: Text(l.aboutBlurb)),
    ]);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title),
          GlassCard(child: Column(children: children)),
        ],
      ),
    );
  }
}

class _SyncSection extends StatefulWidget {
  const _SyncSection();

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _device;
  String? _testResult;
  bool _testOk = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppController>().settings;
    _url = TextEditingController(text: s.serverUrl);
    _token = TextEditingController(text: s.serverToken);
    _device = TextEditingController(text: s.deviceName);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _device.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = context.read<AppController>();
    await c.updateSettings(
      c.settings.copyWith(
        serverUrl: _url.text.trim(),
        serverToken: _token.text.trim(),
        deviceName: _device.text.trim(),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).savedSyncSettings)));
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final error = await context.read<AppController>().testServer(_url.text, _token.text);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _testing = false;
      _testOk = error == null;
      _testResult = error == null ? l.connectionOk : l.connectionFailed(error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.watch<AppController>();
    final s = c.settings;
    final theme = Theme.of(context);
    final modes = kIsWeb
        ? [SyncMode.server]
        : isDesktopPlatform
        ? SyncMode.values
        : [SyncMode.local, SyncMode.server];
    final content = <Widget>[
      if (modes.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SegmentedButton<SyncMode>(
            showSelectedIcon: false,
            segments: [for (final m in modes) ButtonSegment(value: m, label: Text(m.label(l)))],
            selected: {s.syncMode},
            onSelectionChanged: (v) => c.updateSettings(s.copyWith(syncMode: v.first)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(switch (s.syncMode) {
          SyncMode.local => l.syncDescLocal,
          SyncMode.server => kIsWeb ? l.syncDescServerWeb : l.syncDescServerDesktop,
          SyncMode.localPush => l.syncDescPush,
        }, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
      if (s.syncMode.usesServer)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _url,
                decoration: InputDecoration(
                  labelText: l.serverUrl,
                  hintText: 'https://tokenbar.example.com',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _token,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l.accessToken,
                  helperText: s.syncMode == SyncMode.localPush
                      ? l.tokenHelperPush
                      : l.tokenHelperRead,
                ),
              ),
              if (s.syncMode == SyncMode.localPush) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _device,
                  decoration: InputDecoration(labelText: l.deviceName, hintText: l.deviceNameHint),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  GlassButton(kind: GlassButtonKind.primary, onPressed: _save, label: l.save),
                  const SizedBox(width: 8),
                  GlassButton(onPressed: _testing ? null : _test, label: l.testConnection),
                  const SizedBox(width: 12),
                  if (_testing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (_testResult != null)
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _testOk ? theme.colorScheme.primary : theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
    ];
    if (kIsWeb) return _Section(l.sectionServer, content);
    return _Section(l.sectionSyncOptional, [
      ExpansionTile(
        initiallyExpanded: s.syncMode.usesServer,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(s.syncMode.usesServer ? l.syncEnabled(s.syncMode.label(l)) : l.syncDisabled),
        subtitle: Text(
          l.syncOptionalHint,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        children: content,
      ),
    ]);
  }
}
