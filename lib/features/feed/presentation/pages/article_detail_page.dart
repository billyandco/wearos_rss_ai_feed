import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/errors/feed_failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/relative_time.dart';
import '../../domain/entities/article.dart';
import '../../domain/usecases/open_article_on_phone.dart';

/// The whole article, opened by a single tap on a feed row.
///
/// The summary is shown in full (no clamps) and a button at the end of the
/// scroll hands the link to the paired phone, mirroring the double tap on the
/// feed.
@RoutePage()
class ArticleDetailPage extends StatefulWidget {
  const ArticleDetailPage({
    super.key,
    required this.article,
    this.clock,
    this.onOpenOnPhone,
  });

  final Article article;

  /// Injectable clock so relative times can be tested deterministically.
  final DateTime Function()? clock;

  /// Overrides how the link reaches the phone; defaults to the use case.
  final Future<void> Function(Article article)? onOpenOnPhone;

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  /// True from the tap until the phone answers, so a second tap is ignored.
  bool _opening = false;

  Future<void> _openOnPhone() async {
    if (_opening) {
      return;
    }
    final open =
        widget.onOpenOnPhone ?? (article) => sl<OpenArticleOnPhone>()(article);

    setState(() => _opening = true);

    try {
      await open(widget.article);
      _finish('Opening on your phone');
    } catch (error) {
      _finish(_messageFor(error));
    }
  }

  /// Reports the outcome, unless the page is already gone.
  void _finish(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _opening = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  /// Same mapping as the feed bloc, so both surfaces speak one language.
  String _messageFor(Object error) => switch (error) {
    FeedFailure(:final message) => message,
    _ => 'Something went wrong. Try again.',
  };

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final now = (widget.clock ?? DateTime.now)();
    final textTheme = Theme.of(context).textTheme;
    final description = article.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    // Insets stay proportional to the display, but tight enough to use the
    // width a round screen actually has. The generous trailing space lets the
    // button be scrolled up into the wide centre band instead of the narrow
    // bottom chord, and nothing is pinned.
    final d = MediaQuery.sizeOf(context).shortestSide;
    final hPad = d * 0.06;
    final topPad = d * 0.05;
    final trailPad = d * 0.30;

    return Scaffold(
      key: const Key('article-detail'),
      backgroundColor: kWearBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(hPad, topPad, hPad, trailPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Hero(
                tag: 'article-hero-${article.identity}',
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: kWearSurface,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              article.sourceName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: kWearAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Text(
                              '·',
                              style: textTheme.labelSmall?.copyWith(
                                color: kWearMuted,
                              ),
                            ),
                          ),
                          Text(
                            formatRelativeTime(article.publishedAt, now: now),
                            style: textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        article.title,
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      if (hasDescription) ...[
                        const SizedBox(height: 6),
                        Text(description, style: textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: d * 0.08),
              FilledButton.icon(
                key: const Key('article-detail-open-on-phone'),
                onPressed: _opening ? null : () => unawaited(_openOnPhone()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: const Icon(Icons.phone_android_rounded, size: 18),
                label: const Text('Open on phone'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
