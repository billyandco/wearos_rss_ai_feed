import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
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
  bool _onScrollNotification(ScrollNotification notification) {
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
  void _pushDetail(Article article) {
    unawaited(context.router.push(ArticleDetailRoute(article: article)));
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.clock ?? DateTime.now)();

    return Scaffold(
      backgroundColor: kWearBackground,
      body: BlocListener<FeedBloc, FeedState>(
        listenWhen: (previous, current) =>
            !identical(current.articles, previous.articles) ||
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
                onNotification: _onScrollNotification,
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
                    Positioned(
                      top: 22,
                      left: 52,
                      right: 52,
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
                        child: _Header(inlineError: inlineError),
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
  const _Header({this.inlineError});

  final String? inlineError;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Opaque black pill so rows scrolling underneath never show through the
    // header text.
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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
                  'TODAY',
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
                  style: textTheme.labelSmall?.copyWith(color: kWearError),
                ),
              ),
          ],
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
    switch (state.status) {
      case FeedStatus.initial:
      case FeedStatus.loading:
        return const _LoadingView();
      case FeedStatus.failure:
        return _ErrorView(message: state.errorMessage);
      case FeedStatus.ready:
        if (!state.hasArticles) {
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
            itemCount: state.articles.length,
            itemBuilder: (context, index) {
              final article = state.articles[index];
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
