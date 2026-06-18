import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/client_config.dart';
import 'constants.dart';

part 'client_config.g.dart';

/// Holds the current `ClientConfig`. Defaults to the Warren network (baked
/// pin + API base), so a client builds as soon as a wallet exists; the advanced
/// settings can override the pins, DAITA and IPv6 knobs.
@Riverpod(keepAlive: true)
class ClientConfigController extends _$ClientConfigController {
  @override
  ClientConfig build() => ClientConfig(
        apiBase: Uri.parse(AppEnv.apiBase),
        serverPubkeyPin: AppEnv.serverPubkeyPin,
      );

  void update(ClientConfig config) => state = config;

  void reset() => state = build();
}
