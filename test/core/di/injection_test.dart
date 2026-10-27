import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:wearos_rss_ai_feed/core/di/injection.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/article_local_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/datasources/saved_article_local_data_source.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/feed_sources.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/repositories/article_repository_impl.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/repositories/saved_article_repository_impl.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/article_repository.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/remote_article_opener.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/saved_article_repository.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/is_article_saved.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/load_saved_articles.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/refresh_today_articles.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/remove_saved_article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/toggle_saved_article.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_bloc.dart';

import '../../support/article_factory.dart';
import '../../support/fake_http_adapter.dart';
import '../../support/feed_test_doubles.dart';
import '../../support/feed_xml_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<String> box;

  setUp(() async {
    await sl.reset();
    tempDir = await Directory.systemTemp.createTemp('wear_rss_di_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>(HiveArticleLocalDataSource.boxName);
  });

  tearDown(() async {
    await sl.reset();
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('wires the graph and refreshes all eight sources through it', () async {
    final now = DateTime.now();
    final adapter = FakeHttpClientAdapter(
      (_) => xmlResponse(
        feedXml([
          itemXml(
            guid: 'wired-article',
            title: 'Wired through DI',
            pubDate: rfc822(now.subtract(const Duration(minutes: 5))),
            description: '<p>Resolved from the container.</p>',
          ),
        ]),
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final opener = RecordingRemoteOpener();

    await configureDependencies(dio: dio, cacheBox: box, remoteOpener: opener);

    expect(sl<ArticleRepository>(), isA<ArticleRepositoryImpl>());
    expect(sl<RemoteArticleOpener>(), same(opener));
    expect(sl<FeedBloc>(), isA<FeedBloc>());

    final articles = await sl<RefreshTodayArticles>()(now: now);

    expect(adapter.requests, hasLength(kFeedSources.length));
    expect(
      adapter.requests.map((request) => request.uri.toString()),
      unorderedEquals(kFeedSources.map((source) => source.url)),
    );
    // Every fake response carries the same guid, so de-duplication keeps one.
    expect(articles.single.guid, 'wired-article');
    expect(articles.single.description, 'Resolved from the container.');

    final cached = box.get(HiveArticleLocalDataSource.articlesKey);
    expect(cached, isNotNull);
    expect(cached, contains('Wired through DI'));
  });

  test('is idempotent when called twice', () async {
    await configureDependencies(cacheBox: box, dio: Dio());
    await configureDependencies(cacheBox: box, dio: Dio());

    expect(sl<FeedBloc>(), isA<FeedBloc>());
  });

  test('wires the saved-article store on the same Hive box', () async {
    await configureDependencies(cacheBox: box, dio: Dio());

    expect(sl<SavedArticleRepository>(), isA<SavedArticleRepositoryImpl>());

    final bookmarked = article(
      guid: 'saved-through-di',
      title: 'Saved through DI',
    );

    expect(await sl<ToggleSavedArticle>()(bookmarked), isTrue);

    final savedRaw = box.get(HiveSavedArticleLocalDataSource.savedArticlesKey);
    expect(savedRaw, isNotNull);
    expect(savedRaw, contains('Saved through DI'));
    // Saving must never spill into the today cache: that key is disposable and
    // would otherwise resurrect a stale feed.
    expect(box.get(HiveArticleLocalDataSource.articlesKey), isNull);

    expect((await sl<LoadSavedArticles>()()).map((saved) => saved.identity), [
      'saved-through-di',
    ]);
    expect(await sl<IsArticleSaved>()('saved-through-di'), isTrue);

    expect(await sl<ToggleSavedArticle>()(bookmarked), isFalse);
    expect(
      box.get(HiveSavedArticleLocalDataSource.savedArticlesKey),
      isNot(contains('Saved through DI')),
    );
    expect(await sl<IsArticleSaved>()('saved-through-di'), isFalse);

    await sl<RemoveSavedArticle>()('saved-through-di');
    expect(await sl<LoadSavedArticles>()(), isEmpty);
  });
}
