import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

part 'exit_selection.g.dart';

/// The current [ExitQuery] used to filter the exit list and drive
/// `WarrenClient.selectExit`.
@riverpod
class ExitQueryController extends _$ExitQueryController {
  @override
  ExitQuery build() => const ExitQuery();

  void update(ExitQuery query) => state = query;

  void clear() => state = const ExitQuery();
}

/// The exit the user picked to connect through, or null.
@riverpod
class SelectedExit extends _$SelectedExit {
  @override
  ExitInfo? build() => null;

  void select(ExitInfo? exit) => state = exit;
}
