import 'dart:math' as math;

/// Extra horizontal inset a row needs so that it stays inside a circular
/// display.
///
/// A row whose vertical centre is [distanceFromCenter] away from the centre of
/// the circle can be at most `2 * sqrt(radius² - distance²)` wide. The returned
/// inset fills the remaining space on each side, never dropping below
/// [minGutter] and never exceeding [radius].
double roundHorizontalInset({
  required double distanceFromCenter,
  required double radius,
  double minGutter = 12,
}) {
  if (radius <= 0) {
    return minGutter;
  }

  final distance = distanceFromCenter.abs();
  if (distance >= radius) {
    return radius;
  }

  final halfChord = math.sqrt(radius * radius - distance * distance);
  return math.min(radius, radius - halfChord + minGutter);
}
