import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/article_local_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/saved_article_local_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/repositories/saved_article_repository_impl.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';

import '../../../../support/article_factory.dart';

/// In-memory [SavedArticleLocalDataSource] — same storage rules as Hive, no
/// disk, so the repository tests stay fast.
class _FakeSavedArticleDataSource implements SavedArticleLocalDataSource {
  _FakeSavedArticleDataSource({Iterable<Article> stored = const []})
    : stored = List<Article>.of(stored);

  List<Article> stored;
  final List<List<Article>> writes = [];

  int reads = 0;
  Object? readError;
  Object? writeError;

  @override
  Future<List<Article>> readSaved() async {
    reads++;
    if (readError != null) {
      throw readError!;
    }
    return List<Article>.of(stored);
  }

  @override
  Future<void> writeSaved(List<Article> articles) async {
    if (writeError != null) {
      throw writeError!;
    }
    writes.add(List<Article>.of(articles));
    stored = List<Article>.of(articles);
  }
}

/// Stands in for the today cache so cross-writes are observable.
class _RecordingTodayCache implements ArticleLocalDataSource {
  _RecordingTodayCache({Iterable<Article> stored = const []})
    : stored = List<Article>.of(stored);

  List<Article> stored;
  int reads = 0;
  int writes = 0;

  @override
  Future<List<Article>> readArticles() async {
    reads++;
    return List<Article>.of(stored);
  }

  @override
  Future<void> writeArticles(List<Article> articles) async {
    writes++;
    stored = List<Article>.of(articles);
  }
}

void main() {
  SavedArticleRepositoryImpl buildRepository(
    _FakeSavedArticleDataSource dataSource,
  ) => SavedArticleRepositoryImpl(localDataSource: dataSource);

  test('returns the stored saved articles', () async {
    final stored = [
      article(guid: 'two', publishedAt: DateTime(2026, 10, 27, 12)),
      article(guid: 'one', publishedAt: DateTime(2026, 10, 26, 12)),
    ];
    final repository = buildRepository(
      _FakeSavedArticleDataSource(stored: stored),
    );

    expect(await repository.savedArticles(), stored);
  });

  test('returns an empty list when nothing is saved', () async {
    final repository = buildRepository(_FakeSavedArticleDataSource());

    expect(await repository.savedArticles(), isEmpty);
  });

  test('appends a new article to the saved list', () async {
    final existing = article(guid: 'existing');
    final dataSource = _FakeSavedArticleDataSource(stored: [existing]);
    final repository = buildRepository(dataSource);

    await repository.save(article(guid: 'newcomer'));

    // Write order is not part of the contract; the use case owns sorting.
    expect(
      dataSource.stored.map((a) => a.guid),
      unorderedEquals(['existing', 'newcomer']),
    );
    expect(dataSource.writes, hasLength(1));
    expect(dataSource.writes.single, hasLength(2));
  });

  test('keeps only one entry when the same identity is saved twice', () async {
    final dataSource = _FakeSavedArticleDataSource();
    final repository = buildRepository(dataSource);

    await repository.save(
      article(
        guid: 'same-guid',
        title: 'First save',
        publishedAt: DateTime(2026, 10, 27, 9),
      ),
    );
    await repository.save(
      article(
        guid: 'same-guid',
        title: 'Second save',
        publishedAt: DateTime(2026, 10, 27, 17),
      ),
    );

    expect(dataSource.stored, hasLength(1));
    expect(dataSource.stored.single.title, 'Second save');
    expect(dataSource.writes.last, hasLength(1));
  });

  test('is idempotent when the identical article is saved twice', () async {
    final dataSource = _FakeSavedArticleDataSource();
    final repository = buildRepository(dataSource);
    final twice = article(guid: 'identical');

    await repository.save(twice);
    await repository.save(twice);

    expect(dataSource.stored, [twice]);
    expect(dataSource.writes.last, hasLength(1));
  });

  test('de-duplicates by link when the guid is empty', () async {
    final dataSource = _FakeSavedArticleDataSource();
    final repository = buildRepository(dataSource);

    await repository.save(
      article(guid: '', link: 'https://example.com/same', title: 'First'),
    );
    await repository.save(
      article(guid: '', link: 'https://example.com/same', title: 'Second'),
    );

    expect(dataSource.stored, hasLength(1));
    expect(dataSource.stored.single.title, 'Second');
  });

  test('removes only the matching identity', () async {
    final dataSource = _FakeSavedArticleDataSource(
      stored: [
        article(guid: 'keep-me'),
        article(guid: 'delete-me', publishedAt: DateTime(2026, 10, 26, 8)),
      ],
    );
    final repository = buildRepository(dataSource);

    await repository.remove('delete-me');

    expect(dataSource.stored.map((a) => a.guid), ['keep-me']);
  });

  test('does not throw when removing an identity that is not saved', () async {
    final dataSource = _FakeSavedArticleDataSource(
      stored: [article(guid: 'keep-me')],
    );
    final repository = buildRepository(dataSource);

    await repository.remove('never-saved');

    expect(dataSource.stored.map((a) => a.guid), ['keep-me']);
  });

  test('removes from an empty store without throwing', () async {
    final repository = buildRepository(_FakeSavedArticleDataSource());

    await repository.remove('anything');

    expect(await repository.savedArticles(), isEmpty);
  });

  test('keeps a saved article saved across a read', () async {
    final dataSource = _FakeSavedArticleDataSource();
    final repository = buildRepository(dataSource);
    final bookmarked = article(guid: 'bookmarked');

    await repository.save(bookmarked);

    expect(await repository.savedArticles(), [bookmarked]);
    expect(dataSource.reads, greaterThan(0));
  });

  // --- Error mapping -------------------------------------------------------

  test('maps a read failure to FeedCacheFailure', () async {
    final dataSource = _FakeSavedArticleDataSource()
      ..readError = StateError('box closed');
    final repository = buildRepository(dataSource);

    await expectLater(
      repository.savedArticles(),
      throwsA(isA<FeedCacheFailure>()),
    );
  });

  test('maps a write failure while saving to FeedCacheFailure', () async {
    final dataSource = _FakeSavedArticleDataSource()
      ..writeError = StateError('disk full');
    final repository = buildRepository(dataSource);

    await expectLater(
      repository.save(article()),
      throwsA(isA<FeedCacheFailure>()),
    );
  });

  test('maps a write failure while removing to FeedCacheFailure', () async {
    final dataSource = _FakeSavedArticleDataSource(
      stored: [article(guid: 'saved')],
    )..writeError = StateError('disk full');
    final repository = buildRepository(dataSource);

    await expectLater(
      repository.remove('saved'),
      throwsA(isA<FeedCacheFailure>()),
    );
  });

  test('surfaces an existing FeedFailure unchanged', () async {
    final dataSource = _FakeSavedArticleDataSource()
      ..readError = const FeedCacheFailure('Cache is closed.');
    final repository = buildRepository(dataSource);

    await expectLater(
      repository.savedArticles(),
      throwsA(
        isA<FeedCacheFailure>().having(
          (failure) => failure.message,
          'message',
          'Cache is closed.',
        ),
      ),
    );
  });

  // --- Cross-store isolation ----------------------------------------------

  test('saving saved articles never touches the today cache', () async {
    final today = _RecordingTodayCache(stored: [article(guid: 'today')]);
    final dataSource = _FakeSavedArticleDataSource();
    final repository = buildRepository(dataSource);

    await repository.save(article(guid: 'bookmarked'));
    await repository.savedArticles();
    await repository.remove('bookmarked');

    expect(today.reads, 0);
    expect(today.writes, 0);
    expect(today.stored.map((a) => a.guid), ['today']);
    expect(dataSource.writes, hasLength(2));
  });
}
