import '../domain/entities/feed_source.dart';

/// The verified RSS 2.0 sources that make up the merged feed.
///
/// Hardcoded by design: the watch app has one curated reading list and no
/// source management UI.
const List<FeedSource> kFeedSources = <FeedSource>[
  FeedSource(name: 'The Decoder', url: 'https://the-decoder.com/feed/'),
  FeedSource(
    name: 'TechCrunch AI',
    url: 'https://techcrunch.com/category/artificial-intelligence/feed/',
  ),
  FeedSource(name: 'OpenAI News', url: 'https://openai.com/news/rss.xml'),
  FeedSource(
    name: 'Hugging Face Blog',
    url: 'https://huggingface.co/blog/feed.xml',
  ),
  FeedSource(name: 'Interconnects', url: 'https://www.interconnects.ai/feed'),
  FeedSource(
    name: 'MIT Tech Review AI',
    url: 'https://www.technologyreview.com/topic/artificial-intelligence/feed/',
  ),
  FeedSource(name: 'Ars Technica AI', url: 'https://arstechnica.com/ai/feed/'),
];
