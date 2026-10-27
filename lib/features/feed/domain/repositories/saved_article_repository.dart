import '../entities/article.dart';

/// Read/write contract for the articles the wearer bookmarked.
///
/// Implementations live in the data layer; the domain (and therefore the
/// presentation layer) only depends on this abstraction.
abstract interface class SavedArticleRepository {
  /// Every saved article, exactly as stored.
  Future<List<Article>> savedArticles();

  /// Stores [article], replacing any saved copy with the same
  /// [Article.identity] so saving twice never duplicates an entry.
  Future<void> save(Article article);

  /// Removes the saved article whose [Article.identity] is [identity].
  ///
  /// Removing an identity that is not saved is a no-op.
  Future<void> remove(String identity);
}
