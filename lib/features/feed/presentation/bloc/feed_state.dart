import 'package:flutter/foundation.dart';

import '../../domain/entities/article.dart';

enum FeedStatus { initial, loading, ready, failure }

enum FeedNoticeKind { openedOnPhone, openFailed }

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
    this.isRefreshing = false,
    this.errorMessage,
    this.notice,
    this.lastUpdated,
  });

  const FeedState.initial()
    : status = FeedStatus.initial,
      articles = const <Article>[],
      isRefreshing = false,
      errorMessage = null,
      notice = null,
      lastUpdated = null;

  final FeedStatus status;

  /// Merged, today-only articles sorted newest first.
  final List<Article> articles;
  final bool isRefreshing;

  /// Last failure message; articles may still be present from the cache.
  final String? errorMessage;
  final FeedNotice? notice;
  final DateTime? lastUpdated;

  bool get hasArticles => articles.isNotEmpty;

  FeedState copyWith({
    FeedStatus? status,
    List<Article>? articles,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
    FeedNotice? notice,
    DateTime? lastUpdated,
  }) => FeedState(
    status: status ?? this.status,
    articles: articles ?? this.articles,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    notice: notice ?? this.notice,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedState &&
          status == other.status &&
          listEquals(articles, other.articles) &&
          isRefreshing == other.isRefreshing &&
          errorMessage == other.errorMessage &&
          notice == other.notice &&
          lastUpdated == other.lastUpdated;

  @override
  int get hashCode => Object.hash(
    status,
    Object.hashAll(articles),
    isRefreshing,
    errorMessage,
    notice,
    lastUpdated,
  );
}
