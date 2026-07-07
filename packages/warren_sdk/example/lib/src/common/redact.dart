// Display helpers that keep the no-log discipline: identity material is never
// shown in full. Mirrors the SDK rule of redacting to a short prefix.

/// Redacts an SS58 `wb...` address (or any opaque id) to a short, recognizable
/// stub: first 8 and last 4 characters. Short values are returned as-is.
String redactAddress(String value) {
  if (value.length <= 14) return value;
  return '${value.substring(0, 8)}…${value.substring(value.length - 4)}';
}

/// Formats a Unix timestamp (seconds) as a local date-time, or a dash when zero.
String formatUnixSeconds(int seconds) {
  if (seconds <= 0) return '-';
  final dt = DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// Maps an ISO 3166-1 alpha-2 country code to its flag emoji (regional
/// indicator pair). Falls back to a neutral flag for malformed input.
String countryFlag(String isoCode) {
  if (isoCode.length != 2) return '🏳️';
  final cc = isoCode.toUpperCase();
  final a = cc.codeUnitAt(0);
  final b = cc.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return '🏳️';
  return String.fromCharCodes([0x1F1E6 + (a - 0x41), 0x1F1E6 + (b - 0x41)]);
}

/// A compact wall-clock `HH:mm:ss` for log timestamps.
String formatClock(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}
