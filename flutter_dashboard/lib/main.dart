import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/mqtt_service.dart';
import 'models/telemetry.dart';
import 'widgets/telemetry_card.dart';
import 'widgets/alert_banner.dart';

void main() {
  runApp(const MAVLinkDashboardApp());
}

class MAVLinkDashboardApp extends StatelessWidget {
  const MAVLinkDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MqttService(),
      child: MaterialApp(
        title: 'MAVLink Dashboard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF1A1A2E),
          primaryColor: Colors.blue,
          colorScheme: ColorScheme.dark(
            primary: Colors.blue,
            secondary: Colors.cyan,
            surface: const Color(0xFF16213E),
          ),
        ),
        home: const DashboardScreen(),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _brokerController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '1883');

  @override
  void dispose() {
    _brokerController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MAVLink Telemetry Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF16213E),
        elevation: 0,
        actions: [
          Consumer<MqttService>(
            builder: (context, mqtt, _) => ConnectionStatus(
              isConnected: mqtt.isConnected,
              status: mqtt.connectionStatus,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Consumer<MqttService>(
        builder: (context, mqtt, _) {
          return Column(
            children: [
              // Connection panel
              _buildConnectionPanel(mqtt),

              // Alert banner if present
              if (mqtt.latestAlert != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: AlertBanner(
                    alert: mqtt.latestAlert!,
                    onDismiss: mqtt.clearAlert,
                  ),
                ),

              // Telemetry display
              Expanded(
                child: mqtt.isConnected
                    ? _buildTelemetryDisplay(mqtt)
                    : _buildDisconnectedView(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectionPanel(MqttService mqtt) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF16213E),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _brokerController,
              decoration: const InputDecoration(
                labelText: 'MQTT Broker',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              enabled: !mqtt.isConnected,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              keyboardType: TextInputType.number,
              enabled: !mqtt.isConnected,
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              if (mqtt.isConnected) {
                mqtt.disconnect();
              } else {
                mqtt.connect(
                  broker: _brokerController.text,
                  port: int.tryParse(_portController.text) ?? 1883,
                );
              }
            },
            icon: Icon(mqtt.isConnected ? Icons.link_off : Icons.link),
            label: Text(mqtt.isConnected ? 'Disconnect' : 'Connect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: mqtt.isConnected ? Colors.red : Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryDisplay(MqttService mqtt) {
    final telemetry = mqtt.latestTelemetry;

    if (telemetry == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Waiting for telemetry data...',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Main telemetry cards
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  child: TelemetryCard(
                    title: 'Altitude',
                    value: telemetry.altitude.toStringAsFixed(1),
                    unit: 'm',
                    icon: Icons.height,
                    backgroundColor: Colors.indigo.shade700,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TelemetryCard(
                    title: 'Airspeed',
                    value: telemetry.airspeed.toStringAsFixed(1),
                    unit: 'm/s',
                    icon: Icons.speed,
                    backgroundColor: Colors.teal.shade700,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TelemetryCard(
                    title: 'Battery Voltage',
                    value: telemetry.batteryVoltage.toStringAsFixed(2),
                    unit: 'V',
                    icon: Icons.battery_charging_full,
                    isWarning: telemetry.isBatteryWarning,
                    isCritical: telemetry.isBatteryCritical,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Battery gauge
          Expanded(
            child: BatteryGauge(
              voltage: telemetry.batteryVoltage,
              percentage: telemetry.batteryPercentage,
              isWarning: telemetry.isBatteryWarning,
              isCritical: telemetry.isBatteryCritical,
            ),
          ),
          const SizedBox(height: 16),

          // Timestamp
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.access_time, color: Colors.white54, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Last update: ${_formatTimestamp(telemetry.timestamp)}',
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 80,
            color: Colors.grey.shade700,
          ),
          const SizedBox(height: 24),
          const Text(
            'Not Connected',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter MQTT broker details and click Connect',
            style: TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }
}
