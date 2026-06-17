import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/client_config.dart';

part 'client_config.g.dart';

/// Holds the current `ClientConfig`, or null before a client has been
/// configured. Setting it (re)builds `warrenClientProvider` downstream.
@riverpod
class ClientConfigController extends _$ClientConfigController {
  @override
  ClientConfig? build() => null;

  void set(ClientConfig config) => state = config;

  void clear() => state = null;
}
