/// Compact relative timestamps for a 1.2" round display.
///
/// Examples: `now`, `7m`, `3h`, `2d`. Future timestamps (clock skew between
/// the phone and the watch) are clamped to `now`.
String formatRelativeTime(DateTime publishedAt, {required DateTime now}) {
  final elapsed = now.difference(publishedAt);
  if (elapsed.isNegative || elapsed.inMinutes < 1) {
    return 'now';
  }
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes}m';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours}h';
  }
  return '${elapsed.inDays}d';
}
