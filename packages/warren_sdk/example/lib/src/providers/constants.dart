/// Build-time defaults, overridable with `--dart-define`. These keep the test
/// network ergonomic without baking any secret into the binary.
abstract final class AppEnv {
  /// Default account API base. The Warren test network.
  static const String apiBase = String.fromEnvironment(
    'WARREN_API_BASE',
    defaultValue: 'https://api.warrenbrowse.com',
  );

  /// Default pinned server public key (hex) for the Warren network. This is a
  /// public key, not a secret; it matches the pin the `warren-sdk-rs` live
  /// examples use, so the app works against the test network with just a
  /// mnemonic. Override with `--dart-define=WARREN_SERVER_PIN=...`.
  static const String serverPubkeyPin = String.fromEnvironment(
    'WARREN_SERVER_PIN',
    defaultValue:
        '4c2c9253c426ae4db4cc88703f9ac802a020420c7fea6479c87af530ada72c3e',
  );

  /// Unix socket the dev `warrend` daemon listens on (Mode B, system VPN).
  static const String daemonSocket = String.fromEnvironment(
    'WARREN_DAEMON_SOCKET',
    defaultValue: '/tmp/warren-sdk-daemon.sock',
  );

  /// Secure-store key under which the 12-word mnemonic is persisted.
  static const String mnemonicKey = 'warren_mnemonic';
}
