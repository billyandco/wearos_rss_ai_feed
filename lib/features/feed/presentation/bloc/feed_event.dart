import '../../domain/entities/article.dart';

/// Inputs accepted by [FeedBloc].
sealed class FeedEvent {
  const FeedEvent();
}

/// Screen opened: show cache immediately, then refresh in the background.
final class FeedStarted extends FeedEvent {
  const FeedStarted();
}

/// Manual refresh (pull-to-refresh, retry button, header refresh).
final class FeedRefreshRequested extends FeedEvent {
  const FeedRefreshRequested();
}

/// The user double-tapped an article row.
final class FeedArticleOpened extends FeedEvent {
  const FeedArticleOpened(this.article);

  final Article article;
}
