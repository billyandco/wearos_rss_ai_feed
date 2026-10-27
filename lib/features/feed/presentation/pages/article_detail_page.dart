import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/errors/feed_failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/relative_time.dart';
import '../../domain/entities/article.dart';
import '../../domain/usecases/is_article_saved.dart';
import '../../domain/usecases/open_article_on_phone.dart';
import '../../domain/usecases/toggle_saved_article.dart';

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
    this.initiallySaved = false,
    this.onToggleSave,
    this.isArticleSaved,
  });

  final Article article;

  /// Injectable clock so relative times can be tested deterministically.
  final DateTime Function()? clock;

  /// Overrides how the link reaches the phone; defaults to the use case.
  final Future<void> Function(Article article)? onOpenOnPhone;

  /// Whether the store already holds this article, so the very first frame
  /// shows the right label instead of flipping after an async read.
  final bool initiallySaved;

  /// Overrides how the bookmark is written; defaults to the use case.
  final Future<void> Function(Article article)? onToggleSave;

  /// Overrides the authoritative store read that confirms [initiallySaved].
  final Future<bool> Function(String identity)? isArticleSaved;

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  /// True from the tap until the phone answers, so a second tap is ignored.
  bool _opening = false;

  /// The bookmark state shown on screen, seeded synchronously from the route so
  /// the first frame already carries the right label.
  bool _saved = false;

  /// True while a bookmark write is in flight, so repeat taps are ignored.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.initiallySaved;
    unawaited(_resolveSaved());
  }

  /// Confirms the optimistic [ArticleDetailPage.initiallySaved] against the
  /// store; a broken store keeps the optimistic label (the write reports it).
  Future<void> _resolveSaved() async {
    final check =
        widget.isArticleSaved ?? (identity) => sl<IsArticleSaved>()(identity);

    try {
      final saved = await check(widget.article.identity);
      // A bookmark toggled while this read was in flight already answered the
      // question, so the user's action wins over the now stale read.
      if (_saving || _saved != widget.initiallySaved) {
        return;
      }
      if (!mounted || saved == _saved) {
        return;
      }
      setState(() => _saved = saved);
    } catch (_) {
      // Best effort: the button already shows the last known state.
    }
  }

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

  /// Bookmarks or un-bookmarks the article, keeping the label while writing.
  Future<void> _toggleSave() async {
    if (_saving) {
      return;
    }
    final wasSaved = _saved;
    final injected = widget.onToggleSave;

    setState(() => _saving = true);

    try {
      final bool saved;
      if (injected != null) {
        // The seam only reports completion; the toggle flips the known state.
        await injected(widget.article);
        saved = !wasSaved;
      } else {
        saved = await sl<ToggleSavedArticle>()(widget.article);
      }
      if (!mounted) {
        return;
      }
      setState(() => _saved = saved);
      _finish(saved ? 'Saved' : 'Removed from saved');
    } catch (error) {
      _finish(_messageFor(error));
    }
  }

  /// Reports the outcome, unless the page is already gone.
  void _finish(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _opening = false;
      _saving = false;
    });
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
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.phone_android_rounded, size: 18),
                label: const Text('Open on phone'),
              ),
              const SizedBox(height: 8),
              // A quiet text action under the primary filled button: a second
              // filled button would compete, and M3's tonal variant resolves
              // to lavender.
              TextButton.icon(
                key: const Key('article-detail-save'),
                onPressed: () => unawaited(_toggleSave()),
                style: TextButton.styleFrom(
                  foregroundColor: kWearAccent,
                  minimumSize: const Size.fromHeight(44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                // The glyph is driven by the same `_saved` flag as the label, so
                // both flip on one frame and neither moves on a failed write.
                icon: Icon(
                  _saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                  size: 16,
                ),
                label: Text(_saved ? 'Saved' : 'Save article'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
