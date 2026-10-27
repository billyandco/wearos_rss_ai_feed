/// A single article, normalized from any of the configured RSS feeds.
///
/// Instances are produced by the data layer in the device's local timezone:
/// [publishedAt] is always a local [DateTime]. Domain and presentation code can
/// therefore reason about "today" without any further timezone conversion.
class Article {
  const Article({
    required this.guid,
    required this.title,
    required this.link,
    required this.sourceName,
    required this.publishedAt,
    this.description,
    this.author,
  });

  /// Feed-provided stable identifier, or the link when the feed omits a guid.
  final String guid;
  final String title;
  final String link;
  final String sourceName;
  final DateTime publishedAt;
  final String? description;
  final String? author;

  /// Stable key used for de-duplication: guid, falling back to the link.
  String get identity => guid.isNotEmpty ? guid : link;

  /// Whether this article was published on the same local calendar day as
  /// [day].
  bool isOnLocalDayOf(DateTime day) {
    final published = publishedAt.toLocal();
    final reference = day.toLocal();
    return published.year == reference.year &&
        published.month == reference.month &&
        published.day == reference.day;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Article &&
          guid == other.guid &&
          title == other.title &&
          link == other.link &&
          sourceName == other.sourceName &&
          publishedAt == other.publishedAt &&
          description == other.description &&
          author == other.author;

  @override
  int get hashCode => Object.hash(
    guid,
    title,
    link,
    sourceName,
    publishedAt,
    description,
    author,
  );

  @override
  String toString() =>
      'Article($sourceName, $publishedAt, "$title", guid: $guid)';
}
