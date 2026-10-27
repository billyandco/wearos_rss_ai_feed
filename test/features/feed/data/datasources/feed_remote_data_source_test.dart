import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/feed_remote_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/services/rss_article_parser.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/feed_source.dart';

import '../../../../support/article_factory.dart';
import '../../../../support/fake_http_adapter.dart';
import '../../../../support/feed_xml_builder.dart';

void main() {
  final now = DateTime(2026, 10, 27, 18);
  const sources = [
    FeedSource(name: 'The Decoder', url: 'https://a.example/feed/'),
    FeedSource(name: 'Hugging Face Blog', url: 'https://b.example/feed.xml'),
  ];

  Dio dioWith(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;

  test(
    'requests every source as plain text and parses in the background',
    () async {
      final adapter = FakeHttpClientAdapter((options) {
        if (options.uri.toString() == sources.first.url) {
          return xmlResponse(
            feedXml([
              itemXml(
                guid: 'a-1',
                title: 'From A',
                pubDate: rfc822(now.subtract(const Duration(hours: 1))),
              ),
            ]),
          );
        }
        return xmlResponse(
          feedXml([
            itemXml(
              guid: 'b-1',
              title: 'From B',
              link: 'https://b.example/articles/1',
              pubDate: rfc822(now.subtract(const Duration(hours: 2))),
            ),
          ]),
        );
      });

      final dataSource = DioFeedRemoteDataSource(
        dioWith(adapter),
        parser: parseFeedXml,
      );

      final articles = await dataSource.fetchArticles(sources, now: now);

      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.map((request) => request.uri.toString()),
        unorderedEquals(sources.map((source) => source.url)),
      );
      expect(
        adapter.requests.every(
          (request) => request.responseType == ResponseType.plain,
        ),
        isTrue,
        reason: 'RSS is parsed by xml, not by Dio\'s JSON transformer',
      );
      expect(articles.map((a) => a.guid), containsAll(['a-1', 'b-1']));
      expect(
        articles.map((a) => a.sourceName),
        containsAll(['The Decoder', 'Hugging Face Blog']),
      );
    },
  );

  test('keeps working when a single source fails', () async {
    final adapter = FakeHttpClientAdapter((options) {
      if (options.uri.toString() == sources.first.url) {
        return xmlResponse('upstream exploded', statusCode: 503);
      }
      return xmlResponse(
        feedXml([
          itemXml(
            guid: 'survivor',
            pubDate: rfc822(now.subtract(const Duration(minutes: 5))),
          ),
        ]),
      );
    });

    final dataSource = DioFeedRemoteDataSource(
      dioWith(adapter),
      parser: parseFeedXml,
    );

    final articles = await dataSource.fetchArticles(sources, now: now);

    expect(articles.map((a) => a.guid), ['survivor']);
  });

  test('keeps working when a single source returns unparseable XML', () async {
    final adapter = FakeHttpClientAdapter((options) {
      if (options.uri.toString() == sources.first.url) {
        return xmlResponse('<rss><channel><item>');
      }
      return xmlResponse(
        feedXml([
          itemXml(
            guid: 'good-feed',
            pubDate: rfc822(now.subtract(const Duration(minutes: 5))),
          ),
        ]),
      );
    });

    final dataSource = DioFeedRemoteDataSource(
      dioWith(adapter),
      parser: parseFeedXml,
    );

    expect(
      (await dataSource.fetchArticles(sources, now: now)).map((a) => a.guid),
      ['good-feed'],
    );
  });

  test('throws FeedUnavailableFailure only when every source fails', () async {
    final adapter = FakeHttpClientAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'offline',
      ),
    );
    final dataSource = DioFeedRemoteDataSource(dioWith(adapter));

    await expectLater(
      dataSource.fetchArticles(sources, now: now),
      throwsA(isA<FeedUnavailableFailure>()),
    );
  });

  test('passes source metadata and the fetch date to the parser', () async {
    final captured = <FeedParseInput>[];
    final adapter = FakeHttpClientAdapter(
      (options) => xmlResponse('<rss version="2.0"><channel/></rss>'),
    );
    final dataSource = DioFeedRemoteDataSource(
      dioWith(adapter),
      parser: (input) async {
        captured.add(input);
        return <Article>[];
      },
    );

    await dataSource.fetchArticles(sources, now: now);

    expect(captured, hasLength(2));
    expect(
      captured.map((input) => input.sourceName),
      containsAll(sources.map((s) => s.name)),
    );
    expect(captured.every((input) => input.now == now), isTrue);
    expect(captured.map((input) => input.xml), everyElement(isNotEmpty));
  });

  test('wraps unexpected parser errors per source', () async {
    var calls = 0;
    final adapter = FakeHttpClientAdapter(
      (options) => xmlResponse('<rss version="2.0"><channel/></rss>'),
    );
    final dataSource = DioFeedRemoteDataSource(
      dioWith(adapter),
      parser: (input) async {
        calls++;
        if (calls == 1) {
          throw StateError('parser bug');
        }
        return [article(guid: 'only', sourceName: input.sourceName)];
      },
    );

    final articles = await dataSource.fetchArticles(sources, now: now);

    expect(articles.map((a) => a.guid), ['only']);
  });
}
