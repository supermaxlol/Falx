import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/telemetry.dart';

/// MQTT Service: Unified, platform-aware (Web + Native)
class MqttService extends ChangeNotifier {
  /// MQTT client (MqttServerClient for native, MqttBrowserClient for web)
  dynamic _client;

  /// Connection state
  bool _isConnected = false;
  bool _isConnecting = false;
  String _connectionStatus = 'Disconnected';

  /// Retry management
  int _retryCount = 0;
  final int _maxRetries = 5;
  final Duration _retryDelay = const Duration(seconds: 3);

  /// Telemetry and alerts
  Telemetry? _latestTelemetry;
  AlertMessage? _latestAlert;
  final List<Telemetry> _telemetryHistory = [];

  /// Stream controllers
  final _telemetryController = StreamController<Telemetry>.broadcast();
  final _alertController = StreamController<AlertMessage>.broadcast();

  /// Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get connectionStatus => _connectionStatus;
  Telemetry? get latestTelemetry => _latestTelemetry;
  AlertMessage? get latestAlert => _latestAlert;
  List<Telemetry> get telemetryHistory => List.unmodifiable(_telemetryHistory);

  Stream<Telemetry> get telemetryStream => _telemetryController.stream;
  Stream<AlertMessage> get alertStream => _alertController.stream;

  /// Connect to MQTT broker
  Future<bool> connect({
    String broker = 'localhost',
    int? port,
    bool useWebSocket = false,
  }) async {
    if (_isConnecting || _isConnected) return false;

    _isConnecting = true;
    _connectionStatus = 'Connecting...';
    notifyListeners();

    port ??= useWebSocket ? 9001 : 1883;

    // Create platform-aware client
    _client = _createClient(broker, port, useWebSocket);

    // Configure client
    _client.logging(on: true);
    _client.keepAlivePeriod = 30;

    _client.onConnected = () {
      debugPrint('[MQTT] _onConnected fired!');
      _onConnected();
    };

    _client.onDisconnected = () {
      debugPrint('[MQTT] _onDisconnected fired!');
      _onDisconnected(broker, port, useWebSocket);
    };

    _client.onSubscribed = _onSubscribed;

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_dashboard_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    // Attempt connection with timeout
    try {
      await _client.connect().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[MQTT] Connection timed out');
          throw TimeoutException('MQTT connection timed out');
        },
      );
      debugPrint('[MQTT] Connection attempt returned: ${_client.connectionStatus?.state}');
    } catch (e) {
      debugPrint('[MQTT] Connection exception: $e');
      _connectionStatus = 'Connection failed';
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();
      _scheduleRetry(broker, port, useWebSocket);
      return false;
    }

    if (_client.connectionStatus?.state == MqttConnectionState.connected) {
      _subscribeToTopics();
      return true;
    } else {
      _connectionStatus = 'Connection failed: ${_client.connectionStatus?.state}';
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();
      _scheduleRetry(broker, port, useWebSocket);
      return false;
    }
  }

  /// Create MQTT client dynamically
  dynamic _createClient(String broker, int port, bool useWebSocket) {
    if (kIsWeb || useWebSocket) {
      final url = 'ws://$broker:$port/mqtt'; // /mqtt path often required
      debugPrint('[MQTT] Creating MqttBrowserClient: $url');
      return MqttBrowserClient(url, '');
    } else {
      debugPrint('[MQTT] Creating MqttServerClient: $broker:$port');
      return MqttServerClient(broker, '');
    }
  }

  /// Retry logic
  void _scheduleRetry(String broker, int port, bool useWebSocket) {
    if (_retryCount >= _maxRetries) {
      debugPrint('[MQTT] Max retries reached');
      _isConnecting = false;
      _connectionStatus = 'Failed after $_maxRetries retries';
      notifyListeners();
      return;
    }

    _retryCount++;
    _isConnecting = false;
    _connectionStatus = 'Retrying connection ($_retryCount/$_maxRetries)...';
    notifyListeners();

    Future.delayed(_retryDelay, () {
      debugPrint('[MQTT] Retrying connection ($_retryCount/$_maxRetries)...');
      connect(broker: broker, port: port, useWebSocket: useWebSocket);
    });
  }

  /// Subscribe to topics
  void _subscribeToTopics() {
    if (_client == null) return;

    try {
      _client.subscribe('mavlink/telemetry', MqttQos.atLeastOnce);
      _client.subscribe('mavlink/alert', MqttQos.exactlyOnce);
      _client.updates?.listen(_onMessage);
      debugPrint('[MQTT] Subscribed to topics');
    } catch (e) {
      debugPrint('[MQTT] Subscription error: $e');
    }
  }

  /// Handle incoming MQTT messages
  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (var message in messages) {
      try {
        final payload = message.payload as MqttPublishMessage;
        final payloadString =
            MqttPublishPayload.bytesToStringAsString(payload.payload.message);

        final jsonData = jsonDecode(payloadString) as Map<String, dynamic>;

        if (message.topic == 'mavlink/telemetry') {
          _handleTelemetry(jsonData);
        } else if (message.topic == 'mavlink/alert') {
          _handleAlert(jsonData);
        }
      } catch (e) {
        debugPrint('[MQTT] Error parsing message: $e');
      }
    }
  }

  void _handleTelemetry(Map<String, dynamic> jsonData) {
    final telemetry = Telemetry.fromJson(jsonData);
    _latestTelemetry = telemetry;

    _telemetryHistory.add(telemetry);
    if (_telemetryHistory.length > 100) _telemetryHistory.removeAt(0);

    _telemetryController.add(telemetry);
    notifyListeners();
  }

  void _handleAlert(Map<String, dynamic> jsonData) {
    final alert = AlertMessage.fromJson(jsonData);
    _latestAlert = alert;
    _alertController.add(alert);
    notifyListeners();
  }

  /// Connection callbacks
  void _onConnected() {
    _isConnected = true;
    _isConnecting = false;
    _connectionStatus = 'Connected';
    _retryCount = 0;
    notifyListeners();
    debugPrint('[MQTT] Connected successfully');
  }

  void _onDisconnected(String broker, int port, bool useWebSocket) {
    _isConnected = false;
    _isConnecting = false;
    _connectionStatus = 'Disconnected';
    notifyListeners();
    debugPrint('[MQTT] Disconnected');

    // Automatically retry
    _scheduleRetry(broker, port, useWebSocket);
  }

  void _onSubscribed(String topic) {
    debugPrint('[MQTT] Subscribed to $topic');
  }

  /// Disconnect
  void disconnect() {
    try {
      _client?.disconnect();
    } catch (e) {
      debugPrint('[MQTT] Disconnect error: $e');
    } finally {
      _isConnected = false;
      _isConnecting = false;
      _connectionStatus = 'Disconnected';
      notifyListeners();
    }
  }

  /// Restart connection
  Future<void> restart({
    String broker = 'localhost',
    int? port,
    bool useWebSocket = false,
  }) async {
    disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    await connect(broker: broker, port: port, useWebSocket: useWebSocket);
  }

  /// Clear latest alert
  void clearAlert() {
    _latestAlert = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _telemetryController.close();
    _alertController.close();
    disconnect();
    super.dispose();
  }
}