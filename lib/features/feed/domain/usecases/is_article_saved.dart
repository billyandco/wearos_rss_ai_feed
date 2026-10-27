import '../repositories/saved_article_repository.dart';

/// Tells whether the article with a given identity is saved.
class IsArticleSaved {
  const IsArticleSaved(this._repository);

  final SavedArticleRepository _repository;

  Future<bool> call(String identity) async {
    final saved = await _repository.savedArticles();
    return saved.any((article) => article.identity == identity);
  }
}
