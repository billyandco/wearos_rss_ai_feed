import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/curved_list_view.dart';
import '../bloc/feed_bloc.dart';
import '../bloc/feed_event.dart';
import '../bloc/feed_state.dart';
import 'article_tile.dart';

/// The single watch screen: merged, today-only AI news.
class FeedView extends StatelessWidget {
  const FeedView({super.key, this.clock});

  /// Injectable clock so relative times can be tested deterministically.
  final DateTime Function()? clock;

  static const double _itemExtent = 116;

  @override
  Widget build(BuildContext context) {
    final now = (clock ?? DateTime.now)();

    return Scaffold(
      backgroundColor: kWearBackground,
      body: BlocListener<FeedBloc, FeedState>(
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

            return Stack(
              children: [
                Positioned.fill(
                  child: _FeedBody(
                    state: state,
                    now: now,
                    itemExtent: _itemExtent,
                    topPadding: inlineError == null ? 76 : 104,
                  ),
                ),
                Positioned(
                  top: 22,
                  left: 52,
                  right: 52,
                  child: _Header(
                    isRefreshing: state.isRefreshing,
                    inlineError: inlineError,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isRefreshing, this.inlineError});

  final bool isRefreshing;
  final String? inlineError;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TODAY',
              style: textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            SizedBox(
              width: 48,
              height: 48,
              child: isRefreshing
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          key: Key('feed-refreshing'),
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : IconButton(
                      key: const Key('feed-refresh'),
                      tooltip: "Refresh today's news",
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      onPressed: () => context.read<FeedBloc>().add(
                        const FeedRefreshRequested(),
                      ),
                      icon: const Icon(Icons.refresh_rounded),
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
    );
  }
}

class _FeedBody extends StatelessWidget {
  const _FeedBody({
    required this.state,
    required this.now,
    required this.itemExtent,
    required this.topPadding,
  });

  final FeedState state;
  final DateTime now;
  final double itemExtent;
  final double topPadding;

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
        return CurvedListView(
          itemCount: state.articles.length,
          itemExtent: itemExtent,
          topPadding: topPadding,
          bottomPadding: 34,
          itemBuilder: (context, index) {
            final article = state.articles[index];
            return ArticleTile(
              article: article,
              now: now,
              onOpenOnPhone: () =>
                  context.read<FeedBloc>().add(FeedArticleOpened(article)),
            );
          },
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
