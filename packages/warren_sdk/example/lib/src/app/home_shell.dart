import 'package:flutter/material.dart';

import '../features/account/account_screen.dart';
import '../features/client/client_screen.dart';
import '../features/connection/connection_screen.dart';
import '../features/exits/exits_screen.dart';
import '../features/identity/identity_screen.dart';
import '../features/log/activity_log_screen.dart';
import '../features/overview/overview_screen.dart';
import 'status_bar.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.screen);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

const List<_Destination> _destinations = [
  _Destination(
    'Overview',
    Icons.dashboard_outlined,
    Icons.dashboard,
    OverviewScreen(),
  ),
  _Destination(
    'Identity',
    Icons.badge_outlined,
    Icons.badge,
    IdentityScreen(),
  ),
  _Destination(
    'Client',
    Icons.vpn_key_outlined,
    Icons.vpn_key,
    ClientScreen(),
  ),
  _Destination(
    'Account',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet,
    AccountScreen(),
  ),
  _Destination('Exits', Icons.public_outlined, Icons.public, ExitsScreen()),
  _Destination(
    'Connection',
    Icons.vpn_lock_outlined,
    Icons.vpn_lock,
    ConnectionScreen(),
  ),
  _Destination(
    'Activity',
    Icons.receipt_long_outlined,
    Icons.receipt_long,
    ActivityLogScreen(),
  ),
];

/// The app shell: a navigation rail beside the active screen, with a persistent
/// status bar (bound client + live connection state) in the app bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warren SDK Example'),
        actions: const [
          ClientStatusPill(),
          SizedBox(width: 12),
          ConnectionStatusChip(),
          SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            minExtendedWidth: 184,
            labelType: wide
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [for (final d in _destinations) d.screen],
            ),
          ),
        ],
      ),
    );
  }
}
