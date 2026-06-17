import 'dart:io';

/// Returns this host's current public egress IP via `1.1.1.1/cdn-cgi/trace`,
/// addressed by literal IP so it needs no DNS (which a killswitch blocks).
/// Empty string if the lookup fails.
Future<String> egressIp() async {
  final result = await Process.run('curl', [
    '-s',
    '-m',
    '8',
    'https://1.1.1.1/cdn-cgi/trace',
  ]);
  final match = RegExp(r'ip=([0-9a-fA-F:.]+)').firstMatch('${result.stdout}');
  return match?.group(1) ?? '';
}

/// Polls [egressIp] until it returns a non-empty IP or the attempts run out.
/// A freshly established tunnel can drop the first probe while TCP/TLS and PMTU
/// settle, so a single empty result is not yet a datapath failure.
Future<String> egressIpWithRetry({int attempts = 4}) async {
  var egress = '';
  for (var i = 0; i < attempts && egress.isEmpty; i++) {
    egress = await egressIp();
  }
  return egress;
}
