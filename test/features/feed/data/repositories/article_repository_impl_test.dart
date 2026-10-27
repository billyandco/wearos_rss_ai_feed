import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/article_local_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/feed_remote_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/repositories/article_repository_impl.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/feed_source.dart';

import '../../../../support/article_factory.dart';

class _FakeRemoteDataSource implements FeedRemoteDataSource {
  _FakeRemoteDataSource({this.articles = const []});

  List<Article> articles;
  Object? error;
  List<FeedSource>? requestedSources;
  DateTime? requestedNow;

  @override
  Future<List<Article>> fetchArticles(
    List<FeedSource> sources, {
    required DateTime now,
  }) async {
    requestedSources = sources;
    requestedNow = now;
    if (error != null) {
      throw error!;
    }
    return articles;
  }
}

class _FakeLocalDataSource implements ArticleLocalDataSource {
  _FakeLocalDataSource({this.cached = const []});

  List<Article> cached;
  Object? readError;
  Object? writeError;
  List<Article>? written;

  @override
  Future<List<Article>> readArticles() async {
    if (readError != null) {
      throw readError!;
    }
    return cached;
  }

  @override
  Future<void> writeArticles(List<Article> articles) async {
    if (writeError != null) {
      throw writeError!;
    }
    written = articles;
  }
}

void main() {
  final now = DateTime(2026, 10, 27, 18);
  const sources = [feedSource];

  ArticleRepositoryImpl buildRepository(
    _FakeRemoteDataSource remote,
    _FakeLocalDataSource local,
  ) => ArticleRepositoryImpl(
    remoteDataSource: remote,
    localDataSource: local,
    sources: sources,
  );

  test('returns cached articles exactly as stored', () async {
    final cached = [
      article(guid: 'from-yesterday', publishedAt: DateTime(2026, 10, 26, 9)),
    ];
    final local = _FakeLocalDataSource(cached: cached);
    final repository = buildRepository(_FakeRemoteDataSource(), local);

    expect(await repository.cachedArticles(), cached);
  });

  test('wraps unexpected cache read errors as FeedCacheFailure', () async {
    final repository = buildRepository(
      _FakeRemoteDataSource(),
      _FakeLocalDataSource()..readError = StateError('box closed'),
    );

    await expectLater(
      repository.cachedArticles(),
      throwsA(isA<FeedCacheFailure>()),
    );
  });

  test('fetches with the current time and the configured sources', () async {
    final remote = _FakeRemoteDataSource();
    final repository = buildRepository(remote, _FakeLocalDataSource());

    await repository.refreshTodayArticles(now: now);

    expect(remote.requestedNow, now);
    expect(remote.requestedSources, sources);
  });

  test(
    'keeps only today, de-duplicates, sorts and caches the result',
    () async {
      final remote = _FakeRemoteDataSource(
        articles: [
          article(
            guid: 'yesterday',
            publishedAt: DateTime(2026, 10, 26, 23, 30),
          ),
          article(
            guid: 'morning',
            title: 'Morning',
            publishedAt: DateTime(2026, 10, 27, 8),
          ),
          article(
            guid: 'duplicate',
            title: 'First seen',
            publishedAt: DateTime(2026, 10, 27, 9),
          ),
          article(
            guid: 'duplicate',
            title: 'Newest copy',
            publishedAt: DateTime(2026, 10, 27, 14),
          ),
          article(
            guid: 'late',
            title: 'Late',
            publishedAt: DateTime(2026, 10, 27, 17),
          ),
        ],
      );
      final local = _FakeLocalDataSource();
      final repository = buildRepository(remote, local);

      final result = await repository.refreshTodayArticles(now: now);

      expect(result.map((a) => a.title), ['Late', 'Newest copy', 'Morning']);
      expect(local.written, equals(result));
    },
  );

  test('caches an empty list when nothing was published today', () async {
    final remote = _FakeRemoteDataSource(
      articles: [article(publishedAt: DateTime(2026, 10, 25, 9))],
    );
    final local = _FakeLocalDataSource();
    final repository = buildRepository(remote, local);

    final result = await repository.refreshTodayArticles(now: now);

    expect(result, isEmpty);
    expect(local.written, isEmpty);
  });

  test('does not overwrite the cache when the network fails', () async {
    final local = _FakeLocalDataSource(cached: [article(guid: 'cached')]);
    final repository = buildRepository(
      _FakeRemoteDataSource()..error = const FeedUnavailableFailure('offline'),
      local,
    );

    await expectLater(
      repository.refreshTodayArticles(now: now),
      throwsA(isA<FeedUnavailableFailure>()),
    );
    expect(local.written, isNull);
  });

  test('wraps unexpected cache write errors as FeedCacheFailure', () async {
    final local = _FakeLocalDataSource()..writeError = StateError('disk full');
    final repository = buildRepository(_FakeRemoteDataSource(), local);

    await expectLater(
      repository.refreshTodayArticles(now: now),
      throwsA(isA<FeedCacheFailure>()),
    );
  });

  test('returns an unmodifiable list of articles', () async {
    final repository = buildRepository(
      _FakeRemoteDataSource(articles: [article()]),
      _FakeLocalDataSource(),
    );

    final result = await repository.refreshTodayArticles(now: now);

    expect(result, isA<List<Article>>());
    expect(() => result.add(article()), throwsUnsupportedError);
  });
}
