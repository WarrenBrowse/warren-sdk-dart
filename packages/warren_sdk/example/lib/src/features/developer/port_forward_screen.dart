import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../common/widgets/outcome.dart';
import '../../providers/connection.dart';

/// Exercises inbound NAT-PMP port forwarding over a live proxy session: map a
/// tunnel-side port to a local target and watch the granted external port, which
/// re-maps itself across reconnects. Needs an exit that runs a NAT-PMP gateway.
class PortForwardScreen extends ConsumerStatefulWidget {
  const PortForwardScreen({super.key});

  @override
  ConsumerState<PortForwardScreen> createState() => _PortForwardScreenState();
}

class _PortForwardScreenState extends ConsumerState<PortForwardScreen> {
  final _internal = TextEditingController(text: '8080');
  final _target = TextEditingController(text: '127.0.0.1:8080');
  WarrenForwardedPort? _forward;
  Object? _error;
  bool _busy = false;

  @override
  void dispose() {
    // Tear the mapping down if the screen closes while it is active.
    _forward?.dispose();
    _internal.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _start(WarrenSession session) async {
    final port = int.tryParse(_internal.text.trim());
    if (port == null) {
      setState(() => _error = 'Internal port must be a number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final forward = await session.forwardPort(
        ForwardProtocol.tcp,
        port,
        _target.text.trim(),
      );
      if (mounted) setState(() => _forward = forward);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    await _forward?.dispose();
    if (mounted) setState(() => _forward = null);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(connectionControllerProvider).asData?.value;
    final proxyReady = session?.endpoints != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Port forwarding')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Maps a tunnel-side port at the exit (NAT-PMP) and relays inbound '
            'connections to a local target. The external port re-maps itself '
            'across reconnects. Requires a connected proxy session and an exit '
            'that runs a NAT-PMP gateway.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (!proxyReady)
            const _Hint('Connect in proxy mode first, then come back here.')
          else if (_forward == null)
            _Form(
              internal: _internal,
              target: _target,
              busy: _busy,
              onStart: () => _start(session!),
            )
          else
            _Active(forward: _forward!, onStop: _stop),
          if (_error != null) ...[
            const SizedBox(height: 16),
            OutcomeError(_error!),
          ],
        ],
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.internal,
    required this.target,
    required this.busy,
    required this.onStart,
  });

  final TextEditingController internal;
  final TextEditingController target;
  final bool busy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: internal,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Internal port (at the exit)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: target,
          decoration: const InputDecoration(
            labelText: 'Local target (ip:port)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onStart,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_browser),
          label: const Text('Forward port'),
        ),
      ],
    );
  }
}

class _Active extends StatelessWidget {
  const _Active({required this.forward, required this.onStop});

  final WarrenForwardedPort forward;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Forwarding internal port ${forward.internalPort}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          // The external port can change across reconnects, so observe it live.
          StreamBuilder<int?>(
            stream: forward.externalPorts,
            builder: (context, snap) {
              final ext = snap.data;
              return Row(
                children: [
                  Icon(
                    ext != null ? Icons.public : Icons.hourglass_top,
                    color: ext != null ? Colors.green.shade600 : scheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ext != null
                        ? 'External port: $ext'
                        : 'Awaiting the exit mapping…',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onStop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop forwarding'),
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
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}
