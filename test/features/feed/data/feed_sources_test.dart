import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/feed_sources.dart';

void main() {
  test('configures the seven verified RSS 2.0 sources in order', () {
    expect(kFeedSources, hasLength(7));
    expect(kFeedSources.map((source) => source.name), [
      'The Decoder',
      'TechCrunch AI',
      'OpenAI News',
      'Hugging Face Blog',
      'Interconnects',
      'MIT Tech Review AI',
      'Ars Technica AI',
    ]);
    expect(kFeedSources.map((source) => source.url), [
      'https://the-decoder.com/feed/',
      'https://techcrunch.com/category/artificial-intelligence/feed/',
      'https://openai.com/news/rss.xml',
      'https://huggingface.co/blog/feed.xml',
      'https://www.interconnects.ai/feed',
      'https://www.technologyreview.com/topic/artificial-intelligence/feed/',
      'https://arstechnica.com/ai/feed/',
    ]);
    expect(
      kFeedSources.every((source) => source.url.startsWith('https://')),
      isTrue,
    );
  });
}
