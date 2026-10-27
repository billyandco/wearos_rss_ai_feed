import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/utils/relative_time.dart';

void main() {
  final now = DateTime(2026, 10, 27, 18, 0);

  group('formatRelativeTime', () {
    test('shows "now" for the last minute', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 59)), now: now),
        'now',
      );
    });

    test('shows minutes below one hour', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 7)), now: now),
        '7m',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 59)), now: now),
        '59m',
      );
    });

    test('shows hours below one day', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 60)), now: now),
        '1h',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 23)), now: now),
        '23h',
      );
    });

    test('shows days from one day upwards', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 24)), now: now),
        '1d',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3d',
      );
    });

    test('clamps future timestamps (watch/phone clock skew) to now', () {
      expect(
        formatRelativeTime(now.add(const Duration(minutes: 5)), now: now),
        'now',
      );
    });
  });
}
