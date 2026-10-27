import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/layout/round_geometry.dart';

void main() {
  const radius = 225.0; // Pixel Watch 1: 450 x 450 logical pixels
  const gutter = 12.0;

  test('a row through the centre only needs the minimum gutter', () {
    expect(
      roundHorizontalInset(
        distanceFromCenter: 0,
        radius: radius,
        minGutter: gutter,
      ),
      gutter,
    );
  });

  test('rows further from the centre are inset to stay inside the circle', () {
    final halfRadius = roundHorizontalInset(
      distanceFromCenter: radius / 2,
      radius: radius,
      minGutter: gutter,
    );

    expect(
      halfRadius,
      closeTo(radius - math.sqrt(3) / 2 * radius + gutter, 0.001),
    );
    expect(halfRadius, greaterThan(gutter));
  });

  test('the inset grows monotonically as rows approach the edge', () {
    final insets = [
      for (final fraction in [0.0, 0.25, 0.5, 0.75, 1.0])
        roundHorizontalInset(
          distanceFromCenter: radius * fraction,
          radius: radius,
          minGutter: gutter,
        ),
    ];

    for (var i = 1; i < insets.length; i++) {
      expect(insets[i], greaterThan(insets[i - 1]));
    }
  });

  test('clamps rows at or beyond the edge to the full radius', () {
    expect(
      roundHorizontalInset(
        distanceFromCenter: radius,
        radius: radius,
        minGutter: gutter,
      ),
      closeTo(radius, 0.001),
    );
    expect(
      roundHorizontalInset(
        distanceFromCenter: radius * 2,
        radius: radius,
        minGutter: gutter,
      ),
      closeTo(radius, 0.001),
    );
  });

  test('handles negative distances symmetrically', () {
    expect(
      roundHorizontalInset(
        distanceFromCenter: -radius / 2,
        radius: radius,
        minGutter: gutter,
      ),
      roundHorizontalInset(
        distanceFromCenter: radius / 2,
        radius: radius,
        minGutter: gutter,
      ),
    );
  });

  test('handles a zero radius without dividing by zero', () {
    expect(
      roundHorizontalInset(distanceFromCenter: 0, radius: 0, minGutter: gutter),
      gutter,
    );
  });
}
