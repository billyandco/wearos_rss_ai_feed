/// Builds small RSS 2.0 documents for parser tests, with dates relative to a
/// fixed local calendar day so the tests are independent of the machine's
/// timezone.
library;

String _two(int value) => value.toString().padLeft(2, '0');

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [local] as an RFC 822 date in UTC, e.g. `Tue, 27 Oct 2026 09:15:00 GMT`.
String rfc822(DateTime local) {
  final utc = local.toUtc();
  return '${_weekdays[utc.weekday - 1]}, ${_two(utc.day)} '
      '${_months[utc.month - 1]} ${utc.year} '
      '${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)} GMT';
}

/// Formats [local] as an RFC 822 date with a numeric offset, the format used by
/// WordPress feeds such as The Decoder.
String rfc822WithOffset(DateTime local) {
  final utc = local.toUtc();
  return '${_weekdays[utc.weekday - 1]}, ${_two(utc.day)} '
      '${_months[utc.month - 1]} ${utc.year} '
      '${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)} +0000';
}

String feedXml(Iterable<String> items, {String title = 'Test Feed'}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:content="http://purl.org/rss/1.0/modules/content/"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$title</title>
    <link>https://example.com</link>
    <description>Test feed</description>
    ${items.join('\n')}
  </channel>
</rss>
''';

String itemXml({
  String? title = 'A headline about AI',
  String? link = 'https://example.com/articles/1',
  String? guid = 'guid-1',
  String? pubDate,
  String? description,
  String? contentEncoded,
  String? author,
  String? dcCreator,
}) {
  final buffer = StringBuffer('<item>');
  if (title != null) {
    buffer.write('<title><![CDATA[$title]]></title>');
  }
  if (link != null) {
    buffer.write('<link>$link</link>');
  }
  if (guid != null) {
    buffer.write('<guid isPermaLink="false">$guid</guid>');
  }
  if (pubDate != null) {
    buffer.write('<pubDate>$pubDate</pubDate>');
  }
  if (description != null) {
    buffer.write('<description><![CDATA[$description]]></description>');
  }
  if (contentEncoded != null) {
    buffer.write(
      '<content:encoded><![CDATA[$contentEncoded]]></content:encoded>',
    );
  }
  if (author != null) {
    buffer.write('<author>$author</author>');
  }
  if (dcCreator != null) {
    buffer.write('<dc:creator><![CDATA[$dcCreator]]></dc:creator>');
  }
  buffer.write('</item>');
  return buffer.toString();
}
