import 'package:flutter_test/flutter_test.dart';
import 'package:wearos_rss_ai_feed/features/feed/data/models/article_model.dart';

import '../../../../support/article_factory.dart';

void main() {
  test('round-trips every field through JSON', () {
    final model = ArticleModel.fromEntity(article());

    final restored = ArticleModel.fromJson(model.toJson());

    expect(restored, equals(article()));
    expect(restored.publishedAt.isUtc, isFalse);
  });

  test('round-trips null description and author', () {
    final source = article(description: null, author: null);

    final restored = ArticleModel.fromJson(
      ArticleModel.fromEntity(source).toJson(),
    );

    expect(restored.description, isNull);
    expect(restored.author, isNull);
    expect(restored, equals(source));
  });

  test('keeps the published instant when serialized as ISO-8601', () {
    final source = article(publishedAt: DateTime(2026, 10, 27, 11, 20, 51));
    final json = ArticleModel.fromEntity(source).toJson();

    expect(
      ArticleModel.fromJson(json).publishedAt.toUtc(),
      source.publishedAt.toUtc(),
    );
  });
}
