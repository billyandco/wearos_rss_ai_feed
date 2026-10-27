import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/feed_failure.dart';
import '../../domain/usecases/load_cached_articles.dart';
import '../../domain/usecases/load_saved_articles.dart';
import '../../domain/usecases/open_article_on_phone.dart';
import '../../domain/usecases/refresh_today_articles.dart';
import '../../domain/usecases/remove_saved_article.dart';
import '../../domain/usecases/restore_saved_article.dart';
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
    required LoadSavedArticles loadSavedArticles,
    required RemoveSavedArticle removeSavedArticle,
    required RestoreSavedArticle restoreSavedArticle,
    DateTime Function()? clock,
  }) : _loadCachedArticles = loadCachedArticles,
       _refreshTodayArticles = refreshTodayArticles,
       _openArticleOnPhone = openArticleOnPhone,
       _loadSavedArticles = loadSavedArticles,
       _removeSavedArticle = removeSavedArticle,
       _restoreSavedArticle = restoreSavedArticle,
       _clock = clock ?? DateTime.now,
       super(const FeedState.initial()) {
    on<FeedStarted>(_onStarted);
    on<FeedRefreshRequested>(_onRefreshRequested);
    on<FeedArticleOpened>(_onArticleOpened);
    on<FeedSectionToggled>(_onSectionToggled);
    on<FeedSavedReloadRequested>(_onSavedReloadRequested);
    on<FeedSavedArticleRemoved>(_onSavedArticleRemoved);
    on<FeedSavedArticleRestored>(_onSavedArticleRestored);
  }

  final LoadCachedArticles _loadCachedArticles;
  final RefreshTodayArticles _refreshTodayArticles;
  final OpenArticleOnPhone _openArticleOnPhone;
  final LoadSavedArticles _loadSavedArticles;
  final RemoveSavedArticle _removeSavedArticle;
  final RestoreSavedArticle _restoreSavedArticle;

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

    await _loadSavedSilently(emit);

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

  // ---------------------------------------------------------------------------
  // Saved articles
  // ---------------------------------------------------------------------------

  /// Fills [FeedState.savedArticles] on start without touching status or errors:
  /// a broken saved store must look like an empty list, never like a failure.
  Future<void> _loadSavedSilently(Emitter<FeedState> emit) async {
    try {
      final saved = await _loadSavedArticles();
      emit(state.copyWith(savedArticles: saved, clearSavedError: true));
    } catch (_) {
      // Best effort: the today feed is unaffected.
    }
  }

  Future<void> _onSectionToggled(
    FeedSectionToggled event,
    Emitter<FeedState> emit,
  ) async {
    if (state.section == FeedSection.saved) {
      emit(state.copyWith(section: FeedSection.today));
      return;
    }

    // Re-read the store: a bookmark may have been made on the detail page
    // while the feed kept running. The read is local (Hive), so the flip lands
    // in the same frame as the tap; merging it with the result keeps the first
    // saved state truthful. A failed read keeps the last known list (never a
    // blank one), records `savedErrorMessage` and emits a `savedFailed` notice.
    try {
      final saved = await _loadSavedArticles();
      emit(
        state.copyWith(
          section: FeedSection.saved,
          savedArticles: saved,
          clearSavedError: true,
        ),
      );
    } catch (error) {
      final message = _messageFor(error);
      emit(
        state.copyWith(
          section: FeedSection.saved,
          savedErrorMessage: message,
          notice: _notice(FeedNoticeKind.savedFailed, message),
        ),
      );
    }
  }

  Future<void> _onSavedReloadRequested(
    FeedSavedReloadRequested event,
    Emitter<FeedState> emit,
  ) async {
    try {
      final saved = await _loadSavedArticles();
      emit(state.copyWith(savedArticles: saved, clearSavedError: true));
    } catch (error) {
      _reportSavedFailure(emit, error);
    }
  }

  Future<void> _onSavedArticleRemoved(
    FeedSavedArticleRemoved event,
    Emitter<FeedState> emit,
  ) async {
    try {
      await _removeSavedArticle(event.article.identity);
      final saved = await _loadSavedArticles();
      emit(state.copyWith(savedArticles: saved, clearSavedError: true));
    } catch (error) {
      // Drop nothing locally: the row stays until the store really changed.
      _reportSavedFailure(emit, error);
    }
  }

  Future<void> _onSavedArticleRestored(
    FeedSavedArticleRestored event,
    Emitter<FeedState> emit,
  ) async {
    // Treat the undo as a short busy window: the store is written and re-read,
    // and listeners see that a reload happened even when the content did not
    // change (a second UNDO on an already saved article).
    final wasRefreshing = state.isRefreshing;
    emit(state.copyWith(isRefreshing: true));

    try {
      await _restoreSavedArticle(event.article);
      final saved = await _loadSavedArticles();
      emit(
        state.copyWith(
          savedArticles: saved,
          clearSavedError: true,
          isRefreshing: wasRefreshing,
        ),
      );
    } catch (error) {
      emit(state.copyWith(isRefreshing: wasRefreshing));
      // The visible list stays exactly as it was.
      _reportSavedFailure(emit, error);
    }
  }

  /// A broken saved read: keep today's status/quota untouched and record the
  /// failure where only the saved section looks.
  void _reportSavedFailure(Emitter<FeedState> emit, Object error) {
    final message = _messageFor(error);
    emit(
      state.copyWith(
        savedErrorMessage: message,
        notice: _notice(FeedNoticeKind.savedFailed, message),
      ),
    );
  }

  String _messageFor(Object error) => switch (error) {
    FeedFailure(:final message) => message,
    _ => 'Something went wrong. Try again.',
  };
}
