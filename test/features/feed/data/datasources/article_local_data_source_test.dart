import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/article_local_data_source.dart';

import '../../../../support/article_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;
  late HiveArticleLocalDataSource dataSource;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wear_rss_hive_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>(HiveArticleLocalDataSource.boxName);
    dataSource = HiveArticleLocalDataSource(box);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('returns an empty list when nothing has been cached yet', () async {
    expect(await dataSource.readArticles(), isEmpty);
  });

  test('round-trips articles, including null descriptions', () async {
    final articles = [
      article(guid: 'one'),
      article(
        guid: 'two',
        title: 'Hugging Face item',
        description: null,
        author: null,
        publishedAt: DateTime(2026, 10, 27, 8, 15),
      ),
    ];

    await dataSource.writeArticles(articles);

    expect(await dataSource.readArticles(), equals(articles));
  });

  test('replaces the previous cache instead of appending', () async {
    await dataSource.writeArticles([article(guid: 'old')]);
    await dataSource.writeArticles([article(guid: 'new')]);

    expect((await dataSource.readArticles()).map((a) => a.guid), ['new']);
  });

  test('stores an empty list as an empty cache', () async {
    await dataSource.writeArticles([article()]);
    await dataSource.writeArticles(const []);

    expect(await dataSource.readArticles(), isEmpty);
  });

  test('recovers from a corrupt cache without crashing the app', () async {
    await box.put(HiveArticleLocalDataSource.articlesKey, 'not json at all');

    expect(await dataSource.readArticles(), isEmpty);
  });

  test('tolerates unexpected shapes inside entries', () async {
    await box.put(
      HiveArticleLocalDataSource.articlesKey,
      '[{"guid":"missing-required-fields"}]',
    );

    expect(await dataSource.readArticles(), isEmpty);
  });
}
