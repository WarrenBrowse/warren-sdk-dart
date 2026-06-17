import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A monospace, read-only value with a one-tap copy button. Used for addresses,
/// endpoints, hex keys and other opaque strings the user may want to reuse.
class CopyableValue extends StatelessWidget {
  const CopyableValue({
    required this.value,
    this.label,
    this.maxLines = 2,
    super.key,
  });

  final String value;
  final String? label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                SelectableText(
                  value,
                  maxLines: maxLines,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
