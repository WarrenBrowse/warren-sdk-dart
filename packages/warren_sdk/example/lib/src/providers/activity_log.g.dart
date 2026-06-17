// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_log.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The in-app activity log. Every SDK call and mapped error is recorded here so
/// the whole surface can be exercised and observed in one place. Newest first.

@ProviderFor(ActivityLog)
const activityLogProvider = ActivityLogProvider._();

/// The in-app activity log. Every SDK call and mapped error is recorded here so
/// the whole surface can be exercised and observed in one place. Newest first.
final class ActivityLogProvider
    extends $NotifierProvider<ActivityLog, List<LogEntry>> {
  /// The in-app activity log. Every SDK call and mapped error is recorded here so
  /// the whole surface can be exercised and observed in one place. Newest first.
  const ActivityLogProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'activityLogProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$activityLogHash();

  @$internal
  @override
  ActivityLog create() => ActivityLog();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LogEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LogEntry>>(value),
    );
  }
}

String _$activityLogHash() => r'45fdaf5ab62ec8c1c9cebc69aa4e69d92c0fc272';

/// The in-app activity log. Every SDK call and mapped error is recorded here so
/// the whole surface can be exercised and observed in one place. Newest first.

abstract class _$ActivityLog extends $Notifier<List<LogEntry>> {
  List<LogEntry> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<LogEntry>, List<LogEntry>>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<List<LogEntry>, List<LogEntry>>,
        List<LogEntry>,
        Object?,
        Object?>;
    element.handleValue(ref, created);
  }
}
