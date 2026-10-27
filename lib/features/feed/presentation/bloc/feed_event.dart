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

/// The user switched between today's feed and the saved list.
final class FeedSectionToggled extends FeedEvent {
  const FeedSectionToggled();
}

/// The saved list should be re-read (for example after returning from the
/// detail page).
final class FeedSavedReloadRequested extends FeedEvent {
  const FeedSavedReloadRequested();
}

/// The user un-bookmarked [article] from the saved list.
final class FeedSavedArticleRemoved extends FeedEvent {
  const FeedSavedArticleRemoved(this.article);

  final Article article;
}

/// The user pressed UNDO after un-bookmarking [article].
final class FeedSavedArticleRestored extends FeedEvent {
  const FeedSavedArticleRestored(this.article);

  final Article article;
}
