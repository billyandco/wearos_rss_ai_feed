import '../entities/article.dart';
import '../repositories/article_repository.dart';

/// Fetches every configured source and keeps only today's articles.
class RefreshTodayArticles {
  const RefreshTodayArticles(this._repository);

  final ArticleRepository _repository;

  Future<List<Article>> call({required DateTime now}) =>
      _repository.refreshTodayArticles(now: now);
}
