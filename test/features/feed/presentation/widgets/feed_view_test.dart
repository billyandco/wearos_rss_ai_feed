import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/core/theme/app_theme.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
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
    void Function(Article article)? onOpenArticle,
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
          child: FeedView(clock: () => testNow, onOpenArticle: onOpenArticle),
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

  /// Target opacity of the header's implicit fade, or null when the header is
  /// missing. Reading the [AnimatedOpacity] widget property (not the animated
  /// value) keeps the assertion independent of animation duration.
  double? headerOpacity(WidgetTester tester) {
    final finder = find.byKey(const Key('feed-header-opacity'));
    if (finder.evaluate().isEmpty) {
      return null;
    }
    return tester.widget<AnimatedOpacity>(finder).opacity;
  }

  /// Pumps virtual time in slices until [done] flips, so futures that depend on
  /// animations (e.g. pull-to-refresh) can finish without `pumpAndSettle`.
  Future<bool> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 120 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return done();
  }

  List<Article> twentyArticles() => [
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

  testWidgets('tapping an article opens its detail page', (tester) async {
    final navigated = <Article>[];
    final opener = RecordingRemoteOpener();
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: 'detail-1',
          title: 'Single tap opens the detail page',
          link: 'https://example.com/detail-1',
          publishedAt: testNow.subtract(const Duration(minutes: 5)),
        ),
        article(
          guid: 'detail-2',
          title: 'Second story',
          link: 'https://example.com/detail-2',
          publishedAt: testNow.subtract(const Duration(minutes: 15)),
        ),
        article(
          guid: 'detail-3',
          title: 'Third story',
          link: 'https://example.com/detail-3',
          publishedAt: testNow.subtract(const Duration(minutes: 25)),
        ),
      ];
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      opener: opener,
      onOpenArticle: navigated.add,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    final row = find.byKey(const Key('article-row-detail-1'));
    expect(row, findsOneWidget);

    await tester.tap(row);
    // A single tap only resolves once the double-tap window has elapsed.
    await tester.pump(const Duration(milliseconds: 400));
    await settleFeed(tester);

    expect(
      navigated.map((item) => item.guid).toList(),
      ['detail-1'],
      reason:
          'exactly the tapped article must be handed to the navigation hook',
    );
    expect(
      opener.opened,
      isEmpty,
      reason: 'a single tap navigates, it must never ask the phone to open',
    );
    expect(
      find.text('Opening on your phone'),
      findsNothing,
      reason: 'a single tap must not show the open-on-phone confirmation',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap still opens on phone and does not navigate', (
    tester,
  ) async {
    final navigated = <Article>[];
    final opener = RecordingRemoteOpener();
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: 'double-detail',
          title: 'Double tap still phones home',
          link: 'https://example.com/double-detail',
          publishedAt: testNow.subtract(const Duration(minutes: 10)),
        ),
      ];
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      opener: opener,
      onOpenArticle: navigated.add,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    final row = find.byKey(const Key('article-row-double-detail'));
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 64));
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 20));
    await settleFeed(tester);

    expect(opener.opened, [Uri.parse('https://example.com/double-detail')]);
    expect(
      navigated,
      isEmpty,
      reason: 'a double tap must not also push the detail page',
    );
    expect(find.text('Opening on your phone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('article rows expose a hero tag', (tester) async {
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: 'hero-1',
          title: 'Hero tagged story',
          publishedAt: testNow.subtract(const Duration(minutes: 3)),
        ),
      ];
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    final heroFinder = find.descendant(
      of: find.byKey(const Key('article-row-hero-1')),
      matching: find.byType(Hero),
    );
    expect(
      heroFinder,
      findsOneWidget,
      reason:
          'every article row must be wrapped in a Hero for the shared '
          'transition into the detail page',
    );
    expect(tester.widget<Hero>(heroFinder).tag, 'article-hero-hero-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero tag falls back to the link when the guid is empty', (
    tester,
  ) async {
    const link = 'https://example.com/no-guid';
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: '',
          link: link,
          title: 'Story without a guid',
          publishedAt: testNow.subtract(const Duration(minutes: 4)),
        ),
      ];
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    final heroFinder = find.descendant(
      of: find.byKey(const Key('article-row-$link')),
      matching: find.byType(Hero),
    );
    expect(
      heroFinder,
      findsOneWidget,
      reason: 'rows stay keyed by Article.identity, which is the link here',
    );
    expect(
      tester.widget<Hero>(heroFinder).tag,
      'article-hero-$link',
      reason: 'the hero tag must be built from Article.identity',
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('hides the header when scrolling down and shows it again when '
      'scrolling up', (tester) async {
    final repository = FakeArticleRepository()..refreshed = twentyArticles();
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(find.byKey(const Key('feed-header')), findsOneWidget);
    expect(
      headerOpacity(tester),
      1.0,
      reason: 'the header is always visible at the top of the list',
    );

    await tester.drag(
      find.byKey(const Key('feed-list')),
      const Offset(0, -400),
    );
    await settleFeed(tester);

    expect(
      headerOpacity(tester),
      0.0,
      reason: 'scrolling down past the threshold must fade the header out',
    );

    await tester.drag(find.byKey(const Key('feed-list')), const Offset(0, 200));
    await settleFeed(tester);

    expect(
      headerOpacity(tester),
      1.0,
      reason: 'scrolling back up must fade the header in',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the header visible while the list is at the top', (
    tester,
  ) async {
    final repository = FakeArticleRepository()..refreshed = twentyArticles();
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    // Establish the hidden state first, so returning to the top is what makes
    // the header visible again.
    await tester.drag(
      find.byKey(const Key('feed-list')),
      const Offset(0, -400),
    );
    await settleFeed(tester);
    expect(
      headerOpacity(tester),
      0.0,
      reason: 'precondition: scrolling down fades the header out',
    );

    await tester.drag(
      find.byKey(const Key('feed-list')),
      const Offset(0, 2000),
    );
    await settleFeed(tester);

    expect(
      headerOpacity(tester),
      1.0,
      reason: 'at offset 0 (even while overscrolling) the header is visible',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no longer renders a refresh button in the header', (
    tester,
  ) async {
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: 'header-1',
          publishedAt: testNow.subtract(const Duration(minutes: 3)),
        ),
      ];
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(find.byKey(const Key('feed-header')), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byKey(const Key('feed-refresh')), findsNothing);
    expect(find.byKey(const Key('feed-refreshing')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('feed-header')),
        matching: find.byType(IconButton),
      ),
      findsNothing,
      reason: 'the header must not host any icon button anymore',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('feed-header')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
      reason: 'the header must not host a refreshing spinner anymore',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('feed-header')),
        matching: find.byKey(const Key('feed-header-opacity')),
      ),
      findsOneWidget,
      reason: 'the fade lives inside the keyed header',
    );
  });

  testWidgets('wraps the feed in a pull-to-refresh indicator', (tester) async {
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: 'pull-1',
          publishedAt: testNow.subtract(const Duration(minutes: 4)),
        ),
      ];
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(find.byKey(const Key('feed-list')), findsOneWidget);
    expect(
      find.byType(RefreshIndicator),
      findsOneWidget,
      reason: 'the article list must be wrapped in a RefreshIndicator',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull-to-refresh asks the bloc to refresh', (tester) async {
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: 'pull-2',
          publishedAt: testNow.subtract(const Duration(minutes: 6)),
        ),
      ];
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(repository.refreshCalls, 1);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );

    var refreshCompleted = false;
    Object? refreshError;
    unawaited(() async {
      try {
        await indicator.onRefresh();
        refreshCompleted = true;
      } catch (error) {
        refreshError = error;
      }
    }());

    final finished = await pumpUntil(tester, () => refreshCompleted);
    await settleFeed(tester);

    expect(
      repository.refreshCalls,
      2,
      reason: 'pull-to-refresh must dispatch FeedRefreshRequested',
    );
    expect(
      finished,
      isTrue,
      reason: 'the onRefresh future must complete instead of hanging',
    );
    expect(refreshError, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull gesture from the top triggers a refresh', (tester) async {
    final repository = FakeArticleRepository()..refreshed = twentyArticles();
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(
      repository.refreshCalls,
      1,
      reason: 'precondition: FeedStarted performs the initial fetch',
    );

    // A real finger, not `indicator.onRefresh()`: only the framework's own
    // scroll notifications may arm the indicator and start the refresh.
    await tester.fling(
      find.byKey(const Key('feed-list')),
      const Offset(0, 300),
      1000,
    );
    await tester.pump();

    // Bounded pump loop (120 * 50ms = 6s of virtual time) so the pull can
    // settle without `pumpAndSettle` hanging on the spinner.
    final pulled = await pumpUntil(tester, () => repository.refreshCalls >= 2);
    await settleFeed(tester);

    expect(
      pulled,
      isTrue,
      reason: 'the pull gesture must reach the bloc through the indicator',
    );
    expect(
      repository.refreshCalls,
      2,
      reason: 'a real pull gesture must refresh exactly once more',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the header again when the article list is replaced', (
    tester,
  ) async {
    final repository = FakeArticleRepository()..refreshed = twentyArticles();
    final bloc = await pumpFeedView(tester, repository: repository);
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    await tester.drag(
      find.byKey(const Key('feed-list')),
      const Offset(0, -400),
    );
    await settleFeed(tester);
    expect(
      headerOpacity(tester),
      0.0,
      reason: 'precondition: scrolling down fades the header out',
    );

    // The bloc drops refresh requests while one is in flight, so wait for the
    // first fetch to finish before asking for the replacement.
    final idle = await pumpUntil(tester, () => !bloc.state.isRefreshing);
    expect(
      idle,
      isTrue,
      reason: 'precondition: the initial refresh has finished',
    );

    repository.refreshed = [article(guid: 'fresh-1', title: 'Fresh story')];
    bloc.add(const FeedRefreshRequested());

    final replaced = await pumpUntil(
      tester,
      () => bloc.state.articles.any((item) => item.guid == 'fresh-1'),
    );
    expect(
      replaced,
      isTrue,
      reason: 'precondition: the repository now serves the new list',
    );
    await settleFeed(tester);

    expect(
      find.text('Fresh story'),
      findsOneWidget,
      reason: 'precondition: the new list is on screen',
    );
    expect(
      headerOpacity(tester),
      1.0,
      reason: 'header must not stay hidden after the list is replaced',
    );
    expect(tester.takeException(), isNull);
  });
}
