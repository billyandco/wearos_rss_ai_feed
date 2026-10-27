import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/core/errors/feed_failure.dart';
import 'package:wearos_rss_ai_feed/core/theme/app_theme.dart';
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart';
import 'package:wearos_rss_ai_feed/features/feed/presentation/pages/article_detail_page.dart';

import '../../../../support/article_factory.dart';

void main() {
  final testNow = DateTime(2026, 10, 27, 18);

  Future<void> pumpDetailPage(
    WidgetTester tester, {
    required Article item,
    Future<void> Function(Article article)? onOpenOnPhone,
    bool initiallySaved = false,
    Future<void> Function(Article article)? onToggleSave,
    Future<bool> Function(String identity)? isArticleSaved,
  }) async {
    tester.view.physicalSize = const Size(450, 450);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWearTheme(),
        home: ArticleDetailPage(
          article: item,
          clock: () => testNow,
          onOpenOnPhone: onOpenOnPhone,
          initiallySaved: initiallySaved,
          onToggleSave: onToggleSave,
          isArticleSaved: isArticleSaved,
        ),
      ),
    );
    await tester.pump();
  }

  /// Pumps virtual time in slices until [done] flips, so snackbar animations
  /// never need `pumpAndSettle` (which can hang on a visible snackbar timer).
  Future<bool> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 120 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return done();
  }

  /// Longer than the two-line clamp used by the feed row, so a truncated
  /// description cannot accidentally satisfy the assertion.
  const longDescription =
      'Anthropic says answers should stay the priority, so the assistant will '
      'never be interrupted by sponsored placements, affiliate links or brand '
      'takeovers, even when that leaves money on the table for the company.';

  testWidgets('renders the article with its hero and an open-on-phone button', (
    tester,
  ) async {
    final item = article(
      guid: 'detail-hero-1',
      title: 'Anthropic pledges no ads in Claude',
      description: longDescription,
      sourceName: 'The Decoder',
      publishedAt: testNow.subtract(const Duration(hours: 2)),
    );

    await pumpDetailPage(tester, item: item);

    expect(find.byKey(const Key('article-detail')), findsOneWidget);
    expect(find.text(item.title), findsAtLeastNWidgets(1));
    expect(find.text('The Decoder'), findsAtLeastNWidgets(1));
    expect(find.text('2h'), findsAtLeastNWidgets(1));

    expect(
      find.text(longDescription),
      findsOneWidget,
      reason: 'the full description must be rendered verbatim',
    );
    final descriptionText = tester.widget<Text>(find.text(longDescription));
    expect(
      descriptionText.maxLines,
      isNull,
      reason: 'the detail page must not clamp the description to 2 lines',
    );
    expect(
      descriptionText.overflow,
      isNot(TextOverflow.ellipsis),
      reason: 'the detail page must not ellipsise the description',
    );

    final heroFinder = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'article-hero-detail-hero-1',
    );
    expect(
      heroFinder,
      findsOneWidget,
      reason: 'the detail page must share the row hero tag for the transition',
    );

    expect(
      find.byKey(const Key('article-detail-open-on-phone')),
      findsOneWidget,
    );
    expect(find.text('Open on phone'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('open on phone button calls the injected opener and confirms', (
    tester,
  ) async {
    final opened = <Article>[];
    final item = article(
      guid: 'detail-open-1',
      title: 'Open this one on the phone',
      publishedAt: testNow.subtract(const Duration(minutes: 5)),
    );

    await pumpDetailPage(
      tester,
      item: item,
      onOpenOnPhone: (value) async {
        opened.add(value);
      },
    );

    await tester.tap(find.byKey(const Key('article-detail-open-on-phone')));
    await tester.pump();

    final confirmed = await pumpUntil(
      tester,
      () => find.text('Opening on your phone').evaluate().isNotEmpty,
    );

    expect(opened.map((entry) => entry.guid).toList(), [
      'detail-open-1',
    ], reason: 'the injected opener must receive the page article');
    expect(
      confirmed,
      isTrue,
      reason: 'a successful open must show the confirmation snackbar',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('open on phone failure shows the failure message', (
    tester,
  ) async {
    final item = article(
      guid: 'detail-fail-1',
      title: 'This one cannot reach the phone',
      publishedAt: testNow.subtract(const Duration(minutes: 2)),
    );

    await pumpDetailPage(
      tester,
      item: item,
      onOpenOnPhone: (value) async {
        throw const RemoteOpenFailure('Could not reach your phone.');
      },
    );

    await tester.tap(find.byKey(const Key('article-detail-open-on-phone')));
    await tester.pump();

    final shown = await pumpUntil(
      tester,
      () => find.text('Could not reach your phone.').evaluate().isNotEmpty,
    );

    expect(
      shown,
      isTrue,
      reason: 'the FeedFailure message must be surfaced, not swallowed',
    );
    expect(
      find.text('Opening on your phone'),
      findsNothing,
      reason: 'a failed open must not claim success',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders an article without a description cleanly', (
    tester,
  ) async {
    final item = article(
      guid: 'detail-no-description',
      title: 'Headline only story',
      description: null,
      publishedAt: testNow.subtract(const Duration(seconds: 30)),
    );

    await pumpDetailPage(tester, item: item);

    expect(find.byKey(const Key('article-detail')), findsOneWidget);
    expect(find.text(item.title), findsAtLeastNWidgets(1));
    expect(find.text('now'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const Key('article-detail-open-on-phone')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------------
  // Save article
  // ---------------------------------------------------------------------------

  testWidgets('an unsaved article offers a quiet Save article text button', (
    tester,
  ) async {
    final item = article(guid: 'save-1', title: 'Save this article');
    await pumpDetailPage(tester, item: item);

    final save = find.byKey(const Key('article-detail-save'));
    expect(save, findsOneWidget);
    expect(find.text('Save article'), findsOneWidget);

    final button = tester.widget(save);
    expect(
      button,
      isA<TextButton>(),
      reason: 'Save must be a text action next to the primary filled button',
    );
    expect(
      button,
      isNot(isA<FilledButton>()),
      reason: 'two filled buttons on one screen would compete for the eye',
    );

    // Pin the label instead of "the only RichText in the button": the action is
    // allowed to grow an icon, and an Icon renders its own RichText glyph.
    final label = find.descendant(
      of: save,
      matching: find.text('Save article'),
    );
    expect(
      label,
      findsOneWidget,
      reason: 'the unsaved action must render "Save article" exactly once',
    );

    final renderedForeground = tester
        .widget<RichText>(
          find.descendant(of: label, matching: find.byType(RichText)),
        )
        .text
        .style
        ?.color;
    expect(
      renderedForeground,
      kWearAccent,
      reason: 'the secondary action still uses the accent, not plain white',
    );

    expect(
      find.descendant(
        of: save,
        matching: find.byIcon(Icons.bookmark_add_outlined),
      ),
      findsOneWidget,
      reason:
          'an unsaved article must advertise the action with the outlined '
          'add-bookmark glyph',
    );
    expect(
      find.descendant(of: save, matching: find.byIcon(Icons.bookmark_rounded)),
      findsNothing,
      reason: 'the filled bookmark would claim the article is already saved',
    );
  });

  testWidgets('tapping Save bookmarks the article and confirms', (
    tester,
  ) async {
    final toggled = <Article>[];
    final item = article(guid: 'save-2', title: 'Bookmark me');

    await pumpDetailPage(
      tester,
      item: item,
      onToggleSave: (value) async {
        toggled.add(value);
      },
    );

    await tester.tap(find.byKey(const Key('article-detail-save')));
    await tester.pump();

    final confirmed = await pumpUntil(
      tester,
      () => find
          .descendant(of: find.byType(SnackBar), matching: find.text('Saved'))
          .evaluate()
          .isNotEmpty,
    );

    expect(toggled.map((entry) => entry.guid).toList(), [
      'save-2',
    ], reason: 'the injected writer must receive the page article');
    expect(confirmed, isTrue, reason: 'a successful save must be confirmed');
    expect(
      find.text('Saved'),
      findsAtLeastNWidgets(1),
      reason: 'the label must flip to the saved state',
    );
    expect(find.text('Save article'), findsNothing);

    final save = find.byKey(const Key('article-detail-save'));
    expect(
      find.descendant(of: save, matching: find.byIcon(Icons.bookmark_rounded)),
      findsOneWidget,
      reason:
          'the glyph must flip with the label on the same frame, not only after '
          'a reload',
    );
    expect(
      find.descendant(
        of: save,
        matching: find.byIcon(Icons.bookmark_add_outlined),
      ),
      findsNothing,
      reason: 'a just-saved article must not keep offering "add bookmark"',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an already saved article opens in the Saved state', (
    tester,
  ) async {
    final item = article(guid: 'save-3', title: 'Already bookmarked');
    await pumpDetailPage(tester, item: item, initiallySaved: true);

    expect(
      find.text('Saved'),
      findsOneWidget,
      reason: 'the first frame must already know the article is saved',
    );
    expect(find.text('Save article'), findsNothing);

    final button = tester.widget<TextButton>(
      find.byKey(const Key('article-detail-save')),
    );
    expect(
      button.enabled,
      isTrue,
      reason: 'Saved stays tappable: tapping it unsaves the article',
    );

    final save = find.byKey(const Key('article-detail-save'));
    expect(
      find.descendant(of: save, matching: find.byIcon(Icons.bookmark_rounded)),
      findsOneWidget,
      reason:
          'the saved state shows the filled bookmark, the same glyph the feed '
          'rows use for a bookmark',
    );
    expect(
      find.descendant(
        of: save,
        matching: find.byIcon(Icons.bookmark_add_outlined),
      ),
      findsNothing,
      reason: 'an "add bookmark" glyph beside "Saved" would contradict it',
    );
    expect(
      find.descendant(of: save, matching: find.text('Saved')),
      findsOneWidget,
      reason: 'the label stays pinned while the icon changes',
    );
  });

  testWidgets('tapping Saved unsaves the article and confirms the removal', (
    tester,
  ) async {
    final toggled = <Article>[];
    final item = article(guid: 'save-4', title: 'Unsave me');

    await pumpDetailPage(
      tester,
      item: item,
      initiallySaved: true,
      onToggleSave: (value) async {
        toggled.add(value);
      },
    );

    await tester.tap(find.byKey(const Key('article-detail-save')));
    await tester.pump();

    final undone = await pumpUntil(
      tester,
      () => find.text('Save article').evaluate().isNotEmpty,
    );

    expect(toggled.map((entry) => entry.guid).toList(), ['save-4']);
    expect(undone, isTrue, reason: 'the label must return to Save article');
    expect(find.text('Removed from saved'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('article-detail-save')),
        matching: find.byIcon(Icons.bookmark_add_outlined),
      ),
      findsOneWidget,
      reason: 'unsaving must restore the add-bookmark glyph with the label',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed toggle keeps the label and reports the error', (
    tester,
  ) async {
    final item = article(guid: 'save-5', title: 'Stubborn bookmark');

    await pumpDetailPage(
      tester,
      item: item,
      onToggleSave: (value) async {
        throw const FeedCacheFailure('Could not update saved articles');
      },
    );

    await tester.tap(find.byKey(const Key('article-detail-save')));
    await tester.pump();

    final shown = await pumpUntil(
      tester,
      () => find.text('Could not update saved articles').evaluate().isNotEmpty,
    );

    expect(
      shown,
      isTrue,
      reason: 'the FeedFailure message must be surfaced, not swallowed',
    );
    expect(
      find.text('Save article'),
      findsOneWidget,
      reason: 'a failed write must never claim the article was saved',
    );
    expect(find.text('Saved'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('article-detail-save')),
        matching: find.byIcon(Icons.bookmark_add_outlined),
      ),
      findsOneWidget,
      reason: 'the glyph must not flip when the write failed',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Save sits directly below Open, same size, inside the scroll view',
    (tester) async {
      final item = article(guid: 'save-6', title: 'Two actions');
      await pumpDetailPage(tester, item: item);

      final open = find.byKey(const Key('article-detail-open-on-phone'));
      final save = find.byKey(const Key('article-detail-save'));
      expect(open, findsOneWidget);
      expect(save, findsOneWidget);

      final openRect = tester.getRect(open);
      final saveRect = tester.getRect(save);

      expect(
        openRect.height,
        closeTo(44, 0.5),
        reason:
            'the open button is 44 dp tall '
            '(tapTargetSize: MaterialTapTargetSize.shrinkWrap)',
      );
      expect(
        saveRect.height,
        closeTo(44, 0.5),
        reason:
            'the save button must match the open button height, not the 48 dp '
            'padded tap target (tapTargetSize: MaterialTapTargetSize.shrinkWrap)',
      );
      expect(
        saveRect.top - openRect.bottom,
        closeTo(8, 0.5),
        reason: '8 dp groups the two actions without letting them touch',
      );
      expect(
        saveRect.top,
        greaterThan(openRect.top),
        reason: 'Save is the second action: below Open, never beside it',
      );
      expect(
        saveRect.left,
        closeTo(openRect.left, 0.5),
        reason: 'both actions share one left edge',
      );
      expect(
        saveRect.right,
        closeTo(openRect.right, 0.5),
        reason: 'both actions share one right edge',
      );
      expect(
        saveRect.width,
        closeTo(openRect.width, 0.5),
        reason: 'equal widths stop the pair from looking ragged',
      );

      for (final action in <Finder>[open, save]) {
        expect(
          find.ancestor(
            of: action,
            matching: find.byType(SingleChildScrollView),
          ),
          findsOneWidget,
          reason:
              'both actions travel with the content so they can be scrolled '
              'into the wide middle band of the circle',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the store read can correct an optimistic unsaved first frame', (
    tester,
  ) async {
    final item = article(guid: 'save-7', title: 'Saved elsewhere');

    await pumpDetailPage(
      tester,
      item: item,
      isArticleSaved: (identity) async => identity == 'save-7',
    );

    final labels = <String>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('Saved').evaluate().isNotEmpty) {
        labels.add('saved');
      } else if (find.text('Save article').evaluate().isNotEmpty) {
        labels.add('unsaved');
      }
    }

    expect(
      find.text('Saved'),
      findsOneWidget,
      reason: 'the authoritative store read must win over the optimistic frame',
    );
    expect(find.text('Save article'), findsNothing);
    expect(
      labels,
      isNotEmpty,
      reason: 'precondition: the save label is on screen in some form',
    );
    final firstSaved = labels.indexOf('saved');
    expect(firstSaved, isNot(-1), reason: 'the store read must flip the label');
    expect(
      labels.skip(firstSaved),
      everyElement('saved'),
      reason:
          'once corrected the label must never flip back: a visible flash of '
          '"Save article" reads as a lost bookmark',
    );
  });
}
