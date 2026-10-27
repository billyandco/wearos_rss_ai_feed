import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/theme/app_theme.dart';

/// WCAG 2.1 contrast ratio between two opaque colors.
double _contrastRatio(Color foreground, Color background) {
  final double foregroundLuminance = foreground.computeLuminance();
  final double backgroundLuminance = background.computeLuminance();
  final double lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final double darker = foregroundLuminance < backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final ThemeData theme = buildWearTheme();

  group('pageTransitionsTheme', () {
    test('registers a builder for every TargetPlatform', () {
      final Map<TargetPlatform, PageTransitionsBuilder> builders =
          theme.pageTransitionsTheme.builders;

      expect(
        builders.keys.toSet(),
        TargetPlatform.values.toSet(),
        reason:
            'every TargetPlatform must have an explicit builder, otherwise '
            'Pushing a route falls back to ZoomPageTransitionsBuilder, which '
            'snapshots the entering route and flashes a white frame behind '
            'the hero transition',
      );

      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(
          builders,
          contains(platform),
          reason: '$platform would silently use the default transition',
        );
      }
    });

    test('never leaves a platform without a concrete builder', () {
      final Map<TargetPlatform, PageTransitionsBuilder> builders =
          theme.pageTransitionsTheme.builders;

      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(
          builders[platform],
          isNotNull,
          reason: 'null builder for $platform',
        );
      }
      expect(builders, hasLength(TargetPlatform.values.length));
    });

    test(
      'Android uses a fade transition backed by the OLED black background',
      () {
        final PageTransitionsBuilder? builder =
            theme.pageTransitionsTheme.builders[TargetPlatform.android];

        expect(
          builder,
          isA<FadeForwardsPageTransitionsBuilder>().having(
            (FadeForwardsPageTransitionsBuilder b) => b.backgroundColor,
            'backgroundColor',
            kWearBackground,
          ),
          reason:
              'Android must fade the incoming article detail page over '
              'kWearBackground instead of snapshotting it (PredictiveBack / '
              'Zoom), which is what produces the white flash',
        );
      },
    );

    test('iOS uses a fade transition backed by the OLED black background', () {
      final PageTransitionsBuilder? builder =
          theme.pageTransitionsTheme.builders[TargetPlatform.iOS];

      expect(
        builder,
        isA<FadeForwardsPageTransitionsBuilder>().having(
          (FadeForwardsPageTransitionsBuilder b) => b.backgroundColor,
          'backgroundColor',
          kWearBackground,
        ),
        reason: 'iOS inherits the same black backdrop so no platform flashes',
      );
    });

    test('repeated calls keep the same transition configuration', () {
      final Map<TargetPlatform, PageTransitionsBuilder> first =
          buildWearTheme().pageTransitionsTheme.builders;
      final Map<TargetPlatform, PageTransitionsBuilder> second =
          buildWearTheme().pageTransitionsTheme.builders;

      expect(first.keys.toSet(), second.keys.toSet());
      for (final TargetPlatform platform in TargetPlatform.values) {
        final PageTransitionsBuilder? a = first[platform];
        final PageTransitionsBuilder? b = second[platform];
        expect(a.runtimeType, b.runtimeType, reason: '$platform type drift');
        if (a is FadeForwardsPageTransitionsBuilder &&
            b is FadeForwardsPageTransitionsBuilder) {
          expect(a.backgroundColor, b.backgroundColor, reason: '$platform');
        }
      }
    });
  });

  group('background surfaces', () {
    test('colorScheme.surface is the OLED black background', () {
      expect(
        theme.colorScheme.surface,
        kWearBackground,
        reason: 'the transition backdrop and first engine frame read surface',
      );
    });

    test('scaffoldBackgroundColor and canvasColor are OLED black', () {
      expect(theme.scaffoldBackgroundColor, kWearBackground);
      expect(
        theme.canvasColor,
        kWearBackground,
        reason: 'canvasColor paints the window behind the route stack',
      );
    });

    test('the theme stays dark', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });
  });

  group('foreground colors on black', () {
    test('onSurface is opaque white', () {
      expect(theme.colorScheme.onSurface, Colors.white);
      expect(
        theme.colorScheme.onSurface.a,
        1.0,
        reason: 'a translucent onSurface would dim against OLED black',
      );
    });

    test('onPrimary is opaque black', () {
      expect(theme.colorScheme.onPrimary, Colors.black);
      expect(theme.colorScheme.onPrimary.a, 1.0);
    });

    test('onSurface and onPrimary are readable against surface', () {
      expect(
        _contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface),
        greaterThanOrEqualTo(4.5),
        reason: 'WCAG AA for body text on the black background',
      );
      expect(
        _contrastRatio(theme.colorScheme.onPrimary, theme.colorScheme.primary),
        greaterThanOrEqualTo(4.5),
        reason: 'label text on the accent color must stay readable',
      );
    });
  });

  group('palette wiring', () {
    test('snackBarTheme uses the surface color', () {
      expect(theme.snackBarTheme.backgroundColor, kWearSurface);
      expect(
        theme.snackBarTheme.contentTextStyle?.color,
        Colors.white,
        reason: 'snack bar text must stay readable on kWearSurface',
      );
    });

    test('snackBarTheme action text uses the accent color', () {
      expect(
        theme.snackBarTheme.actionTextColor,
        kWearAccent,
        reason:
            'the M3 default inversePrimary (#6750A4) is only 2.87:1 on '
            'kWearSurface, so the UNDO label would be unreadable',
      );
    });

    test('the floating snack bar clears the round display chord', () {
      final EdgeInsets? insets = theme.snackBarTheme.insetPadding;
      expect(
        insets,
        isNotNull,
        reason: 'a floating bar needs explicit insets on a round screen',
      );
      expect(
        insets!.bottom,
        greaterThanOrEqualTo(44),
        reason:
            'at the bottom edge the circle is only a chord, so the corners of '
            'a floating bar would be clipped without a 44 dp inset',
      );
    });

    test('progressIndicatorTheme uses the accent color', () {
      expect(theme.progressIndicatorTheme.color, kWearAccent);
    });

    test('exposes the OLED palette constants', () {
      expect(kWearBackground, const Color(0xFF000000));
      expect(kWearSurface, const Color(0xFF101418));
      expect(kWearAccent, const Color(0xFF6EE7C8));
      expect(theme.colorScheme.primary, kWearAccent);
      expect(theme.colorScheme.surfaceContainerHighest, kWearSurface);
    });
  });
}
