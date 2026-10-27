import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/services/article_merger.dart';

import '../../../../support/article_factory.dart';

void main() {
  const merger = ArticleMerger();
  final now = DateTime(2026, 10, 27, 18);

  test('keeps only articles published on the local day of now', () {
    final articles = [
      article(guid: 'yesterday', publishedAt: DateTime(2026, 10, 26, 23, 59)),
      article(guid: 'today-morning', publishedAt: DateTime(2026, 10, 27, 0, 0)),
      article(
        guid: 'today-evening',
        publishedAt: DateTime(2026, 10, 27, 23, 59),
      ),
      article(guid: 'tomorrow', publishedAt: DateTime(2026, 10, 28, 0, 1)),
    ];

    final merged = merger.merge(articles, now: now);

    expect(merged.map((a) => a.guid), ['today-evening', 'today-morning']);
  });

  test('sorts newest first', () {
    final articles = [
      article(guid: 'old', publishedAt: DateTime(2026, 10, 27, 8)),
      article(guid: 'new', publishedAt: DateTime(2026, 10, 27, 16)),
      article(guid: 'middle', publishedAt: DateTime(2026, 10, 27, 12)),
    ];

    final merged = merger.merge(articles, now: now);

    expect(merged.map((a) => a.guid), ['new', 'middle', 'old']);
  });

  test('de-duplicates by guid, keeping the newest copy', () {
    final articles = [
      article(
        guid: 'shared',
        title: 'Older copy',
        publishedAt: DateTime(2026, 10, 27, 9),
      ),
      article(
        guid: 'shared',
        title: 'Newer copy',
        publishedAt: DateTime(2026, 10, 27, 15),
      ),
    ];

    final merged = merger.merge(articles, now: now);

    expect(merged, hasLength(1));
    expect(merged.single.title, 'Newer copy');
  });

  test('falls back to the link when guids are empty', () {
    final articles = [
      article(
        guid: '',
        link: 'https://example.com/same',
        title: 'First',
        publishedAt: DateTime(2026, 10, 27, 9),
      ),
      article(
        guid: '',
        link: 'https://example.com/same',
        title: 'Second',
        publishedAt: DateTime(2026, 10, 27, 11),
      ),
      article(
        guid: '',
        link: 'https://example.com/other',
        title: 'Third',
        publishedAt: DateTime(2026, 10, 27, 10),
      ),
    ];

    final merged = merger.merge(articles, now: now);

    expect(merged.map((a) => a.title), ['Second', 'Third']);
  });

  test('ignores articles without a usable identity or title', () {
    final merged = merger.merge([
      article(guid: '', link: ''),
      article(guid: 'blank-title', title: '   '),
      article(guid: 'valid'),
    ], now: now);

    expect(merged.map((a) => a.guid), ['valid']);
  });

  test('breaks publishedAt ties deterministically by title', () {
    final sameInstant = DateTime(2026, 10, 27, 12);
    final merged = merger.merge([
      article(guid: 'b', title: 'Beta', publishedAt: sameInstant),
      article(guid: 'a', title: 'Alpha', publishedAt: sameInstant),
    ], now: now);

    expect(merged.map((a) => a.title), ['Alpha', 'Beta']);
  });

  test('returns an empty immutable list for no input', () {
    final merged = merger.merge(const [], now: now);
    expect(merged, isEmpty);
    expect(() => merged.add(article()), throwsUnsupportedError);
  });
}
