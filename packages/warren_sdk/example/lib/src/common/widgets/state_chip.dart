import 'package:flutter/material.dart' hide ConnectionState;
import 'package:warren_sdk/warren_sdk.dart';

/// A compact, color-coded chip for a [ConnectionState]. Exhaustively switches
/// over the sealed hierarchy so every state has a distinct, readable look.
class ConnectionStateChip extends StatelessWidget {
  const ConnectionStateChip(this.state, {super.key});

  final ConnectionState? state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (:label, :icon, :color) = _visual(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
            ),
          ),
        ],
      ),
    );
  }

  ({String label, IconData icon, Color color}) _visual(ColorScheme scheme) {
    return switch (state) {
      null || Disconnected() => (
          label: 'Disconnected',
          icon: Icons.cloud_off_outlined,
          color: scheme.outline,
        ),
      Connecting() => (
          label: 'Connecting',
          icon: Icons.sync,
          color: scheme.tertiary,
        ),
      Connected() => (
          label: 'Connected',
          icon: Icons.shield_outlined,
          color: Colors.green.shade600,
        ),
      Reconnecting(:final attempt) => (
          label: 'Reconnecting #$attempt',
          icon: Icons.autorenew,
          color: Colors.orange.shade700,
        ),
      ConnectionFailed(:final code) => (
          label: 'Failed ($code)',
          icon: Icons.error_outline,
          color: scheme.error,
        ),
    };
  }
}
