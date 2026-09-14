/// A small, local-first Markdown document captured by the user.
class Scrap {
  const Scrap({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.localDate,
    this.utcOffsetMinutes,
    this.timezoneName,
    this.assets = const <ScrapAsset>[],
    this.location,
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Calendar date at capture time, serialized as `YYYY-MM-DD`.
  ///
  /// This is nullable so documents written before the field was introduced
  /// remain readable.
  final String? localDate;

  /// UTC offset at capture time rather than the offset of the current device.
  final int? utcOffsetMinutes;

  /// Platform-provided time-zone name at capture time, for example `KST`.
  final String? timezoneName;
  final List<ScrapAsset> assets;
  final ScrapLocation? location;

  /// A date-only value for grouping this scrap on the timeline.
  ///
  /// New files use the persisted capture-day components. Legacy files fall
  /// back to the current device's local interpretation of [createdAt].
  DateTime get localCalendarDate {
    final components = _calendarDateComponents(localDate);
    if (components != null) {
      return DateTime(components.$1, components.$2, components.$3);
    }

    final offset = utcOffsetMinutes;
    final wallClock = offset == null
        ? createdAt.toLocal()
        : createdAt.toUtc().add(Duration(minutes: offset));
    return DateTime(wallClock.year, wallClock.month, wallClock.day);
  }

  /// Date-only value for modified-time sorting and Timeline grouping.
  DateTime get localUpdatedCalendarDate {
    final offset = utcOffsetMinutes;
    final wallClock = offset == null
        ? updatedAt.toLocal()
        : updatedAt.toUtc().add(Duration(minutes: offset));
    return DateTime(wallClock.year, wallClock.month, wallClock.day);
  }

  /// The first non-empty body line, suitable for compact list rows.
  ///
  /// An ATX Markdown heading marker is omitted so that `# A thought` is shown
  /// as `A thought`. Empty scraps deliberately return an empty string, leaving
  /// presentation-specific fallback text to the UI layer.
  String get firstLineTitle {
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      return trimmed.replaceFirst(RegExp(r'^#{1,6}\s+'), '').trim();
    }
    return '';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Scrap &&
            id == other.id &&
            body == other.body &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            localDate == other.localDate &&
            utcOffsetMinutes == other.utcOffsetMinutes &&
            timezoneName == other.timezoneName &&
            _listEquals(assets, other.assets) &&
            location == other.location;
  }

  @override
  int get hashCode => Object.hash(
    id,
    body,
    createdAt,
    updatedAt,
    localDate,
    utcOffsetMinutes,
    timezoneName,
    Object.hashAll(assets),
    location,
  );
}

(int, int, int)? _calendarDateComponents(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final candidate = DateTime.utc(year, month, day);
  if (candidate.year != year ||
      candidate.month != month ||
      candidate.day != day) {
    return null;
  }
  return (year, month, day);
}

/// A content-addressed file referenced by a [Scrap].
class ScrapAsset {
  const ScrapAsset({
    required this.hash,
    required this.relativePath,
    required this.originalName,
    required this.mimeType,
  });

  /// Lower-case hexadecimal SHA-256 digest of the original bytes.
  final String hash;

  /// POSIX-style path from the owning Markdown file to the stored asset.
  final String relativePath;
  final String originalName;
  final String mimeType;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ScrapAsset &&
            hash == other.hash &&
            relativePath == other.relativePath &&
            originalName == other.originalName &&
            mimeType == other.mimeType;
  }

  @override
  int get hashCode => Object.hash(hash, relativePath, originalName, mimeType);
}

/// The one-shot location captured when a scrap was saved.
class ScrapLocation {
  const ScrapLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.source,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// A stable source value such as `core_location` or `manual`.
  final String source;
  final DateTime capturedAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ScrapLocation &&
            latitude == other.latitude &&
            longitude == other.longitude &&
            accuracyMeters == other.accuracyMeters &&
            source == other.source &&
            capturedAt == other.capturedAt;
  }

  @override
  int get hashCode =>
      Object.hash(latitude, longitude, accuracyMeters, source, capturedAt);
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
