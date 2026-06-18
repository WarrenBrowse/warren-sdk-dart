/// The Warren VPN client SDK for Flutter.
///
/// A thin, reactive, framework-agnostic surface over the audited Warren Rust
/// engine. Add this single package to embed Warren in any Flutter app, desktop
/// first (Windows, macOS, Linux) and mobile too (Android, iOS).
///
/// Start with `WarrenClient.create`, or use the stateless `WarrenIdentity`
/// helpers. See the package README and `ARCHITECTURE.md` for the design.
///
/// {@macro warren_framework_agnostic}
library;

// The public model, event and error types come from the platform interface and
// are re-exported here so consumers depend on one package.
export 'package:warren_sdk_platform_interface/warren_sdk_platform_interface.dart'
    show
        ConnectMode,
        ConnectOptions,
        ConnectionFailed,
        ConnectionState,
        Connected,
        Connecting,
        Disconnected,
        ExitInfo,
        ExitQuery,
        ProxyEndpoints,
        Reconnecting,
        SubscriptionInfo,
        TunnelCheck,
        WarrenApiError,
        WarrenDiscoveryError,
        WarrenError,
        WarrenIdentityError,
        WarrenPrivilegeError,
        WarrenTunnelError,
        WarrenUnsupportedError;

export 'src/warren_client.dart';
export 'src/warren_identity.dart';
export 'src/warren_session.dart';
