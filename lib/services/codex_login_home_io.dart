import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<({String path, Future<void> Function() discard})> createCodexLoginHome() async {
  final support = await getApplicationSupportDirectory();
  final logins = await Directory.fromUri(support.uri.resolve('codex-logins/'))
      .create(recursive: true);
  final home = await logins.createTemp('account-');
  return (
    path: home.path,
    discard: () async {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          if (await home.exists()) await home.delete(recursive: true);
          return;
        } on PathAccessException {
          if (attempt == 2) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    },
  );
}
