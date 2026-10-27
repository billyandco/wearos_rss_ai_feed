import 'package:flutter_test/flutter_test.dart';

import '../../../../support/article_factory.dart';

void main() {
  group('Article.identity', () {
    test('uses the guid when the feed provides one', () {
      final item = article(guid: 'urn:uuid:1234', link: 'https://a.example/x');
      expect(item.identity, 'urn:uuid:1234');
    });

    test('falls back to the link when the guid is empty', () {
      final item = article(guid: '', link: 'https://a.example/x');
      expect(item.identity, 'https://a.example/x');
    });
  });

  group('Article.isOnLocalDayOf', () {
    test('is true for any time on the same local calendar day', () {
      final item = article(publishedAt: DateTime(2026, 10, 27, 0, 5));
      expect(item.isOnLocalDayOf(DateTime(2026, 10, 27, 23, 59)), isTrue);
    });

    test('is false for the previous and the next local day', () {
      final item = article(publishedAt: DateTime(2026, 10, 27, 9, 30));
      expect(item.isOnLocalDayOf(DateTime(2026, 10, 26, 23, 59)), isFalse);
      expect(item.isOnLocalDayOf(DateTime(2026, 10, 28, 0, 1)), isFalse);
    });

    test('compares against the local day even if the reference is UTC', () {
      final localNoon = DateTime(2026, 10, 27, 12);
      final item = article(publishedAt: localNoon);
      expect(item.isOnLocalDayOf(localNoon.toUtc()), isTrue);
    });
  });

  test('description and author are optional (Hugging Face items)', () {
    final item = article(description: null, author: null);
    expect(item.description, isNull);
    expect(item.author, isNull);
  });

  test('has value equality over every normalized field', () {
    final first = article();
    final second = article();
    final differentDescription = article(description: 'Something else');

    expect(first, equals(second));
    expect(first.hashCode, equals(second.hashCode));
    expect(first, isNot(equals(differentDescription)));
  });
}
