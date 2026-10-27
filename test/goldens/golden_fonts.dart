import 'dart:io';

import 'package:flutter/services.dart';

/// Registers the real Roboto and Material Icons faces for golden tests.
///
/// `flutter test` runs with `--disable-asset-fonts`, so every glyph falls back
/// to the box-drawing test font unless a face is registered by hand. Loading
/// the SDK's own copies here makes the captured PNGs readable: the PNGs are
/// acceptance artifacts a reviewer compares against the watch, and boxes would
/// make them worthless.
///
/// Call this from `setUpAll` of a golden test file only. The test runner
/// isolates each file, so no other test pays for the extra font bytes and no
/// `flutter_test_config.dart` is needed.
Future<void> loadGoldenFonts() async {
  final directory = Directory(
    '${_flutterRoot()}/bin/cache/artifacts/material_fonts',
  );

  if (!directory.existsSync()) {
    throw StateError(
      'Golden fonts are missing: ${directory.path} does not exist. '
      'Set FLUTTER_ROOT to the Flutter SDK that runs these tests.',
    );
  }

  Future<ByteData> read(String fileName) async {
    final file = File('${directory.path}/$fileName');
    if (!file.existsSync()) {
      throw StateError('Golden font is missing: ${file.path}');
    }
    return ByteData.sublistView(await file.readAsBytes());
  }

  // One family with three weights: Roboto is the family the Material text
  // theme asks for, and the engine picks the closest weight per style
  // (regular for body text, medium for labels, bold for the header pill).
  final roboto = FontLoader('Roboto')
    ..addFont(read('Roboto-Regular.ttf'))
    ..addFont(read('Roboto-Medium.ttf'))
    ..addFont(read('Roboto-Bold.ttf'));
  await roboto.load();

  // The test shell's ambient text style asks for `monospace`, which is not
  // installed, so text that inherits it (anything without an explicit family)
  // falls back to the box font. Registering the same Roboto bytes under that
  // name renders it the way the watch does. Nothing in `lib/` changes.
  final shellDefault = FontLoader('monospace')
    ..addFont(read('Roboto-Regular.ttf'))
    ..addFont(read('Roboto-Medium.ttf'))
    ..addFont(read('Roboto-Bold.ttf'));
  await shellDefault.load();

  // Without this every Icon paints as an empty box.
  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

/// The Flutter SDK root, from the environment `flutter test` sets, or derived
/// from the running Dart executable (`…/bin/cache/dart-sdk/bin/dart`).
String _flutterRoot() {
  final fromEnvironment = Platform.environment['FLUTTER_ROOT'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }

  // dart -> bin -> dart-sdk -> cache -> bin -> <flutter root>: five levels.
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 4; level++) {
    directory = directory.parent;
  }

  final derived = directory.path;
  final looksLikeSdk = Directory('$derived/bin/cache/artifacts/material_fonts')
      .existsSync();
  if (!looksLikeSdk) {
    throw StateError(
      'Could not locate the Flutter SDK fonts: FLUTTER_ROOT is unset and '
      '$derived does not look like a Flutter SDK. Export FLUTTER_ROOT or run '
      'through `fvm flutter test`.',
    );
  }
  return derived;
}
