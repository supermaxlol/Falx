#!/usr/bin/env python3
"""
MAVLink Monitor Daemon
A Linux daemon that subscribes to a simulated MAVLink stream (JSON format)
and implements fail-safe checks with MQTT publishing.
"""

import json
import logging
import signal
import sys
import time
import socket
import threading
from datetime import datetime
from typing import Optional
import paho.mqtt.client as mqtt

# Configuration
MAVLINK_HOST = "127.0.0.1"
MAVLINK_PORT = 14550
MQTT_BROKER = "localhost"
MQTT_PORT = 1883
MQTT_TOPIC_TELEMETRY = "mavlink/telemetry"
MQTT_TOPIC_ALERT = "mavlink/alert"
BATTERY_CRITICAL_VOLTAGE = 21.0  # 6S pack critical threshold

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/mavlink_daemon.log', mode='a'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


class MAVLinkDaemon:
    """Daemon for monitoring MAVLink telemetry and publishing to MQTT."""

    def __init__(self):
        self.running = False
        self.mqtt_client: Optional[mqtt.Client] = None
        self.mavlink_socket: Optional[socket.socket] = None
        self.last_telemetry = {
            "altitude": 0.0,
            "airspeed": 0.0,
            "battery_voltage": 0.0,
            "timestamp": None
        }
        self.alert_sent = False

    def setup_mqtt(self) -> bool:
        """Initialize MQTT client connection."""
        try:
            self.mqtt_client = mqtt.Client(client_id="mavlink_daemon", protocol=mqtt.MQTTv311)
            self.mqtt_client.on_connect = self._on_mqtt_connect
            self.mqtt_client.on_disconnect = self._on_mqtt_disconnect
            self.mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            self.mqtt_client.loop_start()
            logger.info(f"MQTT client connected to {MQTT_BROKER}:{MQTT_PORT}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to MQTT broker: {e}")
            return False

    def _on_mqtt_connect(self, client, userdata, flags, rc):
        """MQTT connection callback."""
        if rc == 0:
            logger.info("MQTT connection established")
        else:
            logger.error(f"MQTT connection failed with code: {rc}")

    def _on_mqtt_disconnect(self, client, userdata, rc):
        """MQTT disconnection callback."""
        logger.warning(f"MQTT disconnected with code: {rc}")

    def setup_mavlink_receiver(self) -> bool:
        """Setup UDP socket for receiving MAVLink JSON stream."""
        try:
            self.mavlink_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.mavlink_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.mavlink_socket.bind((MAVLINK_HOST, MAVLINK_PORT))
            self.mavlink_socket.settimeout(5.0)
            logger.info(f"MAVLink receiver listening on {MAVLINK_HOST}:{MAVLINK_PORT}")
            return True
        except Exception as e:
            logger.error(f"Failed to setup MAVLink receiver: {e}")
            return False

    def process_telemetry(self, data: dict):
        """Process incoming telemetry data and check fail-safe conditions."""
        try:
            # Extract telemetry values
            altitude = float(data.get("altitude", 0.0))
            airspeed = float(data.get("airspeed", 0.0))
            battery_voltage = float(data.get("battery_voltage", 0.0))

            self.last_telemetry = {
                "altitude": altitude,
                "airspeed": airspeed,
                "battery_voltage": battery_voltage,
                "timestamp": datetime.utcnow().isoformat()
            }

            # Publish telemetry to MQTT
            self.publish_telemetry()

            # Check fail-safe condition
            self.check_failsafe(battery_voltage)

            logger.debug(f"Telemetry: Alt={altitude}m, Speed={airspeed}m/s, Battery={battery_voltage}V")

        except (KeyError, ValueError) as e:
            logger.error(f"Error processing telemetry: {e}")

    def check_failsafe(self, battery_voltage: float):
        """
        Fail-Safe Check: If battery voltage drops below 21.0V (6S pack),
        log a Critical Alert and publish high-priority message to MQTT.
        """
        if battery_voltage < BATTERY_CRITICAL_VOLTAGE:
            # Log critical alert
            logger.critical(
                f"CRITICAL ALERT: Battery voltage {battery_voltage}V "
                f"below threshold {BATTERY_CRITICAL_VOLTAGE}V!"
            )

            # Publish high-priority alert to MQTT
            alert_message = {
                "type": "CRITICAL_ALERT",
                "priority": "HIGH",
                "message": f"Battery voltage critical: {battery_voltage}V",
                "threshold": BATTERY_CRITICAL_VOLTAGE,
                "current_voltage": battery_voltage,
                "timestamp": datetime.utcnow().isoformat(),
                "action_required": "IMMEDIATE_LANDING_RECOMMENDED"
            }

            if self.mqtt_client and self.mqtt_client.is_connected():
                result = self.mqtt_client.publish(
                    MQTT_TOPIC_ALERT,
                    json.dumps(alert_message),
                    qos=2,  # Exactly once delivery for critical messages
                    retain=True
                )
                if result.rc == mqtt.MQTT_ERR_SUCCESS:
                    logger.info("Critical alert published to MQTT broker")
                else:
                    logger.error(f"Failed to publish alert: {result.rc}")

            self.alert_sent = True
        else:
            # Reset alert flag when voltage recovers
            if self.alert_sent and battery_voltage >= BATTERY_CRITICAL_VOLTAGE + 0.5:
                self.alert_sent = False
                logger.info("Battery voltage recovered above threshold")

    def publish_telemetry(self):
        """Publish current telemetry to MQTT broker."""
        if self.mqtt_client and self.mqtt_client.is_connected():
            message = json.dumps(self.last_telemetry)
            self.mqtt_client.publish(
                MQTT_TOPIC_TELEMETRY,
                message,
                qos=1
            )

    def run(self):
        """Main daemon loop."""
        self.running = True
        logger.info("MAVLink Monitor Daemon starting...")

        if not self.setup_mqtt():
            logger.error("Failed to setup MQTT, exiting")
            return

        if not self.setup_mavlink_receiver():
            logger.error("Failed to setup MAVLink receiver, exiting")
            return

        logger.info("Daemon running, waiting for telemetry data...")

        while self.running:
            try:
                data, addr = self.mavlink_socket.recvfrom(4096)
                telemetry = json.loads(data.decode('utf-8'))
                self.process_telemetry(telemetry)
            except socket.timeout:
                continue
            except json.JSONDecodeError as e:
                logger.error(f"Invalid JSON received: {e}")
            except Exception as e:
                logger.error(f"Error in main loop: {e}")
                time.sleep(1)

        self.shutdown()

    def shutdown(self):
        """Clean shutdown of daemon."""
        logger.info("Shutting down daemon...")
        self.running = False

        if self.mavlink_socket:
            self.mavlink_socket.close()

        if self.mqtt_client:
            self.mqtt_client.loop_stop()
            self.mqtt_client.disconnect()

        logger.info("Daemon shutdown complete")


def signal_handler(signum, frame):
    """Handle termination signals."""
    logger.info(f"Received signal {signum}, initiating shutdown...")
    daemon.running = False


if __name__ == "__main__":
    daemon = MAVLinkDaemon()

    # Setup signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    try:
        daemon.run()
    except Exception as e:
        logger.critical(f"Daemon crashed: {e}")
        sys.exit(1)
