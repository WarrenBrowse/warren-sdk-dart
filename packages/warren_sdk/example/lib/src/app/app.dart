import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'theme.dart';

/// Root of the example. A single-window Material 3 app that follows the system
/// brightness.
class WarrenExampleApp extends StatelessWidget {
  const WarrenExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warren SDK Example',
      debugShowCheckedModeBanner: false,
      theme: WarrenTheme.light(),
      darkTheme: WarrenTheme.dark(),
      home: const HomeShell(),
    );
  }
}
