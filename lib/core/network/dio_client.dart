import 'package:dio/dio.dart';

/// Dio configured for large RSS payloads (OpenAI and Hugging Face return their
/// full archives) and for plain-text responses parsed by `package:xml`.
Dio createFeedDio() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 15),
    // Large archives over a slow phone connection: allow generous read time.
    receiveTimeout: const Duration(seconds: 90),
    responseType: ResponseType.plain,
    headers: const <String, String>{
      'User-Agent': 'WearRssAiFeed/1.0 (Wear OS)',
      'Accept':
          'application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8',
    },
  ),
);
