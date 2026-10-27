import 'package:flutter/foundation.dart';

import '../../domain/entities/article.dart';

enum FeedStatus { initial, loading, ready, failure }

enum FeedNoticeKind { openedOnPhone, openFailed, savedFailed }

/// Which list the single watch screen is showing.
enum FeedSection { today, saved }

/// One-shot user feedback (opening on the phone / failed to reach it).
///
/// [id] makes consecutive notices distinguishable so the UI can show the same
/// message twice in a row.
@immutable
class FeedNotice {
  const FeedNotice({
    required this.id,
    required this.kind,
    required this.message,
  });

  final int id;
  final FeedNoticeKind kind;
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedNotice &&
          id == other.id &&
          kind == other.kind &&
          message == other.message;

  @override
  int get hashCode => Object.hash(id, kind, message);
}

@immutable
class FeedState {
  const FeedState({
    required this.status,
    this.articles = const <Article>[],
    this.section = FeedSection.today,
    this.savedArticles = const <Article>[],
    this.isRefreshing = false,
    this.errorMessage,
    this.savedErrorMessage,
    this.notice,
    this.lastUpdated,
  });

  const FeedState.initial()
    : status = FeedStatus.initial,
      articles = const <Article>[],
      section = FeedSection.today,
      savedArticles = const <Article>[],
      isRefreshing = false,
      errorMessage = null,
      savedErrorMessage = null,
      notice = null,
      lastUpdated = null;

  final FeedStatus status;

  /// Merged, today-only articles sorted newest first.
  final List<Article> articles;
  final FeedSection section;

  /// Bookmarked articles, newest first (ordering comes from the use case).
  final List<Article> savedArticles;
  final bool isRefreshing;

  /// Last failure message; articles may still be present from the cache.
  final String? errorMessage;

  /// Last failure message of the saved store, independent of [errorMessage]:
  /// a broken saved read must not claim the today feed is broken.
  final String? savedErrorMessage;
  final FeedNotice? notice;
  final DateTime? lastUpdated;

  bool get hasArticles => articles.isNotEmpty;

  /// The list for the active [section].
  List<Article> get visibleArticles => switch (section) {
    FeedSection.today => articles,
    FeedSection.saved => savedArticles,
  };

  /// Whether anything has been bookmarked.
  bool get hasSavedArticles => savedArticles.isNotEmpty;

  FeedState copyWith({
    FeedStatus? status,
    List<Article>? articles,
    FeedSection? section,
    List<Article>? savedArticles,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
    String? savedErrorMessage,
    bool clearSavedError = false,
    FeedNotice? notice,
    DateTime? lastUpdated,
  }) => FeedState(
    status: status ?? this.status,
    articles: articles ?? this.articles,
    section: section ?? this.section,
    savedArticles: savedArticles ?? this.savedArticles,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    savedErrorMessage: clearSavedError
        ? null
        : (savedErrorMessage ?? this.savedErrorMessage),
    notice: notice ?? this.notice,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedState &&
          status == other.status &&
          listEquals(articles, other.articles) &&
          section == other.section &&
          listEquals(savedArticles, other.savedArticles) &&
          isRefreshing == other.isRefreshing &&
          errorMessage == other.errorMessage &&
          savedErrorMessage == other.savedErrorMessage &&
          notice == other.notice &&
          lastUpdated == other.lastUpdated;

  @override
  int get hashCode => Object.hash(
    status,
    Object.hashAll(articles),
    section,
    Object.hashAll(savedArticles),
    isRefreshing,
    errorMessage,
    savedErrorMessage,
    notice,
    lastUpdated,
  );
}
