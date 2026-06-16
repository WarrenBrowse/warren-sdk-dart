/// Mobile system-VPN (Mode B) support for the Warren SDK.
///
/// The privileged datapath runs inside the OS network extension (Android
/// `VpnService`, iOS/macOS `NEPacketTunnelProvider`) that embeds the Warren
/// engine; this package drives it over Flutter platform channels. See
/// `MOBILE.md` for the extension's responsibilities.
library;

export 'src/vpn_channel.dart';
