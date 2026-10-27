import '../entities/article.dart';

/// Maximum number of articles in the merged feed.
///
/// Bounds both the watch list and the Hive cache: 7 sources can publish far
/// more than this on a busy day, and only the newest entries are worth keeping
/// on a watch.
const int kMaxFeedArticles = 20;

/// Pure business rules for the merged, today-only reading list.
///
/// Kept in the domain layer so the rules can be unit tested without Dio, Hive
/// or Flutter, and so the data-layer repository only has to orchestrate I/O.
class ArticleMerger {
  const ArticleMerger();

  /// Filters [articles] to the local calendar day of [now], removes duplicates
  /// (by guid, falling back to link), sorts newest first and caps the result at
  /// the [kMaxFeedArticles] newest entries.
  ///
  /// When two copies of the same article differ, the most recently published
  /// copy wins. Articles without a usable identity or title are dropped, since
  /// they cannot be de-duplicated or rendered. The cap is applied after
  /// filtering, de-duplication and sorting, so it keeps the newest stories.
  List<Article> merge(Iterable<Article> articles, {required DateTime now}) {
    final byIdentity = <String, Article>{};

    for (final article in articles) {
      final identity = article.identity.trim();
      if (identity.isEmpty || article.title.trim().isEmpty) {
        continue;
      }
      if (!article.isOnLocalDayOf(now)) {
        continue;
      }

      final existing = byIdentity[identity];
      if (existing == null ||
          article.publishedAt.isAfter(existing.publishedAt)) {
        byIdentity[identity] = article;
      }
    }

    final merged = byIdentity.values.toList()
      ..sort((a, b) {
        final byPublishedAt = b.publishedAt.compareTo(a.publishedAt);
        if (byPublishedAt != 0) {
          return byPublishedAt;
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    return List<Article>.unmodifiable(merged.take(kMaxFeedArticles));
  }
}
