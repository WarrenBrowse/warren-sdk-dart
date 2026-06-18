import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/redact.dart';
import '../../models/log_entry.dart';
import '../../providers/activity_log.dart';

/// The activity log: every SDK call and mapped error, newest first, already
/// redacted. The single place to watch the whole surface react.
class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(activityLogProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity log'),
        actions: [
          TextButton.icon(
            onPressed: entries.isEmpty
                ? null
                : () => ref.read(activityLogProvider.notifier).clear(),
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Clear'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                'No activity yet. Exercise the SDK from the app.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _LogTile(entries[i]),
            ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile(this.entry);

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (:icon, :color) = switch (entry.level) {
      LogLevel.info => (icon: Icons.info_outline, color: scheme.primary),
      LogLevel.success => (
          icon: Icons.check_circle_outline,
          color: Colors.green.shade600,
        ),
      LogLevel.warning => (
          icon: Icons.warning_amber_outlined,
          color: Colors.orange.shade700,
        ),
      LogLevel.error => (icon: Icons.error_outline, color: scheme.error),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(entry.message),
      subtitle: Row(
        children: [
          Text(
            formatClock(entry.time),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          const SizedBox(width: 8),
          _Tag(entry.category),
          if (entry.code != null) ...[
            const SizedBox(width: 6),
            _Tag(entry.code!, mono: true),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.mono = false});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontFamily: mono ? 'monospace' : null,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
