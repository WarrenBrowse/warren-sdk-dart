import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../common/redact.dart';
import '../../common/widgets/copyable.dart';
import '../../common/widgets/outcome.dart';
import '../../common/widgets/page_body.dart';
import '../../common/widgets/section_card.dart';
import '../../common/widgets/state_chip.dart';
import '../../providers/connection.dart';
import '../../providers/constants.dart';
import '../../providers/exit_selection.dart';

/// The datapath: open a connection to the selected exit in proxy or system-VPN
/// mode, tune `ConnectOptions`, then watch the live state stream and endpoints.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  final _socks5 = TextEditingController(text: '127.0.0.1:0');
  final _http = TextEditingController();

  ConnectMode _mode = ConnectMode.proxy;
  MultihopMode _multihop = MultihopMode.auto;
  bool _dnsOverTunnel = true;

  @override
  void dispose() {
    _socks5.dispose();
    _http.dispose();
    super.dispose();
  }

  Future<void> _connect(ExitInfo exit) async {
    final options = ConnectOptions(
      multihop: _multihop,
      socks5Listen:
          _socks5.text.trim().isEmpty ? '127.0.0.1:0' : _socks5.text.trim(),
      httpListen: _http.text.trim().isEmpty ? null : _http.text.trim(),
      dnsOverTunnel: _dnsOverTunnel,
    );
    await ref
        .read(connectionControllerProvider.notifier)
        .connect(exit: exit, mode: _mode, options: options);
  }

  @override
  Widget build(BuildContext context) {
    final exit = ref.watch(selectedExitProvider);
    final connection = ref.watch(connectionControllerProvider);
    final session = connection.asData?.value;
    final connecting = connection.isLoading;

    return PageBody(
      title: 'Connection',
      subtitle: 'Proxy (in-process) or system-VPN (privileged) datapath.',
      children: [
        _exitCard(exit),
        const SizedBox(height: 16),
        _modeAndOptionsCard(),
        const SizedBox(height: 16),
        _actionsCard(exit, session, connecting, connection),
        const SizedBox(height: 16),
        if (session != null) _liveCard(session),
      ],
    );
  }

  Widget _exitCard(ExitInfo? exit) {
    return SectionCard(
      title: 'Target exit',
      icon: Icons.flag_outlined,
      child: exit == null
          ? const Text('No exit selected. Pick one in the Exits tab.')
          : Text(
              '${exit.city}, ${exit.country}'
              '  ·  id ${redactAddress(exit.id)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
    );
  }

  Widget _modeAndOptionsCard() {
    final proxy = _mode == ConnectMode.proxy;
    return SectionCard(
      title: 'Mode & options',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ConnectMode>(
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
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          if (!proxy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'System-VPN needs the privileged warrend daemon at '
                '${AppEnv.daemonSocket}. Without it, connect raises a '
                'WarrenPrivilegeError.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          Text('Multihop', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<MultihopMode>(
            segments: const [
              ButtonSegment(value: MultihopMode.auto, label: Text('Auto')),
              ButtonSegment(
                value: MultihopMode.singleHop,
                label: Text('Single hop'),
              ),
            ],
            selected: {_multihop},
            onSelectionChanged: (s) => setState(() => _multihop = s.first),
          ),
          const SizedBox(height: 16),
          AnimatedOpacity(
            opacity: proxy ? 1 : 0.4,
            duration: const Duration(milliseconds: 150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _socks5,
                  enabled: proxy,
                  decoration: const InputDecoration(
                    labelText: 'SOCKS5 listen (proxy only)',
                    hintText: '127.0.0.1:0',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _http,
                  enabled: proxy,
                  decoration: const InputDecoration(
                    labelText: 'HTTP CONNECT listen (proxy only, optional)',
                    hintText: '127.0.0.1:0',
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('DNS over tunnel'),
            subtitle: const Text('Resolve at the exit gateway'),
            value: _dnsOverTunnel,
            onChanged: (v) => setState(() => _dnsOverTunnel = v),
          ),
        ],
      ),
    );
  }

  Widget _actionsCard(
    ExitInfo? exit,
    WarrenSession? session,
    bool connecting,
    AsyncValue<WarrenSession?> connection,
  ) {
    final connected = session != null;
    return SectionCard(
      title: 'Control',
      icon: Icons.power_settings_new,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: (exit == null || connecting || connected)
                    ? null
                    : () => _connect(exit),
                icon: connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('Connect'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: connected
                    ? () => ref
                        .read(connectionControllerProvider.notifier)
                        .disconnect()
                    : null,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Disconnect'),
              ),
            ],
          ),
          if (connection case AsyncError(:final error)) ...[
            const SizedBox(height: 14),
            OutcomeError(error),
          ],
        ],
      ),
    );
  }

  Widget _liveCard(WarrenSession session) {
    final stateAsync = ref.watch(connectionStateProvider(session));
    final state = stateAsync.asData?.value;
    final endpoints = session.endpoints;

    return SectionCard(
      title: 'Live session',
      icon: Icons.sensors,
      trailing: ConnectionStateChip(state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StateDetail(state),
          const SizedBox(height: 12),
          if (endpoints != null)
            _Endpoints(endpoints)
          else
            const Text(
              'System-VPN session: no local proxy endpoints. All OS traffic is '
              'captured through the privileged TUN datapath.',
            ),
        ],
      ),
    );
  }
}

class _StateDetail extends StatelessWidget {
  const _StateDetail(this.state);

  final ConnectionState? state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = switch (state) {
      null => 'Waiting for the first state…',
      Connecting() => 'Establishing the tunnel (directory fetch, handshake).',
      Connected(:final sinceUnix) => sinceUnix != null
          ? 'Tunnel up since ${formatUnixSeconds(sinceUnix)}.'
          : 'Tunnel up and carrying traffic.',
      Reconnecting(:final attempt) =>
        'Tunnel dropped; supervisor rebuilding (attempt $attempt).',
      Disconnected() => 'Torn down.',
      ConnectionFailed(:final code, :final message) => '$code: $message',
    };
    return Text(text, style: theme.textTheme.bodyMedium);
  }
}

class _Endpoints extends StatelessWidget {
  const _Endpoints(this.endpoints);

  final ProxyEndpoints endpoints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CopyableValue(label: 'SOCKS5', value: endpoints.socks5),
        if (endpoints.http != null) ...[
          const SizedBox(height: 8),
          CopyableValue(label: 'HTTP CONNECT', value: endpoints.http!),
        ],
      ],
    );
  }
}
