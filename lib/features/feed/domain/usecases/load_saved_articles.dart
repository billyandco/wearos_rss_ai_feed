import '../entities/article.dart';
import '../repositories/saved_article_repository.dart';

/// Returns the saved articles, newest published first.
///
/// Unlike the today feed this is not day-filtered and not capped, so an article
/// bookmarked weeks ago stays reachable.
class LoadSavedArticles {
  const LoadSavedArticles(this._repository);

  final SavedArticleRepository _repository;

  /// De-duplicates by [Article.identity] (keeping the newest copy) and sorts
  /// newest first, breaking ties by lowercase title.
  Future<List<Article>> call() async {
    final saved = await _repository.savedArticles();

    final byIdentity = <String, Article>{};
    for (final article in saved) {
      final existing = byIdentity[article.identity];
      if (existing == null ||
          article.publishedAt.isAfter(existing.publishedAt)) {
        byIdentity[article.identity] = article;
      }
    }

    final sorted = byIdentity.values.toList()
      ..sort((a, b) {
        final byPublishedAt = b.publishedAt.compareTo(a.publishedAt);
        if (byPublishedAt != 0) {
          return byPublishedAt;
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    return List<Article>.unmodifiable(sorted);
  }
}
