import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/feed_sources.dart';

void main() {
  test('configures the eight verified RSS 2.0 sources in order', () {
    expect(kFeedSources, hasLength(8));
    expect(kFeedSources.map((source) => source.name), [
      'The Decoder',
      'TechCrunch AI',
      'OpenAI News',
      'Hugging Face Blog',
      'Interconnects',
      'MIT Tech Review AI',
      'Ars Technica AI',
      'Hacker News',
    ]);
    expect(kFeedSources.map((source) => source.url), [
      'https://the-decoder.com/feed/',
      'https://techcrunch.com/category/artificial-intelligence/feed/',
      'https://openai.com/news/rss.xml',
      'https://huggingface.co/blog/feed.xml',
      'https://www.interconnects.ai/feed',
      'https://www.technologyreview.com/topic/artificial-intelligence/feed/',
      'https://arstechnica.com/ai/feed/',
      'https://hnrss.org/frontpage',
    ]);
    expect(
      kFeedSources.every((source) => source.url.startsWith('https://')),
      isTrue,
    );
  });

  test('includes the Hacker News frontpage feed', () {
    expect(
      kFeedSources.any(
        (source) =>
            source.name == 'Hacker News' &&
            source.url == 'https://hnrss.org/frontpage',
      ),
      isTrue,
    );
    expect(kFeedSources.last.name, 'Hacker News');
    expect(kFeedSources.last.url, 'https://hnrss.org/frontpage');
  });
}
