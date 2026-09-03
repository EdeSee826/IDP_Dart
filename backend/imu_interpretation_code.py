import asyncio
import json
import math
import os
import sqlite3
import struct
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np

try:
    import torch
    from torch import nn
except ImportError:
    torch = None
    nn = None

try:
    from bleak import BleakClient, BleakScanner
    BLEAK_IMPORT_ERROR = None
except ImportError as exc:
    BleakClient = None
    BleakScanner = None
    BLEAK_IMPORT_ERROR = exc

try:
    import winsound
    WINDOWS_BEEP_AVAILABLE = True
except ImportError:
    WINDOWS_BEEP_AVAILABLE = False


# ============================================================
# PART 2: BLE CONFIGURATION
# ============================================================
SERVICE_UUID = "1841"
DATA_CHAR_UUID = "FFF1"
COMMAND_CHAR_UUID = "FFF2"
BATTERY_CHAR_UUID = "FFF3"

DEVICE_NAMES = ["XIAO_MG24_Sensor_02"]

EXPECTED_HEADER = {
    "XIAO_MG24_Sensor_02": "im02",
}
STATUS_HEADER = {
    "XIAO_MG24_Sensor_02": "st02",
}
NEUTRAL_HEADER = {
    "XIAO_MG24_Sensor_02": "nt02",
}
VALIDATION_HEADER = {
    "XIAO_MG24_Sensor_02": "va02",
}
SAMPLE_SIZE_BYTES = 36
SAMPLES_PER_NOTIFICATION = 5
EXPECTED_NOTIFICATION_BYTES = SAMPLE_SIZE_BYTES * SAMPLES_PER_NOTIFICATION

CMD_WRITE_WITH_RESPONSE = True
COMMAND_GAP_SEC = 0.15
POST_CONNECT_STABILIZE_SEC = 1.0
BLE_CONNECT_RETRIES = 3
BLE_CONNECT_RETRY_DELAY_SEC = 1.5
START_ARM_DELAY_MS = 1200
STOP_GAP_SEC = 0.05
SHUTDOWN_SETTLE_SEC = 3.0

PLACEMENT_VERY_GOOD_DEG = 8.0
PLACEMENT_PASS_DEG = 15.0
PLACEMENT_CLEARLY_WRONG_DEG = 25.0
# The correct marker-down baselines place gravity primarily on accelerometer X
# (approximately -1 g). Keep this configurable for future sensor revisions.
STATIC_MARKER_AXIS_INDEX = int(os.getenv("STATIC_MARKER_AXIS_INDEX", "0"))
STATIC_MARKER_EXPECTED_SIGN = int(os.getenv("STATIC_MARKER_EXPECTED_SIGN", "-1"))
STATIC_MARKER_MIN_G = float(os.getenv("STATIC_MARKER_MIN_G", "0.55"))

# Calibration collection window.
# At the expected 50 Hz rate this provides about 250 static samples,
# which is sufficient for gravity orientation while keeping the wait short.
STATIC_CALIBRATION_WAIT_SEC = 5.0


# ============================================================
# PART 3: REAL-TIME ML CONFIGURATION
# ============================================================
EXPECTED_FREQ = 50
WINDOW_SEC = 1
OVERLAP = 0.75
WINDOW_SIZE = int(EXPECTED_FREQ * WINDOW_SEC)          
STRIDE = int(WINDOW_SIZE * (1 - OVERLAP))             

STABILIZATION_SEC = 3.0
STABILIZATION_SAMPLES = int(EXPECTED_FREQ * STABILIZATION_SEC)

RISKY_ACTIVITIES = {"elbow_flexion", "shoulder_adduction", "shoulder_abduction_adduction"}
RISKY_BEEP_INTERVAL_WINDOWS = 3
RISKY_CONFIRM_WINDOWS = 6
SAFE_RESET_WINDOWS = 2
PREDICTION_RETENTION_DAYS = 7

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RISK_EVENTS_DB_PATH = os.path.join(BASE_DIR, "risky_events.db")
CALIBRATION_BASELINES_PATH = os.path.join(BASE_DIR, "calibration_baselines.json")
TCN_MODEL_PATH = Path(BASE_DIR).parent / "tcn_activity.pt"

DEFAULT_TCN_LABELS = [
    "elbow_flexion",
    "shoulder_abduction_adduction",
    "sitting",
    "standing",
    "walking",
]
RAW_CHANNELS = [
    "mcu1_ax", "mcu1_ay", "mcu1_az", "mcu1_gx", "mcu1_gy", "mcu1_gz",
    "mcu2_ax", "mcu2_ay", "mcu2_az", "mcu2_gx", "mcu2_gy", "mcu2_gz",
]
DERIVED_CHANNELS = [
    "mcu1_acc_mag", "mcu1_gyro_mag", "mcu2_acc_mag", "mcu2_gyro_mag",
    "rel_ax", "rel_ay", "rel_az", "rel_gx", "rel_gy", "rel_gz",
]
TRAINING_CHANNELS = RAW_CHANNELS + DERIVED_CHANNELS

# Battery voltage to percentage estimation for 1-cell Li-ion/LiPo battery.
# The curve is intentionally non-linear and interpolated between points.
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


# ============================================================
# PART 4: GLOBAL STATE VARIABLES
# ============================================================
sample_queues = {name: deque() for name in DEVICE_NAMES}

expected_seq = 0
pair_seq = 0
prev_mcu_diff = None
first_signed_mcu_diff = None
pc_zero = time.perf_counter()

disconnect_event = None
disconnected_devices = set()
intentional_disconnects = set()

neutral_vectors = {name: None for name in DEVICE_NAMES}
validation_results = {name: None for name in DEVICE_NAMES}

battery_state = {
    name: {
        "raw_adc": None,
        "voltage": None,
        "battery_percent": None,
        "last_updated": None,
        "connected": False,
    }
    for name in DEVICE_NAMES
}

paired_sample_buffer = deque(maxlen=WINDOW_SIZE)
new_samples_since_last_prediction = 0
paired_samples_seen = 0
risky_counter = 0
active_risky_class = None
safe_counter = 0
risk_event_latched = False
pending_risky_event_class = None

tcn_model = None
tcn_labels = DEFAULT_TCN_LABELS.copy()
risky_activity_labels = {
    label.strip().lower().replace(" ", "_").replace("-", "_")
    for label in RISKY_ACTIVITIES
}
tcn_input_channels = None
tcn_channel_names = None
tcn_mean = None
tcn_std = None
active_window_size = WINDOW_SIZE
active_stride = STRIDE

timestamp_zero = None

SESSION_ACTIVE = False
LAST_ERROR = None
CALIBRATION_PHASE = "idle"
CALIBRATION_MESSAGE = None
CALIBRATION_DEADLINE = None
CALIBRATION_ENROLL_BASELINE = True
CALIBRATION_ACCOUNT_ID = "default"
CALIBRATION_RETRY_REQUESTED = False
CALIBRATION_BYPASS_REQUESTED = False

main_event_loop = None
data_ready_event = None


# ============================================================
# PART 7: COMPUTER BEEP ALERT
# ============================================================
alert_sound_lock = threading.Lock()


def play_alert_sound():
    if WINDOWS_BEEP_AVAILABLE:
        winsound.Beep(500, 100)
    else:
        print("\a", end="")


def play_alert_sound_async():
    """Play one non-blocking beep and discard overlapping stale beep requests."""
    if not alert_sound_lock.acquire(blocking=False):
        return False

    def _play_and_release():
        try:
            play_alert_sound()
        finally:
            alert_sound_lock.release()

    threading.Thread(target=_play_and_release, daemon=True).start()
    return True




# ============================================================
# PART 7B: BATTERY VOLTAGE DECODING & LOGGING
# ============================================================
def parse_voltage_data(data: bytes):
    """Parse 6-byte battery packet from Arduino FFF3.

    Packet format:
    - Bytes 0-1: raw ADC value, uint16 big-endian
    - Bytes 2-5: battery voltage, float32 little-endian
    """
    if len(data) < 6:
        return None, None

    raw_adc = (data[0] << 8) | data[1]
    voltage = struct.unpack("<f", bytes(data[2:6]))[0]
    return raw_adc, voltage


def voltage_to_battery_percent(voltage):
    """Convert battery voltage to approximate battery percentage."""
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


def update_battery_state(device_name, raw_adc, voltage, *, connected=True):
    battery_percent = voltage_to_battery_percent(voltage)
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    battery_state[device_name].update({
        "raw_adc": raw_adc,
        "voltage": voltage,
        "battery_percent": battery_percent,
        "last_updated": timestamp,
        "connected": connected,
    })

    print(
        f"[BATTERY] {device_name} | ADC: {raw_adc:4d} | "
        f"Voltage: {voltage:.2f} V | Battery: {battery_percent}%"
    )


def battery_notification_handler(device_name):
    def handler(sender, data):
        raw_adc, voltage = parse_voltage_data(data)
        if voltage is None:
            print(f"[BATTERY] Invalid packet from {device_name}: {bytes(data).hex()}")
            return
        update_battery_state(device_name, raw_adc, voltage, connected=True)

    return handler


def get_battery_values_for_csv():
    b1 = battery_state.get(DEVICE_NAMES[0], {})
    b2 = {}
    return b1, b2


def get_battery_snapshot():
    """Return a lightweight snapshot of the current battery state for the Flask API."""
    b1, b2 = get_battery_values_for_csv()

    return {"sensor1": dict(b1)}


def reset_device_connection_state():
    disconnected_devices.clear()
    for name in DEVICE_NAMES:
        battery_state[name]["connected"] = False


def load_account_baseline():
    if not os.path.exists(CALIBRATION_BASELINES_PATH):
        return None
    try:
        with open(CALIBRATION_BASELINES_PATH, "r", encoding="utf-8") as file:
            baselines = json.load(file)
        return baselines.get(CALIBRATION_ACCOUNT_ID)
    except (OSError, ValueError, TypeError):
        return None


def save_account_baseline():
    baselines = {}
    if os.path.exists(CALIBRATION_BASELINES_PATH):
        try:
            with open(CALIBRATION_BASELINES_PATH, "r", encoding="utf-8") as file:
                baselines = json.load(file)
        except (OSError, ValueError, TypeError):
            baselines = {}

    baselines[CALIBRATION_ACCOUNT_ID] = {
        "created_at": datetime.now().isoformat(),
        "static": {
            name: list(neutral_vectors[name])
            for name in DEVICE_NAMES
            if neutral_vectors.get(name) is not None
        },
    }

    with open(CALIBRATION_BASELINES_PATH, "w", encoding="utf-8") as file:
        json.dump(baselines, file, indent=2)


def vector_angle_degrees(vector_a, vector_b):
    magnitude_a = math.sqrt(sum(value * value for value in vector_a))
    magnitude_b = math.sqrt(sum(value * value for value in vector_b))
    if magnitude_a <= 1e-6 or magnitude_b <= 1e-6:
        return 180.0
    cosine = sum(a * b for a, b in zip(vector_a, vector_b)) / (
        magnitude_a * magnitude_b
    )
    return math.degrees(math.acos(max(-1.0, min(1.0, cosine))))


def apply_static_account_baseline():
    baseline = load_account_baseline()
    static_baseline = baseline.get("static", {}) if baseline else {}

    for name in DEVICE_NAMES:
        result = validation_results.get(name)
        initial_vector = static_baseline.get(name)
        if result is None or initial_vector is None:
            continue
        comparison_angle = vector_angle_degrees(
            result["current_vector"], initial_vector
        )
        result["baseline_angle_deg"] = comparison_angle
        result["baseline_passed"] = comparison_angle <= PLACEMENT_PASS_DEG
        result["passed"] = bool(result["marker_down"] and result["baseline_passed"])
        if not result["baseline_passed"]:
            result["interpretation"] = "Current orientation differs from the initial account baseline"


def get_calibration_validation_snapshot():
    """Return overall static orientation result."""
    static_values = [validation_results.get(name) for name in DEVICE_NAMES]

    static_passed = None
    if all(result is not None for result in static_values):
        static_passed = all(bool(result.get("passed")) for result in static_values)

    return {
        "static_passed": static_passed,
        "baseline_available": load_account_baseline() is not None,
    }


def get_runtime_status():
    """Return safe runtime status for the Flask dashboard."""
    connected_devices = [
        {
            "name": name,
            "connected": bool(battery_state.get(name, {}).get("connected", False)),
        }
        for name in DEVICE_NAMES
    ]

    return {
        "streaming_active": bool(SESSION_ACTIVE),
        "stream_running": bool(SESSION_ACTIVE),
        "connected_count": sum(1 for item in connected_devices if item["connected"]),
        "error_message": str(LAST_ERROR) if LAST_ERROR else None,
        "devices": connected_devices,
        "calibration_phase": CALIBRATION_PHASE,
        "calibration_message": CALIBRATION_MESSAGE,
        "calibration_validation": get_calibration_validation_snapshot(),
        "calibration_remaining_seconds": (
            max(0, int(CALIBRATION_DEADLINE - time.monotonic() + 0.999))
            if CALIBRATION_DEADLINE is not None
            else None
        ),
    }


def request_calibration_retry():
    """Acknowledge calibration guidance and allow the sequence to continue."""
    global CALIBRATION_RETRY_REQUESTED
    if CALIBRATION_PHASE not in {
        "ready_to_stand",
        "static_failed",
    }:
        return False
    CALIBRATION_RETRY_REQUESTED = True
    return True


def request_calibration_bypass():
    """Allow an explicit validation-only bypass while calibration is paused."""
    global CALIBRATION_BYPASS_REQUESTED
    if CALIBRATION_PHASE not in {
        "ready_to_stand",
        "static",
        "static_failed",
    }:
        return False
    CALIBRATION_BYPASS_REQUESTED = True
    return True


def complete_calibration_bypass():
    """Move to monitoring after an explicitly requested validation bypass."""
    global CALIBRATION_PHASE, CALIBRATION_MESSAGE, CALIBRATION_DEADLINE
    CALIBRATION_PHASE = "bypassed"
    CALIBRATION_MESSAGE = (
        "Calibration bypassed for validation only. Monitoring results are uncalibrated."
    )
    CALIBRATION_DEADLINE = None
    return True


async def wait_for_calibration_retry():
    """Pause calibration until the patient acknowledges the correction prompt."""
    global CALIBRATION_RETRY_REQUESTED
    CALIBRATION_RETRY_REQUESTED = False
    while (
        SESSION_ACTIVE
        and not CALIBRATION_RETRY_REQUESTED
        and not CALIBRATION_BYPASS_REQUESTED
    ):
        await asyncio.sleep(0.2)
    CALIBRATION_RETRY_REQUESTED = False
    return SESSION_ACTIVE

# ============================================================
# PART 8: CSV LOGGING
# ============================================================
def init_prediction_database():
    conn = sqlite3.connect(RISK_EVENTS_DB_PATH)
    try:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS prediction_readings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id TEXT NOT NULL,
                recorded_at TEXT NOT NULL,
                raw_received_timestamp_ms INTEGER,
                feature_extraction_timestamp_ms INTEGER,
                model_prediction_timestamp_ms INTEGER,
                pair_seq INTEGER,
                predicted_activity TEXT NOT NULL,
                risk_status TEXT NOT NULL,
                alert_triggered INTEGER NOT NULL,
                risky_counter INTEGER NOT NULL,
                sensor1_neutral_ax REAL,
                sensor1_neutral_ay REAL,
                sensor1_neutral_az REAL,
                sensor2_neutral_ax REAL,
                sensor2_neutral_ay REAL,
                sensor2_neutral_az REAL,
                sensor1_battery_v REAL,
                sensor1_battery_percent INTEGER,
                sensor2_battery_v REAL,
                sensor2_battery_percent INTEGER
            )
        """)
        conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_prediction_readings_account_time
            ON prediction_readings (account_id, recorded_at)
        """)
        conn.execute(
            """
            DELETE FROM prediction_readings
            WHERE recorded_at < datetime('now', ?)
            """,
            (f"-{PREDICTION_RETENTION_DAYS} days",),
        )
        conn.commit()
    finally:
        conn.close()


def get_neutral_values_for_storage():
    n1 = neutral_vectors.get(DEVICE_NAMES[0])
    n2 = None
    
    if n1 is None:
        n1 = ("", "", "")
    if n2 is None:
        n2 = ("", "", "")
        
    return n1, n2

def log_prediction(
    raw_received_timestamp,
    feature_extraction_timestamp,
    model_prediction_timestamp,
    pair_seq_value,
    prediction,
    risk_status,
    alert_triggered,
    counter,
):
    n1, n2 = get_neutral_values_for_storage()
    b1, b2 = get_battery_values_for_csv()
    conn = sqlite3.connect(RISK_EVENTS_DB_PATH)
    try:
        conn.execute(
            """
            INSERT INTO prediction_readings (
                account_id, recorded_at, raw_received_timestamp_ms,
                feature_extraction_timestamp_ms, model_prediction_timestamp_ms,
                pair_seq, predicted_activity, risk_status, alert_triggered,
                risky_counter, sensor1_neutral_ax, sensor1_neutral_ay,
                sensor1_neutral_az, sensor2_neutral_ax, sensor2_neutral_ay,
                sensor2_neutral_az, sensor1_battery_v, sensor1_battery_percent,
                sensor2_battery_v, sensor2_battery_percent
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                CALIBRATION_ACCOUNT_ID,
                datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f"),
                raw_received_timestamp,
                feature_extraction_timestamp,
                model_prediction_timestamp,
                pair_seq_value,
                str(prediction),
                risk_status,
                int(bool(alert_triggered)),
                counter,
                None if n1[0] == "" else n1[0],
                None if n1[1] == "" else n1[1],
                None if n1[2] == "" else n1[2],
                None if n2[0] == "" else n2[0],
                None if n2[1] == "" else n2[1],
                None if n2[2] == "" else n2[2],
                b1.get("voltage"),
                b1.get("battery_percent"),
                b2.get("voltage"),
                b2.get("battery_percent"),
            ),
        )
        conn.commit()
    finally:
        conn.close()


def save_risky_event(event_type):
    """Persist one confirmed risky movement for the dashboard and event log."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(RISK_EVENTS_DB_PATH)

    try:
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS risky_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id TEXT NOT NULL DEFAULT 'legacy',
                event_type TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                risk_level TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        columns = {
            row[1]
            for row in cursor.execute("PRAGMA table_info(risky_events)").fetchall()
        }
        if "account_id" not in columns:
            cursor.execute(
                "ALTER TABLE risky_events ADD COLUMN account_id TEXT NOT NULL DEFAULT 'legacy'"
            )
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_risky_events_account_timestamp
            ON risky_events (account_id, timestamp)
        """)
        cursor.execute(
            """
            INSERT INTO risky_events (account_id, event_type, timestamp, risk_level)
            VALUES (?, ?, ?, ?)
            """,
            (CALIBRATION_ACCOUNT_ID, str(event_type), timestamp, "Risky"),
        )
        conn.commit()
        print(f"[EVENT LOG] Saved risky event: {event_type} at {timestamp}")
    finally:
        conn.close()


# ============================================================
# PART 9: BLE CLIENT HELPER FUNCTIONS
# ============================================================
def get_client_map(clients):
    return {name: client for name, client in zip(DEVICE_NAMES, clients)}

def get_connected_client_map(clients):
    return {name: client for name, client in get_client_map(clients).items() if client.is_connected}


def has_characteristic(client, uuid):
    """Return whether a connected BLE client exposes a characteristic UUID."""
    uuid_lower = uuid.lower()
    suffix = f"0000{uuid_lower}-" if len(uuid_lower) == 4 else uuid_lower
    for service in client.services:
        for char in service.characteristics:
            char_uuid = char.uuid.lower()
            if char_uuid == uuid_lower or char_uuid.startswith(suffix):
                return True
    return False

def handle_disconnect(name):
    if name in battery_state:
        battery_state[name]["connected"] = False
    disconnected_devices.add(name)
    reset_stream_state()
    if disconnect_event is not None:
        try: disconnect_event.set()
        except Exception: pass

def reset_stream_state():
    global expected_seq, pair_seq, prev_mcu_diff, first_signed_mcu_diff
    global new_samples_since_last_prediction, paired_samples_seen, risky_counter
    global active_risky_class, safe_counter, risk_event_latched, pending_risky_event_class
    global timestamp_zero

    expected_seq = pair_seq = 0
    prev_mcu_diff = first_signed_mcu_diff = None
    new_samples_since_last_prediction = paired_samples_seen = risky_counter = 0
    active_risky_class = None
    safe_counter = 0
    risk_event_latched = False
    pending_risky_event_class = None
    timestamp_zero = None

    paired_sample_buffer.clear()
    for q in sample_queues.values(): q.clear()


# ============================================================
# PART 10 & 11: DECODING & SPECIAL PACKETS
# ============================================================
def decode_one_sample(sample_bytes):
    if len(sample_bytes) != SAMPLE_SIZE_BYTES: return None
    header = sample_bytes[0:4].decode(errors="ignore")
    mcu_time = struct.unpack("<f", sample_bytes[4:8])[0]
    global_seq = struct.unpack("<I", sample_bytes[8:12])[0]
    imu = struct.unpack("<6f", sample_bytes[12:36])
    pc_time = (time.perf_counter() - pc_zero) * 1000.0
    return {"header": header, "mcu_time": mcu_time, "global_seq": global_seq, "pc_time": pc_time, "imu": imu}

def handle_special_packet(device_name, decoded):
    header, imu = decoded["header"], decoded["imu"]
    if header == STATUS_HEADER[device_name]:
        return True
    if header == NEUTRAL_HEADER[device_name]:
        neutral_vectors[device_name] = (imu[0], imu[1], imu[2])
        return True
    if header == VALIDATION_HEADER[device_name]:
        current_vector = (imu[0], imu[1], imu[2])
        angle_deg = imu[3]  # Transmitter places validation angle in gyro[0].
        marker_down = is_marker_pointing_down(current_vector)
        angle_passed = angle_deg <= PLACEMENT_PASS_DEG
        validation_results[device_name] = {
            "current_vector": current_vector,
            "angle_deg": angle_deg,
            "angle_passed": angle_passed,
            "marker_down": marker_down,
            "passed": angle_passed and marker_down,
            "interpretation": interpret_placement_angle(angle_deg, marker_down),
        }
        return True
    return False


# ============================================================
# PART 12: STATIC BASELINE ENROLMENT & PLACEMENT VALIDATION
# ============================================================
def is_marker_pointing_down(vector):
    """Best-effort gravity check for marker-down orientation."""
    if vector is None or len(vector) <= STATIC_MARKER_AXIS_INDEX:
        return False
    axis_value = vector[STATIC_MARKER_AXIS_INDEX]
    return axis_value * STATIC_MARKER_EXPECTED_SIGN >= STATIC_MARKER_MIN_G


def interpret_placement_angle(angle_deg, marker_down=True):
    if not marker_down:
        return "Marker is not pointing down toward the earth"
    if angle_deg <= PLACEMENT_VERY_GOOD_DEG:
        return "Very good placement"
    if angle_deg <= PLACEMENT_PASS_DEG:
        return "Acceptable, but slightly different"
    if angle_deg <= PLACEMENT_CLEARLY_WRONG_DEG:
        return "Likely wrong placement/orientation"
    return "Clearly wrong placement"


def print_validation_summary():
    print("\n========== PLACEMENT VALIDATION RESULT ==========")
    for name, label in [(DEVICE_NAMES[0], "Wearable sensor")]:
        result = validation_results.get(name)
        if result is None:
            print(f"{label}: No validation result received.")
        else:
            status = "PASS" if result["passed"] else "FAIL"
            print(
                f"{label}: {status} | angle error = {result['angle_deg']:.2f}° | "
                f"{result['interpretation']}"
            )

    passed = all(
        validation_results.get(name) is not None
        and bool(validation_results[name].get("passed"))
        for name in DEVICE_NAMES
    )
    print(
        "Feedback: Sensor placement pass -> Proceed to real-time prediction.\n"
        if passed
        else "Feedback: Sensor placement fail -> Re-adjust the sensor and repeat neutral pose.\n"
    )
    return passed


async def enrol_static_neutral_baseline(client_map):
    print("\n========== STATIC BASELINE ENROLMENT ==========")
    print("Stand still in the correct neutral pose. The measured vector will be SAVED into each MCU EEPROM.")
    await send_to_all(client_map, b"ENROLL_NEUTRAL")
    await asyncio.sleep(STATIC_CALIBRATION_WAIT_SEC)
    await ensure_clients_connected(client_map, stage="static baseline enrolment")
    await send_to_all(client_map, b"GET_NEUTRAL")
    await asyncio.sleep(1.0)
    print("Static baseline enrolment completed.\n")


async def validate_static_neutral_placement(client_map):
    print("\n========== STATIC PLACEMENT VALIDATION ==========")
    print("Stand still in the same neutral pose. This check will NOT overwrite EEPROM baseline.")

    for name in DEVICE_NAMES:
        validation_results[name] = None

    await send_to_all(client_map, b"CHECK_NEUTRAL")
    await asyncio.sleep(STATIC_CALIBRATION_WAIT_SEC)
    await ensure_clients_connected(client_map, stage="static placement validation")
    return print_validation_summary()


async def automatic_calibration_sequence(client_map):
    """Automatically request static calibration with short user notifications.

    Sequence:
    - Notify user to stand still for ~5s, send ENROLL_NEUTRAL, wait, then GET_NEUTRAL
    """
    global CALIBRATION_PHASE, CALIBRATION_MESSAGE, CALIBRATION_DEADLINE
    global CALIBRATION_BYPASS_REQUESTED

    CALIBRATION_BYPASS_REQUESTED = False

    await ensure_clients_connected(client_map, stage="automatic calibration")

    CALIBRATION_PHASE = "ready_to_stand"
    CALIBRATION_MESSAGE = (
        "The wearable sensor is connected. Stand comfortably with your PICC arm "
        "relaxed beside your body, then tap I understand to begin calibration."
    )
    CALIBRATION_DEADLINE = None
    if not await wait_for_calibration_retry():
        return False
    if CALIBRATION_BYPASS_REQUESTED:
        return complete_calibration_bypass()
    await ensure_clients_connected(client_map, stage="calibration preparation")

    # Clear previous results
    for name in DEVICE_NAMES:
        neutral_vectors[name] = None
        validation_results[name] = None

    if CALIBRATION_ENROLL_BASELINE:
        CALIBRATION_PHASE = "static"
        CALIBRATION_MESSAGE = "Stand still in a neutral arm position while the first baseline is saved."
        CALIBRATION_DEADLINE = time.monotonic() + STATIC_CALIBRATION_WAIT_SEC
        try:
            await send_to_all(client_map, b"ENROLL_NEUTRAL")
        except Exception:
            pass
        await asyncio.sleep(STATIC_CALIBRATION_WAIT_SEC)
        try:
            await send_to_all(client_map, b"GET_NEUTRAL")
        except Exception:
            pass
        await asyncio.sleep(1.0)
        save_account_baseline()
    else:
        while SESSION_ACTIVE:
            for name in DEVICE_NAMES:
                validation_results[name] = None
            CALIBRATION_PHASE = "static"
            CALIBRATION_MESSAGE = "Stand still while the app checks the saved neutral orientation."
            CALIBRATION_DEADLINE = time.monotonic() + STATIC_CALIBRATION_WAIT_SEC
            try:
                await send_to_all(client_map, b"CHECK_NEUTRAL")
            except Exception:
                pass
            await asyncio.sleep(STATIC_CALIBRATION_WAIT_SEC)
            await ensure_clients_connected(client_map, stage="automatic static validation")
            apply_static_account_baseline()
            static_result = get_calibration_validation_snapshot().get("static_passed")
            if static_result is True:
                break

            CALIBRATION_PHASE = "static_failed"
            CALIBRATION_MESSAGE = (
                "Static calibration differs from your initial baseline. Check that the sensor marker points down toward the earth."
            )
            CALIBRATION_DEADLINE = None
            if not await wait_for_calibration_retry():
                return False
            if CALIBRATION_BYPASS_REQUESTED:
                return complete_calibration_bypass()

    if not SESSION_ACTIVE:
        return False

    CALIBRATION_PHASE = "complete"
    CALIBRATION_MESSAGE = "Calibration complete. Monitoring is starting."
    CALIBRATION_DEADLINE = None
    return True


def format_timestamp():
    global timestamp_zero

    now = time.perf_counter()
    if timestamp_zero is None:
        timestamp_zero = now
        return 0

    return int((now - timestamp_zero) * 1000)

# ============================================================
# PART 14: TCN ACTIVITY INFERENCE
# ============================================================

if nn is not None:
    class Block(nn.Module):
        def __init__(self, width, dilation):
            super().__init__()
            padding = dilation
            self.net = nn.Sequential(
                nn.Conv1d(width, width, 3, padding=padding, dilation=dilation),
                nn.ReLU(),
                nn.BatchNorm1d(width),
                nn.Dropout(0.1),
                nn.Conv1d(width, width, 3, padding=padding, dilation=dilation),
                nn.ReLU(),
                nn.BatchNorm1d(width),
                nn.Dropout(0.1),
            )

        def forward(self, x):
            return x + self.net(x)


    class TCN(nn.Module):
        def __init__(self, input_channels=None, output_classes=6):
            super().__init__()
            width = 32
            input_count = input_channels or 12
            self.tcn = nn.Sequential(
                nn.Conv1d(input_count, width, 1),
                Block(width, 1),
                Block(width, 2),
                Block(width, 4),
                Block(width, 8),
                Block(width, 16),
            )
            self.head = nn.Linear(width, output_classes)

        def forward(self, x):
            return self.head(self.tcn(x).mean(-1))
else:
    TCN = None


def normalize_activity_label(label):
    return str(label).strip().lower().replace(" ", "_").replace("-", "_")


def load_tcn_model(model_path):
    if torch is None:
        raise RuntimeError(
            "Missing Python dependency 'torch'. Install PyTorch in the backend Python environment."
        )
    if not model_path.exists():
        raise FileNotFoundError(f"TCN model file not found: {model_path}")

    try:
        loaded_model = torch.jit.load(str(model_path), map_location="cpu")
        loaded_model.eval()
        print(f"[MODEL] Loaded TorchScript TCN model: {model_path}")
        return loaded_model
    except Exception as jit_error:
        try:
            try:
                loaded_model = torch.load(str(model_path), map_location="cpu", weights_only=False)
            except TypeError:
                loaded_model = torch.load(str(model_path), map_location="cpu")
        except Exception as load_error:
            raise RuntimeError(
                "Unable to load tcn_activity.pt as TorchScript, a checkpoint, or a PyTorch module."
            ) from load_error

        if isinstance(loaded_model, dict):
            state_dict = loaded_model.get("state_dict") or loaded_model.get("model_state_dict")
            if state_dict is None:
                keys_preview = ", ".join(list(loaded_model.keys())[:6])
                raise RuntimeError(
                    "tcn_activity.pt is a dictionary but does not contain a state_dict. "
                    f"First keys: {keys_preview}"
                ) from jit_error

            checkpoint_labels = loaded_model.get("labels")
            checkpoint_channels = loaded_model.get("channels")
            output_classes = (
                len(checkpoint_labels)
                if isinstance(checkpoint_labels, (list, tuple)) and checkpoint_labels
                else len(DEFAULT_TCN_LABELS)
            )
            input_channels = (
                len(checkpoint_channels)
                if isinstance(checkpoint_channels, (list, tuple)) and checkpoint_channels
                else None
            )
            if input_channels is None:
                first_weight = state_dict.get("tcn.0.weight")
                if first_weight is None:
                    first_weight = state_dict.get("module.tcn.0.weight")
                if first_weight is not None and hasattr(first_weight, "shape"):
                    input_channels = int(first_weight.shape[1])

            if TCN is None:
                raise RuntimeError("PyTorch nn is not available, so the TCN checkpoint cannot be rebuilt.")
            rebuilt_model = TCN(input_channels=input_channels, output_classes=output_classes)
            rebuilt_model.load_state_dict(state_dict)
            rebuilt_model.eval()
            rebuilt_model.tcn_metadata = {
                "labels": checkpoint_labels,
                "channels": checkpoint_channels,
                "input_channels": input_channels,
                "mean": loaded_model.get("mean"),
                "std": loaded_model.get("std"),
                "window": loaded_model.get("window"),
                "stride": loaded_model.get("stride"),
            }
            print(f"[MODEL] Rebuilt TCN from checkpoint: {model_path}")
            return rebuilt_model

        if not callable(loaded_model):
            raise RuntimeError(f"Loaded TCN object is not callable: {type(loaded_model)!r}") from jit_error

        loaded_model.eval()
        print(f"[MODEL] Loaded PyTorch TCN model: {model_path}")
        return loaded_model


def infer_tcn_input_channels(loaded_model):
    metadata = getattr(loaded_model, "tcn_metadata", None)
    if isinstance(metadata, dict):
        if metadata.get("input_channels"):
            return int(metadata["input_channels"])
        channels = metadata.get("channels")
        if isinstance(channels, (list, tuple)) and channels:
            return len(channels)

    try:
        first_conv = loaded_model.tcn[0]
        weight = getattr(first_conv, "weight", None)
        if weight is not None and hasattr(weight, "shape"):
            return int(weight.shape[1])
    except Exception:
        pass

    return None


def infer_tcn_channel_names(loaded_model):
    metadata = getattr(loaded_model, "tcn_metadata", None)
    if not isinstance(metadata, dict):
        return None
    channels = metadata.get("channels")
    if isinstance(channels, (list, tuple)) and channels:
        return [str(channel) for channel in channels]
    return None


def tcn_metadata_array(loaded_model, key):
    metadata = getattr(loaded_model, "tcn_metadata", None)
    if not isinstance(metadata, dict) or metadata.get(key) is None:
        return None
    value = metadata[key]
    if torch is not None and torch.is_tensor(value):
        value = value.detach().cpu().numpy()
    array = np.asarray(value, dtype=np.float32)
    if array.ndim == 1:
        array = array.reshape(1, -1)
    return array


def tcn_metadata_int(loaded_model, key):
    metadata = getattr(loaded_model, "tcn_metadata", None)
    if not isinstance(metadata, dict) or metadata.get(key) is None:
        return None
    value = metadata[key]
    if torch is not None and torch.is_tensor(value):
        value = value.item()
    return int(value)


def configure_tcn_model():
    global tcn_model, tcn_labels, risky_activity_labels, tcn_input_channels
    global tcn_channel_names, tcn_mean, tcn_std, active_window_size, active_stride
    global paired_sample_buffer

    tcn_model = load_tcn_model(TCN_MODEL_PATH)
    metadata = getattr(tcn_model, "tcn_metadata", None)
    if isinstance(metadata, dict) and metadata.get("labels"):
        tcn_labels = [str(label) for label in metadata["labels"]]
    else:
        tcn_labels = DEFAULT_TCN_LABELS.copy()

    risky_activity_labels = {normalize_activity_label(label) for label in RISKY_ACTIVITIES}
    tcn_input_channels = infer_tcn_input_channels(tcn_model)
    tcn_channel_names = infer_tcn_channel_names(tcn_model)
    tcn_mean = tcn_metadata_array(tcn_model, "mean")
    tcn_std = tcn_metadata_array(tcn_model, "std")
    active_window_size = tcn_metadata_int(tcn_model, "window") or WINDOW_SIZE
    active_stride = tcn_metadata_int(tcn_model, "stride") or STRIDE
    paired_sample_buffer = deque(maxlen=active_window_size)

    print("[MODEL] Labels: " + ", ".join(tcn_labels))
    print("[MODEL] Risky labels: " + ", ".join(sorted(risky_activity_labels)))
    print(f"[MODEL] Input channels: {tcn_input_channels or 'unknown'}")
    if tcn_channel_names:
        print("[MODEL] Channel order: " + ", ".join(tcn_channel_names))
    print(f"[MODEL] Window={active_window_size} samples, stride={active_stride} samples")
    print(
        "[MODEL] Normalization: "
        + ("checkpoint mean/std" if tcn_mean is not None and tcn_std is not None else "none")
    )


def build_training_channel_matrix(window_matrix):
    if window_matrix.shape[1] != 12:
        raise RuntimeError(f"Expected 12 raw IMU channels before derived-channel building, got {window_matrix.shape[1]}.")

    mcu1_acc = window_matrix[:, 0:3]
    mcu1_gyro = window_matrix[:, 3:6]
    mcu2_acc = window_matrix[:, 6:9]
    mcu2_gyro = window_matrix[:, 9:12]

    channel_map = {name: window_matrix[:, i] for i, name in enumerate(RAW_CHANNELS)}
    channel_map.update(
        {
            "mcu1_acc_mag": np.linalg.norm(mcu1_acc, axis=1),
            "mcu1_gyro_mag": np.linalg.norm(mcu1_gyro, axis=1),
            "mcu2_acc_mag": np.linalg.norm(mcu2_acc, axis=1),
            "mcu2_gyro_mag": np.linalg.norm(mcu2_gyro, axis=1),
            "rel_ax": window_matrix[:, 6] - window_matrix[:, 0],
            "rel_ay": window_matrix[:, 7] - window_matrix[:, 1],
            "rel_az": window_matrix[:, 8] - window_matrix[:, 2],
            "rel_gx": window_matrix[:, 9] - window_matrix[:, 3],
            "rel_gy": window_matrix[:, 10] - window_matrix[:, 4],
            "rel_gz": window_matrix[:, 11] - window_matrix[:, 5],
        }
    )
    return {name: np.asarray(values, dtype=np.float32) for name, values in channel_map.items()}


def coerce_window_to_tcn_channels(window_matrix):
    expected_channels = tcn_input_channels or window_matrix.shape[1]
    actual_channels = window_matrix.shape[1]

    if actual_channels == expected_channels:
        return window_matrix

    if actual_channels == 12 and expected_channels in {22, 26}:
        channel_names = tcn_channel_names or TRAINING_CHANNELS[:expected_channels]
        channel_map = build_training_channel_matrix(window_matrix)
        missing = [name for name in channel_names if name not in channel_map]
        if missing:
            raise RuntimeError(f"Cannot build live TCN channels missing from training map: {missing}")
        return np.column_stack([channel_map[name] for name in channel_names]).astype(np.float32)

    raise RuntimeError(
        f"TCN model expects {expected_channels} channels, but live data has {actual_channels}."
    )


def prepare_tcn_input(window_matrix):
    if torch is None:
        raise RuntimeError("Missing Python dependency 'torch'.")

    x = coerce_window_to_tcn_channels(window_matrix.astype(np.float32, copy=True))
    if tcn_mean is not None and tcn_std is not None:
        if tcn_mean.shape[-1] != x.shape[1] or tcn_std.shape[-1] != x.shape[1]:
            raise RuntimeError(
                f"Saved normalization has {tcn_mean.shape[-1]} channels, but live input has {x.shape[1]} channels."
            )
        x = (x - tcn_mean) / np.where(tcn_std < 1e-6, 1.0, tcn_std)

    return torch.from_numpy(x.T[None, :, :])


def decode_tcn_prediction(output):
    if isinstance(output, (tuple, list)):
        output = output[0]
    if not torch.is_tensor(output):
        output = torch.as_tensor(output)

    output = output.detach().cpu()
    if output.ndim == 3:
        output = output[:, :, -1]
    elif output.ndim == 1:
        output = output.unsqueeze(0)
    if output.ndim != 2:
        raise RuntimeError(f"Unsupported TCN output shape: {tuple(output.shape)}")

    probabilities = torch.softmax(output, dim=1)
    confidence_tensor, pred_tensor = probabilities.max(dim=1)
    pred_idx = int(pred_tensor.item())
    confidence = float(confidence_tensor.item())

    top_count = min(3, probabilities.shape[1])
    top_values, top_indices = torch.topk(probabilities[0], k=top_count)
    top_parts = []
    for value, index in zip(top_values, top_indices):
        class_index = int(index.item())
        label = tcn_labels[class_index] if class_index < len(tcn_labels) else f"class_{class_index}"
        top_parts.append(f"{label}:{float(value.item()):.2f}")
    top_summary = ", ".join(top_parts)

    prediction = tcn_labels[pred_idx] if pred_idx < len(tcn_labels) else f"class_{pred_idx}"
    return prediction, pred_idx, confidence, top_summary


def update_alarm_state(prediction):
    global risky_counter, active_risky_class, safe_counter, risk_event_latched
    global pending_risky_event_class

    normalized_prediction = normalize_activity_label(prediction)
    event_to_save = None

    if normalized_prediction in risky_activity_labels:
        if normalized_prediction == active_risky_class:
            risky_counter += 1
        else:
            active_risky_class = normalized_prediction
            risky_counter = 1
            risk_event_latched = False
            pending_risky_event_class = None
        safe_counter = 0
        risk_status = "Risky"
    else:
        if normalized_prediction == "standing":
            event_to_save = pending_risky_event_class
            risky_counter = 0
            active_risky_class = None
            safe_counter = 0
            risk_event_latched = False
            pending_risky_event_class = None
        else:
            safe_counter += 1
            if safe_counter >= SAFE_RESET_WINDOWS:
                event_to_save = pending_risky_event_class
                risky_counter = 0
                active_risky_class = None
                safe_counter = 0
                risk_event_latched = False
                pending_risky_event_class = None
        risk_status = "Safe"

    current_prediction_is_active_risk = (
        normalized_prediction in risky_activity_labels
        and normalized_prediction == active_risky_class
    )
    alert_triggered = (
        current_prediction_is_active_risk
        and risky_counter >= RISKY_CONFIRM_WINDOWS
        and not risk_event_latched
    )
    beep_triggered = (
        current_prediction_is_active_risk
        and risky_counter > 0
        and risky_counter % RISKY_BEEP_INTERVAL_WINDOWS == 0
    )

    if beep_triggered:
        beep_triggered = play_alert_sound_async()

    if alert_triggered:
        risk_event_latched = True
        pending_risky_event_class = active_risky_class

    return risk_status, beep_triggered, alert_triggered, event_to_save


def run_prediction_if_ready():
    global new_samples_since_last_prediction

    if paired_samples_seen < STABILIZATION_SAMPLES:
        return
    if len(paired_sample_buffer) < active_window_size:
        return
    if new_samples_since_last_prediction < active_stride:
        return

    new_samples_since_last_prediction = 0
    raw_received_timestamp = format_timestamp()
    feature_extraction_timestamp = format_timestamp()
    window_matrix = np.array(paired_sample_buffer, dtype=np.float32)

    inference_start = time.perf_counter()
    tensor = prepare_tcn_input(window_matrix)
    with torch.no_grad():
        output = tcn_model(tensor)
    inference_ms = (time.perf_counter() - inference_start) * 1000.0

    prediction, pred_idx, confidence, top_summary = decode_tcn_prediction(output)
    model_prediction_timestamp = format_timestamp()
    risk_status, beep_triggered, alert_triggered, event_to_save = update_alarm_state(prediction)

    log_prediction(
        raw_received_timestamp,
        feature_extraction_timestamp,
        model_prediction_timestamp,
        pair_seq,
        prediction,
        risk_status,
        alert_triggered,
        risky_counter,
    )
    if event_to_save:
        save_risky_event(event_to_save)

    if alert_triggered:
        status_text = "RISKY EVENT CONFIRMED"
    elif risk_status == "Risky":
        status_text = f"Risk warning {risky_counter}/{RISKY_CONFIRM_WINDOWS}"
    else:
        status_text = "Safe"

    print(
        f"[raw={raw_received_timestamp} pred={model_prediction_timestamp}] "
        f"Activity={prediction} idx={pred_idx} conf={confidence:.2f} | "
        f"{status_text} | Counter={risky_counter} | "
        f"Latched={'yes' if risk_event_latched else 'no'} | "
        f"SavedEpisode={event_to_save or '-'} | "
        f"Beep={'yes' if beep_triggered else 'no'} | "
        f"Top=[{top_summary}] | Inference={inference_ms:.1f} ms"
    )


# ============================================================
# PART 15: PAIR SAMPLES
# ============================================================
def pair_samples_if_ready():
    global pair_seq, expected_seq, new_samples_since_last_prediction, paired_samples_seen

    q1 = sample_queues[DEVICE_NAMES[0]]

    while q1:
        s1 = q1.popleft()
        pair_seq += 1
        imu = s1["imu"]
        paired_row = [
            imu[0], imu[1], imu[2], imu[3], imu[4], imu[5],
            imu[0], imu[1], imu[2], imu[3], imu[4], imu[5],
        ]
        paired_sample_buffer.append(paired_row)
        paired_samples_seen += 1
        new_samples_since_last_prediction += 1

        if paired_samples_seen == STABILIZATION_SAMPLES:
            print("\nStabilization completed. Real-time prediction starts now.\n")

        run_prediction_if_ready()

# ============================================================
# PART 16: BLE NOTIFICATION HANDLER (LIGHTWEIGHT)
# ============================================================
def notification_handler(device_name):
    def handler(sender, data):
        if len(data) not in {SAMPLE_SIZE_BYTES, EXPECTED_NOTIFICATION_BYTES}:
            return

        sample_count = len(data) // SAMPLE_SIZE_BYTES
        appended = False

        for i in range(sample_count):
            start = i * SAMPLE_SIZE_BYTES
            decoded = decode_one_sample(data[start:start + SAMPLE_SIZE_BYTES])
            if decoded is None:
                continue
            if handle_special_packet(device_name, decoded):
                continue
            if decoded["header"] != EXPECTED_HEADER[device_name]:
                continue
            decoded["sample_seq"] = decoded["global_seq"]
            sample_queues[device_name].append(decoded)
            appended = True

        # Signal the background task instead of executing heavy ML/CSV writing here.
        if appended and main_event_loop is not None and data_ready_event is not None:
            main_event_loop.call_soon_threadsafe(data_ready_event.set)

    return handler

# ============================================================
# BACKGROUND PROCESSING TASK
# ============================================================
async def background_processing_task():
    while True:
        await data_ready_event.wait()
        data_ready_event.clear()
        
        try:
            pair_samples_if_ready()
        except Exception as e:
            print(f"Error in background processing loop: {e}")
            
        # Allow the asyncio event loop to breathe to prevent blocking BLE traffic
        await asyncio.sleep(0.001)


# ============================================================
# BLE COMMANDS & SESSION LOGIC
# ============================================================
def make_disconnect_callback(name):
    def _cb(client):
        if name in intentional_disconnects:
            intentional_disconnects.discard(name)
            return
        handle_disconnect(name)
    return _cb

async def ensure_clients_connected(client_map, stage="operation"):
    disconnected = [name for name, client in client_map.items() if not client.is_connected]
    if disconnected: raise RuntimeError(f"Disconnected client(s) before {stage}: {disconnected}")


async def connect_client_with_retry(client, device_name):
    global CALIBRATION_MESSAGE
    last_error = None
    for attempt in range(1, BLE_CONNECT_RETRIES + 1):
        try:
            CALIBRATION_MESSAGE = (
                f"Connecting {device_name} "
                f"(attempt {attempt} of {BLE_CONNECT_RETRIES})."
            )
            print(
                f"[BLE] Connecting {device_name} "
                f"(attempt {attempt}/{BLE_CONNECT_RETRIES})..."
            )
            await client.connect()
            if client.is_connected:
                battery_state[device_name]["connected"] = True
                CALIBRATION_MESSAGE = f"Connected {device_name}."
                print(f"[BLE] Connected {device_name}.")
                return
        except Exception as error:
            last_error = error
            battery_state[device_name]["connected"] = False
            print(
                f"[BLE] {device_name} connection attempt {attempt} failed: "
                f"{type(error).__name__}: {error}"
            )
            try:
                if client.is_connected:
                    intentional_disconnects.add(device_name)
                    await client.disconnect()
            except Exception:
                pass
        if attempt < BLE_CONNECT_RETRIES:
            await asyncio.sleep(BLE_CONNECT_RETRY_DELAY_SEC)

    raise RuntimeError(
        f"Unable to connect {device_name} after {BLE_CONNECT_RETRIES} attempts"
    ) from last_error


async def send_to_one(client, device_name, cmd: bytes, *, response: bool | None = None):
    if response is None: response = CMD_WRITE_WITH_RESPONSE
    try:
        await client.write_gatt_char(COMMAND_CHAR_UUID, cmd, response=response)
    except Exception as e:
        if response:
            await client.write_gatt_char(COMMAND_CHAR_UUID, cmd, response=False)
        else:
            raise

async def send_to_all(client_map, cmd: bytes, *, gap_sec: float = COMMAND_GAP_SEC, response: bool | None = None):
    for device_name in [name for name in DEVICE_NAMES if name in client_map]:
        await send_to_one(client_map[device_name], device_name, cmd, response=response)
        if gap_sec > 0: await asyncio.sleep(gap_sec)

async def send_to_all_parallel(client_map, cmd: bytes):
    tasks = [send_to_one(client_map[n], n, cmd, response=False) for n in DEVICE_NAMES if n in client_map]
    await asyncio.gather(*tasks)

async def start_stream_synchronized(client_map):
    reset_stream_state()
    await send_to_all(client_map, b"ARM_START", gap_sec=COMMAND_GAP_SEC)
    await asyncio.sleep(0.05)
    await send_to_all_parallel(client_map, b"FIRE_START")
    await asyncio.sleep(0.3)

async def stop_stream(client_map):
    connected = {name: client for name, client in client_map.items() if client.is_connected}
    if connected:
        await send_to_all(connected, b"STOP", gap_sec=STOP_GAP_SEC)
        await asyncio.sleep(0.3)

async def run_interpretation_session(client_map):
    await ensure_clients_connected(client_map, stage="start")

    init_prediction_database()
    await start_stream_synchronized(client_map)

    if disconnect_event is not None:
        await disconnect_event.wait()
        if disconnected_devices:
            print(f"Disconnect detected: {sorted(disconnected_devices)}")
            return False
    else:
        while SESSION_ACTIVE:
            await asyncio.sleep(0.5)

    await stop_stream(client_map)
    return True

async def cleanup_clients(clients):
    connected_map = get_connected_client_map(clients)
    if connected_map:
        try: await stop_stream(connected_map)
        except Exception: pass

    for client, name in zip(clients, DEVICE_NAMES):
        try:
            if client.is_connected: await client.stop_notify(DATA_CHAR_UUID)
        except Exception: pass
        try:
            if client.is_connected: await client.stop_notify(BATTERY_CHAR_UUID)
        except Exception: pass
        try:
            if client.is_connected:
                intentional_disconnects.add(name)
                await client.disconnect()
        except Exception: pass
        battery_state[name]["connected"] = False

    await asyncio.sleep(SHUTDOWN_SETTLE_SEC)


# ============================================================
# PART 21: MAIN PROGRAM
# ============================================================
async def main():
    global disconnect_event, main_event_loop, data_ready_event
    global CALIBRATION_PHASE, CALIBRATION_MESSAGE, CALIBRATION_DEADLINE, LAST_ERROR

    if BLEAK_IMPORT_ERROR is not None or BleakScanner is None or BleakClient is None:
        raise RuntimeError(
            "Missing Python dependency 'bleak'. Install backend dependencies with "
            "'pip install -r requirements-flask.txt'."
        ) from BLEAK_IMPORT_ERROR

    configure_tcn_model()
    
    main_event_loop = asyncio.get_running_loop()
    data_ready_event = asyncio.Event()
    disconnect_event = asyncio.Event()
    reset_device_connection_state()

    CALIBRATION_PHASE = "connecting"
    CALIBRATION_MESSAGE = "Searching for the wearable sensor."
    CALIBRATION_DEADLINE = None
    print("Scanning for devices...")
    devices = await BleakScanner.discover(timeout=10.0)
    targets = {d.name: d for d in devices if d.name in DEVICE_NAMES}
    print(
        "[BLE] Found target sensors: "
        + ", ".join(sorted(targets))
        if targets
        else "[BLE] Found target sensors: none"
    )

    if len(targets) < len(DEVICE_NAMES):
        missing = [name for name in DEVICE_NAMES if name not in targets]
        raise RuntimeError(f"Could not find the wearable sensor. Missing: {missing}")

    c1 = BleakClient(targets[DEVICE_NAMES[0]], timeout=20, disconnected_callback=make_disconnect_callback(DEVICE_NAMES[0]), services=[SERVICE_UUID])
    clients = [c1]
    client_map = get_client_map(clients)

    bg_task = asyncio.create_task(background_processing_task())

    try:
        await connect_client_with_retry(c1, DEVICE_NAMES[0])
        await asyncio.sleep(POST_CONNECT_STABILIZE_SEC)

        # Subscribe to IMU stream notifications.
        await c1.start_notify(DATA_CHAR_UUID, notification_handler(DEVICE_NAMES[0]))
        await asyncio.sleep(0.3)

        # Subscribe to battery voltage notifications when firmware exposes FFF3.
        # Some sensor firmware builds expose only IMU data/command characteristics.
        for name, client in client_map.items():
            if has_characteristic(client, BATTERY_CHAR_UUID):
                try:
                    await client.start_notify(
                        BATTERY_CHAR_UUID,
                        battery_notification_handler(name),
                    )
                    await asyncio.sleep(0.2)
                except Exception as e:
                    print(f"[BATTERY] Notify setup skipped for {name}: {e}")
            else:
                print(f"[BATTERY] {name} does not expose {BATTERY_CHAR_UUID}; skipping battery notify.")

        # Read initial battery values immediately if available, so the dashboard/CSV is not empty
        # while waiting for the next 1-minute battery notification.
        for name, client in client_map.items():
            try:
                if not has_characteristic(client, BATTERY_CHAR_UUID):
                    continue
                data = await client.read_gatt_char(BATTERY_CHAR_UUID)
                raw_adc, voltage = parse_voltage_data(data)
                if voltage is not None:
                    update_battery_state(name, raw_adc, voltage, connected=True)
            except Exception as e:
                print(f"[BATTERY] Initial read failed for {name}: {e}")

        # Run an automatic calibration sequence (static neutral capture/check).
        try:
            calibration_ok = await automatic_calibration_sequence(client_map)
            if calibration_ok is False:
                return
        except Exception as e:
            LAST_ERROR = f"Calibration failed: {e}"
            CALIBRATION_PHASE = "error"
            CALIBRATION_MESSAGE = LAST_ERROR
            CALIBRATION_DEADLINE = None
            print(f"[CALIBRATION] Automatic calibration sequence failed: {e}")

        await run_interpretation_session(client_map)
    finally:
        bg_task.cancel()
        await cleanup_clients(clients)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Program stopped by user.")
