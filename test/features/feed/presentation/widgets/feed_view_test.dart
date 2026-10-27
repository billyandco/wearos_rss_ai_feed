import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/core/theme/app_theme.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_bloc.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_event.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/widgets/feed_view.dart';

import '../../../../support/article_factory.dart';
import '../../../../support/feed_test_doubles.dart';

void main() {
  final testNow = DateTime(2026, 10, 27, 18);

  Future<FeedBloc> pumpFeedView(
    WidgetTester tester, {
    required FakeArticleRepository repository,
    RecordingRemoteOpener? opener,
  }) async {
    tester.view.physicalSize = const Size(450, 450);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = buildTestFeedBloc(
      repository: repository,
      opener: opener,
      clock: () => testNow,
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWearTheme(),
        home: BlocProvider<FeedBloc>.value(
          value: bloc,
          child: FeedView(clock: () => testNow),
        ),
      ),
    );
    return bloc;
  }

  Future<void> settleFeed(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('renders a loading state while the first fetch runs', (
    tester,
  ) async {
    final repository = FakeArticleRepository()..refreshGate = Completer<void>();
    await pumpFeedView(tester, repository: repository);

    expect(find.byKey(const Key('feed-loading')), findsOneWidget);
    expect(find.text("Fetching today's AI news"), findsOneWidget);

    repository.refreshGate!.complete();
  });

  testWidgets(
    'lists merged articles with source, time, title and description',
    (tester) async {
      final repository = FakeArticleRepository()
        ..refreshed = [
          article(
            guid: 'decoder-1',
            sourceName: 'The Decoder',
            title: 'Anthropic pledges no ads in Claude',
            description: 'The company argues answers should stay the priority.',
            publishedAt: testNow.subtract(const Duration(hours: 2)),
          ),
          article(
            guid: 'hf-1',
            sourceName: 'Hugging Face Blog',
            title: 'LitPivot for literature research',
            description: null,
            author: null,
            publishedAt: testNow.subtract(const Duration(minutes: 20)),
            link: 'https://huggingface.co/blog/allenai/litpivot',
          ),
        ];

      final bloc = await pumpFeedView(tester, repository: repository);
      bloc.add(const FeedStarted());
      await settleFeed(tester);

      expect(find.byKey(const Key('feed-list')), findsOneWidget);
      expect(find.text('The Decoder'), findsOneWidget);
      expect(find.text('Hugging Face Blog'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);
      expect(find.text('20m'), findsOneWidget);
      expect(find.text('Anthropic pledges no ads in Claude'), findsOneWidget);
      expect(
        find.text('The company argues answers should stay the priority.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('article-description-hf-1')),
        findsNothing,
        reason:
            'Hugging Face items have no description and must render cleanly',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('double-tapping a row asks the phone to open the link', (
    tester,
  ) async {
    final opener = RecordingRemoteOpener();
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: 'tap-me',
          title: 'Double tap this story',
          link: 'https://example.com/double-tap',
          publishedAt: testNow.subtract(const Duration(minutes: 10)),
        ),
      ];
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      opener: opener,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    final row = find.byKey(const Key('article-row-tap-me'));
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 64));
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 20));
    await settleFeed(tester);

    expect(opener.opened, [Uri.parse('https://example.com/double-tap')]);
    expect(find.text('Opening on your phone'), findsOneWidget);
  });

  testWidgets('shows the failure message and retries', (tester) async {
    final repository = FakeArticleRepository()
      ..refreshError = const FeedUnavailableFailure(
        'Could not reach any news source.',
      );
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(find.byKey(const Key('feed-error')), findsOneWidget);
    expect(find.text('Could not reach any news source.'), findsOneWidget);
    expect(repository.refreshCalls, 1);

    await tester.tap(find.byKey(const Key('feed-retry')));
    await settleFeed(tester);

    expect(repository.refreshCalls, 2);
  });

  testWidgets('shows a friendly empty state when no article is from today', (
    tester,
  ) async {
    final repository = FakeArticleRepository()..refreshed = const [];
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(find.byKey(const Key('feed-empty')), findsOneWidget);
    expect(find.text('No AI news yet today'), findsOneWidget);
    expect(find.byKey(const Key('feed-empty-refresh')), findsOneWidget);
  });

  testWidgets('scrolls a long list through the round edges without overflow', (
    tester,
  ) async {
    final repository = FakeArticleRepository()
      ..refreshed = [
        for (var i = 0; i < 20; i++)
          article(
            guid: 'long-$i',
            title: 'Story $i about very long model names and benchmarks',
            description:
                'A summary that is long enough to wrap over several lines on a '
                'watch screen and test the row height constraints.',
            publishedAt: testNow.subtract(Duration(minutes: i + 1)),
          ),
      ];
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const Key('feed-list')),
      const Offset(0, -1600),
    );
    await settleFeed(tester);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const Key('feed-list')),
      const Offset(0, 2000),
    );
    await settleFeed(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps cached rows visible when a refresh fails', (tester) async {
    final repository = FakeArticleRepository()
      ..cached = [article(guid: 'cached-story', title: 'Cached story')]
      ..refreshError = const FeedNetworkFailure('Offline');
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(find.text('Cached story'), findsOneWidget);
    expect(find.byKey(const Key('feed-list')), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });
}
