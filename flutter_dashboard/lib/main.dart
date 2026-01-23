import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/mqtt_service.dart';
import 'models/telemetry.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MqttService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MAVLink MQTT Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1F3A),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _brokerController = TextEditingController(text: 'localhost');
  final TextEditingController _portController = TextEditingController(text: '9001');
  bool _showSettings = false;

  @override
  void dispose() {
    _brokerController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mqtt = context.watch<MqttService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MAVLink Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showSettings ? Icons.dashboard : Icons.settings),
            onPressed: () => setState(() => _showSettings = !_showSettings),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Status Banner
            _buildConnectionBanner(mqtt),
            const SizedBox(height: 16),

            // Settings Panel
            if (_showSettings) ...[
              _buildSettingsPanel(mqtt),
              const SizedBox(height: 16),
            ],

            // Alert Section
            if (mqtt.latestAlert != null) ...[
              _buildAlertCard(mqtt),
              const SizedBox(height: 16),
            ],

            // Telemetry Grid
            if (mqtt.latestTelemetry != null) _buildTelemetryGrid(mqtt),

            // No Data State
            if (mqtt.isConnected && mqtt.latestTelemetry == null)
              _buildNoDataCard(),

            // Disconnected State
            if (!mqtt.isConnected && !_showSettings)
              _buildDisconnectedState(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBanner(MqttService mqtt) {
    final color = mqtt.isConnected ? Colors.green : Colors.orange;
    final icon = mqtt.isConnected ? Icons.check_circle : Icons.warning_amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mqtt.connectionStatus,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
          if (mqtt.isConnected)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel(MqttService mqtt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connection Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _brokerController,
              decoration: const InputDecoration(
                labelText: 'Broker Address',
                hintText: 'localhost or 192.168.x.x',
                prefixIcon: Icon(Icons.dns),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'WebSocket Port',
                hintText: '9001',
                prefixIcon: Icon(Icons.network_check),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (!mqtt.isConnected) {
                    mqtt.connect(
                      broker: _brokerController.text,
                      websocketPort: int.tryParse(_portController.text) ?? 9001,
                    );
                  } else {
                    mqtt.disconnect();
                  }
                },
                icon: Icon(mqtt.isConnected ? Icons.close : Icons.link),
                label: Text(
                  mqtt.isConnected ? 'Disconnect' : 'Connect',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: mqtt.isConnected ? Colors.red : Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(MqttService mqtt) {
    final alert = mqtt.latestAlert!;
    final color = alert.priority == AlertPriority.critical
        ? Colors.red
        : alert.priority == AlertPriority.high
            ? Colors.orange
            : Colors.yellow;

    return Card(
      color: color.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    alert.message,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: mqtt.clearAlert,
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildAlertDetail('Type', alert.type.name.toUpperCase()),
            _buildAlertDetail('Priority', alert.priority.name.toUpperCase()),
            _buildAlertDetail(
              'Voltage',
              '${alert.currentVoltage.toStringAsFixed(2)}V (Threshold: ${alert.threshold}V)',
            ),
            _buildAlertDetail('Action', alert.actionRequired),
            _buildAlertDetail(
              'Time',
              '${alert.timestamp.hour}:${alert.timestamp.minute.toString().padLeft(2, '0')}:${alert.timestamp.second.toString().padLeft(2, '0')}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70),
          ),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildTelemetryGrid(MqttService mqtt) {
    final telemetry = mqtt.latestTelemetry!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Telemetry Data',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildTelemetryCard(
              'Battery',
              '${telemetry.batteryVoltage.toStringAsFixed(2)} V',
              Icons.battery_charging_full,
              Colors.green,
            ),
            _buildTelemetryCard(
              'Altitude',
              '${telemetry.altitude.toStringAsFixed(1)} m',
              Icons.height,
              Colors.blue,
            ),
            _buildTelemetryCard(
              'Latitude',
              telemetry.latitude.toStringAsFixed(6),
              Icons.location_on,
              Colors.orange,
            ),
            _buildTelemetryCard(
              'Longitude',
              telemetry.longitude.toStringAsFixed(6),
              Icons.location_on,
              Colors.orange,
            ),
            _buildTelemetryCard(
              'Heading',
              '${telemetry.heading.toStringAsFixed(0)}°',
              Icons.navigation,
              Colors.purple,
            ),
            _buildTelemetryCard(
              'Ground Speed',
              '${telemetry.groundspeed.toStringAsFixed(1)} m/s',
              Icons.speed,
              Colors.teal,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildLastUpdateCard(telemetry),
      ],
    );
  }

  Widget _buildTelemetryCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdateCard(Telemetry telemetry) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Last Update',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              '${telemetry.timestamp.hour}:${telemetry.timestamp.minute.toString().padLeft(2, '0')}:${telemetry.timestamp.second.toString().padLeft(2, '0')}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.pending, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              'Waiting for telemetry data...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectedState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              'Not Connected',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap settings to configure connection',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}