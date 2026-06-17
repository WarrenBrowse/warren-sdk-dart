import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/widgets/page_body.dart';
import '../../common/widgets/section_card.dart';
import '../../providers/constants.dart';

/// A landing page: what the app exercises, the active environment, and a short
/// guide mapping each tab to the SDK surface it covers.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  bool get _desktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return PageBody(
      title: 'Warren SDK Example',
      subtitle:
          'A hands-on tour of every feature of the Warren VPN Dart SDK, wired '
          'through the optional Riverpod 3 integration.',
      children: [
        SectionCard(
          title: 'Environment',
          icon: Icons.tune,
          description: 'Defaults, overridable with --dart-define.',
          child: Column(
            children: [
              const _Row('API base', AppEnv.apiBase),
              _Row(
                'Server pin',
                AppEnv.serverPubkeyPin.isEmpty
                    ? 'not set (fill it in the Client tab)'
                    : '${AppEnv.serverPubkeyPin.substring(0, 8)}… (set)',
              ),
              _Row(
                'Mode B daemon',
                _desktop ? AppEnv.daemonSocket : 'n/a (mobile uses proxy mode)',
              ),
              _Row(
                'Default engine',
                _desktop
                    ? 'Mode A in-process + Mode B desktop daemon registered'
                    : 'Mode A in-process (proxy)',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionCard(
          title: 'What to test',
          icon: Icons.checklist_rounded,
          child: Column(
            children: [
              _Guide(
                Icons.badge_outlined,
                'Identity',
                'generateMnemonic, addressFromMnemonic, ss58Encode/Decode. '
                    'No account needed.',
              ),
              _Guide(
                Icons.vpn_key_outlined,
                'Client',
                'Store the mnemonic securely, configure DAITA / IPv6 / pins, '
                    'create and dispose the client.',
              ),
              _Guide(
                Icons.account_balance_wallet_outlined,
                'Account',
                'subscription() snapshot and redeemVoucher().',
              ),
              _Guide(
                Icons.public_outlined,
                'Exits',
                'listExits() and selectExit() with an ExitQuery filter.',
              ),
              _Guide(
                Icons.vpn_lock_outlined,
                'Connection',
                'connect() in proxy or system-VPN mode, ConnectOptions, the '
                    'live state stream, endpoints and disconnect().',
              ),
              _Guide(
                Icons.receipt_long_outlined,
                'Activity',
                'A redacted log of every SDK call and mapped error.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'No identity material (mnemonic, address, IP) is ever logged in '
          'clear. Addresses are redacted to a short prefix.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
