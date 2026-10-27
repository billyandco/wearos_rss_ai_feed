import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/feed_failure.dart';
import '../../domain/usecases/load_cached_articles.dart';
import '../../domain/usecases/open_article_on_phone.dart';
import '../../domain/usecases/refresh_today_articles.dart';
import 'feed_event.dart';
import 'feed_state.dart';

/// Orchestrates the feed use cases for the single watch screen.
///
/// The bloc knows nothing about Dio, Hive or Android; it only talks to use
/// cases, keeping the dependency arrows pointing inward.
class FeedBloc extends Bloc<FeedEvent, FeedState> {
  FeedBloc({
    required LoadCachedArticles loadCachedArticles,
    required RefreshTodayArticles refreshTodayArticles,
    required OpenArticleOnPhone openArticleOnPhone,
    DateTime Function()? clock,
  }) : _loadCachedArticles = loadCachedArticles,
       _refreshTodayArticles = refreshTodayArticles,
       _openArticleOnPhone = openArticleOnPhone,
       _clock = clock ?? DateTime.now,
       super(const FeedState.initial()) {
    on<FeedStarted>(_onStarted);
    on<FeedRefreshRequested>(_onRefreshRequested);
    on<FeedArticleOpened>(_onArticleOpened);
  }

  final LoadCachedArticles _loadCachedArticles;
  final RefreshTodayArticles _refreshTodayArticles;
  final OpenArticleOnPhone _openArticleOnPhone;
  final DateTime Function() _clock;

  int _lastNoticeId = 0;

  Future<void> _onStarted(FeedStarted event, Emitter<FeedState> emit) async {
    emit(
      state.copyWith(
        status: FeedStatus.loading,
        isRefreshing: false,
        clearError: true,
      ),
    );

    try {
      final cached = await _loadCachedArticles();
      if (cached.isNotEmpty) {
        emit(state.copyWith(status: FeedStatus.ready, articles: cached));
      }
    } catch (error) {
      // A broken cache should never prevent a fresh fetch.
      emit(state.copyWith(errorMessage: _messageFor(error)));
    }

    add(const FeedRefreshRequested());
  }

  Future<void> _onRefreshRequested(
    FeedRefreshRequested event,
    Emitter<FeedState> emit,
  ) async {
    if (state.isRefreshing) {
      return;
    }

    emit(state.copyWith(isRefreshing: true, clearError: true));

    try {
      final articles = await _refreshTodayArticles(now: _clock());
      emit(
        state.copyWith(
          status: FeedStatus.ready,
          articles: articles,
          isRefreshing: false,
          lastUpdated: _clock(),
          clearError: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: state.hasArticles ? FeedStatus.ready : FeedStatus.failure,
          isRefreshing: false,
          errorMessage: _messageFor(error),
        ),
      );
    }
  }

  Future<void> _onArticleOpened(
    FeedArticleOpened event,
    Emitter<FeedState> emit,
  ) async {
    try {
      await _openArticleOnPhone(event.article);
      emit(
        state.copyWith(
          notice: _notice(
            FeedNoticeKind.openedOnPhone,
            'Opening on your phone',
          ),
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          notice: _notice(FeedNoticeKind.openFailed, _messageFor(error)),
        ),
      );
    }
  }

  FeedNotice _notice(FeedNoticeKind kind, String message) =>
      FeedNotice(id: ++_lastNoticeId, kind: kind, message: message);

  String _messageFor(Object error) => switch (error) {
    FeedFailure(:final message) => message,
    _ => 'Something went wrong. Try again.',
  };
}
