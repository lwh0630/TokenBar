class ProcessOutput {
  const ProcessOutput(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// One entry of a directory listing (see `listDirectory`). [modified] and [size] are only
/// filled in for regular files.
class LocalFileEntry {
  const LocalFileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.modified,
    this.size,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final DateTime? modified;
  final int? size;
}

typedef JsonRpcNotification = ({String method, Object? params});

/// A line-delimited JSON-RPC session over a child process' stdio.
abstract class JsonRpcSession {
  Stream<JsonRpcNotification> get notifications;

  /// Sends a request and waits for the response with the same id.
  /// Returns the `result` object; throws [JsonRpcException] on `error`.
  Future<Object?> request(String method, {Object? params, Duration timeout});

  void notify(String method, {Object? params});

  Future<void> close();
}

class JsonRpcException implements Exception {
  JsonRpcException(this.message);

  final String message;

  @override
  String toString() => 'JsonRpcException: $message';
}
