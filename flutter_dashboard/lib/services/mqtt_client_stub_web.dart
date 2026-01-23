import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

BaseMqttClient createMqttClient(String broker, int port) {
  return MqttBrowserClient('ws://$broker:$port/mqtt', '');
}