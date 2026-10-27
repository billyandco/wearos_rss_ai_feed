import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../../../../core/errors/feed_failure.dart';
import '../../domain/entities/article.dart';
import 'pub_date_parser.dart';

/// Description text kept per article. Some feeds inline the full article HTML;
/// retaining all of it would bloat the isolate payload on the watch.
const int maxDescriptionCharacters = 400;

/// Everything the background isolate needs to parse one feed.
class FeedParseInput {
  const FeedParseInput({
    required this.xml,
    required this.sourceName,
    required this.sourceUrl,
    required this.now,
  });

  final String xml;
  final String sourceName;
  final String sourceUrl;

  /// Fetch time used to discard older items *inside* the isolate.
  final DateTime now;
}

/// Parses [FeedParseInput.xml] into normalized, local-time [Article]s.
///
/// Rules:
/// * items without a usable pubDate, title or link are skipped;
/// * guid falls back to the link when the feed omits it;
/// * HTML is converted to plain text and capped at
///   [maxDescriptionCharacters];
/// * items not published on the local day of [FeedParseInput.now] are dropped
///   before they cross the isolate boundary.
List<Article> parseFeedXml(FeedParseInput input) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(input.xml);
  } on XmlException catch (error) {
    throw FeedParseFailure('Could not read ${input.sourceName}.', cause: error);
  }

  final articles = <Article>[];

  for (final item in document.findAllElements('item')) {
    final article = _parseItem(item, input);
    if (article != null) {
      articles.add(article);
    }
  }

  return articles;
}

/// Parses off the UI isolate: OpenAI (~1,300 items) and Hugging Face
/// (~900 items) contain their full archives.
Future<List<Article>> parseFeedXmlInIsolate(FeedParseInput input) =>
    compute(parseFeedXml, input);

Article? _parseItem(XmlElement item, FeedParseInput input) {
  final title = _toPlainText(_childText(item, 'title'));
  final link = _childText(item, 'link').trim();
  final publishedAt = parseFeedDate(_childText(item, 'pubDate'));

  if (title.isEmpty || link.isEmpty || publishedAt == null) {
    return null;
  }

  final guid = _childText(item, 'guid').trim();
  final rawDescription = _firstNonEmpty(<String>[
    _childText(item, 'description'),
    _childText(item, 'encoded'),
  ]);
  final description = _toPlainText(rawDescription);
  final author = _toPlainText(
    _firstNonEmpty(<String>[
      _childText(item, 'author'),
      _childText(item, 'creator'),
    ]),
  );

  final article = Article(
    guid: guid.isEmpty ? link : guid,
    title: title,
    link: link,
    sourceName: input.sourceName,
    publishedAt: publishedAt,
    description: description.isEmpty ? null : _capDescription(description),
    author: author.isEmpty ? null : author,
  );

  if (!article.isOnLocalDayOf(input.now)) {
    return null;
  }
  return article;
}

/// Value of the first direct child whose local name matches [name].
///
/// Local-name matching handles both `creator` and `dc:creator` (same for
/// `content:encoded` -> `encoded`) without hardcoding prefixes.
String _childText(XmlElement element, String name) {
  for (final child in element.childElements) {
    if (child.localName == name) {
      return child.innerText;
    }
  }
  return '';
}

String _firstNonEmpty(Iterable<String> candidates) {
  for (final candidate in candidates) {
    if (candidate.trim().isNotEmpty) {
      return candidate;
    }
  }
  return '';
}

/// Converts feed HTML into a single plain-text line.
String _toPlainText(String html) {
  final trimmed = html.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  try {
    final fragment = XmlDocumentFragment.parse(trimmed);
    for (final element in fragment.findAllElements('script').toList()) {
      element.remove();
    }
    for (final element in fragment.findAllElements('style').toList()) {
      element.remove();
    }
    return _collapseWhitespace(fragment.innerText);
  } on XmlException {
    final withoutTags = trimmed.replaceAll(RegExp('<[^>]*>'), ' ');
    return _collapseWhitespace(_decodeEntities(withoutTags));
  }
}

String _collapseWhitespace(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _decodeEntities(String value) => value
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");

String _capDescription(String value) {
  if (value.length <= maxDescriptionCharacters) {
    return value;
  }
  final cut = value.substring(0, maxDescriptionCharacters - 1).trimRight();
  return '$cut…';
}
