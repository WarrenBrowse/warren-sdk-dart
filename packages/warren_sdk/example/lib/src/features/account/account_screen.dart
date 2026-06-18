import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import '../../common/redact.dart';
import '../../common/widgets/copyable.dart';
import '../../common/widgets/outcome.dart';
import '../../common/widgets/section_card.dart';
import '../../providers/activity_log.dart';
import '../../providers/wallet.dart';

/// The account surface: the wallet address, the subscription snapshot
/// (`subscriptionProvider`) and `redeemVoucher`.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _voucher = TextEditingController();
  bool _busy = false;
  String? _redeemOk;
  Object? _redeemError;

  @override
  void dispose() {
    _voucher.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final secret = _voucher.text.trim();
    if (secret.isEmpty) return;
    setState(() {
      _busy = true;
      _redeemOk = null;
      _redeemError = null;
    });
    final log = ref.read(activityLogProvider.notifier);
    try {
      final client = await ref.read(warrenClientProvider.future);
      await client.redeemVoucher(secret);
      log.success('account', 'voucher redeemed');
      ref.invalidate(subscriptionProvider);
      if (mounted) {
        setState(() {
          _redeemOk = 'Voucher redeemed. Subscription refreshed.';
          _voucher.clear();
        });
      }
    } on WarrenError catch (error) {
      log.error('account', error.message, code: error.code);
      if (mounted) setState(() => _redeemError = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(subscriptionProvider);
    final address = ref.watch(walletProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Wallet',
            icon: Icons.fingerprint,
            child: address == null
                ? const Text('No wallet.')
                : CopyableValue(label: 'address', value: address),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Subscription',
            icon: Icons.workspace_premium_outlined,
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(subscriptionProvider),
              icon: const Icon(Icons.refresh),
            ),
            child: switch (subscription) {
              AsyncData(:final value) => _SubscriptionView(value),
              AsyncLoading() => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              AsyncError(:final error) => OutcomeError(error),
            },
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Redeem voucher',
            icon: Icons.redeem_outlined,
            description: 'Credit the account with a voucher secret.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _voucher,
                  decoration:
                      const InputDecoration(labelText: 'Voucher secret'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _redeem,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.card_giftcard),
                    label: const Text('Redeem'),
                  ),
                ),
                if (_redeemOk != null) ...[
                  const SizedBox(height: 14),
                  OutcomeSuccess(message: _redeemOk!),
                ],
                if (_redeemError != null) ...[
                  const SizedBox(height: 14),
                  OutcomeError(_redeemError!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionView extends StatelessWidget {
  const _SubscriptionView(this.info);

  final SubscriptionInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = info.isActive;
    final color = active ? Colors.green.shade600 : theme.colorScheme.error;
    return Row(
      children: [
        Icon(
          active ? Icons.verified_outlined : Icons.cancel_outlined,
          color: color,
          size: 40,
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              active ? 'Active' : 'Inactive',
              style: theme.textTheme.titleLarge?.copyWith(color: color),
            ),
            const SizedBox(height: 2),
            Text(
              'Expires: ${formatUnixSeconds(info.expiresAtUnix)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
