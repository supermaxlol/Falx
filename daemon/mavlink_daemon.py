#!/usr/bin/env python3
"""
MAVLink Monitor Daemon with WebSocket support
Receives MAVLink JSON telemetry, publishes to MQTT, and broadcasts over WebSocket.
"""

import json
import logging
import signal
import sys
import time
import socket
import asyncio
import threading
from datetime import datetime
from typing import Optional
import paho.mqtt.client as mqtt
import websockets

# Configuration
MAVLINK_HOST = "127.0.0.1"
MAVLINK_PORT = 14550
MQTT_BROKER = "localhost"
MQTT_PORT = 1883
MQTT_TOPIC_TELEMETRY = "mavlink/telemetry"
MQTT_TOPIC_ALERT = "mavlink/alert"
BATTERY_CRITICAL_VOLTAGE = 21.0  # 6S pack critical threshold
WEBSOCKET_PORT = 8765

# Setup logging
import os
LOG_FILE = os.environ.get('MAVLINK_LOG_FILE', 'mavlink_daemon.log')
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, mode='a'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class MAVLinkDaemon:
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
        self.ws_clients = set()
        self.loop = asyncio.get_event_loop()

    # ---------------- MQTT Setup ----------------
    def setup_mqtt(self) -> bool:
        try:
            self.mqtt_client = mqtt.Client(
                callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                client_id="mavlink_daemon",
                protocol=mqtt.MQTTv311
            )
            self.mqtt_client.on_connect = self._on_mqtt_connect
            self.mqtt_client.on_disconnect = self._on_mqtt_disconnect
            self.mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            self.mqtt_client.loop_start()
            logger.info(f"MQTT client connected to {MQTT_BROKER}:{MQTT_PORT}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to MQTT broker: {e}")
            return False

    def _on_mqtt_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code == 0:
            logger.info("MQTT connection established")
        else:
            logger.error(f"MQTT connection failed with code: {reason_code}")

    def _on_mqtt_disconnect(self, client, userdata, disconnect_flags, reason_code, properties):
        logger.warning(f"MQTT disconnected with code: {reason_code}")

    # ---------------- MAVLink UDP ----------------
    def setup_mavlink_receiver(self) -> bool:
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

    # ---------------- WebSocket ----------------
    async def ws_handler(self, websocket, path):
        self.ws_clients.add(websocket)
        try:
            await websocket.wait_closed()
        finally:
            self.ws_clients.remove(websocket)

    async def broadcast_ws(self, telemetry: dict):
        if self.ws_clients:
            message = json.dumps(telemetry)
            await asyncio.gather(*(client.send(message) for client in self.ws_clients))

    async def websocket_server(self):
        server = await websockets.serve(self.ws_handler, "0.0.0.0", WEBSOCKET_PORT)
        logger.info(f"WebSocket server running on ws://127.0.0.1:{WEBSOCKET_PORT}")
        await server.wait_closed()

    # ---------------- Telemetry ----------------
    def process_telemetry(self, data: dict):
        try:
            altitude = float(data.get("altitude", 0.0))
            airspeed = float(data.get("airspeed", 0.0))
            battery_voltage = float(data.get("battery_voltage", 0.0))

            self.last_telemetry = {
                "altitude": altitude,
                "airspeed": airspeed,
                "battery_voltage": battery_voltage,
                "timestamp": datetime.utcnow().isoformat()
            }

            # MQTT
            self.publish_telemetry()
            # Fail-safe
            self.check_failsafe(battery_voltage)
            # WebSocket
            asyncio.run_coroutine_threadsafe(self.broadcast_ws(self.last_telemetry), self.loop)

        except (KeyError, ValueError) as e:
            logger.error(f"Error processing telemetry: {e}")

    def check_failsafe(self, battery_voltage: float):
        if battery_voltage < BATTERY_CRITICAL_VOLTAGE:
            logger.critical(f"CRITICAL ALERT: Battery voltage {battery_voltage}V below threshold {BATTERY_CRITICAL_VOLTAGE}V!")
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
                self.mqtt_client.publish(MQTT_TOPIC_ALERT, json.dumps(alert_message), qos=2, retain=True)
            self.alert_sent = True
        else:
            if self.alert_sent and battery_voltage >= BATTERY_CRITICAL_VOLTAGE + 0.5:
                self.alert_sent = False
                logger.info("Battery voltage recovered above threshold")

    def publish_telemetry(self):
        if self.mqtt_client and self.mqtt_client.is_connected():
            self.mqtt_client.publish(MQTT_TOPIC_TELEMETRY, json.dumps(self.last_telemetry), qos=1)

    # ---------------- Main Loop ----------------
    def run(self):
        self.running = True
        logger.info("MAVLink Monitor Daemon starting...")

        if not self.setup_mqtt():
            logger.error("Failed to setup MQTT, exiting")
            return
        if not self.setup_mavlink_receiver():
            logger.error("Failed to setup MAVLink receiver, exiting")
            return

        # Start WebSocket server in background thread
        threading.Thread(target=lambda: self.loop.run_until_complete(self.websocket_server()), daemon=True).start()

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

    # ---------------- Shutdown ----------------
    def shutdown(self):
        logger.info("Shutting down daemon...")
        self.running = False
        if self.mavlink_socket:
            self.mavlink_socket.close()
        if self.mqtt_client:
            self.mqtt_client.loop_stop()
            self.mqtt_client.disconnect()
        logger.info("Daemon shutdown complete")

def signal_handler(signum, frame):
    logger.info(f"Received signal {signum}, initiating shutdown...")
    daemon.running = False

if __name__ == "__main__":
    daemon = MAVLinkDaemon()
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    try:
        daemon.run()
    except Exception as e:
        logger.critical(f"Daemon crashed: {e}")
        sys.exit(1)