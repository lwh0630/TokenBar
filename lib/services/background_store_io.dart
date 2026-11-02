import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

const bool backgroundImageSupported = true;

const _extensions = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};

Future<Directory> _folder() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}backgrounds');
  await dir.create(recursive: true);
  return dir;
}

/// Lets the user pick a picture and copies it into the app's own folder, so the
/// background keeps working if the original is moved or deleted (and on mobile,
/// where the picker hands out temporary cache files). Returns the stored path,
/// or null when the user cancelled. Each pick gets a fresh file name, so Flutter's
/// image cache never shows a stale picture; older stored pictures are removed.
Future<String?> pickBackgroundImage() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  final source = result?.files.single.path;
  if (source == null) return null;

  final dot = source.lastIndexOf('.');
  final ext = dot >= 0 ? source.substring(dot).toLowerCase() : '';
  final dir = await _folder();
  final target = File(
    '${dir.path}${Platform.pathSeparator}background_${DateTime.now().millisecondsSinceEpoch}'
    '${_extensions.contains(ext) ? ext : '.img'}',
  );
  await File(source).copy(target.path);
  await for (final entry in dir.list()) {
    if (entry is File && entry.path != target.path) {
      try {
        await entry.delete();
      } on FileSystemException {
        // Best effort: a stale picture is harmless.
      }
    }
  }
  return target.path;
}

/// Removes a stored picture (only ever files inside our own folder).
Future<void> deleteBackgroundImage(String path) async {
  if (path.isEmpty) return;
  try {
    final dir = await _folder();
    final file = File(path);
    if (file.parent.path == dir.path && await file.exists()) await file.delete();
  } on FileSystemException {
    // Nothing to clean up.
  }
}

/// Decoded at screen size at most, so a 40 MP photo does not sit in memory.
ImageProvider? backgroundImageProvider(String path) {
  if (path.isEmpty) return null;
  return ResizeImage(FileImage(File(path)), width: 2560, policy: ResizeImagePolicy.fit);
}
