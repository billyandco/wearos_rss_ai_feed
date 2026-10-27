import 'dart:async';

import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/article_repository.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/remote_article_opener.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/load_cached_articles.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/open_article_on_phone.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/refresh_today_articles.dart';
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

FeedBloc buildTestFeedBloc({
  required FakeArticleRepository repository,
  RecordingRemoteOpener? opener,
  DateTime Function()? clock,
}) => FeedBloc(
  loadCachedArticles: LoadCachedArticles(repository),
  refreshTodayArticles: RefreshTodayArticles(repository),
  openArticleOnPhone: OpenArticleOnPhone(opener ?? RecordingRemoteOpener()),
  clock: clock,
);
