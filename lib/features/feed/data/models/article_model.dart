import '../../domain/entities/article.dart';

/// JSON representation of [Article] used by the Hive cache.
class ArticleModel extends Article {
  const ArticleModel({
    required super.guid,
    required super.title,
    required super.link,
    required super.sourceName,
    required super.publishedAt,
    super.description,
    super.author,
  });

  factory ArticleModel.fromEntity(Article article) => ArticleModel(
    guid: article.guid,
    title: article.title,
    link: article.link,
    sourceName: article.sourceName,
    publishedAt: article.publishedAt,
    description: article.description,
    author: article.author,
  );

  factory ArticleModel.fromJson(Map<String, Object?> json) => ArticleModel(
    guid: json['guid']! as String,
    title: json['title']! as String,
    link: json['link']! as String,
    sourceName: json['sourceName']! as String,
    publishedAt: DateTime.parse(json['publishedAt']! as String).toLocal(),
    description: json['description'] as String?,
    author: json['author'] as String?,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'guid': guid,
    'title': title,
    'link': link,
    'sourceName': sourceName,
    'publishedAt': publishedAt.toIso8601String(),
    'description': description,
    'author': author,
  };
}
