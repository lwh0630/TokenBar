import 'dart:async';

import 'process_types.dart';

export 'process_types.dart';

const bool localAccessSupported = false;
const bool isMacOS = false;
const bool isWindows = false;
const String pathSeparator = '/';

String? envVar(String name) => null;

String? homeDirectory() => null;

String joinPath(String a, String b, [String? c, String? d]) =>
    [a, b, c, d].whereType<String>().join('/');

Future<String?> readTextFile(String path) async => null;

Future<DateTime?> fileModified(String path) async => null;

Future<List<LocalFileEntry>> listDirectory(String path) async => const [];

Stream<String> readLines(String path) => const Stream.empty();

/// No isolates on the web: runs [task] on the current one.
Future<T> runInBackground<T>(FutureOr<T> Function() task) async => task();

Future<void> writeTextFileAtomic(String path, String contents) async {
  throw UnsupportedError('File access is not available on this platform');
}

Future<String?> readSqliteText(
  String dbPath,
  String sql, [
  List<Object?> params = const [],
]) async => null;

Future<String?> findExecutable(String name) async => null;

Future<ProcessOutput?> runProcess(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 10),
}) async => null;

Future<JsonRpcSession> startJsonRpcProcess(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  throw UnsupportedError('Processes are not available on this platform');
}
