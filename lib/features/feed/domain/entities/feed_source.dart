/// A configured RSS feed and the display name of its publisher.
class FeedSource {
  const FeedSource({required this.name, required this.url});

  final String name;
  final String url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedSource && name == other.name && url == other.url;

  @override
  int get hashCode => Object.hash(name, url);

  @override
  String toString() => 'FeedSource($name, $url)';
}
