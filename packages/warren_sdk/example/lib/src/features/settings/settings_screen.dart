import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../providers/connection.dart';
import '../../providers/constants.dart';
import '../../providers/session_settings.dart';
import '../../providers/wallet.dart';
import '../developer/developer_screen.dart';

/// Connection preferences plus the door to the developer tools. The
/// SDK-exercising surfaces (identity helpers, raw engine config, activity log)
/// live under Developer so this stays a clean, app-like settings page.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(sessionSettingsControllerProvider);
    final controller = ref.read(sessionSettingsControllerProvider.notifier);
    final connected =
        ref.watch(connectionControllerProvider).asData?.value != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Connection'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<ConnectMode>(
              segments: const [
                ButtonSegment(
                  value: ConnectMode.proxy,
                  icon: Icon(Icons.lan_outlined),
                  label: Text('Proxy'),
                ),
                ButtonSegment(
                  value: ConnectMode.systemVpn,
                  icon: Icon(Icons.vpn_lock_outlined),
                  label: Text('System VPN'),
                ),
              ],
              selected: {settings.mode},
              onSelectionChanged:
                  connected ? null : (s) => controller.setMode(s.first),
            ),
          ),
          if (settings.mode == ConnectMode.systemVpn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Needs the privileged warrend daemon at ${AppEnv.daemonSocket}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (connected)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Disconnect to change the mode.'),
            ),
          // Proxy mode always resolves names remotely at the exit (SOCKS5/HTTP
          // CONNECT), so DNS-over-tunnel is only a meaningful, wired option for
          // the system-VPN datapath.
          if (settings.mode == ConnectMode.systemVpn)
            SwitchListTile(
              secondary: const Icon(Icons.dns_outlined),
              title: const Text('DNS over tunnel'),
              subtitle: const Text('Resolve names at the exit gateway'),
              value: settings.dnsOverTunnel,
              onChanged: controller.setDnsOverTunnel,
            ),
          const Divider(),
          const _Header('Advanced'),
          ListTile(
            leading: const Icon(Icons.developer_mode),
            title: const Text('Developer tools'),
            subtitle:
                const Text('Identity helpers, engine config, activity log'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DeveloperScreen()),
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Reset wallet',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('Wipe the mnemonic from the secure store'),
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset wallet?'),
        content: const Text(
          'This wipes the mnemonic from the secure store and disconnects. '
          'You will need to create or import a wallet again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(connectionControllerProvider.notifier).disconnect();
      await ref.read(walletProvider.notifier).reset();
    }
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
