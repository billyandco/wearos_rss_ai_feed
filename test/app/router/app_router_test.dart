import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/app/router/app_router.dart';
import 'package:wearos_rss_ai_feed/app/router/app_router.gr.dart';

void main() {
  test('registers the article detail route next to the feed route', () {
    expect(
      ArticleDetailRoute.page.name,
      'ArticleDetailRoute',
      reason: 'the generated route must exist for the detail page',
    );

    final names = AppRouter().routes.map((route) => route.name).toList();

    expect(names, contains('FeedRoute'));
    expect(
      names,
      contains('ArticleDetailRoute'),
      reason:
          'AppRouter.routes must expose the detail page so a single tap '
          'can push it',
    );
  });

  test('keeps the feed as the initial destination', () {
    final router = AppRouter();
    final initialRoutes = router.routes
        .where((route) => route.initial)
        .map((route) => route.name)
        .toList();

    expect(initialRoutes, ['FeedRoute']);
  });
}
