import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../../../core/errors/feed_failure.dart';
import '../../domain/entities/article.dart';
import '../models/article_model.dart';

/// Storage contract for bookmarked articles.
///
/// Kept separate from [ArticleLocalDataSource]: the today cache is disposable
/// and rewritten on every refresh, while saved articles must survive it.
abstract interface class SavedArticleLocalDataSource {
  /// Saved articles exactly as they were written, without re-sorting.
  Future<List<Article>> readSaved();

  /// Replaces the saved store with [articles].
  Future<void> writeSaved(List<Article> articles);
}

/// Hive-backed store of bookmarked articles, stored as one JSON string under
/// [savedArticlesKey] in the shared cache box.
///
/// A corrupt store is treated as empty rather than crashing the watch, and the
/// saved key never touches the today cache key.
class HiveSavedArticleLocalDataSource implements SavedArticleLocalDataSource {
  /// Creates the store over the shared cache [box].
  HiveSavedArticleLocalDataSource(this._box);

  /// Key holding the saved-article JSON list inside the shared box.
  static const String savedArticlesKey = 'saved_articles';

  final Box<String> _box;

  @override
  Future<List<Article>> readSaved() async {
    try {
      final raw = _box.get(savedArticlesKey);
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
          // Skip a single unreadable entry instead of dropping every bookmark.
        }
      }
      return articles;
    } on Object {
      return const <Article>[];
    }
  }

  @override
  Future<void> writeSaved(List<Article> articles) async {
    try {
      final encoded = jsonEncode(
        articles
            .map((article) => ArticleModel.fromEntity(article).toJson())
            .toList(),
      );
      await _box.put(savedArticlesKey, encoded);
    } on Object catch (error) {
      throw FeedCacheFailure('Could not save saved articles.', cause: error);
    }
  }
}
