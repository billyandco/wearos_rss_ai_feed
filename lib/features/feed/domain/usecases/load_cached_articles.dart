import '../entities/article.dart';
import '../repositories/article_repository.dart';

/// Returns the articles cached by the previous successful fetch.
class LoadCachedArticles {
  const LoadCachedArticles(this._repository);

  final ArticleRepository _repository;

  Future<List<Article>> call() => _repository.cachedArticles();
}
