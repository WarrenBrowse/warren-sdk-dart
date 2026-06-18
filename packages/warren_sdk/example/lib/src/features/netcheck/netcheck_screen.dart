import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/redact.dart';
import '../../providers/ip_probe.dart';

/// A practical "what is my IP" / leak-test surface. It runs two lookups, one on
/// the real connection and one through the Warren tunnel, and reports whether
/// the egress IP actually changed, plus an IPv6 reachability probe.
class NetCheckScreen extends ConsumerWidget {
  const NetCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(netCheckProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network check'),
        actions: [
          IconButton(
            tooltip: 'Re-run',
            icon: const Icon(Icons.refresh),
            onPressed: check.isLoading
                ? null
                : () {
                    ref.invalidate(netCheckProvider);
                    ref.invalidate(serverCheckProvider);
                  },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(serverCheckProvider);
          ref.invalidate(netCheckProvider);
          await ref.read(netCheckProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _VerdictBanner(check: check),
            const SizedBox(height: 16),
            check.when(
              loading: () => const _Hint('Looking up your public IP…'),
              error: (e, _) => _Hint('Check failed: $e'),
              data: (data) => _Results(data: data),
            ),
            const SizedBox(height: 12),
            const _ServerCheckCard(),
          ],
        ),
      ),
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.check});

  final AsyncValue<NetCheck> check;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verdict = check.isLoading
        ? LeakVerdict.pending
        : (check.asData?.value.verdict ?? LeakVerdict.unknown);

    final (label, detail, icon, color) = switch (verdict) {
      LeakVerdict.protected => (
          'Protected',
          'Your real IP is hidden. Servers see the Warren exit.',
          Icons.verified_user,
          Colors.green.shade600,
        ),
      LeakVerdict.exposed => (
          'Exposed',
          'No tunnel. Servers see your real IP below.',
          Icons.public,
          Colors.orange.shade800,
        ),
      LeakVerdict.leaking => (
          'Leaking',
          'The tunnel egress equals your real IP: traffic is NOT tunneled.',
          Icons.warning_amber,
          scheme.error,
        ),
      LeakVerdict.unknown => (
          'Unverified',
          'Could not reach the lookup service on one of the paths.',
          Icons.help_outline,
          scheme.outline,
        ),
      LeakVerdict.pending => (
          'Checking…',
          'Probing the real connection and the tunnel.',
          Icons.hourglass_top,
          scheme.outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.data});

  final NetCheck data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _IpCard(
          title: 'Real connection',
          subtitle: 'Proxy bypassed. This is your unprotected identity.',
          icon: Icons.home_outlined,
          report: data.direct,
          error: data.directError,
          ipv6: data.directIpv6,
        ),
        const SizedBox(height: 12),
        if (data.systemVpn)
          const _Hint(
            'System VPN (Mode B): all OS traffic is tunneled, so the line above '
            'is already the exit. Capture a baseline before connecting to '
            'compare.',
          )
        else
          _IpCard(
            title: 'Through Warren',
            subtitle: data.connected
                ? 'Routed over the SOCKS5/HTTP proxy to the exit.'
                : 'Connect to route a probe through the tunnel.',
            icon: Icons.shield_outlined,
            report: data.tunnel,
            error: data.connected
                ? (data.tunnelError ??
                    (data.tunnel == null ? 'no answer' : null))
                : 'not connected',
            ipv6: data.tunnelIpv6,
            highlight: true,
          ),
      ],
    );
  }
}

class _IpCard extends StatelessWidget {
  const _IpCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.report,
    required this.error,
    this.ipv6,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final IpReport? report;
  final String? error;
  final IpReport? ipv6;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer.withValues(alpha: 0.4)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
              const Spacer(),
              if (report?.country != null)
                Text(
                  countryFlag(report!.country!),
                  style: const TextStyle(fontSize: 22),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Divider(height: 20),
          if (report != null) ...[
            SelectableText(
              report!.ip,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (report!.country != null)
              Text(
                'Country: ${report!.country}',
                style: theme.textTheme.bodyMedium,
              ),
          ] else
            Text(
              error ?? 'no result',
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.error),
            ),
          const SizedBox(height: 10),
          _Ipv6Row(report: ipv6, highlight: highlight),
        ],
      ),
    );
  }
}

class _Ipv6Row extends StatelessWidget {
  const _Ipv6Row({required this.report, required this.highlight});

  final IpReport? report;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final has = report != null;
    // A reachable IPv6 on the real connection is the usual leak path; on the
    // tunnel it just means the exit offers IPv6 egress.
    final color = has && !highlight ? Colors.orange.shade800 : scheme.outline;
    return Row(
      children: [
        Icon(
          has ? Icons.warning_amber_outlined : Icons.block,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            has ? 'IPv6: ${report!.ip}' : 'IPv6: none',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The account server's authoritative answer via `WarrenClient.checkTunnel()`
/// (`/v1/check`). Confirms, backend-side, whether traffic egresses from a
/// registered exit. Meaningful for system VPN (all traffic tunneled); in proxy
/// mode it reports the device's own IP, since signed account calls go direct.
class _ServerCheckCard extends ConsumerWidget {
  const _ServerCheckCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final check = ref.watch(serverCheckProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.dns_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('Account server', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'What api.warrenbrowse.com sees for the signed /v1/check call: '
            'tunneled in system VPN, direct in proxy mode.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const Divider(height: 20),
          check.when(
            loading: () => const Text('Asking the server…'),
            error: (e, _) => Text(
              'Unavailable: $e',
              style: TextStyle(color: scheme.error),
            ),
            data: (c) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      c.isExit ? Icons.verified_user : Icons.public,
                      size: 18,
                      color: c.isExit ? Colors.green.shade600 : scheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c.isExit ? 'Exit confirmed' : 'Not an exit',
                      style: theme.textTheme.titleSmall,
                    ),
                    if (c.country != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        countryFlag(c.country!),
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(c.ip, style: theme.textTheme.bodyLarge),
                if (c.city != null)
                  Text(
                    c.city!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
