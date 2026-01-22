import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/telemetry.dart';

/// MQTT Service for connecting to the broker and receiving telemetry
class MqttService extends ChangeNotifier {
  MqttServerClient? _client;
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected';

  Telemetry? _latestTelemetry;
  AlertMessage? _latestAlert;
  final List<Telemetry> _telemetryHistory = [];

  // Stream controllers
  final _telemetryController = StreamController<Telemetry>.broadcast();
  final _alertController = StreamController<AlertMessage>.broadcast();

  // Getters
  bool get isConnected => _isConnected;
  String get connectionStatus => _connectionStatus;
  Telemetry? get latestTelemetry => _latestTelemetry;
  AlertMessage? get latestAlert => _latestAlert;
  List<Telemetry> get telemetryHistory => List.unmodifiable(_telemetryHistory);

  Stream<Telemetry> get telemetryStream => _telemetryController.stream;
  Stream<AlertMessage> get alertStream => _alertController.stream;

  /// Connect to MQTT broker
  Future<bool> connect({
    String broker = 'localhost',
    int port = 1883,
  }) async {
    _connectionStatus = 'Connecting...';
    notifyListeners();

    _client = MqttServerClient.withPort(broker, 'flutter_dashboard_${DateTime.now().millisecondsSinceEpoch}', port);
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 30;
    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onSubscribed = _onSubscribed;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_dashboard')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
    } catch (e) {
      debugPrint('MQTT Connection exception: $e');
      _connectionStatus = 'Connection failed: $e';
      _isConnected = false;
      notifyListeners();
      return false;
    }

    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      _subscribeToTopics();
      return true;
    }

    return false;
  }

  void _onConnected() {
    _isConnected = true;
    _connectionStatus = 'Connected';
    debugPrint('MQTT Connected');
    notifyListeners();
  }

  void _onDisconnected() {
    _isConnected = false;
    _connectionStatus = 'Disconnected';
    debugPrint('MQTT Disconnected');
    notifyListeners();
  }

  void _onSubscribed(String topic) {
    debugPrint('Subscribed to: $topic');
  }

  void _subscribeToTopics() {
    // Subscribe to telemetry topic
    _client!.subscribe('mavlink/telemetry', MqttQos.atLeastOnce);

    // Subscribe to alert topic
    _client!.subscribe('mavlink/alert', MqttQos.exactlyOnce);

    // Listen for messages
    _client!.updates!.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      final payload = message.payload as MqttPublishMessage;
      final payloadString = MqttPublishPayload.bytesToStringAsString(
        payload.payload.message,
      );

      try {
        final json = jsonDecode(payloadString) as Map<String, dynamic>;

        if (message.topic == 'mavlink/telemetry') {
          final telemetry = Telemetry.fromJson(json);
          _latestTelemetry = telemetry;

          // Keep last 100 readings for history
          _telemetryHistory.add(telemetry);
          if (_telemetryHistory.length > 100) {
            _telemetryHistory.removeAt(0);
          }

          _telemetryController.add(telemetry);
          notifyListeners();
        } else if (message.topic == 'mavlink/alert') {
          final alert = AlertMessage.fromJson(json);
          _latestAlert = alert;
          _alertController.add(alert);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Error parsing message: $e');
      }
    }
  }

  /// Disconnect from MQTT broker
  void disconnect() {
    _client?.disconnect();
    _isConnected = false;
    _connectionStatus = 'Disconnected';
    notifyListeners();
  }

  /// Clear the latest alert
  void clearAlert() {
    _latestAlert = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _telemetryController.close();
    _alertController.close();
    _client?.disconnect();
    super.dispose();
  }
}
