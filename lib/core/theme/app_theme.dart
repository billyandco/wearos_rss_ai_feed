import 'package:flutter/material.dart';

/// True black for OLED panels: unlit pixels save power on the Pixel Watch.
const Color kWearBackground = Color(0xFF000000);
const Color kWearSurface = Color(0xFF101418);
const Color kWearAccent = Color(0xFF6EE7C8);
const Color kWearMuted = Color(0xFF9AA4AE);
const Color kWearError = Color(0xFFFF8A80);

ThemeData buildWearTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final colorScheme = base.colorScheme.copyWith(
    primary: kWearAccent,
    onPrimary: Colors.black,
    secondary: kWearAccent,
    surface: kWearBackground,
    onSurface: Colors.white,
    surfaceContainerHighest: kWearSurface,
    error: kWearError,
    onError: Colors.black,
  );

  return base.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kWearBackground,
    canvasColor: kWearBackground,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.copyWith(
      titleSmall: const TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      bodySmall: const TextStyle(fontSize: 12, height: 1.25, color: kWearMuted),
      labelSmall: const TextStyle(
        fontSize: 11,
        height: 1.2,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w500,
        color: kWearMuted,
      ),
      headlineSmall: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kWearSurface,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: kWearAccent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kWearAccent,
    ),
  );
}
