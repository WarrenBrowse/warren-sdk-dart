import 'package:flutter/material.dart';

import '../log/activity_log_screen.dart';
import '../netcheck/netcheck_screen.dart';
import 'engine_config_screen.dart';
import 'identity_tools_screen.dart';

/// The developer hub. Everything that exercises the SDK directly (stateless
/// identity helpers, the raw engine configuration, the activity log) lives here,
/// keeping the main app surfaces clean and product-like.
class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Developer tools')),
      body: ListView(
        children: [
          const _Tile(
            icon: Icons.badge_outlined,
            title: 'Identity helpers',
            subtitle:
                'generateMnemonic, addressFromMnemonic, ss58 encode/decode',
            screen: IdentityToolsScreen(),
          ),
          const _Tile(
            icon: Icons.tune,
            title: 'Engine configuration',
            subtitle: 'API base, pins, DAITA, IPv6 (rebuilds the client)',
            screen: EngineConfigScreen(),
          ),
          const _Tile(
            icon: Icons.travel_explore,
            title: 'Network check',
            subtitle: 'Live public IP, real vs exit, IPv6 leak probe',
            screen: NetCheckScreen(),
          ),
          const _Tile(
            icon: Icons.receipt_long_outlined,
            title: 'Activity log',
            subtitle: 'Every SDK call and mapped error, redacted',
            screen: ActivityLogScreen(),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen),
      ),
    );
  }
}
