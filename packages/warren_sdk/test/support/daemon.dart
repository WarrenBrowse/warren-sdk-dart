import 'dart:async';
import 'dart:io';

/// A privileged `warrend` daemon launched for a rooted live test.
class LaunchedDaemon {
  /// Wraps the running [process] and the [socketPath] it listens on.
  LaunchedDaemon(this.process, this.socketPath);

  /// The `sudo` process wrapping the daemon. The real (root) daemon is its
  /// child; the daemon exits itself when its IPC connection closes.
  final Process process;

  /// The Unix socket the daemon listens on.
  final String socketPath;
}

/// Launches the privileged `warrend` daemon via `sudo -n` on a fresh temp socket
/// and waits until it reports it is listening.
///
/// `sudo -n` requires the dev sudoers drop-in to be installed first
/// (`native/warrend/scripts/dev-sudoers.sh`, test-only). Both daemon streams are
/// drained for its lifetime so a child's inherited output never backs up into a
/// broken pipe. The caller owns teardown: kill [LaunchedDaemon.process] and await
/// its exit code.
Future<LaunchedDaemon> launchRootedDaemon(String daemonBin) async {
  final dir = await Directory.systemTemp.createTemp('warrend_root');
  final socketPath = '${dir.path}/d.sock';
  // Canonical path (no `..`), so it matches the pinned sudoers entry.
  final daemonPath = File(daemonBin).resolveSymbolicLinksSync();
  final process = await Process.start('sudo', ['-n', daemonPath, socketPath]);

  unawaited(process.stdout.drain<void>());
  final listening = Completer<void>();
  process.stderr.transform(const SystemEncoding().decoder).listen((line) {
    if (!listening.isCompleted && line.contains('listening')) {
      listening.complete();
    }
  });
  await listening.future.timeout(const Duration(seconds: 10));
  return LaunchedDaemon(process, socketPath);
}
