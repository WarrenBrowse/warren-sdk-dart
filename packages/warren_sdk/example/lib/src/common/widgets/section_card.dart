import 'package:flutter/material.dart';

/// A titled card used to group one feature on a screen. Keeps every screen
/// visually consistent: a leading icon, a title, an optional one-line
/// description, then the content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.description,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
