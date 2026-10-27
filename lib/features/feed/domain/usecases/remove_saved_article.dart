import '../repositories/saved_article_repository.dart';

/// Un-bookmarks the article with a given identity.
class RemoveSavedArticle {
  const RemoveSavedArticle(this._repository);

  final SavedArticleRepository _repository;

  Future<void> call(String identity) => _repository.remove(identity);
}
