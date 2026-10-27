import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/router/app_router.gr.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/article.dart';
import '../bloc/feed_bloc.dart';
import '../bloc/feed_event.dart';
import '../bloc/feed_state.dart';
import 'article_tile.dart';

/// The single watch screen: merged, today-only AI news.
class FeedView extends StatefulWidget {
  const FeedView({super.key, this.clock, this.onOpenArticle});

  /// Injectable clock so relative times can be tested deterministically.
  final DateTime Function()? clock;

  /// Overrides how a single tap opens an article; defaults to pushing the
  /// detail route.
  final void Function(Article article)? onOpenArticle;

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  static const double _itemExtent = 116;

  /// Scroll deltas below this are noise (bounce, sub-pixel jitter).
  static const double _scrollDeadband = 0.5;

  final ValueNotifier<bool> _headerVisible = ValueNotifier<bool>(true);
  double _lastPixels = 0;

  @override
  void dispose() {
    _headerVisible.dispose();
    super.dispose();
  }

  /// Fades the header away while reading and brings it back on the way up.
  bool _onScrollNotification(
    ScrollNotification notification,
    FeedSection section,
  ) {
    // Only react to this list, never to a nested scroll view.
    if (notification.depth != 0) {
      return false;
    }

    // Start/end/overscroll notifications carry no reliable delta, and tracking
    // their pixels would inject a bogus jump after a silent correction.
    if (notification is! ScrollUpdateNotification) {
      return false;
    }

    final pixels = notification.metrics.pixels;
    final delta = notification.scrollDelta ?? (pixels - _lastPixels);
    _lastPixels = pixels;

    // In SAVED the header is both the mode indicator and the only way back to
    // today, so it is pinned: never faded, and therefore never armed with
    // IgnorePointer, whatever the scroll does.
    if (section == FeedSection.saved) {
      if (!_headerVisible.value) {
        _headerVisible.value = true;
      }
      return false;
    }

    final bool visible;
    if (pixels <= 0) {
      // At the top (or bouncing above it) the header always shows.
      visible = true;
    } else if (delta > _scrollDeadband) {
      visible = false; // scrolling down
    } else if (delta < -_scrollDeadband) {
      visible = true; // scrolling up
    } else {
      return false;
    }

    if (visible != _headerVisible.value) {
      _headerVisible.value = visible;
    }
    return false;
  }

  /// Brings the header back whenever a different list (or phase) arrives.
  ///
  /// Scroll notifications are the only other writer of [_headerVisible], so a
  /// replaced list would otherwise leave the header faded out forever.
  void _resetHeader() {
    if (_headerVisible.value && _lastPixels == 0) {
      return;
    }
    _headerVisible.value = true;
    _lastPixels = 0;
  }

  /// Refreshes and completes once the bloc is idle again, never hanging.
  Future<void> _refresh() {
    final bloc = context.read<FeedBloc>();
    if (bloc.state.isRefreshing) {
      return Future<void>.value();
    }
    // Subscribe before dispatching so the idle state cannot be missed.
    // The timeout is a pure safety net: the network budget is 15 s connect /
    // 90 s read, so a shorter one would retract the indicator mid-refresh.
    final done = bloc.stream
        .firstWhere((state) => !state.isRefreshing)
        .timeout(const Duration(seconds: 120), onTimeout: () => bloc.state);
    bloc.add(const FeedRefreshRequested());
    return done;
  }

  /// Opens the detail page for a single tapped article.
  ///
  /// Re-reads the saved store on return so a bookmark toggled on the detail
  /// page disappears from (or appears in) the saved section.
  Future<void> _pushDetail(Article article) async {
    final saved = context.read<FeedBloc>().state.savedArticles;
    final initiallySaved = saved.any(
      (item) => item.identity == article.identity,
    );

    await context.router.push(
      ArticleDetailRoute(article: article, initiallySaved: initiallySaved),
    );
    if (!mounted) {
      return;
    }
    context.read<FeedBloc>().add(const FeedSavedReloadRequested());
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.clock ?? DateTime.now)();

    return Scaffold(
      backgroundColor: kWearBackground,
      body: BlocListener<FeedBloc, FeedState>(
        listenWhen: (previous, current) =>
            !identical(current.articles, previous.articles) ||
            current.section != previous.section ||
            current.status != previous.status,
        listener: (context, state) => _resetHeader(),
        child: BlocListener<FeedBloc, FeedState>(
          listenWhen: (previous, current) =>
              current.notice != null && previous.notice != current.notice,
          listener: (context, state) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.notice!.message),
                  duration: const Duration(seconds: 3),
                ),
              );
          },
          child: BlocBuilder<FeedBloc, FeedState>(
            builder: (context, state) {
              final hasArticles = state.hasArticles;
              final inlineError = state.errorMessage != null && hasArticles
                  ? state.errorMessage
                  : null;

              return NotificationListener<ScrollNotification>(
                onNotification: (notification) =>
                    _onScrollNotification(notification, state.section),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _FeedBody(
                        state: state,
                        now: now,
                        itemExtent: _itemExtent,
                        onRefresh: _refresh,
                        onOpenArticle: widget.onOpenArticle ?? _pushDetail,
                      ),
                    ),
                    // In SAVED the header never fades, so rows scroll under
                    // it; an opaque band across the full 0–45 dp header strip
                    // cuts them on one clean line instead of letting the
                    // capsule's corner arc slice a glyph speck above it.
                    if (state.section == FeedSection.saved)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 45,
                        child: IgnorePointer(
                          child: ColoredBox(
                            key: Key('feed-saved-header-scrim'),
                            color: kWearBackground,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 44,
                      right: 44,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _headerVisible,
                        builder: (context, visible, child) {
                          return IgnorePointer(
                            ignoring: !visible,
                            child: SizedBox(
                              key: const Key('feed-header'),
                              child: AnimatedOpacity(
                                key: const Key('feed-header-opacity'),
                                opacity: visible ? 1 : 0,
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOut,
                                child: AnimatedSlide(
                                  offset: visible
                                      ? Offset.zero
                                      : const Offset(0, -0.7),
                                  duration: const Duration(milliseconds: 160),
                                  curve: Curves.easeOut,
                                  child: child,
                                ),
                              ),
                            ),
                          );
                        },
                        child: _Header(
                          label: state.section == FeedSection.today
                              ? 'TODAY'
                              : 'SAVED',
                          inlineError: state.section == FeedSection.today
                              ? inlineError
                              : null,
                          onTap: () => context.read<FeedBloc>().add(
                            const FeedSectionToggled(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label, required this.onTap, this.inlineError});

  /// `TODAY` or `SAVED`.
  final String label;

  /// Flips the feed between today's list and the saved list.
  final VoidCallback onTap;

  final String? inlineError;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // The visible pill is only ~23 dp tall. The tap target around it is a
    // 45 dp band that bottom-aligns the pill, so the pill stays visually at
    // y≈22 while the whole band is finger-sized.
    return SizedBox(
      height: 45,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('feed-header-toggle'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Semantics(
            button: true,
            label: label == 'SAVED'
                ? "Show today's articles"
                : 'Show saved articles',
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                // Opaque black pill so rows scrolling underneath never show
                // through the header text.
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: kWearBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                    if (inlineError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          inlineError!,
                          key: const Key('feed-inline-error'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: textTheme.labelSmall?.copyWith(
                            color: kWearError,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedBody extends StatelessWidget {
  const _FeedBody({
    required this.state,
    required this.now,
    required this.itemExtent,
    required this.onRefresh,
    required this.onOpenArticle,
  });

  final FeedState state;
  final DateTime now;
  final double itemExtent;
  final Future<void> Function() onRefresh;
  final void Function(Article article) onOpenArticle;

  @override
  Widget build(BuildContext context) {
    final articles = state.visibleArticles;

    if (state.section == FeedSection.saved) {
      return _buildSaved(context, articles);
    }

    switch (state.status) {
      case FeedStatus.initial:
      case FeedStatus.loading:
        return const _LoadingView();
      case FeedStatus.failure:
        return _ErrorView(message: state.errorMessage);
      case FeedStatus.ready:
        if (articles.isEmpty) {
          return const _EmptyView();
        }
        // Room for the overlaid header, which grows when it shows an error.
        final headerSpace = state.errorMessage == null ? 48.0 : 72.0;
        return RefreshIndicator(
          color: kWearAccent,
          backgroundColor: kWearSurface,
          displacement: 44,
          onRefresh: onRefresh,
          child: ListView.builder(
            key: const Key('feed-list'),
            padding: EdgeInsets.only(top: headerSpace, bottom: 34),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemExtent: itemExtent,
            itemCount: articles.length,
            itemBuilder: (context, index) {
              final article = articles[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ArticleTile(
                  article: article,
                  now: now,
                  onTap: () => onOpenArticle(article),
                  onOpenOnPhone: () =>
                      context.read<FeedBloc>().add(FeedArticleOpened(article)),
                ),
              );
            },
          ),
        );
    }
  }

  /// The saved list: no pull-to-refresh (a pull only reloads today's feed),
  /// and each row carries the bookmark marker and the long-press removal.
  Widget _buildSaved(BuildContext context, List<Article> articles) {
    if (articles.isEmpty) {
      final message = state.savedErrorMessage;
      return message == null
          ? const _SavedEmptyView()
          : _SavedErrorView(message: message);
    }

    return ListView.builder(
      key: const Key('saved-list'),
      padding: const EdgeInsets.only(top: 48, bottom: 34),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemExtent: itemExtent,
      itemCount: articles.length,
      itemBuilder: (context, index) {
        final article = articles[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ArticleTile(
            article: article,
            now: now,
            isSaved: true,
            semanticsHint: ArticleTile.savedSemanticsHint,
            onTap: () => onOpenArticle(article),
            onOpenOnPhone: () =>
                context.read<FeedBloc>().add(FeedArticleOpened(article)),
            onLongPress: () => _removeSaved(context, article),
          ),
        );
      },
    );
  }

  /// Removes one saved row, with haptic feedback and an UNDO escape hatch.
  void _removeSaved(BuildContext context, Article article) {
    final bloc = context.read<FeedBloc>();
    unawaited(HapticFeedback.mediumImpact());
    bloc.add(FeedSavedArticleRemoved(article));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Removed'),
          duration: const Duration(seconds: 4),
          // Keep "Removed" and UNDO on one line: the default 0.25 threshold
          // stacks them on a 192 dp watch, doubling the bar's height. The
          // tighter side padding is what lets the 13 dp copy share the row with
          // the action's 70 dp button inside a 152 dp bar.
          actionOverflowThreshold: 1,
          padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => bloc.add(FeedSavedArticleRestored(article)),
          ),
        ),
        // On a watch the bar must be fully on screen (and tappable) at once;
        // the default 250 ms entrance leaves UNDO untouchable for too long.
        snackBarAnimationStyle: const AnimationStyle(
          duration: Duration(milliseconds: 50),
          reverseDuration: Duration(milliseconds: 75),
        ),
      );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                key: Key('feed-loading'),
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Fetching today's AI news",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      key: const Key('feed-error'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 58),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 28, color: kWearMuted),
            const SizedBox(height: 10),
            Text(
              message ?? 'Could not load the news.',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('feed-retry'),
              onPressed: () =>
                  context.read<FeedBloc>().add(const FeedRefreshRequested()),
              style: FilledButton.styleFrom(
                minimumSize: const Size(104, 44),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      key: const Key('feed-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 58),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.newspaper_rounded, size: 28, color: kWearMuted),
            const SizedBox(height: 10),
            Text(
              'No AI news yet today',
              textAlign: TextAlign.center,
              style: textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              key: const Key('feed-empty-refresh'),
              onPressed: () =>
                  context.read<FeedBloc>().add(const FeedRefreshRequested()),
              style: TextButton.styleFrom(
                minimumSize: const Size(104, 44),
                foregroundColor: kWearAccent,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A failed saved read with nothing cached: the message, and no Retry button
/// (pulling only refreshes today's feed, so a retry would be a lie).
class _SavedErrorView extends StatelessWidget {
  const _SavedErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('saved-error'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 28, color: kWearMuted),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing bookmarked yet, plus the way back to today.
///
/// Deliberately short: on a 192 dp circle every extra line pushes the block
/// corners out of the visible area.
class _SavedEmptyView extends StatelessWidget {
  const _SavedEmptyView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      key: const Key('saved-empty'),
      // `top: 46` clears the header pill (which ends at 45 dp) so the title is
      // never painted under it; the bottom corners then sit on a ~117 dp chord,
      // wide enough for the 104 dp button on the 192 dp circle.
      padding: const EdgeInsets.only(top: 46, bottom: 8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bookmark_border_rounded,
                size: 20,
                color: kWearMuted,
              ),
              const SizedBox(height: 6),
              Text(
                'No saved articles yet',
                textAlign: TextAlign.center,
                style: textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('saved-empty-show-today'),
                onPressed: () =>
                    context.read<FeedBloc>().add(const FeedSectionToggled()),
                style: TextButton.styleFrom(
                  foregroundColor: kWearAccent,
                  minimumSize: const Size(104, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.newspaper_rounded, size: 16),
                label: const Text('Show today'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
