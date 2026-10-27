import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/feed_source.dart';

/// Builds local-time articles for tests without repeating every field.
Article article({
  String guid = 'guid-1',
  String title = 'A headline about AI',
  String link = 'https://example.com/articles/1',
  String sourceName = 'The Decoder',
  DateTime? publishedAt,
  String? description = 'A short summary of the article.',
  String? author = 'Jane Doe',
}) => Article(
  guid: guid,
  title: title,
  link: link,
  sourceName: sourceName,
  publishedAt: publishedAt ?? DateTime(2026, 10, 27, 9, 30),
  description: description,
  author: author,
);

const feedSource = FeedSource(
  name: 'The Decoder',
  url: 'https://the-decoder.com/feed/',
);
