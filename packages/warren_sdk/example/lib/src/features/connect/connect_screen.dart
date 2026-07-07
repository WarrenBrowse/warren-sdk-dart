import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../common/redact.dart';
import '../../providers/connection.dart';
import '../../providers/exit_selection.dart';
import '../../providers/ip_probe.dart';
import '../../providers/session_settings.dart';
import '../location/location_screen.dart';
import '../netcheck/netcheck_screen.dart';

typedef _Visual = ({String title, IconData icon, Color color, bool secured});

/// The home screen: a Mullvad-style secured/unsecured shield, the current exit,
/// and one big connect button. Everything else is a tap away.
class ConnectScreen extends ConsumerWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exits = ref.watch(exitsProvider).asData?.value ?? const <ExitInfo>[];
    final selected =
        ref.watch(selectedExitProvider) ?? (exits.isEmpty ? null : exits.first);

    final connection = ref.watch(connectionControllerProvider);
    final session = connection.asData?.value;
    final connecting = connection.isLoading;
    final liveState = session == null
        ? null
        : ref.watch(connectionStateProvider(session)).asData?.value;

    final visual = _visualFor(
      context,
      connecting: connecting,
      hasSession: session != null,
      state: liveState,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Warren VPN'),
        centerTitle: false,
        actions: const [_SubscriptionChip(), SizedBox(width: 12)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // The shield area is flexible so it absorbs spare height and shrinks
            // (scrolling if needed) instead of overflowing on a short window.
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 24),
                      _Shield(visual: visual, busy: connecting),
                      const SizedBox(height: 20),
                      Text(
                        visual.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      _SecuredDetail(secured: visual.secured, session: session),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _IpGlance(),
                  const SizedBox(height: 12),
                  _ExitTile(
                    exit: selected,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LocationScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ActionButton(
                    connecting: connecting,
                    connected: session != null,
                    canConnect: selected != null,
                    onConnect: () => _connect(ref, selected!),
                    onDisconnect: () => ref
                        .read(connectionControllerProvider.notifier)
                        .disconnect(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect(WidgetRef ref, ExitInfo exit) {
    final settings = ref.read(sessionSettingsControllerProvider);
    return ref.read(connectionControllerProvider.notifier).connect(
          exit: exit,
          mode: settings.mode,
          options: settings.toOptions(),
        );
  }

  _Visual _visualFor(
    BuildContext context, {
    required bool connecting,
    required bool hasSession,
    required ConnectionState? state,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (connecting) {
      return (
        title: 'Connecting…',
        icon: Icons.shield_outlined,
        color: Colors.orange.shade700,
        secured: false,
      );
    }
    if (!hasSession) {
      return (
        title: 'Not connected',
        icon: Icons.gpp_bad_outlined,
        color: scheme.outline,
        secured: false,
      );
    }
    return switch (state) {
      Connected() => (
          title: 'Secured',
          icon: Icons.gpp_good,
          color: Colors.green.shade600,
          secured: true,
        ),
      Reconnecting() => (
          title: 'Reconnecting…',
          icon: Icons.shield_outlined,
          color: Colors.orange.shade700,
          secured: false,
        ),
      Connecting() => (
          title: 'Connecting…',
          icon: Icons.shield_outlined,
          color: Colors.orange.shade700,
          secured: false,
        ),
      ConnectionFailed(:final code) => (
          title: 'Failed ($code)',
          icon: Icons.gpp_bad,
          color: scheme.error,
          secured: false,
        ),
      Disconnected() || null => (
          title: 'Secured',
          icon: Icons.gpp_good,
          color: Colors.green.shade600,
          secured: true,
        ),
    };
  }
}

class _Shield extends StatelessWidget {
  const _Shield({required this.visual, required this.busy});

  final _Visual visual;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: visual.color.withValues(alpha: 0.12),
            ),
            child: Icon(visual.icon, size: 72, color: visual.color),
          ),
          if (busy)
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(visual.color),
              ),
            ),
        ],
      ),
    );
  }
}

class _SecuredDetail extends StatelessWidget {
  const _SecuredDetail({required this.secured, required this.session});

  final bool secured;
  final WarrenSession? session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (!secured) {
      return Text('Your traffic is not protected', style: muted);
    }
    final endpoints = session?.endpoints;
    if (endpoints == null) {
      return Text('All device traffic routed through the exit', style: muted);
    }
    return Text('Proxy ready · SOCKS5 ${endpoints.socks5}', style: muted);
  }
}

class _ExitTile extends StatelessWidget {
  const _ExitTile({required this.exit, required this.onTap});

  final ExitInfo? exit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text(
                exit == null ? '🌐' : countryFlag(exit!.country),
                style: const TextStyle(fontSize: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Location',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      exit == null
                          ? 'Loading exits…'
                          : '${exit!.city}, ${exit!.country}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.connecting,
    required this.connected,
    required this.canConnect,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool connecting;
  final bool connected;
  final bool canConnect;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    if (connecting) {
      return const _BigButton(
        label: 'Connecting…',
        icon: null,
        onPressed: null,
        busy: true,
      );
    }
    if (connected) {
      return _BigButton(
        label: 'Disconnect',
        icon: Icons.stop_rounded,
        tonal: true,
        onPressed: onDisconnect,
      );
    }
    return _BigButton(
      label: 'Connect',
      icon: Icons.bolt,
      onPressed: canConnect ? onConnect : null,
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tonal = false,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool tonal;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (icon != null)
            Icon(icon),
          if (busy || icon != null) const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: tonal
          ? FilledButton.tonal(onPressed: onPressed, child: child)
          : FilledButton(onPressed: onPressed, child: child),
    );
  }
}

/// A live "you appear as" glance: the effective public IP (the exit IP when the
/// tunnel carries it, otherwise the real one), with a tap-through to the full
/// network / leak check.
class _IpGlance extends ConsumerWidget {
  const _IpGlance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final check = ref.watch(netCheckProvider);
    final data = check.asData?.value;
    final report = data?.effective;
    final verdict = data?.verdict ?? LeakVerdict.pending;

    final (badge, badgeColor) = switch (verdict) {
      LeakVerdict.protected => ('Protected', Colors.green.shade600),
      LeakVerdict.exposed => ('Exposed', Colors.orange.shade800),
      LeakVerdict.leaking => ('Leaking', scheme.error),
      LeakVerdict.unknown => ('Unverified', scheme.outline),
      LeakVerdict.pending => ('Checking…', scheme.outline),
    };

    final String line;
    if (check.isLoading && report == null) {
      line = 'Resolving your public IP…';
    } else if (report != null) {
      final flag = report.country != null ? countryFlag(report.country!) : '';
      line = flag.isEmpty ? report.ip : '${report.ip} · $flag';
    } else {
      line = 'Public IP unavailable';
    }

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NetCheckScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.travel_explore, color: scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Public IP',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: badgeColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      line,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (check.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionChip extends ConsumerWidget {
  const _SubscriptionChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider);
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (sub) {
      AsyncData(:final value) when value.isActive => (
          'Active · ${formatUnixSeconds(value.expiresAtUnix).split(' ').first}',
          Colors.green.shade600,
        ),
      AsyncData() => ('Inactive', scheme.error),
      AsyncError() => ('Account error', scheme.error),
      _ => ('…', scheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
