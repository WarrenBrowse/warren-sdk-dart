import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk_example/src/models/log_entry.dart';
import 'package:warren_sdk_example/src/providers/activity_log.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  ActivityLog log() => container.read(activityLogProvider.notifier);

  test('starts empty', () {
    expect(container.read(activityLogProvider), isEmpty);
  });

  test('records entries newest-first with level and code', () {
    log().info('identity', 'generated');
    log().error('account', 'redacted failure', code: 'api/401');

    final entries = container.read(activityLogProvider);
    expect(entries, hasLength(2));
    expect(entries.first.level, LogLevel.error);
    expect(entries.first.code, 'api/401');
    expect(entries.last.category, 'identity');
  });

  test('clear empties the log', () {
    log().info('connection', 'up');
    log().clear();
    expect(container.read(activityLogProvider), isEmpty);
  });
}
