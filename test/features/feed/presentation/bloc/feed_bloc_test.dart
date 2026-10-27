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
  }) => buildTestFeedBloc(
    repository: repository,
    opener: opener,
    clock: () => fixedNow,
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
}
