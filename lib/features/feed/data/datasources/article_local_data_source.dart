import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../../../core/errors/feed_failure.dart';
import '../../domain/entities/article.dart';
import '../models/article_model.dart';

abstract interface class ArticleLocalDataSource {
  /// Cached articles exactly as they were written, without re-filtering.
  Future<List<Article>> readArticles();

  /// Replaces the cache with [articles] (today's list).
  Future<void> writeArticles(List<Article> articles);
}

/// Hive-backed cache of the last successful fetch, stored as one JSON string.
///
/// A corrupt or outdated cache is treated as empty rather than crashing the
/// watch; the next refresh repopulates it.
class HiveArticleLocalDataSource implements ArticleLocalDataSource {
  HiveArticleLocalDataSource(this._box);

  static const String boxName = 'articles_cache';
  static const String articlesKey = 'today_articles';

  final Box<String> _box;

  @override
  Future<List<Article>> readArticles() async {
    try {
      final raw = _box.get(articlesKey);
      if (raw == null || raw.isEmpty) {
        return const <Article>[];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) {
        return const <Article>[];
      }

      final articles = <Article>[];
      for (final entry in decoded) {
        if (entry is! Map<Object?, Object?>) {
          continue;
        }
        try {
          articles.add(ArticleModel.fromJson(Map<String, Object?>.from(entry)));
        } on Object {
          // Skip a single unreadable entry instead of dropping the whole cache.
        }
      }
      return articles;
    } on Object {
      return const <Article>[];
    }
  }

  @override
  Future<void> writeArticles(List<Article> articles) async {
    try {
      final encoded = jsonEncode(
        articles
            .map((article) => ArticleModel.fromEntity(article).toJson())
            .toList(),
      );
      await _box.put(articlesKey, encoded);
    } on Object catch (error) {
      throw FeedCacheFailure('Could not save today\'s articles.', cause: error);
    }
  }
}
