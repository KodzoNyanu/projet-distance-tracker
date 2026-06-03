/// Formats a [Duration] as HH:MM:SS (e.g. 01:23:45).
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

/// Formats a [Duration] as a human-readable string (e.g. "1h 23m").
String formatDurationShort(
  Duration d, {
  String hourUnit = 'h',
  String minuteUnit = 'm',
  String secondUnit = 's',
}) {
  if (d.inHours > 0) {
    return '${d.inHours}$hourUnit ${d.inMinutes.remainder(60)}$minuteUnit';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}$minuteUnit ${d.inSeconds.remainder(60)}$secondUnit';
  }
  return '${d.inSeconds}$secondUnit';
}

/// Formats distance in metres to a display string.
/// [useImperial] shows miles; otherwise kilometres.
String formatDistance(double meters, {bool useImperial = false}) {
  if (useImperial) {
    final miles = meters / 1609.344;
    if (miles >= 1.0) return '${miles.toStringAsFixed(2)} mi';
    final feet = meters * 3.28084;
    return '${feet.toStringAsFixed(0)} ft';
  } else {
    final km = meters / 1000.0;
    if (km >= 1.0) return '${km.toStringAsFixed(2)} km';
    return '${meters.toStringAsFixed(0)} m';
  }
}

/// Formats speed in m/s to a display string.
/// [useImperial] shows mph; otherwise km/h.
String formatSpeed(double speedMs, {bool useImperial = false}) {
  if (useImperial) {
    final mph = speedMs * 2.23694;
    return '${mph.toStringAsFixed(1)} mph';
  } else {
    final kmh = speedMs * 3.6;
    return '${kmh.toStringAsFixed(1)} km/h';
  }
}

/// Returns the unit label for a displayed distance value.
String distanceUnitForValue(double meters, {bool useImperial = false}) {
  if (useImperial) return meters / 1609.344 >= 1.0 ? 'mi' : 'ft';
  return meters >= 1000.0 ? 'km' : 'm';
}

/// Returns the large-distance unit label ("km" or "mi").
String distanceUnit({bool useImperial = false}) => useImperial ? 'mi' : 'km';

/// Returns the unit label for speed ("km/h" or "mph").
String speedUnit({bool useImperial = false}) => useImperial ? 'mph' : 'km/h';
