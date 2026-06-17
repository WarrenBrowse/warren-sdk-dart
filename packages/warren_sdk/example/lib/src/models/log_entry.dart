import 'package:flutter/foundation.dart';

/// Severity of an activity-log line.
enum LogLevel { info, success, warning, error }

/// One line in the in-app activity log. The log is the "test everything"
/// surface: every SDK call and every mapped error lands here, already redacted.
@immutable
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.category,
    required this.message,
    this.code,
  });

  final DateTime time;
  final LogLevel level;

  /// A short area tag, e.g. `identity`, `account`, `connection`.
  final String category;

  /// A redacted, human-readable message. Never carries secret material.
  final String message;

  /// The stable error code, when this line records a failure.
  final String? code;
}
