import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk/warren_sdk.dart';

import '../../common/widgets/outcome.dart';
import '../../providers/wallet.dart';

/// First-run wallet setup. The mnemonic is the VPN identity: generate a fresh
/// one or import a recovery phrase. It is written to the secure store and the
/// app moves on; nothing here is kept in memory.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _phrase = TextEditingController();
  bool _importing = false;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      // On success the wallet provider flips and the shell swaps this screen
      // out; no navigation needed here.
    } on WarrenError catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shield_moon_outlined,
                  size: 72,
                  color: scheme.primary,
                ),
                const SizedBox(height: 20),
                Text('Warren VPN', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Your wallet is your VPN identity. Create one to get started, '
                  'it stays in your device keychain.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () =>
                            _run(ref.read(walletProvider.notifier).generate),
                    icon: _busy && !_importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_circle_outline),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Create a new wallet'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!_importing)
                  TextButton(
                    onPressed:
                        _busy ? null : () => setState(() => _importing = true),
                    child: const Text('I have a recovery phrase'),
                  )
                else ...[
                  TextField(
                    controller: _phrase,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Recovery phrase',
                      hintText: '12 words separated by spaces',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () => _run(
                                () => ref
                                    .read(walletProvider.notifier)
                                    .import(_phrase.text),
                              ),
                      child: const Text('Import wallet'),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  OutcomeError(_error!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
