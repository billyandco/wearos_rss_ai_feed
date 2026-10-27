import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/relative_time.dart';
import '../../domain/entities/article.dart';

/// One compact article row: source + relative time, title, optional summary.
///
/// Double-tapping hands the link to the paired phone; the whole row is the tap
/// target, which keeps it usable on a 1.2" screen.
class ArticleTile extends StatelessWidget {
  const ArticleTile({
    super.key,
    required this.article,
    required this.now,
    required this.onOpenOnPhone,
  });

  final Article article;
  final DateTime now;
  final VoidCallback onOpenOnPhone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final description = article.description?.trim();
    final hasDescription = description != null && description.isNotEmpty;

    return Semantics(
      button: true,
      label: '${article.title}. ${article.sourceName}.',
      hint: 'Double tap to open on your phone',
      child: GestureDetector(
        key: ValueKey<String>('article-row-${article.identity}'),
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onOpenOnPhone,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kWearSurface,
            borderRadius: BorderRadius.circular(22),
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
                      style: textTheme.labelSmall?.copyWith(color: kWearMuted),
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
    );
  }
}
