import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../common/redact.dart';
import '../common/widgets/state_chip.dart';
import '../providers/connection.dart';

/// A small pill showing whether a [WarrenClient] is bound, and its redacted
/// address when it is. Reflects the live `warrenClientProvider`.
class ClientStatusPill extends ConsumerWidget {
  const ClientStatusPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(warrenClientProvider);
    final scheme = Theme.of(context).colorScheme;

    final (:label, :icon, :color) = switch (client) {
      AsyncData(:final value) => (
          label: redactAddress(value.address),
          icon: Icons.fingerprint,
          color: scheme.primary,
        ),
      AsyncLoading() => (
          label: 'Creating client…',
          icon: Icons.hourglass_empty,
          color: scheme.tertiary,
        ),
      _ => (
          label: 'No client',
          icon: Icons.person_off_outlined,
          color: scheme.outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// The live connection chip for the app bar. Mirrors the active session's
/// broadcast state through the package's `connectionStateProvider`.
class ConnectionStatusChip extends ConsumerWidget {
  const ConnectionStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(connectionControllerProvider).asData?.value;
    if (session == null) {
      return const ConnectionStateChip(null);
    }
    final state = ref.watch(connectionStateProvider(session)).asData?.value;
    return ConnectionStateChip(state);
  }
}
