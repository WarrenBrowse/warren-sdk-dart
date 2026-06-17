import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../common/redact.dart';
import '../../common/widgets/outcome.dart';
import '../../common/widgets/page_body.dart';
import '../../common/widgets/section_card.dart';
import '../../providers/exit_selection.dart';

/// Exit discovery: the verified relay list (`exitsProvider`) and a live
/// `ExitQuery` filter feeding `WarrenClient.selectExit`. Tap an exit to pick it
/// for the Connection tab.
class ExitsScreen extends ConsumerStatefulWidget {
  const ExitsScreen({super.key});

  @override
  ConsumerState<ExitsScreen> createState() => _ExitsScreenState();
}

class _ExitsScreenState extends ConsumerState<ExitsScreen> {
  final _country = TextEditingController();
  final _city = TextEditingController();

  @override
  void dispose() {
    _country.dispose();
    _city.dispose();
    super.dispose();
  }

  void _updateQuery() {
    ref.read(exitQueryControllerProvider.notifier).update(
          ExitQuery(
            country: _country.text.trim().isEmpty ? null : _country.text.trim(),
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            requireIpv6: ref.read(exitQueryControllerProvider).requireIpv6,
            requirePortForwarding:
                ref.read(exitQueryControllerProvider).requirePortForwarding,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final exitsAsync = ref.watch(exitsProvider);
    final query = ref.watch(exitQueryControllerProvider);
    final selected = ref.watch(selectedExitProvider);

    final exits = exitsAsync.asData?.value ?? const <ExitInfo>[];
    final queryMatch = WarrenClient.selectExit(exits, query);

    return PageBody(
      title: 'Exits',
      subtitle: 'The verified signed relay list, with a selection filter.',
      children: [
        _filterCard(query, queryMatch),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Available exits',
          icon: Icons.public_outlined,
          trailing: IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(exitsProvider),
            icon: const Icon(Icons.refresh),
          ),
          child: switch (exitsAsync) {
            AsyncData(:final value) => value.isEmpty
                ? const Text('No exits returned.')
                : Column(
                    children: [
                      for (final exit in value)
                        _ExitTile(
                          exit: exit,
                          selected: selected == exit,
                          isQueryMatch: queryMatch == exit,
                          onTap: () => ref
                              .read(selectedExitProvider.notifier)
                              .select(exit),
                        ),
                    ],
                  ),
            AsyncLoading() => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            AsyncError(:final error) => OutcomeError(error),
          },
        ),
      ],
    );
  }

  Widget _filterCard(ExitQuery query, ExitInfo? queryMatch) {
    return SectionCard(
      title: 'Filter (ExitQuery)',
      icon: Icons.filter_alt_outlined,
      description: 'AND semantics. selectExit returns the first match.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _country,
                  decoration: const InputDecoration(
                    labelText: 'Country (ISO)',
                    hintText: 'RO',
                  ),
                  onChanged: (_) => _updateQuery(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _city,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    hintText: 'Bucharest',
                  ),
                  onChanged: (_) => _updateQuery(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Require IPv6'),
            value: query.requireIpv6 ?? false,
            onChanged: (v) => ref
                .read(exitQueryControllerProvider.notifier)
                .update(_withFlags(query, ipv6: v)),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Require port forwarding'),
            value: query.requirePortForwarding ?? false,
            onChanged: (v) => ref
                .read(exitQueryControllerProvider.notifier)
                .update(_withFlags(query, portForward: v)),
          ),
          const SizedBox(height: 8),
          if (queryMatch != null)
            OutcomeSuccess(
              message: 'selectExit → ${queryMatch.city}, ${queryMatch.country}',
            )
          else
            Text(
              'selectExit → no match',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  ExitQuery _withFlags(ExitQuery query, {bool? ipv6, bool? portForward}) {
    return ExitQuery(
      country: query.country,
      city: query.city,
      requireIpv6: ipv6 ?? query.requireIpv6,
      requirePortForwarding: portForward ?? query.requirePortForwarding,
    );
  }
}

class _ExitTile extends StatelessWidget {
  const _ExitTile({
    required this.exit,
    required this.selected,
    required this.isQueryMatch,
    required this.onTap,
  });

  final ExitInfo exit;
  final bool selected;
  final bool isQueryMatch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.check_circle : Icons.public,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Row(
          children: [
            Text('${exit.city}, ${exit.country}'),
            if (isQueryMatch) ...[
              const SizedBox(width: 8),
              _Pill(
                'query match',
                scheme.tertiaryContainer,
                scheme.onTertiaryContainer,
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (exit.supportsIpv6)
                  _Pill(
                    'IPv6',
                    scheme.surfaceContainerHighest,
                    scheme.onSurfaceVariant,
                  ),
                if (exit.supportsPortForwarding)
                  _Pill(
                    'port-fwd',
                    scheme.surfaceContainerHighest,
                    scheme.onSurfaceVariant,
                  ),
                if (exit.load != null)
                  _Pill(
                    'load ${(exit.load! * 100).round()}%',
                    scheme.surfaceContainerHighest,
                    scheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'id ${redactAddress(exit.id)}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.bg, this.fg);
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
    );
  }
}
