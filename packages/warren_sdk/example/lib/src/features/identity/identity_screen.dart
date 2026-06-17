import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk/warren_sdk.dart';

import '../../common/widgets/copyable.dart';
import '../../common/widgets/outcome.dart';
import '../../common/widgets/page_body.dart';
import '../../common/widgets/section_card.dart';
import '../../providers/activity_log.dart';

/// Stateless identity playground. Each card drives one `WarrenIdentity` helper;
/// none of them need an account or the network, so they work the moment the
/// engine is loaded. Errors surface as the sealed `WarrenIdentityError`.
class IdentityScreen extends StatelessWidget {
  const IdentityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Identity',
      subtitle:
          'Stateless helpers pinned by the shared golden vectors. No account '
          'or network required.',
      children: [
        _OpCard(
          title: 'Generate mnemonic',
          icon: Icons.casino_outlined,
          description:
              'A fresh 12-word BIP39 mnemonic. Secret: store it in the secure '
              'store (Client tab), never in logs.',
          category: 'identity',
          buttonLabel: 'Generate',
          resultLabel: 'mnemonic (secret)',
          run: (ref, _) => WarrenIdentity.generateMnemonic(),
        ),
        _OpCard(
          title: 'Address from mnemonic',
          icon: Icons.alternate_email,
          description: 'Derive the SS58 wb… address bound to a mnemonic.',
          category: 'identity',
          fields: const [(label: 'Mnemonic', hint: '12 words')],
          buttonLabel: 'Derive address',
          resultLabel: 'address',
          run: (ref, values) =>
              WarrenIdentity.addressFromMnemonic(values[0].trim()),
        ),
        _OpCard(
          title: 'SS58 encode',
          icon: Icons.lock_outline,
          description: 'Encode a 32-byte public key (hex) to its wb… address.',
          category: 'identity',
          fields: const [(label: 'Public key (hex)', hint: '64 hex chars')],
          buttonLabel: 'Encode',
          resultLabel: 'address',
          run: (ref, values) => WarrenIdentity.ss58Encode(values[0].trim()),
        ),
        _OpCard(
          title: 'SS58 decode',
          icon: Icons.lock_open_outlined,
          description: 'Decode a wb… address back to its public key hex.',
          category: 'identity',
          fields: const [(label: 'Address', hint: 'wb…')],
          buttonLabel: 'Decode',
          resultLabel: 'public key (hex)',
          run: (ref, values) => WarrenIdentity.ss58Decode(values[0].trim()),
        ),
      ],
    );
  }
}

typedef _OpRun = Future<String> Function(WidgetRef ref, List<String> values);

class _OpCard extends ConsumerStatefulWidget {
  const _OpCard({
    required this.title,
    required this.icon,
    required this.description,
    required this.category,
    required this.buttonLabel,
    required this.resultLabel,
    required this.run,
    this.fields = const [],
  });

  final String title;
  final IconData icon;
  final String description;
  final String category;
  final String buttonLabel;
  final String resultLabel;
  final List<({String label, String hint})> fields;
  final _OpRun run;

  @override
  ConsumerState<_OpCard> createState() => _OpCardState();
}

class _OpCardState extends ConsumerState<_OpCard> {
  late final List<TextEditingController> _controllers = [
    for (var _ in widget.fields) TextEditingController(),
  ];
  bool _busy = false;
  String? _result;
  Object? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    final log = ref.read(activityLogProvider.notifier);
    try {
      final values = [for (final c in _controllers) c.text];
      final result = await widget.run(ref, values);
      log.success(widget.category, '${widget.title}: ok');
      if (mounted) setState(() => _result = result);
    } on WarrenError catch (error) {
      log.error(widget.category, error.message, code: error.code);
      if (mounted) setState(() => _error = error);
    } catch (error) {
      log.error(widget.category, error.toString());
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SectionCard(
        title: widget.title,
        icon: widget.icon,
        description: widget.description,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.fields.length; i++) ...[
              TextField(
                controller: _controllers[i],
                decoration: InputDecoration(
                  labelText: widget.fields[i].label,
                  hintText: widget.fields[i].hint,
                ),
                minLines: 1,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _run,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(widget.buttonLabel),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              OutcomeSuccess(
                message: 'Done',
                child:
                    CopyableValue(label: widget.resultLabel, value: _result!),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              OutcomeError(_error!),
            ],
          ],
        ),
      ),
    );
  }
}
