import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../features/feed/data/datasources/article_local_data_source.dart';
import '../../features/feed/data/datasources/feed_remote_data_source.dart';
import '../../features/feed/data/datasources/platform_remote_article_opener.dart';
import '../../features/feed/data/datasources/saved_article_local_data_source.dart';
import '../../features/feed/data/feed_sources.dart';
import '../../features/feed/data/repositories/article_repository_impl.dart';
import '../../features/feed/data/repositories/saved_article_repository_impl.dart';
import '../../features/feed/domain/entities/feed_source.dart';
import '../../features/feed/domain/repositories/article_repository.dart';
import '../../features/feed/domain/repositories/remote_article_opener.dart';
import '../../features/feed/domain/repositories/saved_article_repository.dart';
import '../../features/feed/domain/usecases/is_article_saved.dart';
import '../../features/feed/domain/usecases/load_cached_articles.dart';
import '../../features/feed/domain/usecases/load_saved_articles.dart';
import '../../features/feed/domain/usecases/open_article_on_phone.dart';
import '../../features/feed/domain/usecases/refresh_today_articles.dart';
import '../../features/feed/domain/usecases/remove_saved_article.dart';
import '../../features/feed/domain/usecases/restore_saved_article.dart';
import '../../features/feed/domain/usecases/toggle_saved_article.dart';
import '../../features/feed/presentation/bloc/feed_bloc.dart';
import '../network/dio_client.dart';

/// Single service locator for the app.
final GetIt sl = GetIt.instance;

/// Wires the dependency graph: presentation -> use cases -> repository
/// interface -> data implementations.
///
/// Optional overrides exist for tests and for hosts that provide their own Dio
/// or Hive box (for example an integration harness).
Future<void> configureDependencies({
  Dio? dio,
  Box<String>? cacheBox,
  RemoteArticleOpener? remoteOpener,
  List<FeedSource> sources = kFeedSources,
}) async {
  if (sl.isRegistered<FeedBloc>()) {
    return;
  }

  final resolvedDio = dio ?? createFeedDio();
  final resolvedBox = cacheBox ?? await _openCacheBox();

  sl
    ..registerLazySingleton<Dio>(() => resolvedDio)
    ..registerLazySingleton<ArticleLocalDataSource>(
      () => HiveArticleLocalDataSource(resolvedBox),
    )
    // Shares the today cache box: the saved store is just another key in it.
    ..registerLazySingleton<SavedArticleLocalDataSource>(
      () => HiveSavedArticleLocalDataSource(resolvedBox),
    )
    ..registerLazySingleton<FeedRemoteDataSource>(
      () => DioFeedRemoteDataSource(sl<Dio>()),
    )
    ..registerLazySingleton<ArticleRepository>(
      () => ArticleRepositoryImpl(
        remoteDataSource: sl<FeedRemoteDataSource>(),
        localDataSource: sl<ArticleLocalDataSource>(),
        sources: sources,
      ),
    )
    ..registerLazySingleton<RemoteArticleOpener>(
      () => remoteOpener ?? const PlatformRemoteArticleOpener(),
    )
    ..registerLazySingleton<SavedArticleRepository>(
      () => SavedArticleRepositoryImpl(
        localDataSource: sl<SavedArticleLocalDataSource>(),
      ),
    )
    ..registerFactory<LoadCachedArticles>(
      () => LoadCachedArticles(sl<ArticleRepository>()),
    )
    ..registerFactory<LoadSavedArticles>(
      () => LoadSavedArticles(sl<SavedArticleRepository>()),
    )
    ..registerFactory<IsArticleSaved>(
      () => IsArticleSaved(sl<SavedArticleRepository>()),
    )
    ..registerFactory<ToggleSavedArticle>(
      () => ToggleSavedArticle(sl<SavedArticleRepository>()),
    )
    ..registerFactory<RemoveSavedArticle>(
      () => RemoveSavedArticle(sl<SavedArticleRepository>()),
    )
    ..registerFactory<RestoreSavedArticle>(
      () => RestoreSavedArticle(sl<SavedArticleRepository>()),
    )
    ..registerFactory<RefreshTodayArticles>(
      () => RefreshTodayArticles(sl<ArticleRepository>()),
    )
    ..registerFactory<OpenArticleOnPhone>(
      () => OpenArticleOnPhone(sl<RemoteArticleOpener>()),
    )
    ..registerFactory<FeedBloc>(
      () => FeedBloc(
        loadCachedArticles: sl<LoadCachedArticles>(),
        refreshTodayArticles: sl<RefreshTodayArticles>(),
        openArticleOnPhone: sl<OpenArticleOnPhone>(),
        loadSavedArticles: sl<LoadSavedArticles>(),
        removeSavedArticle: sl<RemoveSavedArticle>(),
        restoreSavedArticle: sl<RestoreSavedArticle>(),
      ),
    );
}

Future<Box<String>> _openCacheBox() async {
  await Hive.initFlutter();
  return Hive.openBox<String>(HiveArticleLocalDataSource.boxName);
}
