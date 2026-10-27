import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/services/pub_date_parser.dart';

void main() {
  group('parseFeedDate', () {
    test('parses RFC 1123 dates with GMT', () {
      final parsed = parseFeedDate('Tue, 27 Oct 2026 09:15:50 GMT');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc(), DateTime.utc(2026, 10, 27, 9, 15, 50));
      expect(parsed.isUtc, isFalse, reason: 'normalized to local time');
    });

    test('parses RFC 822 numeric offsets used by WordPress feeds', () {
      final parsed = parseFeedDate('Tue, 27 Oct 2026 11:20:51 +0200');

      expect(parsed!.toUtc(), DateTime.utc(2026, 10, 27, 9, 20, 51));
      expect(parsed.isUtc, isFalse);
    });

    test('parses negative numeric offsets', () {
      final parsed = parseFeedDate('Mon, 26 Oct 2026 20:04:16 -0700');

      expect(parsed!.toUtc(), DateTime.utc(2026, 10, 27, 3, 4, 16));
    });

    test('parses named US zones', () {
      expect(
        parseFeedDate('Tue, 27 Oct 2026 09:00:00 EST')!.toUtc(),
        DateTime.utc(2026, 10, 27, 14),
      );
      expect(
        parseFeedDate('Tue, 27 Oct 2026 09:00:00 PDT')!.toUtc(),
        DateTime.utc(2026, 10, 27, 16),
      );
    });

    test('falls back to ISO-8601 timestamps', () {
      expect(
        parseFeedDate('2026-10-27T09:15:00Z')!.toUtc(),
        DateTime.utc(2026, 10, 27, 9, 15),
      );
    });

    test('accepts a missing weekday and two-digit years', () {
      expect(
        parseFeedDate('27 Oct 26 09:15:00 GMT')!.toUtc(),
        DateTime.utc(2026, 10, 27, 9, 15),
      );
    });

    test('trims surrounding whitespace and newlines', () {
      expect(
        parseFeedDate('\n  Tue, 27 Oct 2026 09:15:50 +0000 \t')!.toUtc(),
        DateTime.utc(2026, 10, 27, 9, 15, 50),
      );
    });

    test('returns null for empty or unparseable values', () {
      expect(parseFeedDate(''), isNull);
      expect(parseFeedDate('   '), isNull);
      expect(parseFeedDate('not a date'), isNull);
      expect(parseFeedDate('32 Oct 2026 09:15:00 GMT'), isNull);
    });
  });
}
