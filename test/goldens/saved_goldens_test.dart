import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/core/theme/app_theme.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_bloc.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/bloc/feed_event.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/pages/article_detail_page.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/widgets/feed_view.dart';

import '../support/article_factory.dart';
import '../support/feed_test_doubles.dart';
import 'golden_fonts.dart';

/// Golden (acceptance) screenshots of the saved-articles UI.
///
/// Every scene is captured at the *real* watch geometry: the Pixel Watch 1
/// reports 384 x 384 physical pixels at devicePixelRatio 2.0, i.e. a 192 dp
/// logical canvas (`screencap` verified). The existing widget tests run at
/// 450 dp with the fast test font, which hides exactly the layout damage this
/// file exists to catch, so nothing outside `test/goldens/` is touched.
///
/// The PNGs are written into `test/goldens/` and are 384 x 384 pixels: the
/// canvas is rasterised at pixelRatio 2.0 (see [_captureCanvas]).
void main() {
  // `flutter test` executes files in their own isolate, so the real fonts live
  // only for this file.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadGoldenFonts();
  });

  /// The single, fixed instant every relative timestamp is measured against.
  /// No scene may read the wall clock.
  final testNow = DateTime(2026, 10, 27, 18);

  /// Logical size of the watch canvas: 384 physical px / dpr 2.0.
  const double watchCanvas = 192;

  /// The panel's own pixel ratio; also the factor the PNG is rasterised at.
  const double panelPixelRatio = 2.0;

  const canvasKey = Key('golden-canvas');

  /// `buildWearTheme()` with the one thing the test shell cannot resolve.
  ///
  /// The theme replaces four text styles with plain `TextStyle`s that carry no
  /// `fontFamily` (and `snackBarTheme` does the same), so the shell falls back
  /// to its box font. On the watch a missing family resolves to Roboto, so the
  /// harness names it explicitly. Sizes, weights, colours and letter spacing
  /// are untouched: this is the same theme the widget tests use.
  ThemeData buildGoldenTheme() {
    final base = buildWearTheme();
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: base.snackBarTheme.contentTextStyle?.copyWith(
          fontFamily: 'Roboto',
        ),
      ),
    );
  }

  /// Runs a golden scene on the watch: Android (the watch platform, and the
  /// only one whose typography asks for the Roboto faces loaded above) at
  /// 384 x 384 physical px.
  ///
  /// The platform override is set and cleared inside the test body: the test
  /// framework asserts that no `debug*` foundation variable is left changed
  /// when the body returns, so `setUp`/`tearDown` are too coarse.
  void goldenTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  /// Long enough to clamp at two lines inside a 145 dp row.
  const longTitle =
      'OpenAI publishes a 120-page system card for its frontier model, '
      'detailing evaluation gaps, refusal rates and the still unresolved '
      'question of how much of the training set came from licensed publishers';

  /// The saved library, already ordered newest-published first, exactly as
  /// `LoadSavedArticles` hands it to the bloc.
  List<Article> savedFixtures() => <Article>[
    // Worst case one: a long source name *and* a title that needs the clamp.
    article(
      guid: 'saved-mit-1',
      sourceName: 'MIT Tech Review AI',
      title: longTitle,
      description:
          'The card is longer than the release notes, and most of its pages '
          'describe what the team could not measure.',
      publishedAt: testNow.subtract(const Duration(hours: 2)),
    ),
    // Worst case two: no description at all.
    article(
      guid: 'saved-hf-2',
      sourceName: 'Hugging Face Blog',
      title: 'LitPivot for literature research',
      description: null,
      author: null,
      link: 'https://huggingface.co/blog/allenai/litpivot',
      publishedAt: testNow.subtract(const Duration(hours: 5)),
    ),
    article(
      guid: 'saved-decoder-3',
      sourceName: 'The Decoder',
      title: 'Anthropic pledges no ads in Claude',
      description: 'The company argues answers should stay the priority.',
      publishedAt: testNow.subtract(const Duration(days: 3)),
    ),
    article(
      guid: 'saved-ars-4',
      sourceName: 'Ars Technica',
      title: 'A small chip startup bets against the transformer',
      description: 'Its first silicon ships next spring, with a compiler.',
      publishedAt: testNow.subtract(const Duration(days: 9)),
    ),
    // Worst case three: a two-month-old bookmark, rendered as `62d`.
    article(
      guid: 'saved-deepmind-5',
      sourceName: 'DeepMind Blog',
      title: 'Weather models beat the forecasters again',
      description: 'Two extra days of skill, at a fraction of the compute.',
      publishedAt: testNow.subtract(const Duration(days: 62)),
    ),
  ];

  /// Today's feed: same row shapes as the saved list, but no bookmark markers
  /// and all published today, so the two headers can be compared pixel for
  /// pixel.
  List<Article> todayFixtures() => <Article>[
    article(
      guid: 'today-1',
      sourceName: 'The Decoder',
      title: 'Anthropic pledges no ads in Claude',
      description: 'The company argues answers should stay the priority.',
      publishedAt: testNow.subtract(const Duration(minutes: 25)),
    ),
    article(
      guid: 'today-2',
      sourceName: 'MIT Tech Review AI',
      title: longTitle,
      description:
          'The card is longer than the release notes, and most of its pages '
          'describe what the team could not measure.',
      publishedAt: testNow.subtract(const Duration(hours: 2)),
    ),
    article(
      guid: 'today-3',
      sourceName: 'Hugging Face Blog',
      title: 'LitPivot for literature research',
      description: null,
      author: null,
      link: 'https://huggingface.co/blog/allenai/litpivot',
      publishedAt: testNow.subtract(const Duration(hours: 5)),
    ),
    article(
      guid: 'today-4',
      sourceName: 'Ars Technica',
      title: 'A small chip startup bets against the transformer',
      description: 'Its first silicon ships next spring, with a compiler.',
      publishedAt: testNow.subtract(const Duration(hours: 9)),
    ),
    article(
      guid: 'today-5',
      sourceName: 'DeepMind Blog',
      title: 'Weather models beat the forecasters again',
      description: 'Two extra days of skill, at a fraction of the compute.',
      publishedAt: testNow.subtract(const Duration(hours: 14)),
    ),
  ];

  /// Pins the surface to the watch panel for one test: 384 x 384 physical
  /// pixels at dpr 2.0, i.e. a 192 dp logical canvas, exactly like `screencap`.
  void useWatchCanvas(WidgetTester tester) {
    tester.view.physicalSize = const Size(
      watchCanvas * panelPixelRatio,
      watchCanvas * panelPixelRatio,
    );
    tester.view.devicePixelRatio = panelPixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Wraps the app in an explicit repaint boundary so the capture is the whole
  /// 192 dp circle, not whatever box happens to be the outermost one.
  Widget canvas(Widget child) => RepaintBoundary(key: canvasKey, child: child);

  Future<FeedBloc> pumpFeed(
    WidgetTester tester, {
    required FakeArticleRepository repository,
    required FakeSavedArticleRepository savedRepository,
  }) async {
    useWatchCanvas(tester);

    final bloc = buildTestFeedBloc(
      repository: repository,
      savedRepository: savedRepository,
      clock: () => testNow,
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      canvas(
        MaterialApp(
          // The watch app ships without the debug banner; a golden that shows
          // it would be measuring the wrong screen.
          debugShowCheckedModeBanner: false,
          theme: buildGoldenTheme(),
          home: BlocProvider<FeedBloc>.value(
            value: bloc,
            child: FeedView(clock: () => testNow),
          ),
        ),
      ),
    );
    return bloc;
  }

  /// Deterministic slice pumps: enough frames for the async bloc work, without
  /// the `pumpAndSettle` hazards (snackbar timers, refresh indicator).
  Future<void> settleFeed(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Pumps past the ink splash a tap leaves on the header pill.
  ///
  /// The header's `Material` is transparent above the pill, so a still-running
  /// splash paints a grey cloud there and gets baked into the PNG: both
  /// `feed_saved_rest.png` and `feed_saved_empty.png` shipped with exactly that
  /// artefact. `InkSparkle` runs for 617 ms (material/ink_sparkle.dart), so the
  /// 400 ms floor is not enough on its own; the bounded loop then keeps
  /// pumping while any animation is still scheduled, which also covers the
  /// 375 ms fade of the older `InkRipple`.
  Future<void> settleInk(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 20 && tester.binding.transientCallbackCount > 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason:
          'an animation is still scheduled here: whatever it paints would be '
          'baked into the golden as a transient',
    );
  }

  /// Pumps virtual time until the current snackbar has left the screen.
  ///
  /// The failed-read notice and the removal UNDO both raise a bar that covers
  /// the bottom of the circle; it must be gone before an error state is
  /// captured. A bounded loop keeps the pump deterministic (no wall clock, no
  /// `pumpAndSettle` on a live timer).
  Future<void> dismissSnackBar(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      if (find.byType(SnackBar).evaluate().isEmpty) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('the snackbar never dismissed');
  }

  /// Starts the feed and flips to the saved section.
  Future<FeedBloc> openSavedSection(
    WidgetTester tester, {
    required FakeArticleRepository repository,
    required FakeSavedArticleRepository savedRepository,
  }) async {
    final bloc = await pumpFeed(
      tester,
      repository: repository,
      savedRepository: savedRepository,
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    await tester.tap(find.byKey(const Key('feed-header-toggle')));
    await settleFeed(tester);
    // The tap starts an ink splash on the pill; capture only once it is gone.
    await settleInk(tester);
    return bloc;
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required Article item,
    required bool initiallySaved,
  }) async {
    useWatchCanvas(tester);

    await tester.pumpWidget(
      canvas(
        MaterialApp(
          // The watch app ships without the debug banner; a golden that shows
          // it would be measuring the wrong screen.
          debugShowCheckedModeBanner: false,
          theme: buildGoldenTheme(),
          home: ArticleDetailPage(
            article: item,
            clock: () => testNow,
            initiallySaved: initiallySaved,
            isArticleSaved: (_) async => initiallySaved,
            onOpenOnPhone: (_) async {},
            onToggleSave: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Scroll to the very end so the stacked actions sit in the wide middle
    // band of the circle. Clamping physics stop at maxScrollExtent, and the
    // loop stops as soon as the end is reached, so no magic pixel offset is
    // baked into the golden.
    final scrollable = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 20; i++) {
      final position = tester.state<ScrollableState>(scrollable).position;
      if ((position.maxScrollExtent - position.pixels).abs() < 0.5) {
        break;
      }
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -160),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// Rasterises the canvas at [panelPixelRatio] and asserts it against the
  /// golden file next to this test (i.e. `test/goldens/<fileName>`).
  ///
  /// `matchesGoldenFile` on a [Finder] captures at pixelRatio 1.0 and would
  /// write a 192 x 192 PNG, so the bytes are produced here at the panel's own
  /// ratio and handed to the same matcher, which still owns `--update-goldens`.
  ///
  /// The whole capture *and* the assertion run inside `runAsync`: the matcher's
  /// byte path writes/reads the file with real async I/O, which never completes
  /// under the fake-async test clock (it hangs until the test times out).
  Future<void> expectCanvasGolden(WidgetTester tester, String fileName) async {
    await tester.runAsync(() async {
      final bytes = await _captureCanvas(tester, canvasKey);
      expect(
        bytes,
        isNotEmpty,
        reason: '$fileName: the canvas could not be rasterised',
      );
      await expectLater(bytes, matchesGoldenFile(fileName));
    });
  }

  goldenTest('feed_today_rest', (tester) async {
    final bloc = await pumpFeed(
      tester,
      repository: FakeArticleRepository()..refreshed = todayFixtures(),
      savedRepository: FakeSavedArticleRepository(saved: savedFixtures()),
    );
    bloc.add(const FeedStarted());
    await settleFeed(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byKey(const Key('feed-list')), findsOneWidget);
    expect(
      find.byIcon(Icons.bookmark_rounded),
      findsNothing,
      reason: 'the today list must carry no saved markers at all',
    );

    await expectCanvasGolden(tester, 'feed_today_rest.png');
  });

  goldenTest('feed_saved_rest', (tester) async {
    await openSavedSection(
      tester,
      repository: FakeArticleRepository()..refreshed = todayFixtures(),
      savedRepository: FakeSavedArticleRepository(saved: savedFixtures()),
    );

    expect(find.text('SAVED'), findsOneWidget);
    expect(find.byKey(const Key('saved-list')), findsOneWidget);

    final marker = find.byKey(const Key('article-saved-marker-saved-mit-1'));
    expect(
      marker,
      findsOneWidget,
      reason: 'every row of the saved list carries the bookmark marker',
    );

    final markerRect = tester.getRect(marker);
    final sourceRect = tester.getRect(find.text('MIT Tech Review AI'));
    expect(
      sourceRect.right,
      lessThan(markerRect.left),
      reason:
          'the long source name must clamp before the marker, never over it',
    );
    expect(
      markerRect.right,
      lessThanOrEqualTo(watchCanvas),
      reason: 'the marker must stay inside the 192 dp panel',
    );

    await expectCanvasGolden(tester, 'feed_saved_rest.png');
  });

  goldenTest('feed_saved_scrolled', (tester) async {
    await openSavedSection(
      tester,
      repository: FakeArticleRepository()..refreshed = todayFixtures(),
      savedRepository: FakeSavedArticleRepository(saved: savedFixtures()),
    );

    // Roughly two rows: far past the point where the header used to go away.
    final savedList = find.byKey(const Key('saved-list'));
    await tester.drag(savedList, const Offset(0, -232));
    await tester.pumpAndSettle();

    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: savedList, matching: find.byType(Scrollable)),
          )
          .position
          .pixels,
      greaterThan(0),
      reason:
          'precondition: the saved list is really scrolled, so a row is '
          'passing under the header in this artifact',
    );

    // SAVED pins the header: it is the only mode indicator and the only way
    // back to today, so reading down must never fade it out.
    expect(
      find.text('SAVED'),
      findsOneWidget,
      reason: 'the SAVED pill must survive scrolling inside the saved list',
    );
    expect(
      tester
          .widget<AnimatedOpacity>(find.byKey(const Key('feed-header-opacity')))
          .opacity,
      1.0,
      reason: 'the pinned header must target full opacity while reading down',
    );
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byKey(const Key('feed-header-opacity')),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      closeTo(1.0, 0.001),
      reason:
          'and it must actually be painted at full opacity once settled, not '
          'left mid-fade',
    );

    final pillRect = tester.getRect(find.text('SAVED'));
    expect(
      pillRect.top,
      greaterThanOrEqualTo(0),
      reason: 'the pill must stay inside the top of the 192 dp canvas',
    );
    expect(
      pillRect.left,
      greaterThanOrEqualTo(0),
      reason: 'the pill must stay inside the left of the 192 dp canvas',
    );
    expect(
      pillRect.right,
      lessThanOrEqualTo(watchCanvas),
      reason: 'the pill must stay inside the right of the 192 dp canvas',
    );
    expect(
      pillRect.bottom,
      lessThanOrEqualTo(watchCanvas),
      reason: 'the pill must stay inside the bottom of the 192 dp canvas',
    );

    // The artifact the designer asked for: the header, legible over a row that
    // has scrolled underneath it.
    await expectCanvasGolden(tester, 'feed_saved_scrolled.png');

    // After the artifact: run to the end of the list so the oldest bookmark is
    // really rendered and its relative time can be asserted.
    final scrollable = find.descendant(
      of: savedList,
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 10; i++) {
      final position = tester.state<ScrollableState>(scrollable).position;
      if ((position.maxScrollExtent - position.pixels).abs() < 0.5) {
        break;
      }
      await tester.drag(savedList, const Offset(0, -160));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('62d'), findsOneWidget);
  });

  goldenTest('feed_saved_empty', (tester) async {
    await openSavedSection(
      tester,
      repository: FakeArticleRepository()..refreshed = todayFixtures(),
      savedRepository: FakeSavedArticleRepository(),
    );

    expect(find.byKey(const Key('saved-empty')), findsOneWidget);
    expect(find.text('No saved articles yet'), findsOneWidget);
    expect(find.text('Show today'), findsOneWidget);

    await expectCanvasGolden(tester, 'feed_saved_empty.png');
  });

  goldenTest('feed_saved_error', (tester) async {
    final savedRepository = FakeSavedArticleRepository()
      ..savedArticlesError = const FeedCacheFailure(
        'Could not read saved articles.',
      );

    await openSavedSection(
      tester,
      repository: FakeArticleRepository()..refreshed = todayFixtures(),
      savedRepository: savedRepository,
    );

    // The failed read also raises a notice snackbar; let it leave so the error
    // copy is readable instead of being covered by its own toast.
    await dismissSnackBar(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('saved-error')), findsOneWidget);
    expect(find.byKey(const Key('saved-empty')), findsNothing);
    expect(find.text('Could not read saved articles.'), findsOneWidget);

    await expectCanvasGolden(tester, 'feed_saved_error.png');
  });

  goldenTest('feed_saved_undo_snackbar', (tester) async {
    await openSavedSection(
      tester,
      repository: FakeArticleRepository()..refreshed = todayFixtures(),
      savedRepository: FakeSavedArticleRepository(saved: savedFixtures()),
    );

    await tester.longPress(find.byKey(const Key('article-row-saved-mit-1')));
    // 4 x 20 ms clears the 50 ms snackbar entrance without touching the 4 s
    // dismissal timer.
    await settleFeed(tester);
    // The long press also leaves an ink splash on the row: pump it away so no
    // transient is baked into the artifact (well inside the 4 s bar).
    await settleInk(tester);

    expect(find.text('Removed'), findsOneWidget);
    final undo = find.text('UNDO');
    expect(undo, findsOneWidget);

    final bar = tester.getRect(find.byType(SnackBar));
    final undoRect = tester.getRect(undo);
    expect(
      bar.left,
      greaterThanOrEqualTo(0),
      reason: 'the bar must sit fully inside the circle, not hang off it',
    );
    expect(bar.right, lessThanOrEqualTo(watchCanvas));
    expect(
      bar.top,
      greaterThanOrEqualTo(0),
      reason: 'a bar taller than the circle would lose its first line',
    );
    expect(bar.bottom, lessThanOrEqualTo(watchCanvas));
    expect(
      undoRect.right,
      lessThanOrEqualTo(bar.right),
      reason: 'UNDO must be inside the bar and therefore tappable',
    );
    expect(
      undoRect.bottom,
      lessThanOrEqualTo(bar.bottom),
      reason: 'UNDO must be fully drawn inside the bar, not clipped by it',
    );

    await expectCanvasGolden(tester, 'feed_saved_undo_snackbar.png');
  });

  goldenTest('detail_buttons_stacked', (tester) async {
    await pumpDetail(
      tester,
      item: savedFixtures().first,
      initiallySaved: false,
    );

    expect(find.text('Save article'), findsOneWidget);
    expect(find.text('Open on phone'), findsOneWidget);

    final openRect = tester.getRect(
      find.byKey(const Key('article-detail-open-on-phone')),
    );
    final saveRect = tester.getRect(
      find.byKey(const Key('article-detail-save')),
    );
    expect(
      openRect.top,
      greaterThanOrEqualTo(0),
      reason: 'scrolling to the end must bring both actions into view',
    );
    expect(
      saveRect.bottom,
      lessThanOrEqualTo(watchCanvas),
      reason: 'the save action must end up on screen too',
    );

    await expectCanvasGolden(tester, 'detail_buttons_stacked.png');
  });

  goldenTest('detail_saved_state', (tester) async {
    await pumpDetail(tester, item: savedFixtures().first, initiallySaved: true);

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Save article'), findsNothing);

    final openRect = tester.getRect(
      find.byKey(const Key('article-detail-open-on-phone')),
    );
    final saveRect = tester.getRect(
      find.byKey(const Key('article-detail-save')),
    );
    expect(
      saveRect.top,
      closeTo(
        tester
                .getRect(find.byKey(const Key('article-detail-open-on-phone')))
                .bottom +
            8,
        0.5,
      ),
      reason: 'the label change must not move the button stack',
    );
    expect(openRect.width, closeTo(saveRect.width, 0.5));

    await expectCanvasGolden(tester, 'detail_saved_state.png');
  });
}

/// Rasterises the repaint boundary behind [key] at [pixelRatio].
Future<List<int>> _captureCanvas(
  WidgetTester tester,
  Key key, {
  double pixelRatio = 2.0,
}) async {
  final element = tester.element(find.byKey(key));
  final root = element.renderObject;
  if (root == null) {
    throw StateError('The golden canvas has no render object.');
  }

  var renderObject = root;
  while (!renderObject.isRepaintBoundary) {
    final parent = renderObject.parent;
    if (parent == null) {
      throw StateError('The golden canvas is not inside a repaint boundary.');
    }
    renderObject = parent;
  }

  final layer = renderObject.debugLayer;
  if (layer is! OffsetLayer) {
    throw StateError('The golden canvas has no offset layer to capture.');
  }

  final image = await layer.toImage(
    renderObject.paintBounds,
    pixelRatio: pixelRatio,
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('The golden canvas could not be encoded as PNG.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
