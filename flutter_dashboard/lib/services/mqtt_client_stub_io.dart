import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

BaseMqttClient createMqttClient(String broker, int port) {
  return MqttServerClient(broker, '');
}