import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/article_local_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/saved_article_local_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/models/article_model.dart';

import '../../../../support/article_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late HiveSavedArticleLocalDataSource dataSource;
  late HiveArticleLocalDataSource todayDataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wear_rss_saved_hive');
    Hive.init(tempDir.path);
    // Both data sources share one box, exactly as the DI graph wires them.
    box = await Hive.openBox<String>(HiveArticleLocalDataSource.boxName);
    dataSource = HiveSavedArticleLocalDataSource(box);
    todayDataSource = HiveArticleLocalDataSource(box);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('returns an empty list when nothing has been saved yet', () async {
    expect(await dataSource.readSaved(), isEmpty);
  });

  test('round-trips articles, including null description and author', () async {
    final articles = [
      article(guid: 'one'),
      article(
        guid: 'two',
        title: 'Hugging Face item',
        description: null,
        author: null,
        publishedAt: DateTime(2026, 10, 24, 8, 15),
      ),
    ];

    await dataSource.writeSaved(articles);

    expect(await dataSource.readSaved(), equals(articles));
  });

  test('round-trips an article whose guid is empty', () async {
    final articles = [article(guid: '', link: 'https://example.com/link-only')];

    await dataSource.writeSaved(articles);

    final restored = await dataSource.readSaved();
    expect(restored.single.identity, 'https://example.com/link-only');
  });

  test('replaces the previous list instead of appending', () async {
    await dataSource.writeSaved([article(guid: 'old')]);
    await dataSource.writeSaved([article(guid: 'new')]);

    expect((await dataSource.readSaved()).map((a) => a.guid), ['new']);
  });

  test('stores an empty list as an empty store', () async {
    await dataSource.writeSaved([article()]);
    await dataSource.writeSaved(const []);

    expect(await dataSource.readSaved(), isEmpty);
  });

  test('recovers from corrupt JSON without crashing the app', () async {
    await box.put(HiveSavedArticleLocalDataSource.savedArticlesKey, 'not json');

    expect(await dataSource.readSaved(), isEmpty);
  });

  test('treats a non-list payload as empty', () async {
    await box.put(
      HiveSavedArticleLocalDataSource.savedArticlesKey,
      '{"guid":"not-a-list"}',
    );

    expect(await dataSource.readSaved(), isEmpty);
  });

  test('treats a blank stored value as empty', () async {
    await box.put(HiveSavedArticleLocalDataSource.savedArticlesKey, '');

    expect(await dataSource.readSaved(), isEmpty);
  });

  test('skips one unreadable entry while its siblings survive', () async {
    final readable = ArticleModel.fromEntity(
      article(guid: 'survivor', title: 'Still saved'),
    ).toJson();
    await box.put(
      HiveSavedArticleLocalDataSource.savedArticlesKey,
      jsonEncode(<Object?>[
        readable,
        <String, Object?>{'guid': 'missing-required-fields'},
        42,
        'not-an-object',
      ]),
    );

    final restored = await dataSource.readSaved();

    expect(restored.map((a) => a.guid), ['survivor']);
    expect(restored.single.title, 'Still saved');
  });

  // --- Isolation from the today cache -------------------------------------
  // Both stores share one Hive box, so a key mix-up would silently wipe the
  // other side. Each direction is asserted on the raw box value.

  test('writes only the saved key, never the today key', () async {
    await dataSource.writeSaved([
      article(guid: 'saved-only', title: 'Saved headline'),
    ]);

    final raw = box.get(HiveSavedArticleLocalDataSource.savedArticlesKey);
    expect(raw, isNotNull);
    expect(raw, contains('Saved headline'));
    expect(box.get(HiveArticleLocalDataSource.articlesKey), isNull);
    expect(await todayDataSource.readArticles(), isEmpty);
  });

  test('never overwrites the today cache when saving', () async {
    await todayDataSource.writeArticles([
      article(guid: 'today-1', title: 'Today headline'),
    ]);
    final todayRaw = box.get(HiveArticleLocalDataSource.articlesKey);

    await dataSource.writeSaved([
      article(guid: 'saved-1', title: 'Saved headline'),
    ]);

    expect(box.get(HiveArticleLocalDataSource.articlesKey), todayRaw);
    expect((await todayDataSource.readArticles()).map((a) => a.guid), [
      'today-1',
    ]);
    expect((await dataSource.readSaved()).map((a) => a.guid), ['saved-1']);
  });

  test('ignores the today key when reading saved articles', () async {
    await todayDataSource.writeArticles([article(guid: 'today-only')]);

    expect(box.get(HiveSavedArticleLocalDataSource.savedArticlesKey), isNull);
    expect(await dataSource.readSaved(), isEmpty);
  });

  test('keeps the saved store when the today cache is rewritten', () async {
    await dataSource.writeSaved([
      article(guid: 'saved-1', title: 'Saved headline'),
    ]);
    final savedRaw = box.get(HiveSavedArticleLocalDataSource.savedArticlesKey);

    await todayDataSource.writeArticles([
      article(guid: 'today-1', title: 'Today headline'),
    ]);
    await todayDataSource.writeArticles(const []);

    expect(box.get(HiveSavedArticleLocalDataSource.savedArticlesKey), savedRaw);
    expect((await dataSource.readSaved()).map((a) => a.guid), ['saved-1']);
  });

  // --- Failures ------------------------------------------------------------

  test('returns an empty list when the box cannot be read', () async {
    await dataSource.writeSaved([article(guid: 'unreachable')]);
    await box.close();

    expect(await dataSource.readSaved(), isEmpty);
  });

  test('wraps a failed write as FeedCacheFailure', () async {
    await dataSource.writeSaved([article(guid: 'before-close')]);
    await box.close();

    await expectLater(
      dataSource.writeSaved([article(guid: 'after-close')]),
      throwsA(isA<FeedCacheFailure>()),
    );
  });
}
