import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/widgets/outcome.dart';
import '../features/account/account_screen.dart';
import '../features/connect/connect_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/settings_screen.dart';
import '../providers/wallet.dart';

/// Root gate: shows onboarding until a wallet exists, then the main app.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    return switch (wallet) {
      AsyncData(:final value) =>
        value == null ? const OnboardingScreen() : const _MainScaffold(),
      AsyncError(:final error) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: OutcomeError(error)),
          ),
        ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// The bottom-nav shell once a wallet is set up: Connect, Account, Settings.
class _MainScaffold extends StatefulWidget {
  const _MainScaffold();

  @override
  State<_MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<_MainScaffold> {
  int _index = 0;

  static const _screens = [ConnectScreen(), AccountScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Connect',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Account',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
