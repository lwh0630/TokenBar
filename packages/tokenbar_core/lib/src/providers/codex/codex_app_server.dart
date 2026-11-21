import 'dart:async';

import '../../platform/platform.dart' as platform;
import '../../util/json_utils.dart';
import 'codex_credentials.dart';

class CodexCliNotFound implements Exception {
  const CodexCliNotFound();
}

String? _cachedCodexExecutable;

/// PATH first (cached by the platform layer), then the places a GUI-launched app
/// cannot see through its own PATH: the Windows desktop app bundle and the usual
/// user-level install directories on macOS / Linux. A hit is remembered.
Future<String?> _codexExecutable() async {
  final cached = _cachedCodexExecutable;
  if (cached != null && await platform.fileModified(cached) != null) return cached;
  final found =
      await platform.findExecutable('codex') ??
      (platform.isWindows ? await _windowsBundledCodex() : await _unixInstalledCodex());
  return _cachedCodexExecutable = found;
}

Future<String?> _unixInstalledCodex() async {
  final home = platform.envVar('HOME');
  for (final path in [
    '/opt/homebrew/bin/codex',
    '/usr/local/bin/codex',
    '/usr/bin/codex',
    if (home != null) ...[
      platform.joinPath(home, '.local/bin/codex'),
      platform.joinPath(home, '.npm-global/bin/codex'),
      platform.joinPath(home, '.bun/bin/codex'),
      platform.joinPath(home, '.volta/bin/codex'),
    ],
  ]) {
    if (await platform.fileModified(path) != null) return path;
  }
  return null;
}

/// The Windows desktop app includes the official CLI, even without a PATH entry.
Future<String?> _windowsBundledCodex() async {
  if (platform.isWindows) {
    final systemRoot = platform.envVar('SystemRoot');
    if (systemRoot != null) {
      final powershell = platform.joinPath(
        systemRoot,
        r'System32\WindowsPowerShell\v1.0\powershell.exe',
      );
      final result = await platform.runProcess(powershell, [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
[Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$locations = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty InstallLocation
if ($locations) {
  $locations
} else {
  # Some desktop processes cannot query AppX deployment services.
  Get-ChildItem -LiteralPath 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -like 'OpenAI.Codex_*' } |
    ForEach-Object { $_.GetValue('PackageRootFolder') }
}
''',
      ]);
      if (result?.exitCode == 0) {
        for (final line in result!.stdout.split('\n')) {
          final installLocation = line.trim();
          if (installLocation.isEmpty) continue;
          final bundled = platform.joinPath(installLocation, r'app\resources\codex.exe');
          if (await platform.fileModified(bundled) != null) return bundled;
        }
      }
    }
  }
  return null;
}

/// Opens the official CLI protocol in one account's home. Interactive account
/// actions use the ChatGPT service and the same file-backed login TokenBar reads.
Future<platform.JsonRpcSession> openCodexAppServer(
  String home, {
  bool officialAccount = false,
}) async {
  final executable = await _codexExecutable();
  if (executable == null) throw const CodexCliNotFound();
  final session = await platform.startJsonRpcProcess(
    executable,
    [
      '-s',
      'read-only',
      '-a',
      'never',
      'app-server',
      if (officialAccount) ...[
        '-c',
        "cli_auth_credentials_store='file'",
        '-c',
        "chatgpt_base_url='$defaultChatGptBaseUrl'",
      ],
    ],
    environment: {'CODEX_HOME': home},
  );
  try {
    await session.request(
      'initialize',
      params: {
        'clientInfo': {'name': 'tokenbar', 'version': '0.1.0'},
      },
      timeout: const Duration(seconds: 15),
    );
    session.notify('initialized');
    return session;
  } catch (_) {
    await session.close();
    rethrow;
  }
}

/// Lets Codex own the OAuth callback and tokens. Only the browser URL is given
/// to the caller, and completion is matched to this server's login ID.
Future<void> signInToCodex(
  platform.JsonRpcSession session,
  Future<void> Function(Uri) openBrowser, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  String? loginId;
  var succeeded = false;
  final early = <String, bool>{};
  final completed = Completer<bool>();
  final messages = session.notifications.listen(
    (notification) {
      if (notification.method != 'account/login/completed' || completed.isCompleted) return;
      final params = asMap(notification.params);
      final id = asString(params?['loginId']);
      if (id == null) return;
      final success = params?['success'] == true;
      if (loginId == null) {
        early[id] = success;
      } else if (id == loginId) {
        completed.complete(success);
      }
    },
    onDone: () {
      if (!completed.isCompleted) completed.complete(false);
    },
  );
  try {
    final response = asMap(
      await session.request(
        'account/login/start',
        params: {'type': 'chatgpt'},
        timeout: const Duration(seconds: 15),
      ),
    );
    loginId = asString(response?['loginId']);
    final link = Uri.tryParse(asString(response?['authUrl']) ?? '');
    if (response?['type'] != 'chatgpt' ||
        loginId == null ||
        link == null ||
        link.scheme != 'https' ||
        link.host != 'auth.openai.com' ||
        link.port != 443 ||
        link.userInfo.isNotEmpty) {
      throw const FormatException('Invalid Codex sign-in response');
    }
    final earlyResult = early[loginId];
    if (earlyResult != null && !completed.isCompleted) completed.complete(earlyResult);
    if (!completed.isCompleted) await openBrowser(link);
    if (!await completed.future.timeout(timeout)) {
      throw platform.JsonRpcException('Codex sign-in did not complete');
    }
    succeeded = true;
  } finally {
    await messages.cancel();
    if (!succeeded && loginId != null) {
      try {
        await session.request(
          'account/login/cancel',
          params: {'loginId': loginId},
          timeout: const Duration(seconds: 2),
        );
      } catch (_) {
        // The owner also closes the app-server process on dismissal.
      }
    }
  }
}
