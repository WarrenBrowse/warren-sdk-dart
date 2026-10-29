@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warren_sdk/warren_sdk.dart';

import 'support/engine.dart';

/// Replays the shared `vectors/device_registry_v1.json` golden vectors through
/// the public Dart surface over the real engine: a loopback server answers
/// the engine with the frozen bodies, and records the requests the engine
/// sends, so the bridge and the Dart mapping are pinned against the same wire
/// every sibling SDK replays. The vectors are never edited to make a test
/// pass.
void main() {
  if (!tryRegisterEngine()) {
    fail(
      'Native engine library not found at ${engineLibraryPath()}. Build it:\n'
      '  (cd native/warren_sdk_frb && cargo build --release)',
    );
  }

  final vectors = jsonDecode(
    File('../../vectors/device_registry_v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  Map<String, dynamic> vector(String name) =>
      vectors[name] as Map<String, dynamic>;
  final thisDeviceId =
      (vectors['device_id'] as Map<String, dynamic>)['b64url'] as String;

  late _Registry registry;
  late WarrenClient client;

  setUp(() async {
    registry = await _Registry.start();
    final stateDir =
        await Directory.systemTemp.createTemp('warren-device-vectors-');
    // The install's kept identity is the vector's device, so the requests
    // the engine signs name it exactly as the vectors do.
    File('${stateDir.path}/device').writeAsStringSync(
      jsonEncode({'device_id': thisDeviceId, 'name': 'calm heron'}),
    );
    client = await WarrenClient.create(
      mnemonic: await WarrenIdentity.generateMnemonic(),
      apiBase: Uri.parse('http://127.0.0.1:${registry.port}'),
      serverPubkeyPin: '00' * 32,
      stateDir: stateDir.path,
      appVersion: '1.1.55',
    );
    addTearDown(() async {
      await client.dispose();
      await registry.close();
      await stateDir.delete(recursive: true);
    });
  });

  String endpointPath(Map<String, dynamic> v) =>
      (v['_endpoint'] as String).split(' ').last;

  test('device_list_response reads whole, asked as this device', () async {
    final v = vector('device_list_response');
    registry.answer(200, v['json']);

    final list = await client.devices.list();

    expect(registry.sent('GET').single.target, endpointPath(v));
    final json = v['json'] as Map<String, dynamic>;
    final views = (json['devices'] as List).cast<Map<String, dynamic>>();
    expect(list.devices, hasLength(views.length));
    for (var i = 0; i < views.length; i++) {
      final device = list.devices[i];
      expect(device.deviceId, views[i]['device_id']);
      expect(device.name, views[i]['name']);
      expect(device.platform.name, views[i]['platform']);
      expect(device.appVersion, views[i]['app_version']);
      expect(device.registeredOn, _day(views[i]['registered_on'] as String));
      expect(device.lastSeenOn, _day(views[i]['last_seen_on'] as String));
      expect(device.isThisDevice, views[i]['this_device']);
    }
    expect(
      list.olderClientSeenOn,
      _day(json['older_client_seen_on'] as String),
    );
  });

  test('device_registration is what the engine registers, as this platform',
      () async {
    final v = vector('device_registration');
    registry.answer(200, vector('device_view')['json']);

    final registration = await registry.registration();

    expect(registration.target, endpointPath(v));
    final body = jsonDecode(registration.body) as Map<String, dynamic>;
    final frozen = v['json'] as Map<String, dynamic>;
    expect(body.keys.toSet(), frozen.keys.toSet());
    expect(body['device_id'], frozen['device_id']);
    expect(body['name'], frozen['name']);
    // This install's own platform and version, never the vector's.
    expect(body['platform'], Platform.operatingSystem);
    expect(body['app_version'], '1.1.55');
  });

  test('device_list_response_without_older_client has no older day', () async {
    registry.answer(
      200,
      vector('device_list_response_without_older_client')['json'],
    );

    final list = await client.devices.list();

    expect(list.olderClientSeenOn, isNull);
    expect(list.thisDevice, isNull);
  });

  test(
      'every platform of the closed set reads under its own name, and an '
      'unknown one as other', () async {
    final view = vector('device_view')['json'] as Map<String, dynamic>;
    final platforms = (vectors['platforms'] as List).cast<String>();
    final unknown = vector('unknown_platform');
    registry.answer(200, {
      'devices': [
        for (final p in [...platforms, unknown['json'] as String])
          {...view, 'platform': p},
      ],
    });

    final list = await client.devices.list();

    expect(
      list.devices.map((d) => d.platform.name),
      [...platforms, unknown['reads_as']],
    );
  });

  test('device_rename is the body and path the engine sends', () async {
    final v = vector('device_rename');
    registry.answer(204, null);

    await client.devices.rename(
      thisDeviceId,
      (v['json'] as Map<String, dynamic>)['name'] as String,
    );

    final request = registry.sent('PATCH').single;
    expect(request.target, endpointPath(v));
    expect(jsonDecode(request.body), v['json']);
  });

  test('a url-alphabet device id is accepted and sent as is', () async {
    final id = (vectors['device_id_url_alphabet']
        as Map<String, dynamic>)['b64url'] as String;
    registry.answer(204, null);

    await client.devices.revoke(id);

    expect(registry.sent('DELETE').single.target, '/v1/devices/$id');
  });

  test('every invalid_device_ids spelling is refused before any request',
      () async {
    for (final entry in (vectors['invalid_device_ids'] as List)
        .cast<Map<String, dynamic>>()) {
      await expectLater(
        client.devices.revoke(entry['b64url'] as String),
        throwsA(isA<WarrenInvalidDeviceIdError>()),
        reason: entry['_why'] as String,
      );
    }
    expect(registry.sent('DELETE'), isEmpty);
  });

  test('refusal_device_revoked reaches Dart as the typed revocation', () async {
    final v = vector('refusal_device_revoked');
    registry.answer(v['_status'] as int, v['json']);

    await expectLater(
      client.devices.revoke(thisDeviceId),
      throwsA(isA<WarrenDeviceRevokedError>()),
    );
  });
}

DateTime _day(String day) {
  final parts = day.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

/// One request the loopback registry received.
class _Request {
  _Request(this.method, this.target, this.body);

  final String method;

  /// The path and query, as the engine sent them.
  final String target;
  final String body;
}

/// A loopback stand-in for the account registry: answers every request with
/// the configured status and JSON body, and records what it was sent.
class _Registry {
  _Registry._(this._server) {
    _server.listen(_serve);
  }

  static Future<_Registry> start() async =>
      _Registry._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final List<_Request> requests = [];

  /// What reached a device route by [method], leaving out the credential
  /// refresh the engine runs in the background from the moment the client
  /// is built.
  List<_Request> sent(String method) => requests
      .where((r) => r.method == method && r.target.startsWith('/v1/devices'))
      .toList();
  int _status = 500;
  Object? _json;

  int get port => _server.port;

  final Completer<_Request> _registered = Completer<_Request>();

  /// The first registration the engine sent.
  Future<_Request> registration() =>
      _registered.future.timeout(const Duration(seconds: 20));

  void answer(int status, Object? json) {
    _status = status;
    _json = json;
  }

  Future<void> _serve(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final recorded = _Request(request.method, request.uri.toString(), body);
    requests.add(recorded);
    if (request.method == 'POST' &&
        recorded.target == '/v1/devices' &&
        !_registered.isCompleted) {
      _registered.complete(recorded);
    }
    request.response.statusCode = _status;
    final json = _json;
    if (json != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(json));
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
