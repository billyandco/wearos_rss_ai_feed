import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/article_repository.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/remote_article_opener.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/load_cached_articles.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/open_article_on_phone.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/refresh_today_articles.dart';

import '../../../../support/article_factory.dart';

class _FakeArticleRepository implements ArticleRepository {
  _FakeArticleRepository({this.cached = const [], this.refreshed = const []});

  List<Article> cached;
  List<Article> refreshed;
  DateTime? lastNow;
  Object? refreshError;

  @override
  Future<List<Article>> cachedArticles() async => cached;

  @override
  Future<List<Article>> refreshTodayArticles({required DateTime now}) async {
    lastNow = now;
    if (refreshError != null) {
      throw refreshError!;
    }
    return refreshed;
  }
}

class _RecordingOpener implements RemoteArticleOpener {
  final opened = <Uri>[];
  Object? error;

  @override
  Future<void> openOnPhone(Uri url) async {
    if (error != null) {
      throw error!;
    }
    opened.add(url);
  }
}

void main() {
  group('LoadCachedArticles', () {
    test('returns whatever the repository has cached', () async {
      final cached = [article(guid: 'cached')];
      final repository = _FakeArticleRepository(cached: cached);

      final result = await LoadCachedArticles(repository)();

      expect(result, cached);
    });
  });

  group('RefreshTodayArticles', () {
    test('delegates to the repository with the given local time', () async {
      final now = DateTime(2026, 10, 27, 18);
      final repository = _FakeArticleRepository(refreshed: [article()]);

      final result = await RefreshTodayArticles(repository)(now: now);

      expect(repository.lastNow, now);
      expect(result, [article()]);
    });

    test('propagates repository failures to the caller', () async {
      final repository = _FakeArticleRepository()
        ..refreshError = const FeedNetworkFailure('Offline');

      await expectLater(
        RefreshTodayArticles(repository)(now: DateTime(2026, 10, 27)),
        throwsA(isA<FeedNetworkFailure>()),
      );
    });
  });

  group('OpenArticleOnPhone', () {
    test('asks the platform opener to open the article link', () async {
      final opener = _RecordingOpener();

      await OpenArticleOnPhone(opener)(article(link: 'https://example.com/a'));

      expect(opener.opened, [Uri.parse('https://example.com/a')]);
    });

    test('rejects articles with unusable links', () async {
      final opener = _RecordingOpener();
      final useCase = OpenArticleOnPhone(opener);

      await expectLater(
        useCase(article(link: 'not a link')),
        throwsA(isA<RemoteOpenFailure>()),
      );
      await expectLater(
        useCase(article(link: 'ftp://example.com/file')),
        throwsA(isA<RemoteOpenFailure>()),
      );
      expect(opener.opened, isEmpty);
    });

    test('propagates platform failures', () async {
      final opener = _RecordingOpener()
        ..error = const RemoteOpenFailure('Phone not connected');

      await expectLater(
        OpenArticleOnPhone(opener)(article()),
        throwsA(isA<RemoteOpenFailure>()),
      );
    });
  });
}
