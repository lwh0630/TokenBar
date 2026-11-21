import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:tokenbar_core/tokenbar_core.dart';
import 'package:tokenbar_server/tokenbar_server.dart';

final _usageText =
    '''
TokenBar - AI quota monitor

Usage:
  tokenbar usage   [--provider ID] [--home DIR] [--accounts FILE] [--json]
  tokenbar collect --server URL --token TOKEN [--accounts FILE] [--interval 5m] [--once]
  tokenbar serve   [--port 8787] [--data DIR] [--web DIR] [--token T] [--read-token R]
                   [--collect FILE|local] [--interval 5m]

Providers (--provider):
${_wrap(ProviderRegistry.instance.all.map((p) => p.id).join(' '))}

Environment: TOKENBAR_TOKEN, TOKENBAR_READ_TOKEN, TOKENBAR_DATA, TOKENBAR_WEB, PORT
''';

String _wrap(String words, {int width = 76}) {
  final lines = <String>[];
  var line = StringBuffer('  ');
  for (final w in words.split(' ')) {
    if (line.length + w.length > width) {
      lines.add(line.toString().trimRight());
      line = StringBuffer('  ');
    }
    line.write('$w ');
  }
  lines.add(line.toString().trimRight());
  return lines.join('\n');
}

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addCommand(
      'usage',
      _commonFetchOptions(ArgParser())
        ..addOption('provider', abbr: 'p')
        ..addOption('home', help: 'CODEX_HOME / CLAUDE_CONFIG_DIR override')
        ..addFlag('json', negatable: false),
    )
    ..addCommand(
      'collect',
      _commonFetchOptions(ArgParser())
        ..addOption('server', mandatory: true)
        ..addOption('token', defaultsTo: Platform.environment['TOKENBAR_TOKEN'])
        ..addOption('interval', defaultsTo: '5m')
        ..addOption('origin')
        ..addFlag('once', negatable: false),
    )
    ..addCommand(
      'serve',
      _commonFetchOptions(ArgParser())
        ..addOption('port', defaultsTo: Platform.environment['PORT'] ?? '8787')
        ..addOption('host', defaultsTo: '0.0.0.0')
        ..addOption('data', defaultsTo: Platform.environment['TOKENBAR_DATA'] ?? 'data')
        ..addOption('web', defaultsTo: Platform.environment['TOKENBAR_WEB'])
        ..addOption('token', defaultsTo: Platform.environment['TOKENBAR_TOKEN'])
        ..addOption('read-token', defaultsTo: Platform.environment['TOKENBAR_READ_TOKEN'])
        ..addOption('collect', help: 'Accounts file, or "local" for this machine\'s CLI logins')
        ..addOption('interval', defaultsTo: '5m')
        ..addFlag('insecure-no-auth', negatable: false),
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.write(_usageText);
    exit(64);
  }
  final command = results.command;
  if (results['help'] as bool || command == null) {
    stdout.write(_usageText);
    return;
  }

  switch (command.name) {
    case 'usage':
      await _usage(command);
    case 'collect':
      await _collect(command);
    case 'serve':
      await _serve(command);
  }
}

ArgParser _commonFetchOptions(ArgParser p) => p
  ..addOption('accounts', help: 'JSON file with account configs')
  ..addFlag(
    'allow-claude-refresh',
    negatable: false,
    help: 'Refresh expired Claude tokens and write them back (rotates refresh token)',
  )
  ..addFlag('no-cli', negatable: false, help: 'Never launch provider CLIs')
  ..addFlag(
    'no-browser-cookies',
    negatable: false,
    help: 'Never read browser cookies (Xiaomi MiMo, Cursor, Gemini)',
  );

FetchContext _ctx(ArgResults r) => FetchContext(
  allowClaudeTokenRefresh: r['allow-claude-refresh'] as bool,
  allowCliFallback: !(r['no-cli'] as bool),
  browserCookies: (r['no-browser-cookies'] as bool) ? null : const BrowserCookieEnvironment(),
  userAgent: 'TokenBar/0.1',
);

Future<void> _usage(ArgResults r) async {
  var accounts = await loadAccounts(r['accounts'] as String?);
  final provider = r['provider'] as String?;
  if (provider != null) {
    accounts = accounts.where((a) => a.providerId == provider).toList();
    if (accounts.isEmpty) {
      final p = ProviderRegistry.instance.byId(provider);
      if (p == null) {
        stderr.writeln('Unknown provider "$provider"');
        exit(64);
      }
      accounts = [
        AccountConfig(
          id: '$provider@${hostName()}',
          providerId: provider,
          label: provider,
          sourceType: p.supportedSources.contains(SourceType.localCli)
              ? SourceType.localCli
              : SourceType.apiKey,
        ),
      ];
    }
  }
  final home = r['home'] as String?;
  if (home != null) accounts = accounts.map((a) => a.copyWith(homeDir: home)).toList();

  final snapshots = await collectOnce(accounts, _ctx(r));
  if (r['json'] as bool) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(snapshots.map((s) => s.toJson()).toList()),
    );
  } else {
    final now = DateTime.now();
    for (final s in snapshots) {
      stdout.writeln(renderSnapshot(s, now));
    }
  }
  exit(snapshots.every((s) => s.hasError) ? 1 : 0);
}

Future<void> _collect(ArgResults r) async {
  final token = r['token'] as String?;
  if (token == null || token.isEmpty) {
    stderr.writeln('Missing --token (or TOKENBAR_TOKEN)');
    exit(64);
  }
  final accounts = await loadAccounts(r['accounts'] as String?);
  final client = TokenBarApiClient(baseUrl: r['server'] as String, token: token);
  final origin = (r['origin'] as String?) ?? hostName();
  final interval = parseInterval(r['interval'] as String);

  Future<void> tick() async {
    final snapshots = await collectOnce(accounts, _ctx(r), origin: origin);
    try {
      await client.push(snapshots, origin: origin);
      final ok = snapshots.where((s) => !s.hasError).length;
      stdout.writeln(
        '[${DateTime.now().toIso8601String()}] pushed ${snapshots.length} snapshots ($ok ok)',
      );
    } catch (e) {
      stderr.writeln('[${DateTime.now().toIso8601String()}] push failed: $e');
    }
  }

  await tick();
  if (r['once'] as bool) {
    client.close();
    return;
  }
  Timer.periodic(interval, (_) => tick());
}

Future<void> _serve(ArgResults r) async {
  final token = r['token'] as String?;
  final noAuth = r['insecure-no-auth'] as bool;
  if ((token == null || token.isEmpty) && !noAuth) {
    stderr.writeln(
      'Refusing to start without --token / TOKENBAR_TOKEN (use --insecure-no-auth for local testing).',
    );
    exit(64);
  }
  final store = SnapshotStore(r['data'] as String);
  final config = ServerConfig(
    adminToken: (token == null || token.isEmpty) ? null : token,
    readToken: r['read-token'] as String?,
    webDir: r['web'] as String?,
    allowNoAuth: noAuth,
  );
  final handler = buildHandler(store, config);
  final server = await shelf_io.serve(handler, r['host'] as String, int.parse(r['port'] as String));
  stdout.writeln('TokenBar server listening on http://${server.address.host}:${server.port}');
  if (config.webDir != null) stdout.writeln('Serving web UI from ${config.webDir}');

  final collect = r['collect'] as String?;
  if (collect != null) {
    final accounts = collect == 'local'
        ? await defaultLocalAccounts()
        : await loadAccounts(collect);
    final interval = parseInterval(r['interval'] as String);
    Future<void> tick() async {
      final snapshots = await collectOnce(accounts, _ctx(r), origin: '${hostName()} (server)');
      await store.put(snapshots);
    }

    unawaited(tick());
    Timer.periodic(interval, (_) => tick());
    stdout.writeln(
      'Server-side collection enabled for ${accounts.length} account(s) every ${r['interval']}',
    );
  }
}
