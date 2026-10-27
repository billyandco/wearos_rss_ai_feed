import 'dart:async';

import 'package:dio/dio.dart';

import '../../../../core/errors/feed_failure.dart';
import '../../domain/entities/article.dart';
import '../../domain/entities/feed_source.dart';
import '../services/rss_article_parser.dart';

/// Signature of the feed parser, injectable so tests can avoid spawning
/// isolates (production uses [parseFeedXmlInIsolate]).
typedef FeedParser = FutureOr<List<Article>> Function(FeedParseInput input);

abstract interface class FeedRemoteDataSource {
  /// Downloads and normalizes every source. [now] is forwarded to the parser
  /// so only today's items leave the background isolate.
  Future<List<Article>> fetchArticles(
    List<FeedSource> sources, {
    required DateTime now,
  });
}

class DioFeedRemoteDataSource implements FeedRemoteDataSource {
  DioFeedRemoteDataSource(this._dio, {FeedParser? parser})
    : _parser = parser ?? parseFeedXmlInIsolate;

  static const String userAgent = 'WearRssAiFeed/1.0 (Wear OS)';

  final Dio _dio;
  final FeedParser _parser;

  @override
  Future<List<Article>> fetchArticles(
    List<FeedSource> sources, {
    required DateTime now,
  }) async {
    if (sources.isEmpty) {
      return const <Article>[];
    }

    Object? firstFailure;

    final settled = await Future.wait(
      sources.map((source) async {
        try {
          final xml = await _download(source);
          return await _parser(
            FeedParseInput(
              xml: xml,
              sourceName: source.name,
              sourceUrl: source.url,
              now: now,
            ),
          );
        } catch (error) {
          firstFailure ??= error;
          return null;
        }
      }),
    );

    final successful = settled.whereType<List<Article>>().toList();

    // A single flaky feed should not blank the watch; only a total failure is
    // surfaced to the user.
    if (successful.isEmpty) {
      throw FeedUnavailableFailure(
        'Could not reach any news source.',
        cause: firstFailure,
      );
    }

    return successful.expand((articles) => articles).toList(growable: false);
  }

  Future<String> _download(FeedSource source) async {
    try {
      final response = await _dio.get<String>(
        source.url,
        options: Options(
          responseType: ResponseType.plain,
          headers: const <String, String>{
            'User-Agent': userAgent,
            'Accept': 'application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8',
          },
        ),
      );

      final body = response.data;
      if (body == null || body.trim().isEmpty) {
        throw FeedParseFailure('${source.name} returned an empty feed.');
      }
      return body;
    } on FeedFailure {
      rethrow;
    } on DioException catch (error) {
      throw FeedNetworkFailure(
        'Could not download ${source.name}.',
        cause: error,
      );
    }
  }
}
