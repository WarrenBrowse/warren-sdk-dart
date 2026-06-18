import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../common/redact.dart';
import '../../common/widgets/outcome.dart';
import '../../providers/exit_selection.dart';

/// The exit picker: the verified relay list, searchable and filterable, grouped
/// by country. Choosing one sets it as the connection target and pops back.
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key});

  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  final _search = TextEditingController();
  bool _ipv6 = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ExitInfo> _filter(List<ExitInfo> exits) {
    final q = _search.text.trim().toLowerCase();
    return exits.where((e) {
      if (_ipv6 && !e.supportsIpv6) return false;
      if (q.isEmpty) return true;
      return e.city.toLowerCase().contains(q) ||
          e.country.toLowerCase().contains(q);
    }).toList();
  }

  void _select(ExitInfo exit) {
    ref.read(selectedExitProvider.notifier).select(exit);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final exitsAsync = ref.watch(exitsProvider);
    final selected = ref.watch(selectedExitProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select location'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(exitsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search city or country',
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('IPv6'),
                  selected: _ipv6,
                  onSelected: (v) => setState(() => _ipv6 = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (exitsAsync) {
              AsyncData(:final value) => _ExitList(
                  exits: _filter(value),
                  selected: selected,
                  onSelect: _select,
                ),
              AsyncLoading() =>
                const Center(child: CircularProgressIndicator()),
              AsyncError(:final error) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutcomeError(error),
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _ExitList extends StatelessWidget {
  const _ExitList({
    required this.exits,
    required this.selected,
    required this.onSelect,
  });

  final List<ExitInfo> exits;
  final ExitInfo? selected;
  final ValueChanged<ExitInfo> onSelect;

  @override
  Widget build(BuildContext context) {
    if (exits.isEmpty) {
      return const Center(child: Text('No matching exits.'));
    }
    // Group by country for a country-then-city layout.
    final byCountry = <String, List<ExitInfo>>{};
    for (final e in exits) {
      byCountry.putIfAbsent(e.country, () => []).add(e);
    }
    final countries = byCountry.keys.toList()..sort();

    return ListView.builder(
      itemCount: countries.length,
      itemBuilder: (context, i) {
        final country = countries[i];
        final cities = byCountry[country]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Text(
                    countryFlag(country),
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    country,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            for (final exit in cities)
              _CityTile(
                exit: exit,
                selected: selected == exit,
                onTap: () => onSelect(exit),
              ),
          ],
        );
      },
    );
  }
}

class _CityTile extends StatelessWidget {
  const _CityTile({
    required this.exit,
    required this.selected,
    required this.onTap,
  });

  final ExitInfo exit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(exit.city),
      subtitle: exit.supportsIpv6 ? const _MiniTag('IPv6') : null,
      trailing: selected ? Icon(Icons.check, color: scheme.primary) : null,
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
