import 'dart:io';

/// Parses the `pubDate` values found in the supported RSS feeds.
///
/// The feeds mix RFC 1123 (`GMT`), RFC 822 with numeric offsets (`+0000`, as
/// used by WordPress) and, occasionally, ISO-8601. [HttpDate.parse] only
/// understands the `GMT` form, so numeric offsets and named zones are handled
/// explicitly. The returned value is always in the device's local timezone.
DateTime? parseFeedDate(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }

  try {
    return HttpDate.parse(value).toLocal();
  } on HttpException {
    // Not an RFC 1123 GMT date: try the other shapes below.
  } on FormatException {
    // Not an RFC 1123 GMT date: try the other shapes below.
  }

  final isoDate = DateTime.tryParse(value);
  if (isoDate != null) {
    return isoDate.toLocal();
  }

  return _parseRfc822(value);
}

final RegExp _rfc822Pattern = RegExp(
  r'^(?:(?<weekday>[A-Za-z]{3}),?\s+)?'
  r'(?<day>\d{1,2})[\s-]+(?<month>[A-Za-z]{3})[\s-]+(?<year>\d{2,4})\s+'
  r'(?<hour>\d{1,2}):(?<minute>\d{2})(?::(?<second>\d{2}))?\s+'
  r'(?<zone>[+-]\d{4}|[A-Za-z]{1,5})$',
);

const Map<String, int> _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Offset in minutes east of UTC for the three-letter zones seen in RSS.
const Map<String, int> _namedZones = <String, int>{
  'ut': 0,
  'utc': 0,
  'gmt': 0,
  'z': 0,
  'est': -5 * 60,
  'edt': -4 * 60,
  'cst': -6 * 60,
  'cdt': -5 * 60,
  'mst': -7 * 60,
  'mdt': -6 * 60,
  'pst': -8 * 60,
  'pdt': -7 * 60,
};

DateTime? _parseRfc822(String value) {
  final match = _rfc822Pattern.firstMatch(value);
  if (match == null) {
    return null;
  }

  final day = int.tryParse(match.namedGroup('day') ?? '');
  final month = _months[match.namedGroup('month')?.toLowerCase()];
  final rawYear = int.tryParse(match.namedGroup('year') ?? '');
  final hour = int.tryParse(match.namedGroup('hour') ?? '');
  final minute = int.tryParse(match.namedGroup('minute') ?? '');
  final second = int.tryParse(match.namedGroup('second') ?? '0');
  final offsetMinutes = _zoneOffsetMinutes(match.namedGroup('zone') ?? '');

  if (day == null ||
      month == null ||
      rawYear == null ||
      hour == null ||
      minute == null ||
      second == null ||
      offsetMinutes == null) {
    return null;
  }

  // RFC 822 allows two-digit years: 00-49 are 2000-2049, 50-99 are 1950-1999.
  final year = rawYear < 100
      ? (rawYear < 50 ? 2000 + rawYear : 1900 + rawYear)
      : rawYear;

  if (month < 1 || month > 12 || day < 1 || day > _daysInMonth(year, month)) {
    return null;
  }
  if (hour > 23 || minute > 59 || second > 59) {
    return null;
  }

  final utc = DateTime.utc(year, month, day, hour, minute, second);
  return utc.subtract(Duration(minutes: offsetMinutes)).toLocal();
}

int _daysInMonth(int year, int month) {
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  final isLeapYear = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  return month == 2 && isLeapYear ? 29 : days[month - 1];
}

int? _zoneOffsetMinutes(String zone) {
  if (zone.isEmpty) {
    return null;
  }

  if (zone.startsWith('+') || zone.startsWith('-')) {
    if (zone.length != 5) {
      return null;
    }
    final hours = int.tryParse(zone.substring(1, 3));
    final minutes = int.tryParse(zone.substring(3, 5));
    if (hours == null || minutes == null || hours > 14 || minutes > 59) {
      return null;
    }
    final offset = hours * 60 + minutes;
    return zone.startsWith('-') ? -offset : offset;
  }

  return _namedZones[zone.toLowerCase()];
}
