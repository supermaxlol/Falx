import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'mqtt_client_stub.dart';

class NativeMqttClient implements BaseMqttClient {
  final MqttServerClient _client;
  final _messageController = StreamController<MapEntry<String, String>>.broadcast();

  NativeMqttClient(String broker, int port)
      : _client = MqttServerClient.withPort(broker, 'flutter_dashboard_native', port) {
    _client.logging(on: false);
    _client.keepAlivePeriod = 30;
    _client.onConnected = () => print('Native MQTT connected');
    _client.onDisconnected = () => print('Native MQTT disconnected');
  }

  @override
  Future<void> connect() async {
    await _client.connect();
    _client.updates?.listen((msgs) {
      for (final msg in msgs) {
        final payload = MqttPublishPayload.bytesToStringAsString(
            (msg.payload as MqttPublishMessage).payload.message);
        _messageController.add(MapEntry(msg.topic, payload));
      }
    });
  }

  @override
  bool get isConnected => _client.connectionStatus?.state == MqttConnectionState.connected;

  @override
  void subscribe(String topic) {
    _client.subscribe(topic, MqttQos.atLeastOnce);
  }

  @override
  Stream<MapEntry<String, String>> get messages => _messageController.stream;

  @override
  void disconnect() {
    _client.disconnect();
  }
}

BaseMqttClient createMqttClient(String broker, int port) => NativeMqttClient(broker, port);