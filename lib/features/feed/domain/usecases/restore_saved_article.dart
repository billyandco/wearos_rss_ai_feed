import '../entities/article.dart';
import '../repositories/saved_article_repository.dart';

/// Writes [article] back into the saved store (the UNDO path).
///
/// Unlike a toggle this is unconditional: the article is saved whether or not
/// it is currently bookmarked, so pressing UNDO twice is harmless.
class RestoreSavedArticle {
  const RestoreSavedArticle(this._repository);

  final SavedArticleRepository _repository;

  Future<void> call(Article article) => _repository.save(article);
}
