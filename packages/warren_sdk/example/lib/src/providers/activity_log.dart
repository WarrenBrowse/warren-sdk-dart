import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/log_entry.dart';

part 'activity_log.g.dart';

/// The in-app activity log. Every SDK call and mapped error is recorded here so
/// the whole surface can be exercised and observed in one place. Newest first.
@Riverpod(keepAlive: true)
class ActivityLog extends _$ActivityLog {
  static const int _cap = 500;

  @override
  List<LogEntry> build() => const [];

  void info(String category, String message) =>
      _add(LogLevel.info, category, message);

  void success(String category, String message) =>
      _add(LogLevel.success, category, message);

  void warning(String category, String message) =>
      _add(LogLevel.warning, category, message);

  void error(String category, String message, {String? code}) =>
      _add(LogLevel.error, category, message, code: code);

  void clear() => state = const [];

  void _add(LogLevel level, String category, String message, {String? code}) {
    final entry = LogEntry(
      time: DateTime.now(),
      level: level,
      category: category,
      message: message,
      code: code,
    );
    final next = <LogEntry>[entry, ...state];
    state = next.length > _cap ? next.sublist(0, _cap) : next;
  }
}
