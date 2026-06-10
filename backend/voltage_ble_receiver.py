"""
BLE Voltage Monitor Receiver

Connects to the VOLTAGE-MONITOR BLE device and receives voltage readings.
Can run standalone or as a background service for the Flask backend.
"""

from __future__ import annotations

import asyncio
import csv
import logging
import struct
import threading
from datetime import datetime
from typing import Any

from bleak import BleakClient, BleakScanner

logger = logging.getLogger(__name__)

# BLE Configuration
DEVICE_NAME = "VOLTAGE-MONITOR"
SERVICE_UUID = "12345678-1234-1234-1234-123456789000"
VOLTAGE_CHAR_UUID = "12345678-1234-1234-1234-1234567890ab"

# Logging configuration
LOG_TO_CSV = True
CSV_FILENAME = f"voltage_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"

# Calibration curve used for battery percentage estimation.
# The curve is intentionally non-linear and is interpolated between points.
CALIBRATION_POINTS = [
    (4.20, 100),
    (4.10, 100),
    (4.00, 95),
    (3.90, 90),
    (3.80, 70),
    (3.70, 60),
    (3.60, 50),
    (3.50, 40),
    (3.40, 30),
    (3.30, 20),
    (3.20, 10),
]

# Global CSV writer state
csv_file = None
csv_writer = None

# Latest values exposed to the backend
_state_lock = threading.Lock()
_latest_snapshot = {
    "raw_adc": None,
    "voltage": None,
    "battery_percent": None,
    "last_updated": None,
    "connected": False,
}

_monitor_stop_event = threading.Event()
_monitor_thread: threading.Thread | None = None


def _set_snapshot(**updates: Any) -> None:
    with _state_lock:
        _latest_snapshot.update(updates)


def get_voltage_snapshot() -> dict[str, Any]:
    with _state_lock:
        return dict(_latest_snapshot)


def parse_voltage_data(data: bytes) -> tuple[int | None, float | None]:
    """Parse voltage data packet from BLE.

    Data format:
    - Bytes 0-1: Raw ADC value (uint16, big-endian)
    - Bytes 2-5: Voltage as float (little-endian)
    """
    if len(data) >= 6:
        raw_adc = (data[0] << 8) | data[1]
        voltage = struct.unpack("<f", bytes(data[2:6]))[0]
        return raw_adc, voltage
    return None, None


def voltage_to_battery_percent(voltage: float | None) -> int | None:
    """Convert voltage to a battery percentage using interpolated calibration points."""
    if voltage is None:
        return None

    if voltage >= CALIBRATION_POINTS[0][0]:
        return 100
    if voltage <= CALIBRATION_POINTS[-1][0]:
        return 0 if voltage < CALIBRATION_POINTS[-1][0] else CALIBRATION_POINTS[-1][1]

    for index in range(len(CALIBRATION_POINTS) - 1):
        high_voltage, high_percent = CALIBRATION_POINTS[index]
        low_voltage, low_percent = CALIBRATION_POINTS[index + 1]

        if high_voltage >= voltage >= low_voltage:
            span = high_voltage - low_voltage
            if span <= 0:
                return high_percent
            ratio = (voltage - low_voltage) / span
            interpolated = low_percent + ratio * (high_percent - low_percent)
            return max(0, min(100, int(interpolated + 0.5)))

    return 0


def update_voltage_snapshot(raw_adc: int | None, voltage: float | None, *, connected: bool | None = None) -> None:
    battery_percent = voltage_to_battery_percent(voltage)
    updates: dict[str, Any] = {
        "raw_adc": raw_adc,
        "voltage": voltage,
        "battery_percent": battery_percent,
        "last_updated": datetime.now().isoformat(),
    }
    if connected is not None:
        updates["connected"] = connected
    _set_snapshot(**updates)


def notification_handler(sender, data):
    """Handle incoming BLE notifications."""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
    raw_adc, voltage = parse_voltage_data(data)

    if voltage is not None:
        battery_percent = voltage_to_battery_percent(voltage)
        update_voltage_snapshot(raw_adc, voltage, connected=True)
        logger.info(
            "[%s] ADC: %4d | Voltage: %.2f V | Battery: %s%%",
            timestamp,
            raw_adc if raw_adc is not None else -1,
            voltage,
            battery_percent if battery_percent is not None else "?",
        )

        if LOG_TO_CSV and csv_writer:
            csv_writer.writerow([timestamp, raw_adc, voltage, battery_percent])
            csv_file.flush()
    else:
        logger.warning("[%s] Invalid data received: %s", timestamp, data.hex())


async def scan_for_device():
    """Scan for the voltage monitor device."""
    logger.info("Scanning for '%s'...", DEVICE_NAME)
    try:
        devices = await BleakScanner.discover(timeout=10.0)
    except OSError as exc:
        logger.warning(
            "Bluetooth scan unavailable on this machine: %s", exc
        )
        return None

    for device in devices:
        if device.name == DEVICE_NAME:
            logger.info("Found: %s [%s]", device.name, device.address)
            return device

    return None


async def main(stop_event: threading.Event | None = None):
    global csv_file, csv_writer

    stop_event = stop_event or _monitor_stop_event
    logger.info("%s", "=" * 50)
    logger.info("BLE Voltage Monitor Receiver")
    logger.info("%s", "=" * 50)

    if LOG_TO_CSV:
        csv_file = open(CSV_FILENAME, 'w', newline='', encoding='utf-8')
        csv_writer = csv.writer(csv_file)
        csv_writer.writerow(['Timestamp', 'Raw_ADC', 'Voltage_V', 'Battery_Percent'])
        logger.info("Logging to: %s", CSV_FILENAME)

    try:
        while not stop_event.is_set():
            device = await scan_for_device()

            if device is None:
                _set_snapshot(connected=False)
                logger.warning("Device '%s' not found; retrying soon.", DEVICE_NAME)
                await asyncio.sleep(10.0)
                continue

            try:
                async with BleakClient(device, timeout=30.0) as client:
                    _set_snapshot(connected=True)
                    logger.info("Connected to %s", device.name)
                    logger.info("%s", "-" * 50)

                    try:
                        data = await client.read_gatt_char(VOLTAGE_CHAR_UUID)
                        raw_adc, voltage = parse_voltage_data(data)
                        if voltage is not None:
                            update_voltage_snapshot(raw_adc, voltage, connected=True)
                            logger.info(
                                "Initial reading: ADC=%s, Voltage=%.2f V, Battery=%s%%",
                                raw_adc,
                                voltage,
                                voltage_to_battery_percent(voltage),
                            )
                    except Exception as e:
                        logger.warning("Could not read initial value: %s", e)

                    await client.start_notify(VOLTAGE_CHAR_UUID, notification_handler)
                    logger.info("Receiving voltage data (Press Ctrl+C to stop)...")

                    while client.is_connected and not stop_event.is_set():
                        await asyncio.sleep(1)
            except Exception as e:
                _set_snapshot(connected=False)
                logger.exception("Voltage monitor error: %s", e)

            if not stop_event.is_set():
                await asyncio.sleep(5.0)

    except asyncio.CancelledError:
        raise
    except KeyboardInterrupt:
        logger.info("Stopped by user")
    except Exception as e:
        logger.exception("Voltage monitor fatal error: %s", e)
    finally:
        _set_snapshot(connected=False)
        if csv_file:
            csv_file.close()
            logger.info("Data saved to: %s", CSV_FILENAME)


def _thread_main() -> None:
    asyncio.run(main(_monitor_stop_event))


def start_background_monitor() -> None:
    """Start the voltage monitor in a background thread if it is not already running."""
    global _monitor_thread
    if _monitor_thread is not None and _monitor_thread.is_alive():
        return

    _monitor_stop_event.clear()
    _monitor_thread = threading.Thread(target=_thread_main, daemon=True)
    _monitor_thread.start()


def stop_background_monitor() -> None:
    """Request the background monitor to stop."""
    _monitor_stop_event.set()


if __name__ == "__main__":
    asyncio.run(main())
