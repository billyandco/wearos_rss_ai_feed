import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_bloc.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_event.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_state.dart';

import '../../../../support/article_factory.dart';
import '../../../../support/feed_test_doubles.dart';

void main() {
  final fixedNow = DateTime(2026, 10, 27, 18);

  FeedBloc buildBloc(
    FakeArticleRepository repository, {
    RecordingRemoteOpener? opener,
    FakeSavedArticleRepository? savedRepository,
  }) => buildTestFeedBloc(
    repository: repository,
    opener: opener,
    savedRepository: savedRepository,
    clock: () => fixedNow,
  );

  /// Waits for the first state matching [test]; fails the test (instead of
  /// hanging until the 30 s test timeout) when the bloc never gets there.
  Future<FeedState> awaitState(
    FeedBloc bloc,
    bool Function(FeedState state) test,
    String reason,
  ) => bloc.stream
      .firstWhere(test)
      .timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('FeedBloc never emitted a state where $reason'),
      );

  test('starts empty and idle', () {
    final bloc = buildBloc(FakeArticleRepository());
    addTearDown(bloc.close);

    expect(bloc.state.status, FeedStatus.initial);
    expect(bloc.state.articles, isEmpty);
    expect(bloc.state.isRefreshing, isFalse);
  });

  test(
    'shows cached articles immediately, then replaces them with fresh ones',
    () async {
      final repository = FakeArticleRepository()
        ..cached = [article(guid: 'cached', title: 'Cached story')]
        ..refreshed = [article(guid: 'fresh', title: 'Fresh story')];
      final bloc = buildBloc(repository);
      addTearDown(bloc.close);

      final seen = <List<String>>[];
      final subscription = bloc.stream.listen(
        (state) => seen.add(state.articles.map((a) => a.guid).toList()),
      );

      bloc.add(const FeedStarted());
      final finalState = await bloc.stream.firstWhere(
        (state) => state.lastUpdated != null,
      );
      await subscription.cancel();

      expect(seen, anyElement(equals(['cached'])));
      expect(finalState.status, FeedStatus.ready);
      expect(finalState.articles.map((a) => a.guid), ['fresh']);
      expect(finalState.isRefreshing, isFalse);
      expect(finalState.lastUpdated, fixedNow);
      expect(repository.refreshCalls, 1);
      expect(repository.lastRequestedNow, fixedNow);
    },
  );

  test('shows a loading state while the first fetch is in flight', () async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'fresh')];
    final bloc = buildBloc(repository);
    addTearDown(bloc.close);

    final statuses = <FeedStatus>[];
    final subscription = bloc.stream.listen((s) => statuses.add(s.status));

    bloc.add(const FeedStarted());
    await bloc.stream.firstWhere((state) => state.lastUpdated != null);
    await subscription.cancel();

    expect(statuses.first, FeedStatus.loading);
    expect(statuses.last, FeedStatus.ready);
  });

  test(
    'keeps cached articles and reports the error when refresh fails',
    () async {
      final repository = FakeArticleRepository()
        ..cached = [article(guid: 'cached')]
        ..refreshError = const FeedUnavailableFailure(
          'Could not reach any news source.',
        );
      final bloc = buildBloc(repository);
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      final state = await bloc.stream.firstWhere(
        (state) => state.errorMessage != null && !state.isRefreshing,
      );

      expect(state.status, FeedStatus.ready);
      expect(state.articles.map((a) => a.guid), ['cached']);
      expect(state.errorMessage, contains('Could not reach'));
    },
  );

  test('reports failure when refresh fails without a cache', () async {
    final repository = FakeArticleRepository()
      ..refreshError = const FeedNetworkFailure('Offline');
    final bloc = buildBloc(repository);
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    final state = await bloc.stream.firstWhere(
      (state) => state.status == FeedStatus.failure,
    );

    expect(state.articles, isEmpty);
    expect(state.errorMessage, 'Offline');
    expect(state.isRefreshing, isFalse);
  });

  test('ignores refresh requests while a refresh is running', () async {
    final repository = FakeArticleRepository()
      ..refreshGate = Completer<void>()
      ..refreshed = [article()];
    final bloc = buildBloc(repository);
    addTearDown(bloc.close);

    bloc
      ..add(const FeedStarted())
      ..add(const FeedRefreshRequested());
    await Future<void>.delayed(Duration.zero);
    repository.refreshGate!.complete();
    await bloc.stream.firstWhere((state) => state.lastUpdated != null);

    expect(repository.refreshCalls, 1);
  });

  test('a manual refresh clears the previous error', () async {
    final repository = FakeArticleRepository()
      ..refreshError = const FeedNetworkFailure('Offline');
    final bloc = buildBloc(repository);
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    await bloc.stream.firstWhere((s) => s.status == FeedStatus.failure);

    repository
      ..refreshError = null
      ..refreshed = [article(guid: 'recovered')];
    bloc.add(const FeedRefreshRequested());
    final state = await bloc.stream.firstWhere((s) => s.lastUpdated != null);

    expect(state.status, FeedStatus.ready);
    expect(state.errorMessage, isNull);
    expect(state.articles.map((a) => a.guid), ['recovered']);
  });

  test('asks the phone to open the article on double tap', () async {
    final opener = RecordingRemoteOpener();
    final repository = FakeArticleRepository();
    final bloc = buildBloc(repository, opener: opener);
    addTearDown(bloc.close);
    final target = article(link: 'https://example.com/story');

    bloc.add(FeedArticleOpened(target));
    final state = await bloc.stream.firstWhere((s) => s.notice != null);

    expect(opener.opened, [Uri.parse('https://example.com/story')]);
    expect(state.notice!.kind, FeedNoticeKind.openedOnPhone);
  });

  test('surfaces a notice when the phone cannot be reached', () async {
    final opener = RecordingRemoteOpener()
      ..error = const RemoteOpenFailure('Phone not connected');
    final bloc = buildBloc(FakeArticleRepository(), opener: opener);
    addTearDown(bloc.close);

    bloc.add(FeedArticleOpened(article()));
    final state = await bloc.stream.firstWhere((s) => s.notice != null);

    expect(state.notice!.kind, FeedNoticeKind.openFailed);
    expect(state.notice!.message, contains('Phone not connected'));
  });

  test(
    'open notices are distinct so repeated taps are announced again',
    () async {
      final bloc = buildBloc(
        FakeArticleRepository(),
        opener: RecordingRemoteOpener(),
      );
      addTearDown(bloc.close);

      bloc.add(FeedArticleOpened(article()));
      final first = await bloc.stream.firstWhere((s) => s.notice != null);

      bloc.add(FeedArticleOpened(article()));
      final second = await bloc.stream.firstWhere(
        (s) => s.notice != null && s.notice!.id != first.notice!.id,
      );

      expect(second.notice!.kind, FeedNoticeKind.openedOnPhone);
    },
  );

  // ---------------------------------------------------------------------------
  // Saved articles
  // ---------------------------------------------------------------------------

  test('starts in the today section with an empty saved list', () {
    final bloc = buildBloc(FakeArticleRepository());
    addTearDown(bloc.close);

    expect(bloc.state.section, FeedSection.today);
    expect(bloc.state.savedArticles, isEmpty);
    expect(bloc.state.hasSavedArticles, isFalse);
    expect(bloc.state.visibleArticles, isEmpty);
    expect(bloc.state.savedErrorMessage, isNull);
  });

  test('savedErrorMessage is carried by copyWith and by equality', () {
    const base = FeedState.initial();
    final failed = base.copyWith(
      savedErrorMessage: 'Saved storage unavailable',
    );

    expect(failed.savedErrorMessage, 'Saved storage unavailable');
    expect(
      failed,
      base.copyWith(savedErrorMessage: 'Saved storage unavailable'),
      reason: 'two states with the same saved error must compare equal',
    );
    expect(
      failed.hashCode,
      base.copyWith(savedErrorMessage: 'Saved storage unavailable').hashCode,
    );
    expect(
      failed,
      isNot(base),
      reason: 'a state carrying a saved error is not the initial state',
    );
    expect(
      failed.copyWith(section: FeedSection.saved).savedErrorMessage,
      'Saved storage unavailable',
      reason: 'an unrelated copyWith must not drop the saved error',
    );
    expect(
      failed.copyWith(clearSavedError: true).savedErrorMessage,
      isNull,
      reason: 'clearSavedError is the only way back to a clean saved state',
    );
  });

  test('FeedStarted loads the saved articles without touching today', () async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'fresh')];
    final savedRepository = FakeSavedArticleRepository(
      saved: [article(guid: 'saved', title: 'Bookmarked story')],
    );
    final bloc = buildBloc(repository, savedRepository: savedRepository);
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    final state = await awaitState(
      bloc,
      (state) => state.lastUpdated != null && state.savedArticles.isNotEmpty,
      'the saved articles were loaded',
    );

    expect(state.status, FeedStatus.ready);
    expect(state.errorMessage, isNull);
    expect(state.articles.map((a) => a.guid), ['fresh']);
    expect(state.savedArticles.map((a) => a.guid), ['saved']);
    expect(state.section, FeedSection.today);
    expect(savedRepository.savedArticlesCalls, 1);
  });

  test('a saved-load failure during start is silent', () async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'fresh')];
    final savedRepository = FakeSavedArticleRepository()
      ..savedArticlesError = const FeedCacheFailure(
        'Saved storage unavailable',
      );
    final bloc = buildBloc(repository, savedRepository: savedRepository);
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    final state = await awaitState(
      bloc,
      (state) => state.lastUpdated != null,
      'the today feed finished refreshing',
    );

    expect(state.status, FeedStatus.ready);
    expect(state.errorMessage, isNull);
    expect(state.articles.map((a) => a.guid), ['fresh']);
    expect(state.savedArticles, isEmpty);
    // The load must have been attempted at all: a broken saved store shows up
    // as an empty list, never as an error.
    expect(savedRepository.savedArticlesCalls, 1);
  });

  test(
    'FeedSectionToggled switches to saved and exposes the saved list',
    () async {
      final repository = FakeArticleRepository()
        ..refreshed = [article(guid: 'fresh', title: 'Today story')];
      final savedRepository = FakeSavedArticleRepository(
        saved: [
          article(
            guid: 'saved-new',
            title: 'Newest save',
            publishedAt: DateTime(2026, 10, 26, 9),
          ),
          article(
            guid: 'saved-old',
            title: 'Older save',
            publishedAt: DateTime(2026, 10, 20, 9),
          ),
        ],
      );
      final bloc = buildBloc(repository, savedRepository: savedRepository);
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed refreshed',
      );

      bloc.add(const FeedSectionToggled());
      final state = await awaitState(
        bloc,
        (state) => state.section == FeedSection.saved,
        'the saved section is active',
      );

      // Exactly what LoadSavedArticles returned: newest published first.
      expect(state.visibleArticles.map((a) => a.identity), [
        'saved-new',
        'saved-old',
      ]);
      expect(state.savedArticles.map((a) => a.identity), [
        'saved-new',
        'saved-old',
      ]);
      expect(state.hasSavedArticles, isTrue);
      expect(state.articles.map((a) => a.guid), ['fresh']);
    },
  );

  test(
    'FeedSectionToggled back to today restores today and keeps saved',
    () async {
      final repository = FakeArticleRepository()
        ..refreshed = [article(guid: 'fresh', title: 'Today story')];
      final savedRepository = FakeSavedArticleRepository(
        saved: [article(guid: 'saved', title: 'Saved story')],
      );
      final bloc = buildBloc(repository, savedRepository: savedRepository);
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed refreshed',
      );

      bloc
        ..add(const FeedSectionToggled())
        ..add(const FeedSectionToggled());
      final state = await awaitState(
        bloc,
        (state) => state.section == FeedSection.today,
        'the today section is active again',
      );

      expect(state.articles.map((a) => a.guid), ['fresh']);
      expect(state.visibleArticles.map((a) => a.guid), ['fresh']);
      // Switching back must not throw the saved list away.
      expect(state.savedArticles.map((a) => a.identity), ['saved']);
      expect(state.hasSavedArticles, isTrue);
    },
  );

  test('switching to saved reloads the repository every time', () async {
    final savedRepository = FakeSavedArticleRepository();
    final bloc = buildBloc(
      FakeArticleRepository()..refreshed = [article(guid: 'fresh')],
      savedRepository: savedRepository,
    );
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    await awaitState(
      bloc,
      (state) => state.lastUpdated != null,
      'the today feed refreshed',
    );
    final callsAfterStart = savedRepository.savedArticlesCalls;

    bloc.add(const FeedSectionToggled());
    var state = await awaitState(
      bloc,
      (state) => state.section == FeedSection.saved,
      'the saved section is active',
    );
    expect(state.savedArticles, isEmpty);
    // Switching to saved reads the store instead of replaying a stale list.
    expect(
      savedRepository.savedArticlesCalls,
      greaterThan(callsAfterStart),
      reason: 'switching to saved must reload the saved list',
    );

    // A bookmark made on the detail page while the feed kept running.
    await savedRepository.save(
      article(guid: 'just-saved', title: 'Saved on the detail page'),
    );

    bloc.add(const FeedSectionToggled());
    await awaitState(
      bloc,
      (state) => state.section == FeedSection.today,
      'the today section is active',
    );

    final callsBeforeSecondSwitch = savedRepository.savedArticlesCalls;
    bloc.add(const FeedSectionToggled());
    state = await awaitState(
      bloc,
      (state) => state.section == FeedSection.saved && state.hasSavedArticles,
      'the new bookmark shows up in the saved list',
    );

    expect(state.savedArticles.map((a) => a.identity), ['just-saved']);
    expect(savedRepository.savedArticlesCalls, callsBeforeSecondSwitch + 1);
  });

  test('FeedSavedReloadRequested picks up a newly saved article', () async {
    final savedRepository = FakeSavedArticleRepository();
    final bloc = buildBloc(
      FakeArticleRepository(),
      savedRepository: savedRepository,
    );
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    await awaitState(
      bloc,
      (state) => state.lastUpdated != null,
      'the today feed finished starting',
    );

    await savedRepository.save(
      article(guid: 'later', title: 'Bookmarked later'),
    );
    bloc.add(const FeedSavedReloadRequested());
    final state = await awaitState(
      bloc,
      (state) => state.savedArticles.isNotEmpty,
      'the saved list was reloaded',
    );

    expect(state.savedArticles.map((a) => a.identity), ['later']);
    expect(state.section, FeedSection.today);
  });

  test(
    'a failed saved reload keeps the previous list and reports savedFailed',
    () async {
      final savedRepository = FakeSavedArticleRepository(
        saved: [article(guid: 'saved', title: 'Saved story')],
      );
      final bloc = buildBloc(
        FakeArticleRepository(),
        savedRepository: savedRepository,
      );
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed finished starting',
      );
      final statusBefore = bloc.state.status;
      final sectionBefore = bloc.state.section;

      savedRepository.savedArticlesError = const FeedCacheFailure(
        'Saved storage unavailable',
      );
      bloc.add(const FeedSavedReloadRequested());
      final state = await awaitState(
        bloc,
        (state) => state.notice?.kind == FeedNoticeKind.savedFailed,
        'the failed saved reload is reported',
      );

      expect(state.savedArticles.map((a) => a.identity), ['saved']);
      expect(state.notice!.message, 'Saved storage unavailable');
      expect(state.section, sectionBefore);
      expect(state.status, statusBefore);
      expect(state.errorMessage, isNull);
    },
  );

  test(
    'FeedStarted with a healthy saved store leaves savedErrorMessage null',
    () async {
      final savedRepository = FakeSavedArticleRepository(
        saved: [article(guid: 'saved', title: 'Saved story')],
      );
      final bloc = buildBloc(
        FakeArticleRepository()..refreshed = [article(guid: 'fresh')],
        savedRepository: savedRepository,
      );
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      final state = await awaitState(
        bloc,
        (state) => state.lastUpdated != null && state.hasSavedArticles,
        'the today feed refreshed and the saved list loaded',
      );

      expect(state.savedErrorMessage, isNull);
      expect(state.errorMessage, isNull);
      expect(state.notice, isNull);
      expect(state.savedArticles.map((a) => a.identity), ['saved']);
    },
  );

  test(
    'a failed saved reload records savedErrorMessage and keeps the list',
    () async {
      final savedRepository = FakeSavedArticleRepository(
        saved: [article(guid: 'saved', title: 'Saved story')],
      );
      final bloc = buildBloc(
        FakeArticleRepository(),
        savedRepository: savedRepository,
      );
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed finished starting',
      );
      expect(
        bloc.state.savedErrorMessage,
        isNull,
        reason: 'precondition: a healthy read leaves no saved error',
      );

      savedRepository.savedArticlesError = const FeedCacheFailure(
        'Saved storage unavailable',
      );
      bloc.add(const FeedSavedReloadRequested());
      final state = await awaitState(
        bloc,
        (state) => state.savedErrorMessage != null,
        'the failed saved read is recorded in the state',
      );

      expect(
        state.savedErrorMessage,
        'Saved storage unavailable',
        reason:
            'the FeedFailure message is surfaced verbatim, not a generic one',
      );
      expect(state.savedArticles.map((a) => a.identity), [
        'saved',
      ], reason: 'a failed read must not blank the list the user was reading');
      expect(state.notice!.kind, FeedNoticeKind.savedFailed);
      expect(
        state.errorMessage,
        isNull,
        reason: 'a broken saved store must never claim the today feed failed',
      );
    },
  );

  test('a later successful saved reload clears savedErrorMessage', () async {
    final savedRepository = FakeSavedArticleRepository(
      saved: [article(guid: 'saved', title: 'Saved story')],
    );
    final bloc = buildBloc(
      FakeArticleRepository(),
      savedRepository: savedRepository,
    );
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    await awaitState(
      bloc,
      (state) => state.lastUpdated != null,
      'the today feed finished starting',
    );

    savedRepository.savedArticlesError = const FeedCacheFailure(
      'Saved storage unavailable',
    );
    bloc.add(const FeedSavedReloadRequested());
    await awaitState(
      bloc,
      (state) => state.savedErrorMessage != null,
      'the failed saved read is recorded',
    );

    savedRepository
      ..savedArticlesError = null
      ..saved.add(article(guid: 'recovered', title: 'Recovered story'));
    bloc.add(const FeedSavedReloadRequested());
    final state = await awaitState(
      bloc,
      (state) => state.savedArticles.any((a) => a.identity == 'recovered'),
      'the recovered saved list is in the state',
    );

    expect(
      state.savedErrorMessage,
      isNull,
      reason: 'a successful read is the only thing that clears the error',
    );
    expect(state.savedArticles.map((a) => a.identity), contains('recovered'));
  });

  test(
    'switching to saved when the read fails keeps the list and sets the error',
    () async {
      final savedRepository = FakeSavedArticleRepository(
        saved: [article(guid: 'saved', title: 'Saved story')],
      );
      final bloc = buildBloc(
        FakeArticleRepository()..refreshed = [article(guid: 'fresh')],
        savedRepository: savedRepository,
      );
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null && state.hasSavedArticles,
        'the today feed refreshed and the saved list loaded',
      );

      savedRepository.savedArticlesError = const FeedCacheFailure(
        'Saved storage unavailable',
      );
      bloc.add(const FeedSectionToggled());
      final state = await awaitState(
        bloc,
        (state) => state.section == FeedSection.saved,
        'the saved section is active',
      );

      expect(state.savedArticles.map((a) => a.identity), [
        'saved',
      ], reason: 'the previously loaded list survives a failed re-read');
      expect(state.savedErrorMessage, 'Saved storage unavailable');
      expect(state.notice!.kind, FeedNoticeKind.savedFailed);
      expect(state.errorMessage, isNull);
    },
  );

  test(
    'FeedSavedArticleRemoved removes by identity, reloads, and the row goes',
    () async {
      final kept = article(guid: 'kept', title: 'Kept story');
      final removed = article(guid: 'gone', title: 'Gone story');
      final savedRepository = FakeSavedArticleRepository(
        saved: [removed, kept],
      );
      final bloc = buildBloc(
        FakeArticleRepository(),
        savedRepository: savedRepository,
      );
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed finished starting',
      );

      final callsBeforeRemoval = savedRepository.savedArticlesCalls;
      bloc.add(FeedSavedArticleRemoved(removed));
      final state = await awaitState(
        bloc,
        (state) =>
            !state.savedArticles.any((a) => a.identity == 'gone') &&
            savedRepository.savedArticlesCalls == callsBeforeRemoval + 1,
        'the removal finished and the saved list was reloaded',
      );

      expect(savedRepository.removedIdentities, ['gone']);
      expect(savedRepository.removeCalls, 1);
      expect(state.savedArticles.map((a) => a.identity), ['kept']);
    },
  );

  test('a failed removal keeps the row and reports savedFailed', () async {
    final target = article(guid: 'stubborn', title: 'Stubborn story');
    final savedRepository = FakeSavedArticleRepository(saved: [target])
      ..removeError = const FeedCacheFailure('Could not update saved articles');
    final bloc = buildBloc(
      FakeArticleRepository(),
      savedRepository: savedRepository,
    );
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    await awaitState(
      bloc,
      (state) => state.lastUpdated != null,
      'the today feed finished starting',
    );
    final statusBefore = bloc.state.status;

    bloc.add(FeedSavedArticleRemoved(target));
    final state = await awaitState(
      bloc,
      (state) => state.notice?.kind == FeedNoticeKind.savedFailed,
      'the failed removal is reported',
    );

    expect(state.savedArticles.map((a) => a.identity), ['stubborn']);
    expect(state.hasSavedArticles, isTrue);
    expect(state.notice!.message, 'Could not update saved articles');
    expect(state.status, statusBefore);
  });

  test(
    'FeedSavedArticleRestored writes the article back and reloads',
    () async {
      final removed = article(guid: 'gone', title: 'Gone story');
      final kept = article(
        guid: 'kept',
        title: 'Kept story',
        publishedAt: DateTime(2026, 10, 26, 9),
      );
      final savedRepository = FakeSavedArticleRepository(
        saved: [removed, kept],
      );
      final bloc = buildBloc(
        FakeArticleRepository(),
        savedRepository: savedRepository,
      );
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed finished starting',
      );
      bloc.add(const FeedSectionToggled());
      await awaitState(
        bloc,
        (state) => state.section == FeedSection.saved,
        'the saved section is active',
      );

      // The user removed a row, then pressed UNDO.
      bloc.add(FeedSavedArticleRemoved(removed));
      await awaitState(
        bloc,
        (state) => !state.savedArticles.any((a) => a.identity == 'gone'),
        'the removal finished',
      );
      expect(savedRepository.removeCalls, 1);

      final callsBeforeRestore = savedRepository.savedArticlesCalls;
      bloc.add(FeedSavedArticleRestored(removed));
      final state = await awaitState(
        bloc,
        (state) => state.savedArticles.any((a) => a.identity == 'gone'),
        'the removed article is back in the saved list',
      );

      expect(savedRepository.saveCalls, 1);
      expect(savedRepository.savedArguments.map((a) => a.identity), ['gone']);
      expect(
        savedRepository.savedArticlesCalls,
        callsBeforeRestore + 1,
        reason: 'the list is re-read from the store, not patched locally',
      );
      expect(
        state.section,
        FeedSection.saved,
        reason: 'UNDO must not bounce the user out of the saved section',
      );
      expect(state.savedErrorMessage, isNull);
      expect(state.notice, isNull, reason: 'a successful undo needs no notice');
    },
  );

  test('a failed restore keeps the list and reports savedFailed', () async {
    final stored = article(guid: 'stored', title: 'Stored story');
    final savedRepository = FakeSavedArticleRepository(saved: [stored]);
    final bloc = buildBloc(
      FakeArticleRepository(),
      savedRepository: savedRepository,
    );
    addTearDown(bloc.close);

    bloc.add(const FeedStarted());
    await awaitState(
      bloc,
      (state) => state.lastUpdated != null,
      'the today feed finished starting',
    );

    savedRepository.saveError = const FeedCacheFailure(
      'Could not update saved articles',
    );
    bloc.add(FeedSavedArticleRestored(article(guid: 'restore-me')));
    final state = await awaitState(
      bloc,
      (state) => state.notice?.kind == FeedNoticeKind.savedFailed,
      'the failed restore is reported',
    );

    expect(
      savedRepository.saveCalls,
      1,
      reason: 'the restore must reach the repository before failing',
    );
    expect(
      state.notice!.message,
      'Could not update saved articles',
      reason: 'the failure message is mapped, not replaced by a generic one',
    );
    expect(state.savedArticles.map((a) => a.identity), [
      'stored',
    ], reason: 'a failed write leaves the visible list untouched');
  });

  test(
    'restoring an article that is already saved does not duplicate it',
    () async {
      final stored = article(guid: 'stored', title: 'Stored story');
      final savedRepository = FakeSavedArticleRepository(saved: [stored]);
      final bloc = buildBloc(
        FakeArticleRepository(),
        savedRepository: savedRepository,
      );
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed finished starting',
      );

      final callsBeforeRestore = savedRepository.savedArticlesCalls;
      bloc.add(FeedSavedArticleRestored(stored));
      final state = await awaitState(
        bloc,
        (state) =>
            savedRepository.saveCalls == 1 &&
            savedRepository.savedArticlesCalls == callsBeforeRestore + 1,
        'the restore wrote through and reloaded the list',
      );

      expect(state.savedArticles.map((a) => a.identity), ['stored']);
      expect(state.savedArticles, hasLength(1));
      expect(
        state.notice,
        isNull,
        reason: 'a second UNDO on a saved article is a no-op, not an error',
      );
    },
  );

  test(
    'FeedRefreshRequested leaves the saved list and section untouched',
    () async {
      final repository = FakeArticleRepository()
        ..refreshed = [article(guid: 'first')];
      final savedRepository = FakeSavedArticleRepository(
        saved: [article(guid: 'saved', title: 'Saved story')],
      );
      final bloc = buildBloc(repository, savedRepository: savedRepository);
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed refreshed',
      );

      bloc.add(const FeedSectionToggled());
      await awaitState(
        bloc,
        (state) => state.section == FeedSection.saved,
        'the saved section is active',
      );

      repository.refreshed = [article(guid: 'second')];
      bloc.add(const FeedRefreshRequested());
      final state = await awaitState(
        bloc,
        (state) => state.articles.any((a) => a.guid == 'second'),
        'the today feed refreshed again',
      );

      expect(state.section, FeedSection.saved);
      expect(state.savedArticles.map((a) => a.identity), ['saved']);
      expect(state.visibleArticles.map((a) => a.identity), ['saved']);
      expect(state.articles.map((a) => a.guid), ['second']);
    },
  );

  test(
    'visibleArticles follows the active section in both directions',
    () async {
      final repository = FakeArticleRepository()
        ..refreshed = [article(guid: 'today', title: 'Today story')];
      final savedRepository = FakeSavedArticleRepository(
        saved: [article(guid: 'saved', title: 'Saved story')],
      );
      final bloc = buildBloc(repository, savedRepository: savedRepository);
      addTearDown(bloc.close);

      bloc.add(const FeedStarted());
      var state = await awaitState(
        bloc,
        (state) => state.lastUpdated != null,
        'the today feed refreshed',
      );

      expect(state.section, FeedSection.today);
      expect(state.visibleArticles.map((a) => a.identity), ['today']);

      bloc.add(const FeedSectionToggled());
      state = await awaitState(
        bloc,
        (state) => state.section == FeedSection.saved,
        'the saved section is active',
      );
      expect(state.visibleArticles.map((a) => a.identity), ['saved']);

      bloc.add(const FeedSectionToggled());
      state = await awaitState(
        bloc,
        (state) => state.section == FeedSection.today,
        'the today section is active again',
      );
      expect(state.visibleArticles.map((a) => a.identity), ['today']);
      expect(state.hasSavedArticles, isTrue);
    },
  );
}
