#!/usr/bin/env python3
"""
MAVLink Stream Simulator
Generates simulated MAVLink telemetry data in JSON format for testing.
"""

import json
import socket
import time
import random
import argparse
import math
from datetime import datetime

# Configuration
TARGET_HOST = "127.0.0.1"
TARGET_PORT = 14550
UPDATE_RATE = 10  # Hz


class MAVLinkSimulator:
    """Simulates MAVLink telemetry stream with configurable scenarios."""

    def __init__(self, host: str = TARGET_HOST, port: int = TARGET_PORT):
        self.host = host
        self.port = port
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        # Initial telemetry values
        self.altitude = 100.0  # meters
        self.airspeed = 15.0   # m/s
        self.battery_voltage = 25.2  # Fully charged 6S (4.2V per cell)

        # Simulation parameters
        self.time_elapsed = 0.0
        self.battery_drain_rate = 0.01  # V per second (adjustable)
        self.simulate_critical = False
        self.critical_triggered = False

    def generate_telemetry(self) -> dict:
        """Generate realistic telemetry data."""
        # Simulate altitude variations (gentle oscillation)
        altitude_variation = math.sin(self.time_elapsed * 0.1) * 5.0
        self.altitude = max(0, 100.0 + altitude_variation + random.uniform(-1, 1))

        # Simulate airspeed variations
        airspeed_variation = math.sin(self.time_elapsed * 0.2) * 2.0
        self.airspeed = max(0, 15.0 + airspeed_variation + random.uniform(-0.5, 0.5))

        # Simulate battery drain
        self.battery_voltage -= self.battery_drain_rate / UPDATE_RATE
        self.battery_voltage = max(18.0, self.battery_voltage)  # Don't go below 18V

        # Add small noise to battery voltage
        voltage_noise = random.uniform(-0.05, 0.05)

        return {
            "altitude": round(self.altitude, 2),
            "airspeed": round(self.airspeed, 2),
            "battery_voltage": round(self.battery_voltage + voltage_noise, 2),
            "timestamp": datetime.utcnow().isoformat(),
            "message_type": "TELEMETRY"
        }

    def send_telemetry(self, telemetry: dict):
        """Send telemetry data via UDP."""
        message = json.dumps(telemetry).encode('utf-8')
        self.socket.sendto(message, (self.host, self.port))

    def run(self, duration: int = None, fast_drain: bool = False):
        """
        Run the simulator.

        Args:
            duration: Run for specified seconds, None for infinite
            fast_drain: If True, drain battery faster to trigger alert
        """
        if fast_drain:
            self.battery_drain_rate = 0.1  # Fast drain for testing
            print("Fast drain mode enabled - battery will deplete quickly")

        print(f"Starting MAVLink Simulator")
        print(f"Target: {self.host}:{self.port}")
        print(f"Update rate: {UPDATE_RATE} Hz")
        print(f"Initial battery: {self.battery_voltage}V")
        print(f"Critical threshold: 21.0V")
        print("-" * 50)

        start_time = time.time()
        interval = 1.0 / UPDATE_RATE

        try:
            while True:
                loop_start = time.time()

                telemetry = self.generate_telemetry()
                self.send_telemetry(telemetry)

                # Log status
                status = "NORMAL"
                if telemetry["battery_voltage"] < 21.0:
                    status = "CRITICAL"
                    if not self.critical_triggered:
                        print(f"\n*** BATTERY CRITICAL - {telemetry['battery_voltage']}V ***\n")
                        self.critical_triggered = True
                elif telemetry["battery_voltage"] < 22.0:
                    status = "WARNING"

                print(
                    f"[{status:8}] Alt: {telemetry['altitude']:6.1f}m | "
                    f"Speed: {telemetry['airspeed']:5.1f}m/s | "
                    f"Battery: {telemetry['battery_voltage']:5.2f}V",
                    end='\r'
                )

                self.time_elapsed += interval

                # Check duration
                if duration and (time.time() - start_time) >= duration:
                    print("\nSimulation duration reached")
                    break

                # Maintain update rate
                elapsed = time.time() - loop_start
                if elapsed < interval:
                    time.sleep(interval - elapsed)

        except KeyboardInterrupt:
            print("\nSimulator stopped by user")
        finally:
            self.socket.close()


def main():
    parser = argparse.ArgumentParser(description="MAVLink Telemetry Simulator")
    parser.add_argument(
        "--host",
        default=TARGET_HOST,
        help=f"Target host (default: {TARGET_HOST})"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=TARGET_PORT,
        help=f"Target port (default: {TARGET_PORT})"
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=None,
        help="Simulation duration in seconds (default: infinite)"
    )
    parser.add_argument(
        "--fast-drain",
        action="store_true",
        help="Enable fast battery drain for testing critical alerts"
    )
    parser.add_argument(
        "--initial-voltage",
        type=float,
        default=25.2,
        help="Initial battery voltage (default: 25.2V)"
    )

    args = parser.parse_args()

    simulator = MAVLinkSimulator(args.host, args.port)
    simulator.battery_voltage = args.initial_voltage
    simulator.run(duration=args.duration, fast_drain=args.fast_drain)


if __name__ == "__main__":
    main()
