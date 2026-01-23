import 'dart:async';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'mqtt_client_stub.dart';

class WebMqttClient implements BaseMqttClient {
  final MqttBrowserClient _client;
  final _messageController = StreamController<MapEntry<String, String>>.broadcast();

  WebMqttClient(String broker, int port)
      : _client = MqttBrowserClient('ws://$broker:$port', 'flutter_dashboard_web') {
    _client.port = port;
    _client.keepAlivePeriod = 20;
    _client.logging(on: false);
    _client.onDisconnected = () => print('Web MQTT disconnected');
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

BaseMqttClient createMqttClient(String broker, int port) => WebMqttClient(broker, port);