// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'dart:async' as _i6;

import 'package:auto_route/auto_route.dart' as _i3;
import 'package:flutter/material.dart' as _i4;
import 'package:wearos_rss_ai_feed/features/feed/domain/entities/article.dart'
    as _i5;
import 'package:wearos_rss_ai_feed/features/feed/presentation/pages/article_detail_page.dart'
    as _i1;
import 'package:wearos_rss_ai_feed/features/feed/presentation/pages/feed_page.dart'
    as _i2;

/// generated route for
/// [_i1.ArticleDetailPage]
class ArticleDetailRoute extends _i3.PageRouteInfo<ArticleDetailRouteArgs> {
  ArticleDetailRoute({
    _i4.Key? key,
    required _i5.Article article,
    DateTime Function()? clock,
    _i6.Future<void> Function(_i5.Article)? onOpenOnPhone,
    List<_i3.PageRouteInfo>? children,
  }) : super(
         ArticleDetailRoute.name,
         args: ArticleDetailRouteArgs(
           key: key,
           article: article,
           clock: clock,
           onOpenOnPhone: onOpenOnPhone,
         ),
         initialChildren: children,
       );

  static const String name = 'ArticleDetailRoute';

  static _i3.PageInfo page = _i3.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ArticleDetailRouteArgs>();
      return _i1.ArticleDetailPage(
        key: args.key,
        article: args.article,
        clock: args.clock,
        onOpenOnPhone: args.onOpenOnPhone,
      );
    },
  );
}

class ArticleDetailRouteArgs {
  const ArticleDetailRouteArgs({
    this.key,
    required this.article,
    this.clock,
    this.onOpenOnPhone,
  });

  final _i4.Key? key;

  final _i5.Article article;

  final DateTime Function()? clock;

  final _i6.Future<void> Function(_i5.Article)? onOpenOnPhone;

  @override
  String toString() {
    return 'ArticleDetailRouteArgs{key: $key, article: $article, clock: $clock, onOpenOnPhone: $onOpenOnPhone}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ArticleDetailRouteArgs) return false;
    return key == other.key && article == other.article;
  }

  @override
  int get hashCode => key.hashCode ^ article.hashCode;
}

/// generated route for
/// [_i2.FeedPage]
class FeedRoute extends _i3.PageRouteInfo<void> {
  const FeedRoute({List<_i3.PageRouteInfo>? children})
    : super(FeedRoute.name, initialChildren: children);

  static const String name = 'FeedRoute';

  static _i3.PageInfo page = _i3.PageInfo(
    name,
    builder: (data) {
      return const _i2.FeedPage();
    },
  );
}
