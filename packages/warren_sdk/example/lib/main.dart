import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warren_sdk_desktop/warren_sdk_desktop.dart';
import 'package:warren_sdk_riverpod/warren_sdk_riverpod.dart';

import 'src/app/app.dart';
import 'src/providers/client.dart';
import 'src/providers/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // On desktop, register the Mode B platform so `ConnectMode.systemVpn` is
  // served by the privileged `warrend` daemon. It delegates identity, account,
  // exit discovery and proxy connections to the in-process engine, so proxy
  // mode keeps working even with no daemon running. On mobile and elsewhere the
  // default in-process engine (Mode A) is used.
  if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    DesktopWarrenSdkPlatform.registerWith(socketPath: AppEnv.daemonSocket);
  }

  runApp(
    ProviderScope(
      // Make the package's `warrenClientProvider` build a live client from the
      // app's config + the mnemonic in secure storage. `subscriptionProvider`
      // and `exitsProvider` then resolve with no extra wiring.
      overrides: [warrenClientProvider.overrideWith(createWarrenClient)],
      child: const WarrenExampleApp(),
    ),
  );
}
