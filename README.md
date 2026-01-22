# MAVLink Telemetry Monitor

A complete system for monitoring MAVLink telemetry data with fail-safe alerting and real-time visualization.

## System Components

1. **Python Daemon** - Linux daemon that subscribes to MAVLink JSON streams and publishes to MQTT
2. **MAVLink Simulator** - Generates simulated telemetry data for testing
3. **Flutter Dashboard** - Real-time visualization with warning/critical state indicators

## Architecture

```
┌─────────────────┐     UDP/JSON      ┌─────────────────┐
│   MAVLink       │ ───────────────►  │   Python        │
│   Simulator     │    Port 14550     │   Daemon        │
└─────────────────┘                   └────────┬────────┘
                                               │
                                               │ MQTT
                                               ▼
                                      ┌─────────────────┐
                                      │   Mosquitto     │
                                      │   MQTT Broker   │
                                      └────────┬────────┘
                                               │
                                               │ MQTT
                                               ▼
                                      ┌─────────────────┐
                                      │   Flutter       │
                                      │   Dashboard     │
                                      └─────────────────┘
```

## Prerequisites

- Python 3.8+
- Flutter 3.0+
- Mosquitto MQTT Broker
- Linux/macOS (daemon designed for Linux, works on macOS for testing)

## Environment Setup

### 1. Install Mosquitto MQTT Broker

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install mosquitto mosquitto-clients
sudo systemctl enable mosquitto
sudo systemctl start mosquitto
```

**macOS:**
```bash
brew install mosquitto
brew services start mosquitto
```

**Verify MQTT is running:**
```bash
mosquitto_sub -h localhost -t test &
mosquitto_pub -h localhost -t test -m "hello"
# Should output "hello"
```

### 2. Setup Python Daemon

```bash
cd daemon

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create log file (if running as non-root)
sudo touch /var/log/mavlink_daemon.log
sudo chmod 666 /var/log/mavlink_daemon.log
```

### 3. Setup Flutter Dashboard

```bash
cd flutter_dashboard

# Get dependencies
flutter pub get

# Verify setup
flutter doctor
```

## Running the System

### Step 1: Start the Python Daemon

```bash
cd daemon
source venv/bin/activate
python mavlink_daemon.py
```

The daemon will:
- Listen for MAVLink JSON data on UDP port 14550
- Publish telemetry to MQTT topic `mavlink/telemetry`
- Publish critical alerts to `mavlink/alert` when battery < 21.0V

### Step 2: Start the MAVLink Simulator

In a new terminal:

```bash
cd simulator
python mavlink_simulator.py
```

**Options:**
```bash
# Normal simulation (slow battery drain)
python mavlink_simulator.py

# Fast battery drain to test critical alerts
python mavlink_simulator.py --fast-drain

# Custom initial voltage
python mavlink_simulator.py --initial-voltage 22.0

# Run for specific duration (seconds)
python mavlink_simulator.py --duration 60 --fast-drain
```

### Step 3: Start the Flutter Dashboard

```bash
cd flutter_dashboard
flutter run -d chrome  # For web
# or
flutter run -d macos   # For macOS desktop
# or
flutter run -d linux   # For Linux desktop
```

## Configuration

### Daemon Configuration

Edit `daemon/mavlink_daemon.py`:

```python
MAVLINK_HOST = "127.0.0.1"      # MAVLink receiver address
MAVLINK_PORT = 14550            # MAVLink receiver port
MQTT_BROKER = "localhost"       # MQTT broker address
MQTT_PORT = 1883                # MQTT broker port
BATTERY_CRITICAL_VOLTAGE = 21.0 # Critical threshold for 6S LiPo
```

### MQTT Topics

| Topic | Description | QoS |
|-------|-------------|-----|
| `mavlink/telemetry` | Real-time telemetry data | 1 |
| `mavlink/alert` | Critical battery alerts | 2 |

### Telemetry Message Format

```json
{
  "altitude": 105.23,
  "airspeed": 14.8,
  "battery_voltage": 24.15,
  "timestamp": "2024-01-15T10:30:45.123456"
}
```

### Alert Message Format

```json
{
  "type": "CRITICAL_ALERT",
  "priority": "HIGH",
  "message": "Battery voltage critical: 20.5V",
  "threshold": 21.0,
  "current_voltage": 20.5,
  "timestamp": "2024-01-15T10:30:45.123456",
  "action_required": "IMMEDIATE_LANDING_RECOMMENDED"
}
```

## Running as a Linux Service

### Install the Daemon

```bash
# Copy daemon to /opt
sudo mkdir -p /opt/mavlink-daemon
sudo cp daemon/mavlink_daemon.py /opt/mavlink-daemon/
sudo cp daemon/requirements.txt /opt/mavlink-daemon/

# Install dependencies globally or use venv
sudo pip3 install paho-mqtt

# Install systemd service
sudo cp daemon/mavlink-daemon.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mavlink-daemon
sudo systemctl start mavlink-daemon

# Check status
sudo systemctl status mavlink-daemon
sudo journalctl -u mavlink-daemon -f
```

## Testing

### Verify MQTT Messages

```bash
# Subscribe to telemetry
mosquitto_sub -h localhost -t "mavlink/telemetry" -v

# Subscribe to alerts
mosquitto_sub -h localhost -t "mavlink/alert" -v
```

### Test Critical Alert

```bash
# Start daemon and simulator with fast drain
python mavlink_simulator.py --fast-drain --initial-voltage 22.0
```

Watch for the "CRITICAL ALERT" in daemon logs when voltage drops below 21.0V.

## Flutter Dashboard Features

- **Real-time telemetry display**: Altitude, airspeed, battery voltage
- **Battery gauge**: Visual percentage indicator
- **Warning states**:
  - Normal (green): Battery > 22.0V
  - Warning (orange): Battery 21.0V - 22.0V
  - Critical (red): Battery < 21.0V with pulsing alert
- **Alert banner**: Displays critical alerts with dismiss option
- **Connection status**: Shows MQTT connection state

## Project Structure

```
mavlink-monitor/
├── README.md
├── daemon/
│   ├── mavlink_daemon.py       # Main daemon code
│   ├── mavlink-daemon.service  # Systemd service file
│   └── requirements.txt        # Python dependencies
├── simulator/
│   └── mavlink_simulator.py    # Telemetry simulator
└── flutter_dashboard/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart           # App entry point
        ├── models/
        │   └── telemetry.dart  # Data models
        ├── services/
        │   └── mqtt_service.dart
        └── widgets/
            ├── telemetry_card.dart
            └── alert_banner.dart
```

## Troubleshooting

### MQTT Connection Failed
- Verify Mosquitto is running: `systemctl status mosquitto`
- Check firewall: `sudo ufw allow 1883`

### No Telemetry Data
- Verify simulator is running and targeting correct port
- Check daemon logs: `tail -f /var/log/mavlink_daemon.log`

### Flutter Build Errors
- Run `flutter clean && flutter pub get`
- Ensure Flutter SDK is up to date: `flutter upgrade`

## License

MIT License
