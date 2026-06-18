import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../common/widgets/copyable.dart';
import '../../common/widgets/outcome.dart';
import '../../common/widgets/section_card.dart';
import '../../models/client_config.dart';
import '../../providers/activity_log.dart';
import '../../providers/client_config.dart';

/// Raw editor for the engine `ClientConfig`. Applying it rebuilds the live
/// `WarrenClient`, exercising every `WarrenClient.create` parameter.
class EngineConfigScreen extends ConsumerStatefulWidget {
  const EngineConfigScreen({super.key});

  @override
  ConsumerState<EngineConfigScreen> createState() => _EngineConfigScreenState();
}

class _EngineConfigScreenState extends ConsumerState<EngineConfigScreen> {
  late final ClientConfig _initial = ref.read(clientConfigControllerProvider);
  late final _apiBase =
      TextEditingController(text: _initial.apiBase.toString());
  late final _serverPin = TextEditingController(text: _initial.serverPubkeyPin);
  late final _multihopPin =
      TextEditingController(text: _initial.multihopRootPin ?? '');
  late final _daitaMachine =
      TextEditingController(text: _initial.daitaMachine ?? '');
  late bool _daita = _initial.daita;
  late bool _requestIpv6 = _initial.requestIpv6;

  @override
  void dispose() {
    _apiBase.dispose();
    _serverPin.dispose();
    _multihopPin.dispose();
    _daitaMachine.dispose();
    super.dispose();
  }

  void _apply() {
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
    ref.read(clientConfigControllerProvider.notifier).update(config);
    ref.read(activityLogProvider.notifier).info(
          'client',
          'config applied (daita: $_daita, ipv6: $_requestIpv6)',
        );
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(warrenClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Engine configuration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Live client',
            icon: Icons.bolt_outlined,
            child: switch (client) {
              AsyncData(:final value) => OutcomeSuccess(
                  message: 'Client bound',
                  child: CopyableValue(label: 'address', value: value.address),
                ),
              AsyncLoading() => const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Rebuilding client…'),
                  ],
                ),
              AsyncError(:final error) => OutcomeError(error),
            },
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Configuration',
            icon: Icons.tune,
            description: 'Maps to WarrenClient.create. Apply to rebuild.',
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
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Request IPv6'),
                  value: _requestIpv6,
                  onChanged: (v) => setState(() => _requestIpv6 = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('DAITA'),
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
                    onPressed: _apply,
                    icon: const Icon(Icons.check),
                    label: const Text('Apply'),
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
