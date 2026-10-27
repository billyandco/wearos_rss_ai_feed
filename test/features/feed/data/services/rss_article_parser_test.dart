import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/services/rss_article_parser.dart';

import '../../../../support/feed_xml_builder.dart';

void main() {
  final now = DateTime(2026, 10, 27, 18);

  FeedParseInput inputFor(
    String xml, {
    String sourceName = 'The Decoder',
    String sourceUrl = 'https://the-decoder.com/feed/',
    DateTime? at,
  }) => FeedParseInput(
    xml: xml,
    sourceName: sourceName,
    sourceUrl: sourceUrl,
    now: at ?? now,
  );

  group('parseFeedXml normalization', () {
    test('normalizes every field into a local-time Article', () {
      final xml = feedXml([
        itemXml(
          title: '  Anthropic renews its pledge\n',
          pubDate: rfc822(DateTime(2026, 10, 27, 10)),
          description: '<p>Anthropic says it will keep <b>ads</b> out of Claude &amp; more.</p>',
          dcCreator: '  Matthias Bastian\n',
        ),
      ]);

      final articles = parseFeedXml(inputFor(xml));

      expect(articles, hasLength(1));
      final article = articles.single;
      expect(article.title, 'Anthropic renews its pledge');
      expect(article.link, 'https://example.com/articles/1');
      expect(article.guid, 'guid-1');
      expect(article.sourceName, 'The Decoder');
      expect(article.author, 'Matthias Bastian');
      expect(
        article.description,
        'Anthropic says it will keep ads out of Claude & more.',
      );
      expect(article.publishedAt.toUtc(), DateTime(2026, 10, 27, 10).toUtc());
      expect(article.publishedAt.isUtc, isFalse);
    });

    test('supports items without description or author (Hugging Face)', () {
      final xml = feedXml([
        itemXml(title: 'LitPivot', pubDate: rfc822(DateTime(2026, 10, 27, 10))),
      ]);

      final article = parseFeedXml(
        inputFor(xml, sourceName: 'Hugging Face Blog'),
      ).single;

      expect(article.description, isNull);
      expect(article.author, isNull);
      expect(article.sourceName, 'Hugging Face Blog');
    });

    test('falls back to content:encoded when description is absent', () {
      final xml = feedXml([
        itemXml(
          title: 'Encoded body',
          pubDate: rfc822(DateTime(2026, 10, 27, 10)),
          contentEncoded: '<p>Full body from <b>content:encoded</b>.</p>',
        ),
      ]);

      expect(
        parseFeedXml(inputFor(xml)).single.description,
        'Full body from content:encoded.',
      );
    });

    test('reads author from <author> when dc:creator is absent', () {
      final xml = feedXml([
        itemXml(
          pubDate: rfc822(DateTime(2026, 10, 27, 10)),
          author: 'jane@example.com (Jane Doe)',
        ),
      ]);

      expect(
        parseFeedXml(inputFor(xml)).single.author,
        'jane@example.com (Jane Doe)',
      );
    });

    test('falls back to the link when the guid is missing', () {
      final xml = feedXml([
        itemXml(
          guid: null,
          link: 'https://example.com/no-guid',
          pubDate: rfc822(DateTime(2026, 10, 27, 10)),
        ),
      ]);

      final article = parseFeedXml(inputFor(xml)).single;

      expect(article.guid, 'https://example.com/no-guid');
      expect(article.identity, article.link);
    });

    test('collapses whitespace and caps very long descriptions', () {
      final longText = '<p>${'word ' * 200}</p>';
      final xml = feedXml([
        itemXml(
          pubDate: rfc822(DateTime(2026, 10, 27, 10)),
          description: longText,
        ),
      ]);

      final description = parseFeedXml(inputFor(xml)).single.description!;

      expect(description.length, lessThanOrEqualTo(400));
      expect(description, endsWith('…'));
      expect(description, isNot(contains('  ')));
    });

    test('decodes escaped HTML in a non-CDATA description', () {
      final xml =
          '<?xml version="1.0"?><rss version="2.0"><channel><title>t</title>'
          '<item><title>Escaped</title><link>https://example.com/escaped</link>'
          '<guid>escaped</guid><pubDate>${rfc822(DateTime(2026, 10, 27, 10))}</pubDate>'
          '<description>&lt;p&gt;Fish &amp; chips&lt;/p&gt;</description>'
          '</item></channel></rss>';

      expect(parseFeedXml(inputFor(xml)).single.description, 'Fish & chips');
    });
  });

  group('parseFeedXml filtering', () {
    test('keeps only articles from the local day of now', () {
      final xml = feedXml([
        itemXml(
          guid: 'yesterday',
          title: 'Yesterday',
          pubDate: rfc822(DateTime(2026, 10, 26, 23)),
        ),
        itemXml(
          guid: 'today',
          title: 'Today',
          pubDate: rfc822(DateTime(2026, 10, 27, 9)),
        ),
        itemXml(
          guid: 'tomorrow',
          title: 'Tomorrow',
          pubDate: rfc822(DateTime(2026, 10, 28, 1)),
        ),
      ]);

      final articles = parseFeedXml(inputFor(xml));

      expect(articles.map((a) => a.guid), ['today']);
    });

    test('drops items without a usable date, title or link', () {
      final xml = feedXml([
        itemXml(title: 'Invalid date', guid: 'bad-date', pubDate: 'soon'),
        itemXml(title: 'Missing date', guid: 'no-date'),
        itemXml(
          title: '   ',
          guid: 'blank-title',
          pubDate: rfc822(DateTime(2026, 10, 27, 9)),
        ),
        itemXml(
          title: 'No link',
          guid: 'no-link',
          link: null,
          pubDate: rfc822(DateTime(2026, 10, 27, 9)),
        ),
        itemXml(
          title: 'Valid',
          guid: 'valid',
          pubDate: rfc822(DateTime(2026, 10, 27, 9)),
        ),
      ]);

      expect(parseFeedXml(inputFor(xml)).map((a) => a.guid), ['valid']);
    });

    test('returns an empty list for a feed without items', () {
      expect(parseFeedXml(inputFor(feedXml(const []))), isEmpty);
    });

    test('throws FeedParseFailure for malformed XML', () {
      expect(
        () => parseFeedXml(inputFor('<rss><channel><item>')),
        throwsA(isA<FeedParseFailure>()),
      );
    });
  });

  group('realistic feed fixture', () {
    test('parses The Decoder feed fields from CDATA HTML', () {
      final xml = File('test/fixtures/the_decoder.xml').readAsStringSync();
      final articles = parseFeedXml(
        inputFor(
          xml,
          // Anchor on the newest item's own local day so the assertion never
          // depends on the timezone of the machine running the tests.
          at: DateTime.parse('2026-10-27T11:20:51Z').toLocal(),
        ),
      );

      expect(articles, isNotEmpty);
      final first = articles.first;
      expect(first.sourceName, 'The Decoder');
      expect(first.guid, 'https://the-decoder.com/?p=42031');
      expect(first.author, 'Matthias Bastian');
      expect(first.description, isNotNull);
      expect(first.description, contains('keep ads out of Claude'));
      expect(first.description, isNot(contains('<p>')));
      expect(first.link, startsWith('https://the-decoder.com/'));
    });
  });

  group('parseFeedXmlInIsolate', () {
    test('produces the same result on a background isolate', () async {
      final xml = feedXml([
        itemXml(
          guid: 'isolated',
          title: 'Isolated',
          pubDate: rfc822(DateTime(2026, 10, 27, 10)),
          description: '<p>Parsed off the UI isolate.</p>',
        ),
      ]);

      final articles = await parseFeedXmlInIsolate(inputFor(xml));

      expect(articles.single.guid, 'isolated');
      expect(articles.single.description, 'Parsed off the UI isolate.');
    });
  });
}
