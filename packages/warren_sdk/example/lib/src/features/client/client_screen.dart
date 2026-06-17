import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../common/widgets/copyable.dart';
import '../../common/widgets/outcome.dart';
import '../../common/widgets/page_body.dart';
import '../../common/widgets/section_card.dart';
import '../../models/client_config.dart';
import '../../providers/activity_log.dart';
import '../../providers/client_config.dart';
import '../../providers/constants.dart';
import '../../providers/secure_store.dart';

/// Manages the mnemonic (in the platform secure store) and the client config,
/// then builds the live `WarrenClient`. Creating the client (re)resolves the
/// package's `warrenClientProvider`, which the Account and Exits tabs consume.
class ClientScreen extends ConsumerStatefulWidget {
  const ClientScreen({super.key});

  @override
  ConsumerState<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends ConsumerState<ClientScreen> {
  final _apiBase = TextEditingController(text: AppEnv.apiBase);
  final _serverPin = TextEditingController(text: AppEnv.serverPubkeyPin);
  final _multihopPin = TextEditingController();
  final _daitaMachine = TextEditingController();
  final _pasteMnemonic = TextEditingController();

  bool _requestIpv6 = true;
  bool _daita = false;

  String? _storedAddress;
  bool _busy = false;

  bool get _desktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  String? get _envMnemonic =>
      _desktop ? Platform.environment['WARREN_MNEMONIC'] : null;

  @override
  void initState() {
    super.initState();
    _refreshStored();
  }

  @override
  void dispose() {
    _apiBase.dispose();
    _serverPin.dispose();
    _multihopPin.dispose();
    _daitaMachine.dispose();
    _pasteMnemonic.dispose();
    super.dispose();
  }

  Future<void> _refreshStored() async {
    final store = ref.read(secureStoreProvider);
    final mnemonic = await store.read(key: AppEnv.mnemonicKey);
    if (!mounted) return;
    if (mnemonic == null || mnemonic.isEmpty) {
      setState(() => _storedAddress = null);
      return;
    }
    try {
      final address = await WarrenIdentity.addressFromMnemonic(mnemonic);
      if (mounted) setState(() => _storedAddress = address);
    } on WarrenError {
      if (mounted) setState(() => _storedAddress = null);
    }
  }

  Future<void> _store(String mnemonic, String source) async {
    if (mnemonic.trim().isEmpty) return;
    setState(() => _busy = true);
    final log = ref.read(activityLogProvider.notifier);
    try {
      await ref
          .read(secureStoreProvider)
          .write(key: AppEnv.mnemonicKey, value: mnemonic.trim());
      log.success('secure-store', 'mnemonic stored ($source)');
      _pasteMnemonic.clear();
      await _refreshStored();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateAndStore() async {
    final mnemonic = await WarrenIdentity.generateMnemonic();
    await _store(mnemonic, 'generated');
  }

  Future<void> _clearStored() async {
    await ref.read(secureStoreProvider).delete(key: AppEnv.mnemonicKey);
    ref
        .read(activityLogProvider.notifier)
        .info('secure-store', 'mnemonic cleared');
    await _refreshStored();
  }

  void _createClient() {
    final config = ClientConfig(
      apiBase: Uri.parse(_apiBase.text.trim()),
      serverPubkeyPin: _serverPin.text.trim(),
      multihopRootPin:
          _multihopPin.text.trim().isEmpty ? null : _multihopPin.text.trim(),
      daita: _daita,
      daitaMachine: _daita && _daitaMachine.text.trim().isNotEmpty
          ? _daitaMachine.text.trim()
          : null,
      requestIpv6: _requestIpv6,
    );
    ref.read(clientConfigControllerProvider.notifier).set(config);
    ref.read(activityLogProvider.notifier).info(
          'client',
          'WarrenClient.create(daita: $_daita, ipv6: $_requestIpv6)',
        );
  }

  void _resetClient() {
    ref.read(clientConfigControllerProvider.notifier).clear();
    ref.invalidate(warrenClientProvider);
    ref.read(activityLogProvider.notifier).info('client', 'client disposed');
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(warrenClientProvider);
    return PageBody(
      title: 'Client',
      subtitle: 'Secure the mnemonic, configure the account, build the client.',
      children: [
        _mnemonicCard(),
        const SizedBox(height: 16),
        _configCard(),
        const SizedBox(height: 16),
        _statusCard(client),
      ],
    );
  }

  Widget _mnemonicCard() {
    final stored = _storedAddress != null;
    return SectionCard(
      title: 'Mnemonic (secure store)',
      icon: Icons.password,
      description:
          'The seed lives only in the platform secure store and is handed once '
          'to the engine, which zeroizes it. The app keeps only the address.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stored)
            OutcomeSuccess(
              message: 'Mnemonic stored',
              child: CopyableValue(
                label: 'derived address',
                value: _storedAddress!,
              ),
            )
          else
            const _InfoBanner('No mnemonic stored yet.'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _generateAndStore,
                icon: const Icon(Icons.casino_outlined, size: 18),
                label: const Text('Generate & store'),
              ),
              if (_envMnemonic != null && _envMnemonic!.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => _store(_envMnemonic!, 'WARREN_MNEMONIC env'),
                  icon: const Icon(Icons.terminal, size: 18),
                  label: const Text('Load from env'),
                ),
              if (stored)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clearStored,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pasteMnemonic,
            decoration: const InputDecoration(
              labelText: 'Paste a 12-word mnemonic',
              hintText: 'word1 word2 …',
            ),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  _busy ? null : () => _store(_pasteMnemonic.text, 'pasted'),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Store pasted'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _configCard() {
    return SectionCard(
      title: 'Client configuration',
      icon: Icons.settings_outlined,
      description: 'Maps directly to WarrenClient.create parameters.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _apiBase,
            decoration: const InputDecoration(labelText: 'API base'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _serverPin,
            decoration: const InputDecoration(
              labelText: 'Server pubkey pin (hex)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _multihopPin,
            decoration: const InputDecoration(
              labelText: 'Multihop root pin (hex, optional)',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Request IPv6'),
            subtitle: const Text('Ask the exit for a dual-stack allocation'),
            value: _requestIpv6,
            onChanged: (v) => setState(() => _requestIpv6 = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('DAITA'),
            subtitle: const Text('Defense against traffic-analysis shaping'),
            value: _daita,
            onChanged: (v) => setState(() => _daita = v),
          ),
          if (_daita) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _daitaMachine,
              decoration: const InputDecoration(
                labelText: 'DAITA machine (optional)',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _storedAddress == null ? null : _createClient,
              icon: const Icon(Icons.bolt),
              label: const Text('Create client'),
            ),
          ),
          if (_storedAddress == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Store a mnemonic first.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusCard(AsyncValue<WarrenClient> client) {
    return SectionCard(
      title: 'Live client',
      icon: Icons.bolt_outlined,
      trailing: client.hasValue
          ? OutlinedButton.icon(
              onPressed: _resetClient,
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: const Text('Dispose'),
            )
          : null,
      child: switch (client) {
        AsyncData(:final value) => OutcomeSuccess(
            message: 'Client bound',
            child: CopyableValue(
              label: 'address',
              value: value.address,
            ),
          ),
        AsyncLoading() => const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Creating client…'),
            ],
          ),
        AsyncError(:final error) => OutcomeError(error),
      },
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text),
    );
  }
}
