import 'dart:async';

import 'package:warren_sdk_ffi/warren_sdk_ffi.dart';
import 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart';

import 'ipc/daemon_client.dart';
import 'ipc/messages.dart';
import 'socket_transport.dart';

/// The default production socket the privileged daemon listens on.
const String defaultDaemonSocketPath = '/var/run/warren-vpn.sock';

/// Desktop system-VPN (Mode B) platform implementation.
///
/// Reuses an in-process engine (the [WarrenSdkFfi] control plane) for identity,
/// account and exit discovery and for proxy-mode connections, and adds the
/// privileged TUN datapath by driving the out-of-process `warrend` daemon over
/// its IPC socket. Register it before creating a client so [ConnectMode.systemVpn]
/// is served on desktop:
///
/// ```dart
/// DesktopWarrenSdkPlatform.registerWith();
/// final client = await WarrenClient.create(...); // proxy + system-VPN both work
/// ```
class DesktopWarrenSdkPlatform extends WarrenSdkPlatform {
  /// Creates the platform over an [inner] control-plane implementation and a
  /// [daemonConnector] that opens a fresh [DaemonClient] per system-VPN session.
  /// [connectTimeout] bounds how long a connect waits for the daemon to report
  /// `Connected`. The [inner] and [daemonConnector] seams keep this unit-testable
  /// without the native engine or a real daemon.
  DesktopWarrenSdkPlatform({
    required WarrenSdkPlatform inner,
    required Future<DaemonClient> Function() daemonConnector,
    Duration connectTimeout = const Duration(seconds: 60),
  })  : _inner = inner,
        _daemonConnector = daemonConnector,
        _connectTimeout = connectTimeout;

  final WarrenSdkPlatform _inner;
  final Future<DaemonClient> Function() _daemonConnector;
  final Duration _connectTimeout;

  /// Registers a desktop platform as the active [WarrenSdkPlatform.instance],
  /// wrapping the in-process engine. Idempotent in spirit: call it once at
  /// startup, before `WarrenClient.create`. The daemon at [socketPath] is only
  /// contacted when a system-VPN connection is actually opened.
  ///
  /// [inner] and [daemonConnector] are test seams; production leaves them null.
  static void registerWith({
    String socketPath = defaultDaemonSocketPath,
    Future<DaemonClient> Function()? daemonConnector,
    Duration connectTimeout = const Duration(seconds: 60),
    WarrenSdkPlatform? inner,
  }) {
    final WarrenSdkPlatform base;
    if (inner != null) {
      base = inner;
    } else {
      WarrenSdkFfi.ensureRegistered();
      base = WarrenSdkPlatform.instance;
    }
    WarrenSdkPlatform.instance = DesktopWarrenSdkPlatform(
      inner: base,
      daemonConnector:
          daemonConnector ?? (() => connectDaemonSocket(socketPath)),
      connectTimeout: connectTimeout,
    );
  }

  @override
  Future<String> generateMnemonic() => _inner.generateMnemonic();

  @override
  Future<String> addressFromMnemonic(String mnemonic) =>
      _inner.addressFromMnemonic(mnemonic);

  @override
  Future<String> ss58Encode(String publicKeyHex) =>
      _inner.ss58Encode(publicKeyHex);

  @override
  Future<String> ss58Decode(String address) => _inner.ss58Decode(address);

  @override
  Future<WarrenClientHandle> createClient(WarrenClientConfig config) async {
    final inner = await _inner.createClient(config);
    return DesktopClientHandle(
      inner: inner,
      daemonConnector: _daemonConnector,
      configure: ConfigureRequest(
        mnemonic: config.mnemonic,
        apiBase: config.apiBase.toString(),
        serverPubkeyPin: config.serverPubkeyPin,
        multihopRootPin: config.multihopRootPin,
      ),
      connectTimeout: _connectTimeout,
    );
  }
}

/// A client handle that serves proxy mode in-process and system-VPN mode through
/// the daemon. Control-plane calls forward to the wrapped in-process handle.
class DesktopClientHandle implements WarrenClientHandle {
  /// Wraps an in-process [inner] handle and the daemon seam.
  DesktopClientHandle({
    required WarrenClientHandle inner,
    required Future<DaemonClient> Function() daemonConnector,
    required ConfigureRequest configure,
    Duration connectTimeout = const Duration(seconds: 60),
  })  : _inner = inner,
        _daemonConnector = daemonConnector,
        _configure = configure,
        _connectTimeout = connectTimeout;

  final WarrenClientHandle _inner;
  final Future<DaemonClient> Function() _daemonConnector;

  /// Held only to configure the privileged daemon when a system-VPN session is
  /// opened (the daemon derives and zeroizes the key, and never logs it). It is
  /// released when this handle is disposed.
  final ConfigureRequest _configure;
  final Duration _connectTimeout;

  @override
  String get address => _inner.address;

  @override
  Future<SubscriptionInfo> subscription() => _inner.subscription();

  @override
  Future<void> redeemVoucher(String secret) => _inner.redeemVoucher(secret);

  @override
  Future<TunnelCheck> checkTunnel() => _inner.checkTunnel();

  @override
  Future<List<ExitInfo>> listExits() => _inner.listExits();

  @override
  Future<void> dispose() => _inner.dispose();

  @override
  Future<WarrenSessionHandle> connect(
    ExitInfo exit,
    ConnectMode mode,
    ConnectOptions options,
  ) async {
    if (mode == ConnectMode.proxy) {
      return _inner.connect(exit, mode, options);
    }

    final DaemonClient daemon;
    try {
      daemon = await _daemonConnector();
    } on Object {
      // The daemon is not installed or not running; this is a privilege/setup
      // failure, not a tunnel failure. The cause may carry a local socket path,
      // so it is not echoed into the message.
      throw const WarrenPrivilegeError(
        code: 'privilege/daemon-unreachable',
        message: 'the Warren system-VPN daemon is not reachable; ensure it is '
            'installed and running',
      );
    }

    // Subscribe before sending so a fast Connected (broadcast, no replay) is not
    // missed between the request and the first listen.
    final settled = daemon.states
        .firstWhere((s) => s is Connected || s is ConnectionFailed)
        .timeout(_connectTimeout);
    daemon
      ..configure(_configure)
      ..connect(
        ConnectRequest(
          exitPubkeyHex: exit.id,
          dnsOverTunnel: options.dnsOverTunnel,
        ),
      );

    final ConnectionState state;
    try {
      state = await settled;
    } on WarrenError {
      // A daemon error event arrives as a typed stream error; tear down and
      // surface it unchanged.
      await daemon.close();
      rethrow;
    } on TimeoutException {
      await daemon.close();
      throw const WarrenTunnelError(
        code: 'tunnel/connect-timeout',
        message: 'the system-VPN tunnel did not come up in time',
      );
    }

    if (state is ConnectionFailed) {
      await daemon.close();
      throw WarrenTunnelError(code: state.code, message: state.message);
    }
    return DaemonSessionHandle(daemon);
  }
}

/// A system-VPN session backed by the daemon. It captures all OS traffic through
/// the TUN device, so it exposes no local proxy endpoints.
class DaemonSessionHandle implements WarrenSessionHandle {
  /// Wraps a connected [DaemonClient].
  DaemonSessionHandle(this._daemon);

  final DaemonClient _daemon;

  @override
  ProxyEndpoints? get endpoints => null;

  @override
  Stream<ConnectionState> get states => _daemon.states;

  @override
  Future<void> disconnect() async {
    _daemon.disconnect();
    await _daemon.close();
  }
}
