import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import '../models/telemetry.dart';

class MqttService extends ChangeNotifier {
  MqttBrowserClient? _client;
  bool isConnected = false;
  String connectionStatus = 'Disconnected';
  Telemetry? latestTelemetry;
  AlertMessage? latestAlert;
  
  // Connection stats
  int messageCount = 0;
  DateTime? lastMessageTime;
  StreamSubscription? _messageSubscription;

  /// Connect to MQTT broker via WebSocket
  Future<void> connect({
    required String broker,
    required int websocketPort,
    String clientIdentifier = '',
  }) async {
    if (isConnected) {
      print('[MQTT] Already connected, disconnecting first...');
      disconnect();
    }

    final clientId = clientIdentifier.isEmpty 
        ? 'flutter_web_${DateTime.now().millisecondsSinceEpoch}' 
        : clientIdentifier;
    
    try {
      // Create the client with the broker address
      _client = MqttBrowserClient('ws://$broker/mqtt', clientId);
      
      // Set the WebSocket port explicitly
      _client!.port = websocketPort;
      
      // Configure WebSocket protocols
      _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      
      // Logging & keep‑alive
      _client!.logging(on: true);
      _client!.keepAlivePeriod = 30;
      
      // Set connection timeout
      _client!.connectTimeoutPeriod = 10000; // 10 seconds
      
      // Use MQTT 3.1 protocol (compatible with most brokers)
      _client!.setProtocolV31();

      // Connection callbacks
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.onSubscribed = _onSubscribed;
      _client!.onUnsubscribed = _onUnsubscribed;
      _client!.onAutoReconnect = _onAutoReconnect;
      _client!.onAutoReconnected = _onAutoReconnected;

      // Configure connection message
      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce)
          .keepAliveFor(30);
      _client!.connectionMessage = connMessage;

      // Update status
      connectionStatus = 'Connecting to ws://$broker:$websocketPort/mqtt...';
      notifyListeners();
      
      print('[MQTT] Attempting connection to ws://$broker:$websocketPort/mqtt');
      
      // Attempt connection
      await _client!.connect();
      
      if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
        print('[MQTT] Connection successful!');
      } else {
        throw Exception('Connection failed: ${_client!.connectionStatus?.returnCode}');
      }
    } catch (e) {
      connectionStatus = 'Connection failed: ${e.toString().split(':').last.trim()}';
      notifyListeners();
      
      if (_client != null) {
        _client!.disconnect();
        _client = null;
      }
      
      print('[MQTT] Connect error: $e');
      print('[MQTT] Connection status: ${_client?.connectionStatus}');
    }
  }

  void _onConnected() {
    isConnected = true;
    connectionStatus = 'Connected';
    messageCount = 0;
    notifyListeners();
    print('[MQTT] ✅ Connected successfully');
    
    // Subscribe to telemetry topic
    _client!.subscribe('mavlink/telemetry', MqttQos.atMostOnce);
    
    // Subscribe to additional topics if needed
    _client!.subscribe('mavlink/status', MqttQos.atMostOnce);
    _client!.subscribe('mavlink/alerts', MqttQos.atMostOnce);
    
    // Listen for messages
    _messageSubscription?.cancel();
    _messageSubscription = _client!.updates?.listen(_onMessage);
  }

  void _onDisconnected() {
    isConnected = false;
    connectionStatus = 'Disconnected';
    _messageSubscription?.cancel();
    notifyListeners();
    print('[MQTT] ⚠️ Disconnected');
  }

  void _onSubscribed(String topic) {
    print('[MQTT] 📡 Subscribed to $topic');
  }

  void _onUnsubscribed(String? topic) {
    print('[MQTT] 📴 Unsubscribed from $topic');
  }

  void _onAutoReconnect() {
    connectionStatus = 'Reconnecting...';
    notifyListeners();
    print('[MQTT] 🔄 Auto-reconnecting...');
  }

  void _onAutoReconnected() {
    isConnected = true;
    connectionStatus = 'Reconnected';
    notifyListeners();
    print('[MQTT] ✅ Auto-reconnected');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>>? messages) {
    if (messages == null || messages.isEmpty) return;

    final recMess = messages[0].payload as MqttPublishMessage;
    final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    final topic = messages[0].topic;
    
    messageCount++;
    lastMessageTime = DateTime.now();
    
    print('[MQTT] 📨 Received on $topic: $payload');

    try {
      final jsonData = jsonDecode(payload) as Map<String, dynamic>;
      
      // Handle different topics
      if (topic == 'mavlink/telemetry') {
        _handleTelemetry(jsonData);
      } else if (topic == 'mavlink/status') {
        _handleStatus(jsonData);
      } else if (topic == 'mavlink/alerts') {
        _handleAlert(jsonData);
      }
      
      notifyListeners();
    } catch (e) {
      print('[MQTT] ❌ Message parse failed: $e');
      print('[MQTT] Payload was: $payload');
    }
  }

  void _handleTelemetry(Map<String, dynamic> jsonData) {
    try {
      final data = Telemetry.fromJson(jsonData);
      latestTelemetry = data;
      
      // Check for automatic alerts
      _checkAlertConditions(data);
    } catch (e) {
      print('[MQTT] Failed to parse telemetry: $e');
    }
  }

  void _handleStatus(Map<String, dynamic> jsonData) {
    // Handle status messages if needed
    print('[MQTT] Status update: $jsonData');
  }

  void _handleAlert(Map<String, dynamic> jsonData) {
    // Handle alert messages from broker
    print('[MQTT] Alert received: $jsonData');
  }

  void _checkAlertConditions(Telemetry data) {
    // Battery low alert
    if (data.batteryVoltage < 10.5) {
      final priority = data.batteryVoltage < 10.0 
          ? AlertPriority.critical 
          : AlertPriority.high;
      
      latestAlert = AlertMessage(
        message: data.batteryVoltage < 10.0 
            ? 'CRITICAL: Battery critically low!' 
            : 'WARNING: Battery low',
        type: AlertType.warning,
        priority: priority,
        timestamp: DateTime.now(),
        currentVoltage: data.batteryVoltage,
        threshold: 10.5,
        actionRequired: data.batteryVoltage < 10.0 
            ? 'Land immediately!' 
            : 'Return to base soon',
      );
    }
    
    // Altitude alert (example)
    if (data.altitude > 120) {
      latestAlert = AlertMessage(
        message: 'Altitude exceeds regulatory limit',
        type: AlertType.warning,
        priority: AlertPriority.medium,
        timestamp: DateTime.now(),
        currentVoltage: data.batteryVoltage,
        threshold: 120.0,
        actionRequired: 'Descend to safe altitude',
      );
    }
  }

  /// Publish a message to a topic
  void publish(String topic, String message, {MqttQos qos = MqttQos.atLeastOnce}) {
    if (!isConnected || _client == null) {
      print('[MQTT] Cannot publish - not connected');
      return;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _client!.publishMessage(topic, qos, builder.payload!);
      print('[MQTT] 📤 Published to $topic: $message');
    } catch (e) {
      print('[MQTT] ❌ Publish failed: $e');
    }
  }

  /// Subscribe to additional topics
  void subscribeToTopic(String topic, {MqttQos qos = MqttQos.atMostOnce}) {
    if (!isConnected || _client == null) {
      print('[MQTT] Cannot subscribe - not connected');
      return;
    }

    _client!.subscribe(topic, qos);
  }

  /// Unsubscribe from a topic
  void unsubscribeFromTopic(String topic) {
    if (!isConnected || _client == null) {
      print('[MQTT] Cannot unsubscribe - not connected');
      return;
    }

    _client!.unsubscribe(topic);
  }

  void disconnect() {
    try {
      _messageSubscription?.cancel();
      _client?.disconnect();
    } catch (e) {
      print('[MQTT] Error during disconnect: $e');
    } finally {
      _client = null;
      isConnected = false;
      connectionStatus = 'Disconnected';
      messageCount = 0;
      lastMessageTime = null;
      notifyListeners();
      print('[MQTT] 🔌 Disconnected');
    }
  }

  void clearAlert() {
    latestAlert = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}