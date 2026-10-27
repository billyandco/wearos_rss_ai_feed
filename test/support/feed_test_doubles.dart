import 'dart:async';

import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/article_repository.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/remote_article_opener.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/saved_article_repository.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/load_cached_articles.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/load_saved_articles.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/open_article_on_phone.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/refresh_today_articles.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/remove_saved_article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/restore_saved_article.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_bloc.dart';

class FakeArticleRepository implements ArticleRepository {
  List<Article> cached = const [];
  List<Article> refreshed = const [];
  Object? refreshError;
  Object? cachedError;

  /// When set, refresh waits for this completer before returning.
  Completer<void>? refreshGate;

  int refreshCalls = 0;
  int cachedCalls = 0;
  DateTime? lastRequestedNow;

  @override
  Future<List<Article>> cachedArticles() async {
    cachedCalls++;
    if (cachedError != null) {
      throw cachedError!;
    }
    return cached;
  }

  @override
  Future<List<Article>> refreshTodayArticles({required DateTime now}) async {
    refreshCalls++;
    lastRequestedNow = now;
    if (refreshGate != null) {
      await refreshGate!.future;
    }
    if (refreshError != null) {
      throw refreshError!;
    }
    return refreshed;
  }
}

class RecordingRemoteOpener implements RemoteArticleOpener {
  final List<Uri> opened = [];
  Object? error;

  @override
  Future<void> openOnPhone(Uri url) async {
    if (error != null) {
      throw error!;
    }
    opened.add(url);
  }
}

/// In-memory [SavedArticleRepository] the bloc tests can inspect and break.
///
/// [saved] is mutable on purpose: tests mutate it between events to simulate a
/// bookmark made on the detail page.
class FakeSavedArticleRepository implements SavedArticleRepository {
  FakeSavedArticleRepository({Iterable<Article> saved = const []})
    : saved = List<Article>.of(saved);

  final List<Article> saved;

  /// Each is thrown by the matching call when non-null.
  Object? savedArticlesError;
  Object? saveError;
  Object? removeError;

  int savedArticlesCalls = 0;
  int saveCalls = 0;
  int removeCalls = 0;

  final List<Article> savedArguments = [];
  final List<String> removedIdentities = [];

  @override
  Future<List<Article>> savedArticles() async {
    savedArticlesCalls++;
    if (savedArticlesError != null) {
      throw savedArticlesError!;
    }
    return List<Article>.of(saved);
  }

  @override
  Future<void> save(Article article) async {
    saveCalls++;
    savedArguments.add(article);
    if (saveError != null) {
      throw saveError!;
    }
    saved.removeWhere((existing) => existing.identity == article.identity);
    saved.add(article);
  }

  @override
  Future<void> remove(String identity) async {
    removeCalls++;
    removedIdentities.add(identity);
    if (removeError != null) {
      throw removeError!;
    }
    saved.removeWhere((existing) => existing.identity == identity);
  }
}

FeedBloc buildTestFeedBloc({
  required FakeArticleRepository repository,
  RecordingRemoteOpener? opener,
  FakeSavedArticleRepository? savedRepository,
  DateTime Function()? clock,
}) {
  final saved = savedRepository ?? FakeSavedArticleRepository();
  return FeedBloc(
    loadCachedArticles: LoadCachedArticles(repository),
    refreshTodayArticles: RefreshTodayArticles(repository),
    openArticleOnPhone: OpenArticleOnPhone(opener ?? RecordingRemoteOpener()),
    loadSavedArticles: LoadSavedArticles(saved),
    removeSavedArticle: RemoveSavedArticle(saved),
    restoreSavedArticle: RestoreSavedArticle(saved),
    clock: clock,
  );
}
