import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/services/article_merger.dart';

import '../../../../support/article_factory.dart';

void main() {
  const merger = ArticleMerger();
  final now = DateTime(2026, 10, 27, 18);

  /// Deterministic scramble of a newest-first list: newest, oldest, second
  /// newest, second oldest, … A cap that lazily keeps the first 20 *inputs*
  /// (instead of the 20 newest) therefore fails, while the input stays stable
  /// across runs.
  List<Article> scramble(List<Article> newestFirst) {
    final scrambled = <Article>[];
    var front = 0;
    var back = newestFirst.length - 1;
    while (front <= back) {
      scrambled.add(newestFirst[front]);
      front++;
      if (front <= back) {
        scrambled.add(newestFirst[back]);
        back--;
      }
    }
    return scrambled;
  }

  /// [count] today-only articles, strictly newest first, one minute apart.
  List<Article> todayArticles(int count, {String prefix = 'story'}) => [
    for (var i = 0; i < count; i++)
      article(
        guid: '$prefix-$i',
        title: 'Headline $i',
        link: 'https://example.com/$prefix/$i',
        publishedAt: now.subtract(Duration(minutes: i + 1)),
      ),
  ];

  /// The guids of the [count] newest [todayArticles], newest first.
  List<String> newestGuids(int count, {String prefix = 'story'}) => [
    for (var i = 0; i < count; i++) '$prefix-$i',
  ];

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

  // --- Feed cap -----------------------------------------------------------
  // The merged feed must never show more than the 20 newest articles, even
  // though 7 sources can publish far more than that on a busy day.

  test('caps the merged list at the 20 newest articles', () {
    // Literal guard: a constant that drifts away from 20 must fail loudly.
    expect(kMaxFeedArticles, 20);

    final newestFirst = todayArticles(35);

    final merged = merger.merge(scramble(newestFirst), now: now);

    expect(merged, hasLength(20));
    expect(merged, hasLength(kMaxFeedArticles));
    expect(merged.map((a) => a.guid), newestGuids(20));
    expect(merged.first.guid, 'story-0');
    expect(merged.last.guid, 'story-19');
    // The 21st newest article (and everything older) is dropped.
    expect(merged.map((a) => a.guid), isNot(contains('story-20')));
    expect(merged.map((a) => a.guid), isNot(contains('story-34')));
    expect(() => merged.add(article()), throwsUnsupportedError);
  });

  test('does not cap when today has fewer than 20 articles', () {
    final newestFirst = todayArticles(5);

    final merged = merger.merge(scramble(newestFirst), now: now);

    expect(merged, hasLength(5));
    expect(merged.map((a) => a.guid), newestGuids(5));
    expect(merged.map((a) => a.guid), isNot(contains('story-5')));
  });

  test('applies the cap after de-duplication and today-filtering', () {
    final newestFirst = todayArticles(25);

    // Older copies of the five newest stories, so an un-deduped merge would
    // spend cap slots on duplicates.
    final duplicates = [
      for (var i = 0; i < 5; i++)
        article(
          guid: 'story-$i',
          title: 'Older copy of $i',
          link: 'https://example.com/story/$i',
          publishedAt: newestFirst[i].publishedAt.subtract(
            const Duration(seconds: 30),
          ),
        ),
    ];

    final otherDays = [
      article(
        guid: 'yesterday-late',
        title: 'Yesterday late',
        publishedAt: DateTime(2026, 10, 26, 23, 59),
      ),
      article(
        guid: 'yesterday-early',
        title: 'Yesterday early',
        publishedAt: DateTime(2026, 10, 26, 0, 0),
      ),
      article(
        guid: 'tomorrow',
        title: 'Tomorrow',
        publishedAt: DateTime(2026, 10, 28, 0, 1),
      ),
    ];

    final merged = merger.merge(
      scramble([...newestFirst, ...duplicates, ...otherDays]),
      now: now,
    );

    final guids = merged.map((a) => a.guid).toList();

    expect(merged, hasLength(20));
    expect(merged, hasLength(kMaxFeedArticles));
    expect(
      merged.every((a) => a.isOnLocalDayOf(now)),
      isTrue,
      reason: 'only today should reach the feed',
    );
    expect(guids.toSet(), hasLength(20), reason: 'duplicates consumed a slot');
    expect(guids, newestGuids(20));
    expect(guids, contains('story-0'));
    expect(guids, isNot(contains('story-24')));
    expect(guids, isNot(contains('yesterday-late')));
    expect(guids, isNot(contains('yesterday-early')));
    expect(guids, isNot(contains('tomorrow')));
    // The surviving copy of a de-duplicated story is the newest one.
    expect(merged.first.title, 'Headline 0');
    expect(merged.where((a) => a.guid == 'story-0'), hasLength(1));
  });

  test('keeps all 20 articles when today has exactly the maximum', () {
    final newestFirst = todayArticles(20);

    final merged = merger.merge(scramble(newestFirst), now: now);

    expect(merged, hasLength(20));
    expect(merged, hasLength(kMaxFeedArticles));
    expect(merged.map((a) => a.guid), newestGuids(20));
    expect(merged.last.guid, 'story-19');
    expect(() => merged.add(article()), throwsUnsupportedError);
  });

  test('resolves the publishedAt tie-break before truncating', () {
    // 19 strictly newer articles, then two published at the same instant: they
    // compete for the single remaining slot and the title tie-break decides.
    final tiedAt = DateTime(2026, 10, 27, 9);
    final newestAt = DateTime(2026, 10, 27, 17);
    final articles = [
      for (var i = 0; i < 19; i++)
        article(
          guid: 'newer-$i',
          title: 'Newer $i',
          publishedAt: newestAt.subtract(Duration(minutes: i)),
        ),
      article(guid: 'tie-zulu', title: 'Zulu', publishedAt: tiedAt),
      article(guid: 'tie-alpha', title: 'Alpha', publishedAt: tiedAt),
    ];

    final merged = merger.merge(scramble(articles), now: now);

    expect(merged, hasLength(20));
    expect(merged.where((a) => a.guid.startsWith('tie-')), hasLength(1));
    expect(merged.last.guid, 'tie-alpha');
    expect(merged.map((a) => a.guid), isNot(contains('tie-zulu')));
  });

  test('stays capped for a large single-day batch', () {
    final newestFirst = todayArticles(500);

    final merged = merger.merge(scramble(newestFirst), now: now);

    expect(merged, hasLength(20));
    expect(merged.map((a) => a.guid), newestGuids(20));
  });
}
