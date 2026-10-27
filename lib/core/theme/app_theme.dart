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
      // M3's default (inversePrimary, #6750A4) is only 2.87:1 on kWearSurface.
      actionTextColor: kWearAccent,
      // A floating bar at the bottom edge of a round display would have its
      // corners clipped by the circle's chord without this inset.
      insetPadding: EdgeInsets.fromLTRB(20, 5, 20, 52),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: kWearAccent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kWearAccent,
    ),
    // An explicit transition for every platform keeps route pushes on a fade
    // over the OLED-black backdrop instead of the platform default. Android's
    // ZoomPageTransitionsBuilder snapshots the entering route, and that
    // snapshot renders a blank (white) frame behind the hero flight on the
    // watch. Fading over kWearBackground keeps every frame dark.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(
          backgroundColor: kWearBackground,
        ),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(
          backgroundColor: kWearBackground,
        ),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(
          backgroundColor: kWearBackground,
        ),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(
          backgroundColor: kWearBackground,
        ),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(
          backgroundColor: kWearBackground,
        ),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(
          backgroundColor: kWearBackground,
        ),
      },
    ),
  );
}
