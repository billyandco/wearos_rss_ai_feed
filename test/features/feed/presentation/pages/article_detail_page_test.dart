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
}
