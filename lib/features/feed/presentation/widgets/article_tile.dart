import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/relative_time.dart';
import '../../domain/entities/article.dart';

/// One compact article row: source + relative time, title, optional summary.
///
/// A single tap opens the article's detail page; double-tapping hands the link
/// to the paired phone. The whole row is the tap target, which keeps both
/// gestures usable on a 1.2" screen.
class ArticleTile extends StatelessWidget {
  const ArticleTile({
    super.key,
    required this.article,
    required this.now,
    required this.onOpenOnPhone,
    this.onTap,
  });

  final Article article;
  final DateTime now;
  final VoidCallback onOpenOnPhone;

  /// Called on a single tap, once the double-tap window has elapsed.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final description = article.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    return Semantics(
      button: true,
      label: '${article.title}. ${article.sourceName}.',
      hint: 'Tap to read, double tap to open on your phone',
      child: Padding(
        key: ValueKey<String>('article-row-${article.identity}'),
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Hero(
          tag: 'article-hero-${article.identity}',
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: kWearSurface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onTap,
                onDoubleTap: onOpenOnPhone,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      const SizedBox(height: 2),
                      Text(
                        article.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                      if (hasDescription) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          key: ValueKey<String>(
                            'article-description-${article.identity}',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
