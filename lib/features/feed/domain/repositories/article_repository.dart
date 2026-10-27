import '../entities/article.dart';

/// Read/write contract for the merged article feed.
///
/// Implementations live in the data layer; the domain (and therefore the
/// presentation layer) only depends on this abstraction.
abstract interface class ArticleRepository {
  /// Articles stored during a previous fetch, returned exactly as cached.
  ///
  /// The "today only" rule is applied when fetching, never when reading the
  /// cache, so callers may receive articles from an earlier day until the next
  /// successful refresh replaces them.
  Future<List<Article>> cachedArticles();

  /// Downloads every source, normalizes the items to the local day of [now],
  /// de-duplicates and sorts them newest first, then caches the result.
  Future<List<Article>> refreshTodayArticles({required DateTime now});
}
