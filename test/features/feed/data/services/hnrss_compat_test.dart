import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/services/rss_article_parser.dart';

import '../../../../support/feed_xml_builder.dart';

/// Compatibility coverage for the hnrss.org frontpage feed
/// (`https://hnrss.org/frontpage`, display name `Hacker News`).
///
/// Shape of the live feed (standard RSS 2.0): `<rss version="2.0">` with
/// `xmlns:dc` + `xmlns:atom`, items carrying a CDATA `<title>`, CDATA HTML
/// `<description>` (`<p>Article URL: ...</p><p>Comments URL: ...</p>`
/// `<p>Points: N</p><p># Comments: M</p>`), an RFC 822 `<pubDate>` with
/// `+0000`, a `<link>` to the article, a `<dc:creator>`, and a
/// `<guid isPermaLink="false">` holding the HN comments URL (not a permalink
/// to the article).
void main() {
  group('hnrss.org frontpage compatibility', () {
    test('parses an hnrss.org frontpage item', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>Hacker News Frontpage</title>
    <link>https://news.ycombinator.com</link>
    <description>Hacker News frontpage via hnrss.org</description>
    <item>
      <title><![CDATA[Show HN: Someone's frontpage experiment]]></title>
      <description><![CDATA[<p>Article URL: <a href="https://example.com/some-article">https://example.com/some-article</a></p><p>Comments URL: <a href="https://news.ycombinator.com/item?id=50261819">https://news.ycombinator.com/item?id=50261819</a></p><p>Points: 342</p><p># Comments: 128</p>]]></description>
      <pubDate>Tue, 27 Oct 2026 16:40:15 +0000</pubDate>
      <link>https://example.com/some-article</link>
      <dc:creator><![CDATA[gumby]]></dc:creator>
      <guid isPermaLink="false">https://news.ycombinator.com/item?id=50261819</guid>
    </item>
  </channel>
</rss>
''';

      final articles = parseFeedXml(
        FeedParseInput(
          xml: xml,
          sourceName: 'Hacker News',
          sourceUrl: 'https://hnrss.org/frontpage',
          // Anchor on the item's own local day so the assertion never depends
          // on the timezone of the machine running the tests.
          now: DateTime.parse('2026-10-27T16:40:15Z').toLocal(),
        ),
      );

      expect(articles, hasLength(1));
      final article = articles.single;
      expect(article.title, "Show HN: Someone's frontpage experiment");
      // The link must be the article URL (<link>), NOT the guid comments URL.
      expect(article.link, 'https://example.com/some-article');
      expect(article.author, 'gumby');
      expect(
        article.publishedAt.toUtc(),
        DateTime.utc(2026, 10, 27, 16, 40, 15),
      );
      expect(article.description, isNotNull);
      expect(article.description, contains('Points: 342'));
      expect(article.description, contains('# Comments: 128'));
      expect(article.description, isNot(contains('<p>')));
      expect(article.description, isNot(contains('<a')));
      expect(article.description!.length, lessThanOrEqualTo(400));
      // The guid is the HN comments URL; it doubles as the identity fallback.
      expect(article.guid, 'https://news.ycombinator.com/item?id=50261819');
    });

    test(
      'drops an hnrss item with an unparseable date but keeps its siblings',
      () {
        final xml = feedXml([
          itemXml(
            title: "Show HN: Someone's frontpage experiment",
            link: 'https://example.com/some-article',
            guid: 'https://news.ycombinator.com/item?id=50261819',
            pubDate: 'not a date',
            description:
                '<p>Article URL: https://example.com/some-article</p>'
                '<p>Comments URL: https://news.ycombinator.com/item?id=50261819</p>'
                '<p>Points: 342</p><p># Comments: 128</p>',
            dcCreator: 'gumby',
          ),
          itemXml(
            title: 'A valid sibling story',
            link: 'https://example.com/sibling-story',
            guid: 'https://news.ycombinator.com/item?id=50261820',
            pubDate: rfc822WithOffset(DateTime(2026, 10, 27, 12)),
            description: '<p>Points: 10</p><p># Comments: 2</p>',
            dcCreator: 'pg',
          ),
        ]);

        final articles = parseFeedXml(
          FeedParseInput(
            xml: xml,
            sourceName: 'Hacker News',
            sourceUrl: 'https://hnrss.org/frontpage',
            now: DateTime(2026, 10, 27, 18),
          ),
        );

        expect(articles, hasLength(1));
        expect(articles.single.title, 'A valid sibling story');
        expect(
          articles.single.guid,
          'https://news.ycombinator.com/item?id=50261820',
        );
      },
    );
  });
}
