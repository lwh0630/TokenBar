import 'package:flutter/painting.dart';

/// The web build has no local file system: custom background pictures are
/// unavailable there (gradient presets still work).
const bool backgroundImageSupported = false;

Future<String?> pickBackgroundImage() async => null;

Future<void> deleteBackgroundImage(String path) async {}

ImageProvider? backgroundImageProvider(String path) => null;
