import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'process_types.dart';

export 'process_types.dart';

const bool localAccessSupported = true;
final bool isMacOS = Platform.isMacOS;
final bool isWindows = Platform.isWindows;
final String pathSeparator = Platform.pathSeparator;

String? envVar(String name) {
  final value = Platform.environment[name]?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

String? homeDirectory() => envVar('HOME') ?? envVar('USERPROFILE') ?? _windowsHomeFromDrive();

String? _windowsHomeFromDrive() {
  final drive = envVar('HOMEDRIVE');
  final path = envVar('HOMEPATH');
  return (drive != null && path != null) ? '$drive$path' : null;
}

String joinPath(String a, String b, [String? c, String? d]) {
  final parts = [a, b, c, d].whereType<String>().toList();
  final buffer = StringBuffer(parts.first);
  for (final part in parts.skip(1)) {
    final current = buffer.toString();
    if (!current.endsWith('/') && !current.endsWith('\\')) {
      buffer.write(Platform.pathSeparator);
    }
    buffer.write(part);
  }
  return buffer.toString();
}

Future<String?> readTextFile(String path) async {
  final file = File(path);
  try {
    if (!await file.exists()) return null;
    return await file.readAsString();
  } on FileSystemException {
    return null;
  }
}

Future<DateTime?> fileModified(String path) async {
  try {
    final stat = await File(path).stat();
    return stat.type == FileSystemEntityType.notFound ? null : stat.modified;
  } on FileSystemException {
    return null;
  }
}

/// Lists the direct children of [path] (read-only; symlinks are not followed). Files get
/// their modification time and size. Returns an empty list when the directory is missing
/// or unreadable.
Future<List<LocalFileEntry>> listDirectory(String path) async {
  final entries = <LocalFileEntry>[];
  try {
    final dir = Directory(path);
    if (!await dir.exists()) return entries;
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? entity.path;
      if (entity is Directory) {
        entries.add(LocalFileEntry(path: entity.path, name: name, isDirectory: true));
      } else if (entity is File) {
        try {
          final stat = await entity.stat();
          entries.add(
            LocalFileEntry(
              path: entity.path,
              name: name,
              isDirectory: false,
              modified: stat.modified,
              size: stat.size,
            ),
          );
        } on FileSystemException {
          continue;
        }
      }
    }
  } on FileSystemException {
    return entries;
  }
  return entries;
}

/// Streams the lines of a text file without loading it into memory (read-only). Invalid
/// UTF-8 is replaced instead of failing; a missing file yields an error on the stream.
Stream<String> readLines(String path) =>
    File(path)
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());

/// Runs [task] on a short-lived background isolate so heavy parsing (session logs can be
/// many megabytes) never blocks the UI thread. [task] and its result must be sendable: only
/// capture plain values (strings, dates), never `this` of an object holding a client or
/// controller.
Future<T> runInBackground<T>(FutureOr<T> Function() task) => Isolate.run(task);

Future<void> writeTextFileAtomic(String path, String contents) async {
  final target = File(path);
  await target.parent.create(recursive: true);
  final temp = File('$path.tokenbar.tmp');
  await temp.writeAsString(contents, flush: true);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['600', temp.path]);
  }
  await temp.rename(target.path);
}

/// Reads the first column of the first row from a SQLite database opened
/// read-only (safe while the owning app has it open). Returns null when the
/// file or row is missing.
Future<String?> readSqliteText(String dbPath, String sql, [List<Object?> params = const []]) async {
  if (!await File(dbPath).exists()) return null;
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final rows = db.select(sql, params);
    if (rows.isEmpty) return null;
    return switch (rows.first.values.first) {
      final String s => s,
      final List<int> bytes => _decodeBlobText(bytes),
      _ => null,
    };
  } on SqliteException {
    return null;
  } finally {
    db.close();
  }
}

/// VS Code-style state DBs may store text as UTF-8 or BOM-less UTF-16LE.
String _decodeBlobText(List<int> bytes) {
  final looksUtf16 = bytes.length >= 4 && bytes.length.isEven && bytes[1] == 0 && bytes[3] == 0;
  if (looksUtf16) {
    return String.fromCharCodes([
      for (var i = 0; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
    ]);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

final Map<String, String?> _executableCache = {};

Future<String?> findExecutable(String name) async {
  if (_executableCache.containsKey(name)) return _executableCache[name];
  String? found;
  try {
    final result = Platform.isWindows
        ? await Process.run('where.exe', [name])
        : await Process.run('/bin/sh', ['-lc', 'command -v $name']);
    if (result.exitCode == 0) {
      final lines = (result.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (Platform.isWindows) {
        // `where` lists extensionless npm shims first; they are not runnable.
        found = lines.firstWhere(
          (l) => RegExp(r'\.(exe|cmd|bat)$', caseSensitive: false).hasMatch(l),
          orElse: () => lines.isEmpty ? '' : lines.first,
        );
        if (found.isEmpty) found = null;
      } else {
        found = lines.isEmpty ? null : lines.first;
      }
    }
  } on ProcessException {
    found = null;
  }
  _executableCache[name] = found;
  return found;
}

bool _needsShell(String executable) =>
    Platform.isWindows && RegExp(r'\.(cmd|bat)$', caseSensitive: false).hasMatch(executable);

Future<ProcessOutput?> runProcess(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      runInShell: _needsShell(executable),
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    return ProcessOutput(exitCode, await stdoutFuture, await stderrFuture);
  } on ProcessException {
    return null;
  }
}

Future<JsonRpcSession> startJsonRpcProcess(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    args,
    environment: environment,
    runInShell: _needsShell(executable),
  );
  return _IoJsonRpcSession(process);
}

class _IoJsonRpcSession implements JsonRpcSession {
  _IoJsonRpcSession(this._process) {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone);
    _process.stderr.drain<void>();
  }

  final Process _process;
  late final StreamSubscription<String> _stdoutSub;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 1;
  bool _closed = false;

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (message is! Map) return;
    final id = message['id'];
    if (id is! num) return;
    final completer = _pending.remove(id.toInt());
    if (completer == null) return;
    final error = message['error'];
    if (error is Map) {
      completer.completeError(JsonRpcException(error['message']?.toString() ?? 'RPC error'));
    } else {
      completer.complete(message['result']);
    }
  }

  void _onDone() {
    for (final completer in _pending.values) {
      completer.completeError(JsonRpcException('process closed stdout'));
    }
    _pending.clear();
  }

  void _send(Map<String, Object?> payload) {
    if (_closed) throw JsonRpcException('session closed');
    _process.stdin.writeln(jsonEncode(payload));
  }

  @override
  Future<Object?> request(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 5),
  }) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send({'id': id, 'method': method, 'params': params ?? <String, Object?>{}});
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw JsonRpcException('timed out waiting for $method');
      },
    );
  }

  @override
  void notify(String method, {Object? params}) =>
      _send({'method': method, 'params': params ?? <String, Object?>{}});

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _process.stdin.close();
    } catch (_) {}
    final exited = await _process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
    if (exited == -1) _process.kill(ProcessSignal.sigkill);
    await _stdoutSub.cancel();
  }
}
