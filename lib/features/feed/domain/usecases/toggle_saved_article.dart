import '../entities/article.dart';
import '../repositories/saved_article_repository.dart';

/// Bookmarks [article] or un-bookmarks it, depending on its current state.
///
/// Returns `true` when the article is saved afterwards, `false` when it was
/// removed.
class ToggleSavedArticle {
  const ToggleSavedArticle(this._repository);

  final SavedArticleRepository _repository;

  /// Reads the saved list once, then either saves or removes [article].
  Future<bool> call(Article article) async {
    final saved = await _repository.savedArticles();
    final isSaved = saved.any(
      (existing) => existing.identity == article.identity,
    );

    if (isSaved) {
      await _repository.remove(article.identity);
      return false;
    }

    await _repository.save(article);
    return true;
  }
}
