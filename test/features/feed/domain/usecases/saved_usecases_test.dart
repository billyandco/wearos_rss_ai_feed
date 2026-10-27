import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/repositories/saved_article_repository.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/is_article_saved.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/load_saved_articles.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/remove_saved_article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/restore_saved_article.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/usecases/toggle_saved_article.dart';

import '../../../../support/article_factory.dart';

/// In-memory [SavedArticleRepository] that records every interaction.
///
/// It deliberately returns a mutable copy of its contents, so a use case that
/// forgets to hand out an unmodifiable list fails the immutability test.
class _InMemorySavedArticleRepository implements SavedArticleRepository {
  _InMemorySavedArticleRepository({Iterable<Article> saved = const []})
    : saved = List<Article>.of(saved);

  final List<Article> saved;

  final List<Article> savedArguments = [];
  final List<String> removedIdentities = [];

  int savedArticlesCalls = 0;
  int saveCalls = 0;
  int removeCalls = 0;

  Object? savedArticlesError;
  Object? saveError;
  Object? removeError;

  @override
  Future<List<Article>> savedArticles() async {
    savedArticlesCalls++;
    if (savedArticlesError != null) {
      throw savedArticlesError!;
    }
    return List<Article>.of(saved);
  }

  @override
  Future<void> save(Article article) async {
    saveCalls++;
    savedArguments.add(article);
    if (saveError != null) {
      throw saveError!;
    }
    saved.removeWhere((existing) => existing.identity == article.identity);
    saved.add(article);
  }

  @override
  Future<void> remove(String identity) async {
    removeCalls++;
    removedIdentities.add(identity);
    if (removeError != null) {
      throw removeError!;
    }
    saved.removeWhere((existing) => existing.identity == identity);
  }
}

void main() {
  group('LoadSavedArticles', () {
    test('returns an empty list when nothing is saved', () async {
      final repository = _InMemorySavedArticleRepository();

      expect(await LoadSavedArticles(repository)(), isEmpty);
    });

    test('sorts newest publishedAt first', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [
          article(guid: 'old', publishedAt: DateTime(2026, 10, 20, 8)),
          article(guid: 'new', publishedAt: DateTime(2026, 10, 27, 16)),
          article(guid: 'middle', publishedAt: DateTime(2026, 10, 24, 12)),
        ],
      );

      final result = await LoadSavedArticles(repository)();

      expect(result.map((a) => a.guid), ['new', 'middle', 'old']);
    });

    test('breaks publishedAt ties by lowercase title', () async {
      // Case-sensitively 'Banana' would sort before 'apple'; the comparator
      // lowercases both titles, so 'apple' must come first.
      final sameInstant = DateTime(2026, 10, 27, 12);
      final repository = _InMemorySavedArticleRepository(
        saved: [
          article(guid: 'banana', title: 'Banana', publishedAt: sameInstant),
          article(guid: 'apple', title: 'apple', publishedAt: sameInstant),
        ],
      );

      final result = await LoadSavedArticles(repository)();

      expect(result.map((a) => a.title), ['apple', 'Banana']);
    });

    test('de-duplicates by identity, keeping the newest copy', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [
          article(
            guid: 'shared',
            title: 'Older copy',
            publishedAt: DateTime(2026, 10, 27, 9),
          ),
          article(
            guid: 'shared',
            title: 'Newer copy',
            publishedAt: DateTime(2026, 10, 27, 15),
          ),
        ],
      );

      final result = await LoadSavedArticles(repository)();

      expect(result, hasLength(1));
      expect(result.single.title, 'Newer copy');
    });

    test('de-duplicates by link when the guid is empty', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [
          article(
            guid: '',
            link: 'https://example.com/same',
            title: 'First',
            publishedAt: DateTime(2026, 10, 27, 9),
          ),
          article(
            guid: '',
            link: 'https://example.com/same',
            title: 'Second',
            publishedAt: DateTime(2026, 10, 27, 11),
          ),
          article(
            guid: '',
            link: 'https://example.com/other',
            title: 'Third',
            publishedAt: DateTime(2026, 10, 27, 10),
          ),
        ],
      );

      final result = await LoadSavedArticles(repository)();

      expect(result.map((a) => a.title), ['Second', 'Third']);
    });

    test('keeps articles from older days and ignores the 20 cap', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [
          for (var i = 0; i < 25; i++)
            article(
              guid: 'saved-$i',
              title: 'Saved $i',
              publishedAt: DateTime(2020, 1, 1).add(Duration(days: i)),
            ),
        ],
      );

      final result = await LoadSavedArticles(repository)();

      expect(result, hasLength(25));
      expect(result.first.guid, 'saved-24');
      expect(result.last.guid, 'saved-0');
    });

    test('returns an unmodifiable list', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: 'saved')],
      );

      final result = await LoadSavedArticles(repository)();

      expect(result, isA<List<Article>>());
      expect(() => result.add(article()), throwsUnsupportedError);
    });

    test('propagates repository failures', () async {
      final repository = _InMemorySavedArticleRepository()
        ..savedArticlesError = const FeedCacheFailure('Cache unavailable');

      await expectLater(
        LoadSavedArticles(repository)(),
        throwsA(isA<FeedCacheFailure>()),
      );
    });
  });

  group('IsArticleSaved', () {
    test('is true when the identity is saved', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: 'saved-guid')],
      );

      expect(await IsArticleSaved(repository)('saved-guid'), isTrue);
    });

    test('is false when the identity is not saved', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: 'saved-guid')],
      );

      expect(await IsArticleSaved(repository)('other-guid'), isFalse);
    });

    test('is false for an empty store', () async {
      final repository = _InMemorySavedArticleRepository();

      expect(await IsArticleSaved(repository)('anything'), isFalse);
    });

    test('matches on identity only, ignoring the other fields', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: 'saved-guid', title: 'Stored title')],
      );

      expect(await IsArticleSaved(repository)('saved-guid'), isTrue);
      expect(await IsArticleSaved(repository)('Stored title'), isFalse);
    });

    test('falls back to the link when the guid is empty', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: '', link: 'https://example.com/only-link')],
      );
      final useCase = IsArticleSaved(repository);

      expect(await useCase('https://example.com/only-link'), isTrue);
      expect(await useCase(''), isFalse);
    });

    test('propagates repository failures', () async {
      final repository = _InMemorySavedArticleRepository()
        ..savedArticlesError = const FeedCacheFailure('Cache unavailable');

      await expectLater(
        IsArticleSaved(repository)('saved-guid'),
        throwsA(isA<FeedCacheFailure>()),
      );
    });
  });

  group('ToggleSavedArticle', () {
    test('saves an unsaved article and returns true', () async {
      final repository = _InMemorySavedArticleRepository();
      final candidate = article(guid: 'fresh');

      final result = await ToggleSavedArticle(repository)(candidate);

      expect(result, isTrue);
      expect(repository.savedArguments, [candidate]);
      expect(repository.saved.map((a) => a.identity), ['fresh']);
      expect(repository.removeCalls, 0);
    });

    test('removes a saved article and returns false', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: 'already-saved')],
      );

      final result = await ToggleSavedArticle(repository)(
        article(guid: 'already-saved'),
      );

      expect(result, isFalse);
      expect(repository.removedIdentities, ['already-saved']);
      expect(repository.saveCalls, 0);
      expect(repository.saved, isEmpty);
    });

    test('toggles by identity, not by whole-article equality', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: 'shared-guid', title: 'Original title')],
      );

      final result = await ToggleSavedArticle(repository)(
        article(
          guid: 'shared-guid',
          title: 'A different title',
          publishedAt: DateTime(2026, 10, 27, 23),
        ),
      );

      expect(result, isFalse);
      expect(repository.removedIdentities, ['shared-guid']);
      expect(repository.saved, isEmpty);
    });

    test('uses the repository exactly once per call', () async {
      final repository = _InMemorySavedArticleRepository();
      final useCase = ToggleSavedArticle(repository);
      final candidate = article(guid: 'repeated');

      expect(await useCase(candidate), isTrue);
      expect(repository.saveCalls, 1);
      expect(repository.removeCalls, 0);
      expect(repository.savedArticlesCalls, 1);
      expect(repository.saved, hasLength(1));

      expect(await useCase(candidate), isFalse);
      expect(repository.saveCalls, 1);
      expect(repository.removeCalls, 1);
      expect(repository.savedArticlesCalls, 2);
      expect(repository.saved, isEmpty);
    });

    test(
      'propagates repository failures and does not report success',
      () async {
        final repository = _InMemorySavedArticleRepository()
          ..saveError = const FeedCacheFailure('Disk full');

        await expectLater(
          ToggleSavedArticle(repository)(article(guid: 'fresh')),
          throwsA(isA<FeedCacheFailure>()),
        );
        expect(repository.saved, isEmpty);
      },
    );

    test('propagates failures while removing a saved article', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: 'saved-guid')],
      )..removeError = const FeedCacheFailure('Disk full');

      await expectLater(
        ToggleSavedArticle(repository)(article(guid: 'saved-guid')),
        throwsA(isA<FeedCacheFailure>()),
      );
    });
  });

  group('RestoreSavedArticle', () {
    test('forwards the article to save', () async {
      final repository = _InMemorySavedArticleRepository();
      final candidate = article(guid: 'restored', title: 'Restored story');

      await RestoreSavedArticle(repository)(candidate);

      expect(repository.saveCalls, 1);
      expect(repository.savedArguments, [candidate]);
      expect(repository.saved.map((a) => a.identity), ['restored']);
      expect(
        repository.removeCalls,
        0,
        reason: 'UNDO only writes: it must never delete anything',
      );
    });

    test('is safe to call when the article is already saved', () async {
      final stored = article(guid: 'already', title: 'Already saved');
      final repository = _InMemorySavedArticleRepository(saved: [stored]);
      final useCase = RestoreSavedArticle(repository);

      // The repository is idempotent, so a double UNDO writes twice without
      // creating a second copy.
      await useCase(stored);
      await useCase(stored);

      expect(repository.savedArguments, [stored, stored]);
      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.identity, 'already');
      expect(
        repository.savedArticlesCalls,
        0,
        reason:
            'restore is unconditional: a read-then-decide toggle would drop '
            'the article back out if the store already held it',
      );
    });

    test('propagates repository failures', () async {
      final repository = _InMemorySavedArticleRepository()
        ..saveError = const FeedCacheFailure('Disk full');

      await expectLater(
        RestoreSavedArticle(repository)(article(guid: 'restore-fail')),
        throwsA(isA<FeedCacheFailure>()),
      );
      expect(repository.saved, isEmpty);
    });
  });

  group('RemoveSavedArticle', () {
    test('forwards the identity to the repository', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [
          article(guid: 'to-remove'),
          article(guid: 'kept', publishedAt: DateTime(2026, 10, 20, 8)),
        ],
      );

      await RemoveSavedArticle(repository)('to-remove');

      expect(repository.removedIdentities, ['to-remove']);
      expect(repository.saved.map((a) => a.identity), ['kept']);
    });

    test('forwards the link identity when the guid is empty', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: '', link: 'https://example.com/no-guid')],
      );

      await RemoveSavedArticle(repository)('https://example.com/no-guid');

      expect(repository.removedIdentities, ['https://example.com/no-guid']);
      expect(repository.saved, isEmpty);
    });

    test('does not throw when the identity was never saved', () async {
      final repository = _InMemorySavedArticleRepository(
        saved: [article(guid: 'kept')],
      );

      await RemoveSavedArticle(repository)('never-saved');

      expect(repository.removedIdentities, ['never-saved']);
      expect(repository.saved.map((a) => a.identity), ['kept']);
    });

    test('propagates repository failures', () async {
      final repository = _InMemorySavedArticleRepository()
        ..removeError = const FeedCacheFailure('Disk full');

      await expectLater(
        RemoveSavedArticle(repository)('saved-guid'),
        throwsA(isA<FeedCacheFailure>()),
      );
    });
  });
}
