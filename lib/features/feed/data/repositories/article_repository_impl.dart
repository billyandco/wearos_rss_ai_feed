import '../../../../core/errors/feed_failure.dart';
import '../../domain/entities/article.dart';
import '../../domain/entities/feed_source.dart';
import '../../domain/repositories/article_repository.dart';
import '../../domain/services/article_merger.dart';
import '../datasources/article_local_data_source.dart';
import '../datasources/feed_remote_data_source.dart';

class ArticleRepositoryImpl implements ArticleRepository {
  ArticleRepositoryImpl({
    required FeedRemoteDataSource remoteDataSource,
    required ArticleLocalDataSource localDataSource,
    required List<FeedSource> sources,
    ArticleMerger merger = const ArticleMerger(),
  }) : _remoteDataSource = remoteDataSource,
       _localDataSource = localDataSource,
       _sources = List<FeedSource>.unmodifiable(sources),
       _merger = merger;

  final FeedRemoteDataSource _remoteDataSource;
  final ArticleLocalDataSource _localDataSource;
  final List<FeedSource> _sources;
  final ArticleMerger _merger;

  @override
  Future<List<Article>> cachedArticles() async {
    try {
      return await _localDataSource.readArticles();
    } on FeedFailure {
      rethrow;
    } on Object catch (error) {
      throw FeedCacheFailure('Could not read cached articles.', cause: error);
    }
  }

  @override
  Future<List<Article>> refreshTodayArticles({required DateTime now}) async {
    final fetched = await _remoteDataSource.fetchArticles(_sources, now: now);
    final merged = _merger.merge(fetched, now: now);

    try {
      await _localDataSource.writeArticles(merged);
    } on FeedFailure {
      rethrow;
    } on Object catch (error) {
      throw FeedCacheFailure('Could not save today\'s articles.', cause: error);
    }

    return merged;
  }
}
