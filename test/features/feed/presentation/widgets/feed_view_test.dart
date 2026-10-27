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
    FakeSavedArticleRepository? savedRepository,
    void Function(Article article)? onOpenArticle,
  }) async {
    tester.view.physicalSize = const Size(450, 450);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bloc = buildTestFeedBloc(
      repository: repository,
      opener: opener,
      savedRepository: savedRepository,
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

  /// Taps the header pill, the only way into the saved list.
  Future<void> tapSectionToggle(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('feed-header-toggle')));
    await settleFeed(tester);
  }

  /// Scroll offset of the list behind [listKey].
  double scrollOffset(WidgetTester tester, Key listKey) {
    final finder = find.descendant(
      of: find.byKey(listKey),
      matching: find.byType(Scrollable),
    );
    return tester.state<ScrollableState>(finder).position.pixels;
  }

  /// The label inside the header toggle, in whichever mode it is.
  Text headerLabel(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label));

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

  /// A saved library long enough to scroll: the saved list has no refresh
  /// indicator, so it is the only list whose scroll can be studied alone.
  List<Article> twentySavedArticles() => [
    for (var i = 0; i < 20; i++)
      article(
        guid: 'saved-long-$i',
        title: 'Bookmarked story $i about very long model names',
        description:
            'A saved summary that is long enough to wrap over several lines '
            'and test the row height constraints.',
        publishedAt: testNow.subtract(Duration(hours: i + 1)),
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

  testWidgets(
    'fades the header away while reading today and pins it in the saved list',
    (tester) async {
      final repository = FakeArticleRepository()..refreshed = twentyArticles();
      final savedRepository = FakeSavedArticleRepository(
        saved: twentySavedArticles(),
      );
      final bloc = await pumpFeedView(
        tester,
        repository: repository,
        savedRepository: savedRepository,
      );
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

      await tester.drag(
        find.byKey(const Key('feed-list')),
        const Offset(0, 200),
      );
      await settleFeed(tester);

      expect(
        headerOpacity(tester),
        1.0,
        reason: 'scrolling back up must fade the header in',
      );

      // Now the same gesture on the saved list, where the header is pinned.
      await tapSectionToggle(tester);
      expect(
        find.text('SAVED'),
        findsOneWidget,
        reason: 'precondition: the saved section is on screen',
      );

      await tester.drag(
        find.byKey(const Key('saved-list')),
        const Offset(0, -400),
      );
      await settleFeed(tester);

      expect(
        scrollOffset(tester, const Key('saved-list')),
        greaterThan(0),
        reason: 'precondition: the saved list is really scrolled down',
      );
      expect(
        headerOpacity(tester),
        1.0,
        reason:
            'in SAVED the header is the only mode indicator and the only way '
            'back to today, so reading down must never fade it out',
      );

      // It must also stay usable, not just painted: the faded header ignores
      // pointers, so a pinned header that still armed IgnorePointer would be a
      // dead end.
      await tapSectionToggle(tester);
      expect(
        find.text('TODAY'),
        findsOneWidget,
        reason: 'the pinned header must still be tappable while scrolled',
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  // ---------------------------------------------------------------------------
  // Saved section
  // ---------------------------------------------------------------------------

  testWidgets('the header toggle switches between TODAY and SAVED', (
    tester,
  ) async {
    final repository = FakeArticleRepository()
      ..refreshed = [
        article(
          guid: 'today-1',
          title: 'Today story',
          publishedAt: testNow.subtract(const Duration(minutes: 5)),
        ),
      ];
    final savedRepository = FakeSavedArticleRepository(
      saved: [
        article(
          guid: 'saved-1',
          title: 'Saved story',
          publishedAt: testNow.subtract(const Duration(days: 1)),
        ),
      ],
    );
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: savedRepository,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byKey(const Key('feed-list')), findsOneWidget);
    expect(find.text('Today story'), findsOneWidget);
    expect(find.byKey(const Key('saved-list')), findsNothing);
    expect(find.text('SAVED'), findsNothing);

    await tapSectionToggle(tester);

    expect(find.text('SAVED'), findsOneWidget);
    expect(find.text('TODAY'), findsNothing);
    expect(find.byKey(const Key('saved-list')), findsOneWidget);
    expect(find.text('Saved story'), findsOneWidget);
    expect(
      find.text('Today story'),
      findsNothing,
      reason: 'only one list is on a 1.2" screen at a time',
    );

    await tapSectionToggle(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byKey(const Key('feed-list')), findsOneWidget);
    expect(find.text('Today story'), findsOneWidget);
    expect(find.text('Saved story'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the header toggle is a 44 dp target that reacts above the pill',
    (tester) async {
      final repository = FakeArticleRepository()
        ..refreshed = [article(guid: 'today-1', title: 'Today story')];
      final bloc = await pumpFeedView(
        tester,
        repository: repository,
        savedRepository: FakeSavedArticleRepository(),
      );
      bloc.add(const FeedStarted());
      await settleFeed(tester);

      final toggle = find.byKey(const Key('feed-header-toggle'));
      expect(toggle, findsOneWidget);

      final rect = tester.getRect(toggle);
      expect(
        rect.height,
        greaterThanOrEqualTo(44),
        reason:
            'the band must be 44 dp tall: the visual pill alone is too small',
      );
      expect(
        rect.width,
        greaterThanOrEqualTo(44),
        reason: 'a narrow pill is a hard target for a finger on a watch',
      );

      // A point in the band but above the visible pill, derived from the target
      // itself instead of a hardcoded offset.
      await tester.tapAt(Offset(rect.center.dx, rect.top + 4));
      await settleFeed(tester);

      expect(
        find.text('SAVED'),
        findsOneWidget,
        reason: 'the whole 44 dp band flips the mode, not just the drawn pill',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the header label keeps one type style in both modes', (
    tester,
  ) async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'today-1', title: 'Today story')];
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: FakeSavedArticleRepository(),
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    void expectLabelType(String label) {
      final style = headerLabel(tester, label).style;
      expect(style, isNotNull, reason: '"$label" must carry an explicit style');
      expect(style!.color, Colors.white);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.letterSpacing, closeTo(1.4, 0.001));
    }

    expectLabelType('TODAY');
    await tapSectionToggle(tester);
    expectLabelType('SAVED');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the saved list has no pull-to-refresh', (tester) async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'today-1', title: 'Today story')];
    final savedRepository = FakeSavedArticleRepository(
      saved: [article(guid: 'saved-1', title: 'Saved story')],
    );
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: savedRepository,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);
    await tapSectionToggle(tester);

    expect(find.byKey(const Key('saved-list')), findsOneWidget);
    expect(
      find.byType(RefreshIndicator),
      findsNothing,
      reason:
          'refreshing only replaces today\'s feed, so the saved list must not '
          'pretend a pull would reload it',
    );

    final callsBeforeDrag = repository.refreshCalls;
    await tester.drag(
      find.byKey(const Key('saved-list')),
      const Offset(0, 300),
    );
    await settleFeed(tester);

    expect(
      repository.refreshCalls,
      callsBeforeDrag,
      reason: 'a downward drag on the saved list must never refresh today',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the saved empty state offers a way back to today', (
    tester,
  ) async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'today-1', title: 'Today story')];
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: FakeSavedArticleRepository(),
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);
    await tapSectionToggle(tester);

    final empty = find.byKey(const Key('saved-empty'));
    expect(empty, findsOneWidget);
    expect(find.text('No saved articles yet'), findsOneWidget);

    final bookmark = find.byWidgetPredicate(
      (widget) =>
          widget is Icon &&
          (widget.icon == Icons.bookmark_border_rounded ||
              widget.icon == Icons.bookmark_border),
      description: 'an outlined bookmark icon',
    );
    expect(
      find.descendant(of: empty, matching: bookmark),
      findsOneWidget,
      reason: 'the empty state must reuse the bookmark language of the rows',
    );

    expect(find.byKey(const Key('saved-empty-show-today')), findsOneWidget);
    expect(find.text('Show today'), findsOneWidget);

    final texts = tester
        .widgetList<Text>(
          find.descendant(of: empty, matching: find.byType(Text)),
        )
        .map((widget) => widget.data)
        .toList();
    expect(
      texts,
      ['No saved articles yet', 'Show today'],
      reason:
          'no extra hint line: on a 192 dp screen only the title and the '
          'action fit inside the circle',
    );

    await tester.tap(find.byKey(const Key('saved-empty-show-today')));
    await settleFeed(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byKey(const Key('feed-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed saved read shows the error slot, not the empty state', (
    tester,
  ) async {
    final savedRepository = FakeSavedArticleRepository()
      ..savedArticlesError = const FeedCacheFailure(
        'Saved storage unavailable',
      );
    final bloc = await pumpFeedView(
      tester,
      repository: FakeArticleRepository()
        ..refreshed = [article(guid: 'today-1', title: 'Today story')],
      savedRepository: savedRepository,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);
    await tapSectionToggle(tester);

    final error = find.byKey(const Key('saved-error'));
    expect(error, findsOneWidget);
    expect(
      find.descendant(
        of: error,
        matching: find.text('Saved storage unavailable'),
      ),
      findsOneWidget,
      reason: 'the failure copy must be the mapped FeedFailure message',
    );
    expect(
      find.byKey(const Key('saved-empty')),
      findsNothing,
      reason:
          'an empty list after a failed read is not an empty library: the user '
          'must not be told there is nothing saved',
    );
    expect(find.text('No saved articles yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved rows carry a bookmark marker, today rows do not', (
    tester,
  ) async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'today-1', title: 'Today story')];
    final savedRepository = FakeSavedArticleRepository(
      saved: [article(guid: 'saved-1', title: 'Saved story')],
    );
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: savedRepository,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(
      find.byKey(const Key('article-row-today-1')),
      findsOneWidget,
      reason: 'precondition: the today row is rendered',
    );
    expect(
      find.byKey(const Key('article-saved-marker-today-1')),
      findsNothing,
      reason: 'the marker is redundant while browsing today',
    );

    await tapSectionToggle(tester);

    expect(find.byKey(const Key('article-row-saved-1')), findsOneWidget);
    expect(
      find.byKey(const Key('article-saved-marker-saved-1')),
      findsOneWidget,
      reason: 'inside the saved list every row is saved, so each must say so',
    );

    await tapSectionToggle(tester);

    expect(find.byKey(const Key('article-row-today-1')), findsOneWidget);
    expect(
      find.byKey(const Key('article-saved-marker-today-1')),
      findsNothing,
      reason: 'the marker must not leak into the today list',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-pressing a saved row removes it and UNDO puts it back', (
    tester,
  ) async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'today-1', title: 'Today story')];
    final savedRepository = FakeSavedArticleRepository(
      saved: [article(guid: 'saved-1', title: 'Saved story')],
    );
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: savedRepository,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);
    await tapSectionToggle(tester);

    final row = find.byKey(const Key('article-row-saved-1'));
    expect(row, findsOneWidget);

    await tester.longPress(row);
    await settleFeed(tester);

    expect(savedRepository.removeCalls, 1);
    expect(savedRepository.removedIdentities, ['saved-1']);
    expect(
      find.byKey(const Key('article-row-saved-1')),
      findsNothing,
      reason: 'the removed row must leave the list immediately',
    );
    expect(find.text('Removed'), findsOneWidget);
    expect(
      find.text('UNDO'),
      findsOneWidget,
      reason: 'a removal without UNDO is a trap on a screen with no back-out',
    );

    await tester.tap(find.text('UNDO'));
    await settleFeed(tester);

    expect(
      savedRepository.saveCalls,
      1,
      reason: 'UNDO must write the article back into the store',
    );
    expect(
      find.byKey(const Key('article-row-saved-1')),
      findsOneWidget,
      reason: 'the restored row must reappear without leaving the section',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-pressing a today row removes nothing', (tester) async {
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'today-1', title: 'Today story')];
    final savedRepository = FakeSavedArticleRepository();
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: savedRepository,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    await tester.longPress(find.byKey(const Key('article-row-today-1')));
    await settleFeed(tester);

    expect(
      savedRepository.removeCalls,
      0,
      reason: 'today rows are not bookmarks: a long press must not delete one',
    );
    expect(find.text('Removed'), findsNothing);
    expect(find.byKey(const Key('article-row-today-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved row announces the long-press removal, a today row does '
      'not', (tester) async {
    // Disposed at the end of the body, not through `addTearDown`: the
    // framework's `_endOfTestVerifications` (which enforces "no SemanticsHandle
    // left active") runs *before* tear-down callbacks, so a handle handed to
    // `addTearDown` is still live when the test is verified and the test fails
    // on teardown even though every assertion below passed. The handle must
    // stay open for the whole body so both rows are inspected with semantics on.
    final handle = tester.ensureSemantics();

    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'today-1', title: 'Today story')];
    final savedRepository = FakeSavedArticleRepository(
      saved: [article(guid: 'saved-1', title: 'Saved story')],
    );
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: savedRepository,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    final todayRow = find.byKey(const Key('article-row-today-1'));
    expect(
      tester.getSemantics(todayRow).label,
      contains('Today story'),
      reason: 'precondition: the finder resolves the row\'s own semantics node',
    );
    expect(
      tester.getSemantics(todayRow).hint,
      'Tap to read, double tap to open on your phone',
      reason:
          'today rows have nothing to remove, so their hint must stay exactly '
          'as it was',
    );
    expect(
      tester.getSemantics(todayRow).hint,
      isNot(contains('long press')),
      reason: 'offering a long press that does nothing only wastes a gesture',
    );

    await tapSectionToggle(tester);

    final savedRow = find.byKey(const Key('article-row-saved-1'));
    expect(savedRow, findsOneWidget);
    expect(
      tester.getSemantics(savedRow).label,
      contains('Saved story'),
      reason: 'precondition: the finder resolves the saved row\'s own node',
    );
    expect(
      tester.getSemantics(savedRow).hint,
      contains('long press to remove'),
      reason:
          'on a watch the row is removed by a long press and nothing else on '
          'screen says so: a screen reader user must be told, or the saved '
          'library is append-only for them',
    );
    expect(tester.takeException(), isNull);

    // Last statement of the body: every semantics assertion above has run.
    handle.dispose();
  });

  testWidgets('switching to saved resets the header and the scroll offset', (
    tester,
  ) async {
    final repository = FakeArticleRepository()..refreshed = twentyArticles();
    final savedRepository = FakeSavedArticleRepository(
      saved: [article(guid: 'saved-1', title: 'Saved story')],
    );
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: savedRepository,
    );
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
      reason: 'precondition: reading down fades the header out',
    );
    final todayOffset = scrollOffset(tester, const Key('feed-list'));
    expect(
      todayOffset,
      greaterThan(0),
      reason: 'precondition: the today list is scrolled past its top',
    );

    // The toggle is inside the faded header, so the section change is driven
    // through the bloc: what matters here is what the view does with it.
    bloc.add(const FeedSectionToggled());
    final switched = await pumpUntil(
      tester,
      () => find.byKey(const Key('saved-list')).evaluate().isNotEmpty,
    );
    await settleFeed(tester);
    expect(switched, isTrue, reason: 'the saved list must appear');

    expect(
      headerOpacity(tester),
      1.0,
      reason:
          'a new section must never inherit a hidden header (it would be '
          'unreachable: the faded header ignores pointers)',
    );
    expect(
      scrollOffset(tester, const Key('saved-list')),
      0.0,
      reason: 'the saved list opens at its own top, not the today offset',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a saved row opens its detail page', (tester) async {
    final navigated = <Article>[];
    final repository = FakeArticleRepository()
      ..refreshed = [article(guid: 'today-1', title: 'Today story')];
    final savedRepository = FakeSavedArticleRepository(
      saved: [
        article(
          guid: 'saved-1',
          title: 'Saved story',
          link: 'https://example.com/saved-1',
        ),
      ],
    );
    final bloc = await pumpFeedView(
      tester,
      repository: repository,
      savedRepository: savedRepository,
      onOpenArticle: navigated.add,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);
    await tapSectionToggle(tester);

    await tester.tap(find.byKey(const Key('article-row-saved-1')));
    await tester.pump(const Duration(milliseconds: 400));
    await settleFeed(tester);

    expect(navigated.map((item) => item.guid).toList(), [
      'saved-1',
    ], reason: 'saved rows are articles like any other: one tap opens them');
    expect(tester.takeException(), isNull);
  });
}
