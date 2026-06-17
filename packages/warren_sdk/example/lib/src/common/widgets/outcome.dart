import 'package:flutter/material.dart';
import 'package:warren_sdk/warren_sdk.dart';

/// The sealed-error category of a [WarrenError], for display. Mirrors the
/// hierarchy in the SDK so the example shows exactly which subtype was raised.
({String label, IconData icon}) warrenErrorKind(WarrenError error) {
  return switch (error) {
    WarrenIdentityError() => (label: 'Identity', icon: Icons.badge_outlined),
    WarrenApiError() => (label: 'API', icon: Icons.cloud_outlined),
    WarrenDiscoveryError() => (
        label: 'Discovery',
        icon: Icons.travel_explore_outlined,
      ),
    WarrenTunnelError() => (label: 'Tunnel', icon: Icons.vpn_lock_outlined),
    WarrenPrivilegeError() => (
        label: 'Privilege',
        icon: Icons.admin_panel_settings_outlined,
      ),
    WarrenUnsupportedError() => (
        label: 'Unsupported',
        icon: Icons.block_outlined,
      ),
  };
}

/// Renders a thrown object. A [WarrenError] shows its sealed subtype, stable
/// code and redacted message; anything else is shown generically.
class OutcomeError extends StatelessWidget {
  const OutcomeError(this.error, {super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final err = error;

    final String title;
    final IconData icon;
    final String? code;
    final String message;
    if (err is WarrenError) {
      final kind = warrenErrorKind(err);
      title = '${kind.label} error';
      icon = kind.icon;
      code = err.code;
      message = err.message;
    } else {
      title = 'Error';
      icon = Icons.error_outline;
      code = null;
      message = err.toString();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
              if (code != null) ...[
                const SizedBox(width: 8),
                _CodeBadge(code, scheme: scheme),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// A success banner with a short message and an optional child (e.g. a copyable
/// value) underneath.
class OutcomeSuccess extends StatelessWidget {
  const OutcomeSuccess({required this.message, this.child, super.key});

  final String message;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (child != null) ...[const SizedBox(height: 12), child!],
        ],
      ),
    );
  }
}

class _CodeBadge extends StatelessWidget {
  const _CodeBadge(this.code, {required this.scheme});

  final String code;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.onErrorContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: scheme.onErrorContainer,
        ),
      ),
    );
  }
}
