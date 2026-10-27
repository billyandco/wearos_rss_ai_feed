import '../../../../core/errors/feed_failure.dart';
import '../../domain/entities/article.dart';
import '../../domain/repositories/saved_article_repository.dart';
import '../datasources/saved_article_local_data_source.dart';

/// Persists bookmarked articles through [SavedArticleLocalDataSource].
///
/// Saving is idempotent: an article is keyed by [Article.identity], so a second
/// save replaces the stored copy instead of duplicating it.
class SavedArticleRepositoryImpl implements SavedArticleRepository {
  SavedArticleRepositoryImpl({
    required SavedArticleLocalDataSource localDataSource,
  }) : _localDataSource = localDataSource;

  final SavedArticleLocalDataSource _localDataSource;

  @override
  Future<List<Article>> savedArticles() async {
    try {
      return await _localDataSource.readSaved();
    } on FeedFailure {
      rethrow;
    } on Object catch (error) {
      throw FeedCacheFailure('Could not read saved articles.', cause: error);
    }
  }

  @override
  Future<void> save(Article article) async {
    try {
      final saved = await _localDataSource.readSaved();
      final updated = <Article>[
        ...saved.where((existing) => existing.identity != article.identity),
        article,
      ];
      await _localDataSource.writeSaved(updated);
    } on FeedFailure {
      rethrow;
    } on Object catch (error) {
      throw FeedCacheFailure('Could not save the article.', cause: error);
    }
  }

  @override
  Future<void> remove(String identity) async {
    try {
      final saved = await _localDataSource.readSaved();
      final updated = saved
          .where((existing) => existing.identity != identity)
          .toList();
      await _localDataSource.writeSaved(updated);
    } on FeedFailure {
      rethrow;
    } on Object catch (error) {
      throw FeedCacheFailure(
        'Could not remove the saved article.',
        cause: error,
      );
    }
  }
}
