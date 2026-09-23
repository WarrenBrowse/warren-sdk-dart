import 'dart:async';
import 'dart:io';

import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';

/// The root-owned copy of the daemon that the dev sudoers rule names
/// (`native/warrend/scripts/dev-sudoers.sh`, test-only).
const String devDaemonCopy = '/usr/local/libexec/warren-sdk-dev/warrend';

/// A privileged `warrend` daemon launched for a rooted live test.
class LaunchedDaemon {
  /// Wraps the running [process] and the [socketPath] it listens on.
  LaunchedDaemon(this.process, this.socketPath);

  /// The process running the daemon: `sudo` wrapping it, or the daemon itself
  /// when the test already runs as root. The daemon exits itself when its IPC
  /// connection closes.
  final Process process;

  /// The Unix socket the daemon listens on.
  final String socketPath;
}

/// Launches the privileged `warrend` daemon on its default socket and waits
/// until it reports it is listening.
///
/// Run as root (the CI network namespace), it starts [daemonBin] directly.
/// Otherwise it goes through `sudo -n`, which the dev sudoers drop-in allows
/// only for [devDaemonCopy] with no argument; that copy must be byte-identical
/// to [daemonBin], or the test would validate an older daemon. Both daemon
/// streams are drained for its lifetime so a child's inherited output never
/// backs up into a broken pipe. The caller owns teardown: kill
/// [LaunchedDaemon.process] and await its exit code.
Future<LaunchedDaemon> launchRootedDaemon(String daemonBin) async {
  final uid = (Process.runSync('id', ['-u']).stdout as String).trim();
  final Process process;
  if (uid == '0') {
    process = await Process.start(daemonBin, const []);
  } else {
    if (!_sameContent(File(devDaemonCopy), File(daemonBin))) {
      throw StateError(
        '$devDaemonCopy is missing or differs from $daemonBin: rerun '
        'native/warrend/scripts/dev-sudoers.sh after building the daemon',
      );
    }
    process = await Process.start('sudo', ['-n', devDaemonCopy]);
  }

  unawaited(process.stdout.drain<void>());
  final listening = Completer<void>();
  process.stderr.transform(const SystemEncoding().decoder).listen((line) {
    if (!listening.isCompleted && line.contains('listening')) {
      listening.complete();
    }
  });
  await listening.future.timeout(const Duration(seconds: 10));
  return LaunchedDaemon(process, defaultDaemonSocketPath);
}

bool _sameContent(File a, File b) {
  if (!a.existsSync() || !b.existsSync()) return false;
  final left = a.readAsBytesSync();
  final right = b.readAsBytesSync();
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
