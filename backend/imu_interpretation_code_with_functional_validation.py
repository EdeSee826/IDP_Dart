import asyncio
import json
import math
import os
import pickle
import sqlite3
import struct
import threading
import time
import warnings
from collections import deque
from datetime import datetime

import numpy as np
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

DEVICE_NAMES = ["XIAO_MG24_Sensor_01", "XIAO_MG24_Sensor_02"]

EXPECTED_HEADER = {
    "XIAO_MG24_Sensor_01": "im01",
    "XIAO_MG24_Sensor_02": "im02",
}
STATUS_HEADER = {
    "XIAO_MG24_Sensor_01": "st01",
    "XIAO_MG24_Sensor_02": "st02",
}
NEUTRAL_HEADER = {
    "XIAO_MG24_Sensor_01": "nt01",
    "XIAO_MG24_Sensor_02": "nt02",
}
VALIDATION_HEADER = {
    "XIAO_MG24_Sensor_01": "va01",
    "XIAO_MG24_Sensor_02": "va02",
}
FUNCTIONAL_VALIDATION_HEADER = {
    "XIAO_MG24_Sensor_01": "fp01",
    "XIAO_MG24_Sensor_02": "fp02",
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

# Calibration collection windows.
# At the expected 50 Hz rate these provide about 250 static samples and
# 600 functional samples, which is sufficient for gravity orientation and
# three deliberate thigh taps while keeping the patient-facing wait short.
STATIC_CALIBRATION_WAIT_SEC = 5.0
FUNCTIONAL_VALIDATION_WAIT_SEC = 12.0

# Short thigh-pat functional placement check thresholds.
# These are intentionally adjustable because axis directions depend on how the sensors are mounted.
FUNCTIONAL_MIN_TOTAL_AMP_G = 0.15
FUNCTIONAL_MCU1_Y_DOMINANCE_RATIO = 0.90
FUNCTIONAL_MCU2_Z_DOMINANCE_RATIO = 1.05
FUNCTIONAL_MCU2_MIN_TOTAL_TO_MCU1_RATIO = 1.15
FUNCTIONAL_BASELINE_MIN_SIMILARITY = 0.75
FUNCTIONAL_BASELINE_MIN_TOTAL_RATIO = 0.45
FUNCTIONAL_BASELINE_MAX_TOTAL_RATIO = 2.20


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

RISKY_ACTIVITIES = {"elbow_flexion", "shoulder_adduction"}
# Give an audible warning every three consecutive risky predictions, but only
# confirm and store a risky event after six consecutive risky predictions.
RISKY_BEEP_INTERVAL_WINDOWS = 3
RISKY_CONFIRM_WINDOWS = 6
SAFE_RESET_WINDOWS = 2
PREDICTION_RETENTION_DAYS = 7

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
RISK_EVENTS_DB_PATH = os.path.join(BASE_DIR, "risky_events.db")
CALIBRATION_BASELINES_PATH = os.path.join(BASE_DIR, "calibration_baselines.json")

MODEL_PATH = os.path.join(BASE_DIR, "svm_rfe_model (1).pkl")
SCALER_PATH = os.path.join(BASE_DIR, "scaler (1).pkl")

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
functional_results = {name: None for name in DEVICE_NAMES}
functional_timestamps = {name: None for name in DEVICE_NAMES}

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

scaler = None
svm_rfe_model = None

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
# PART 5: LOAD TRAINED ML MODEL FILES
# ============================================================
def resolve_model_file(filename):
    candidates = [
        os.path.join(BASE_DIR, filename),
        os.path.join(os.path.dirname(BASE_DIR), filename),
    ]

    for candidate in candidates:
        if os.path.exists(candidate):
            return candidate

    return None


def load_ml_objects():
    global scaler, svm_rfe_model

    scaler_path = resolve_model_file(os.path.basename(SCALER_PATH))
    model_path = resolve_model_file(os.path.basename(MODEL_PATH))

    if scaler_path is None:
        raise FileNotFoundError(f"Missing file: {os.path.basename(SCALER_PATH)}")
    if model_path is None:
        raise FileNotFoundError(f"Missing file: {os.path.basename(MODEL_PATH)}")

    with open(scaler_path, "rb") as f:
        scaler = pickle.load(f)
    with open(model_path, "rb") as f:
        svm_rfe_model = pickle.load(f)

    print("ML files loaded successfully.")


# ============================================================
# PART 6: FEATURE COLUMN ORDER
# ============================================================
def generate_default_feature_columns():
    axes = [
        "mcu1_ax", "mcu1_ay", "mcu1_az", "mcu1_gx", "mcu1_gy", "mcu1_gz",
        "mcu2_ax", "mcu2_ay", "mcu2_az", "mcu2_gx", "mcu2_gy", "mcu2_gz",
    ]
    USE_ENERGY_FEATURES = True 
    columns = []

    for stat in ["mean", "std", "min", "max"]:
        for axis in axes:
            columns.append(f"{axis}_{stat}")

    if USE_ENERGY_FEATURES:
        for axis in axes:
            columns.append(f"{axis}_energy")

    return columns


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
    b1 = battery_state.get("XIAO_MG24_Sensor_01", {})
    b2 = battery_state.get("XIAO_MG24_Sensor_02", {})
    return b1, b2


def get_battery_snapshot():
    """Return a lightweight snapshot of the current battery state for the Flask API."""
    b1, b2 = get_battery_values_for_csv()

    return {
        "sensor1": dict(b1),
        "sensor2": dict(b2),
    }


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
        "functional": {
            name: {
                key: functional_results[name][key]
                for key in ("range_x", "range_y", "range_z", "total_amp")
            }
            for name in DEVICE_NAMES
            if functional_results.get(name) is not None
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


def functional_signature(result):
    values = [
        float(result["range_x"]),
        float(result["range_y"]),
        float(result["range_z"]),
        float(result["total_amp"]),
    ]
    magnitude = math.sqrt(sum(value * value for value in values))
    return [value / max(magnitude, 1e-6) for value in values]


def functional_matches_account_baseline():
    baseline = load_account_baseline()
    functional_baseline = baseline.get("functional", {}) if baseline else {}
    comparisons = {}

    for name in DEVICE_NAMES:
        current = functional_results.get(name)
        initial = functional_baseline.get(name)
        if current is None or initial is None:
            return False, comparisons

        current_signature = functional_signature(current)
        initial_signature = functional_signature(initial)
        similarity = sum(
            current_value * initial_value
            for current_value, initial_value in zip(
                current_signature, initial_signature
            )
        )
        total_ratio = current["total_amp"] / max(float(initial["total_amp"]), 1e-6)
        passed = (
            similarity >= FUNCTIONAL_BASELINE_MIN_SIMILARITY
            and FUNCTIONAL_BASELINE_MIN_TOTAL_RATIO
            <= total_ratio
            <= FUNCTIONAL_BASELINE_MAX_TOTAL_RATIO
        )
        comparisons[name] = {
            "similarity": similarity,
            "total_ratio": total_ratio,
            "passed": passed,
        }

    return all(item["passed"] for item in comparisons.values()), comparisons


def get_calibration_validation_snapshot():
    """Return overall static orientation and functional placement results."""
    static_values = [validation_results.get(name) for name in DEVICE_NAMES]
    functional_values = [functional_results.get(name) for name in DEVICE_NAMES]

    static_passed = None
    if all(result is not None for result in static_values):
        static_passed = all(bool(result.get("passed")) for result in static_values)

    functional_passed = None
    functional_comparison = {}
    if all(result is not None for result in functional_values):
        r1, r2 = functional_values
        movement_enough = (
            r1["total_amp"] >= FUNCTIONAL_MIN_TOTAL_AMP_G
            and r2["total_amp"] >= FUNCTIONAL_MIN_TOTAL_AMP_G
        )
        wrist_ranges_larger = (
            r2["range_x"] > r1["range_x"]
            and r2["range_y"] > r1["range_y"]
            and r2["range_z"] > r1["range_z"]
        )
        wrist_total_larger = (
            r2["total_amp"]
            >= FUNCTIONAL_MCU2_MIN_TOTAL_TO_MCU1_RATIO * r1["total_amp"]
        )
        functional_passed = movement_enough and wrist_ranges_larger and wrist_total_larger
        if not CALIBRATION_ENROLL_BASELINE:
            baseline_passed, functional_comparison = functional_matches_account_baseline()
            functional_passed = functional_passed and baseline_passed

    return {
        "static_passed": static_passed,
        "functional_passed": functional_passed,
        "baseline_available": load_account_baseline() is not None,
        "functional_comparison": functional_comparison,
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
        "ready_for_functional",
        "static_failed",
        "functional_failed",
    }:
        return False
    CALIBRATION_RETRY_REQUESTED = True
    return True


def request_calibration_bypass():
    """Allow an explicit validation-only bypass while calibration is paused."""
    global CALIBRATION_BYPASS_REQUESTED
    if CALIBRATION_PHASE not in {
        "ready_to_stand",
        "ready_for_functional",
        "static",
        "static_failed",
        "functional",
        "functional_failed",
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
    n1 = neutral_vectors.get("XIAO_MG24_Sensor_01")
    n2 = neutral_vectors.get("XIAO_MG24_Sensor_02")
    
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
    global active_risky_class, safe_counter
    global timestamp_zero

    expected_seq = pair_seq = 0
    prev_mcu_diff = first_signed_mcu_diff = None
    new_samples_since_last_prediction = paired_samples_seen = risky_counter = 0
    active_risky_class = None
    safe_counter = 0
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
    if header == FUNCTIONAL_VALIDATION_HEADER[device_name]:
        # Transmitter sends acc peak-to-peak ranges in acc[0:3] and total amplitude in gyro[0].
        functional_results[device_name] = {
            "range_x": imu[0],
            "range_y": imu[1],
            "range_z": imu[2],
            "total_amp": imu[3],
            "received_at": datetime.now().isoformat(),
            "requested_at": functional_timestamps.get(device_name),
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
    r1 = validation_results.get("XIAO_MG24_Sensor_01")
    r2 = validation_results.get("XIAO_MG24_Sensor_02")

    print("\n========== PLACEMENT VALIDATION RESULT ==========")
    for name, label in [
        ("XIAO_MG24_Sensor_01", "MCU1 upper arm sensor"),
        ("XIAO_MG24_Sensor_02", "MCU2 wrist sensor"),
    ]:
        result = validation_results.get(name)
        if result is None:
            print(f"{label}: No validation result received.")
        else:
            status = "PASS" if result["passed"] else "FAIL"
            print(
                f"{label}: {status} | angle error = {result['angle_deg']:.2f}° | "
                f"{result['interpretation']}"
            )

    if r1 and r1["passed"] and r2 and r2["passed"]:
        print("Feedback: MCU1 pass, MCU2 pass -> Proceed to real-time prediction.\n")
        return True
    if r1 and not r1["passed"] and r2 and r2["passed"]:
        print("Feedback: MCU1 fail, MCU2 pass -> Re-adjust upper arm sensor.\n")
        return False
    if r1 and r1["passed"] and r2 and not r2["passed"]:
        print("Feedback: MCU1 pass, MCU2 fail -> Re-adjust wrist sensor.\n")
        return False
    print("Feedback: MCU1 fail, MCU2 fail -> Re-wear both sensors and repeat neutral pose.\n")
    return False


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


def print_functional_validation_summary():
    r1 = functional_results.get("XIAO_MG24_Sensor_01")
    r2 = functional_results.get("XIAO_MG24_Sensor_02")

    print("\n========== FUNCTIONAL ANATOMICAL PLACEMENT VALIDATION RESULT ==========")
    if r1 is None:
        print("MCU1 upper arm sensor: No functional result received.")
    else:
        ts_info = f" (requested at {r1.get('requested_at')})" if r1.get('requested_at') else ""
        recv_info = f" received at {r1.get('received_at')}" if r1.get('received_at') else ""
        print(
            "MCU1 upper arm sensor ranges: "
            f"X={r1['range_x']:.3f} g, Y={r1['range_y']:.3f} g, "
            f"Z={r1['range_z']:.3f} g, total={r1['total_amp']:.3f} g{ts_info}{recv_info}"
        )

    if r2 is None:
        print("MCU2 wrist sensor: No functional result received.")
    else:
        ts_info = f" (requested at {r2.get('requested_at')})" if r2.get('requested_at') else ""
        recv_info = f" received at {r2.get('received_at')}" if r2.get('received_at') else ""
        print(
            "MCU2 wrist sensor ranges: "
            f"X={r2['range_x']:.3f} g, Y={r2['range_y']:.3f} g, "
            f"Z={r2['range_z']:.3f} g, total={r2['total_amp']:.3f} g{ts_info}{recv_info}"
        )

    if r1 is None or r2 is None:
        print("Feedback: Missing functional validation result -> repeat the thigh-pat check.\n")
        return False

    movement_enough = (r1["total_amp"] >= FUNCTIONAL_MIN_TOTAL_AMP_G and
                       r2["total_amp"] >= FUNCTIONAL_MIN_TOTAL_AMP_G)
    # 2. NEW LOGIC: Check if MCU2 (wrist) ranges are larger than MCU1 (arm) for ALL axes
    mcu2_x_larger = r2["range_x"] > r1["range_x"]
    mcu2_y_larger = r2["range_y"] > r1["range_y"]
    mcu2_z_larger = r2["range_z"] > r1["range_z"]
    mcu2_all_larger = mcu2_x_larger and mcu2_y_larger and mcu2_z_larger
    
    # 3. Check if total amplitude is larger on MCU2
    wrist_larger_ok = (r2["total_amp"] >= FUNCTIONAL_MCU2_MIN_TOTAL_TO_MCU1_RATIO * r1["total_amp"])

    print("Functional criteria:")
    print(f"- Movement amplitude sufficient: {'PASS' if movement_enough else 'FAIL'}")
    print(f"- MCU1 expected upper-arm X-axis dominance: {'PASS' if mcu2_x_larger else 'FAIL'}")
    print(f"- MCU1 expected upper-arm Y-axis dominance: {'PASS' if mcu2_y_larger else 'FAIL'}")
    print(f"- MCU1 expected upper-arm Z-axis dominance: {'PASS' if mcu2_z_larger else 'FAIL'}")
    print(f"- MCU2 wrist total amplitude greater than MCU1 upper-arm amplitude: {'PASS' if wrist_larger_ok else 'FAIL'}")

    if movement_enough and mcu2_all_larger and wrist_larger_ok:
        print("Feedback: Functional placement check PASS -> anatomical placement is consistent.\n")
        return True

    # Extra diagnosis for the common swapped-sensor case.
    possible_swap = (r1["total_amp"] > r2["total_amp"] and
                     r1["range_z"] >= r1["range_y"] and
                     r2["range_y"] >= r2["range_z"])
    
    if possible_swap:
        print("Feedback: Functional placement check FAIL -> possible MCU1/MCU2 swapped. MCU1 may be at wrist and MCU2 may be at upper arm.\n")
    elif not wrist_larger_ok:
        print("Feedback: Functional placement check FAIL -> wrist sensor movement is not larger than upper-arm sensor. Check whether MCU2 is really at the wrist.\n")
    elif not mcu2_all_larger:
        print("Feedback: Functional placement check FAIL -> MCU2 (wrist) movement was not entirely larger than MCU1 (upper arm) on all axes. Check orientation.\n")
    else:
        print("Feedback: Functional placement check FAIL -> repeat the thigh-pat movement more consistently.\n")
    
    return False

async def validate_functional_anatomical_placement(client_map):
    print("\n========== FUNCTIONAL ANATOMICAL PLACEMENT VALIDATION ==========")
    print("Gently pat/touch the front thigh for a few seconds by moving the forearm forward and backward.")
    print("This check does NOT save anything into EEPROM; it only verifies MCU1/MCU2 anatomical placement.")

    for name in DEVICE_NAMES:
        functional_results[name] = None

    await send_to_all(client_map, b"CHECK_FUNC_PLACE")
    await asyncio.sleep(FUNCTIONAL_VALIDATION_WAIT_SEC)
    await ensure_clients_connected(client_map, stage="functional anatomical placement validation")
    return print_functional_validation_summary()


async def automatic_calibration_sequence(client_map):
    """Automatically request static then functional calibration with short user notifications.

    Sequence:
    - Notify user to stand still for ~5s, send ENROLL_NEUTRAL, wait, then GET_NEUTRAL
    - Notify user to tap laps ~5 times (~5s), send CHECK_FUNC_PLACE and wait
    """
    global CALIBRATION_PHASE, CALIBRATION_MESSAGE, CALIBRATION_DEADLINE
    global CALIBRATION_BYPASS_REQUESTED

    CALIBRATION_BYPASS_REQUESTED = False

    await ensure_clients_connected(client_map, stage="automatic calibration")

    CALIBRATION_PHASE = "ready_to_stand"
    CALIBRATION_MESSAGE = (
        "Both sensors are connected. Stand comfortably with your PICC arm "
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
        functional_results[name] = None

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
                "Static calibration differs from your initial baseline. Check that each sensor marker points down toward the earth."
            )
            CALIBRATION_DEADLINE = None
            if not await wait_for_calibration_retry():
                return False
            if CALIBRATION_BYPASS_REQUESTED:
                return complete_calibration_bypass()

    # Functional calibration
    while SESSION_ACTIVE:
        for name in DEVICE_NAMES:
            functional_results[name] = None
        CALIBRATION_PHASE = "ready_for_functional"
        CALIBRATION_MESSAGE = (
            "Get ready to gently pat the front of your thigh with your PICC arm. "
            "Tap I understand when you are ready to begin functional calibration."
        )
        CALIBRATION_DEADLINE = None
        if not await wait_for_calibration_retry():
            return False
        if CALIBRATION_BYPASS_REQUESTED:
            return complete_calibration_bypass()
        await ensure_clients_connected(client_map, stage="functional calibration preparation")

        CALIBRATION_PHASE = "functional"
        CALIBRATION_MESSAGE = "Gently tap your thigh with the PICC arm for functional calibration."
        CALIBRATION_DEADLINE = time.monotonic() + FUNCTIONAL_VALIDATION_WAIT_SEC
        # record the requested timestamp so backend can align received packets
        ts = datetime.now().isoformat()
        for name in DEVICE_NAMES:
            functional_timestamps[name] = ts
        try:
            await send_to_all(client_map, b"CHECK_FUNC_PLACE")
        except Exception:
            pass
        await asyncio.sleep(FUNCTIONAL_VALIDATION_WAIT_SEC)
        await ensure_clients_connected(client_map, stage="automatic functional validation")

        if CALIBRATION_ENROLL_BASELINE:
            if all(functional_results.get(name) is not None for name in DEVICE_NAMES):
                save_account_baseline()
                break
            CALIBRATION_MESSAGE = (
                "Functional baseline data was incomplete. Repeating the baseline recording."
            )
            CALIBRATION_DEADLINE = None
            await asyncio.sleep(1.0)
            continue

        functional_result = get_calibration_validation_snapshot().get("functional_passed")
        if functional_result is True:
            break

        CALIBRATION_PHASE = "functional_failed"
        CALIBRATION_MESSAGE = (
            "Functional calibration failed. Sensor 1 and Sensor 2 may be swapped. "
            "Check that Sensor 1 is on the upper arm and Sensor 2 is on the wrist."
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


# ============================================================
# PART 13: PREPROCESSING & FEATURE EXTRACTION
# ============================================================
def preprocess_live_window(window_matrix):
    processed_window = np.copy(window_matrix)
    
    # Accel indices: mcu1(0,1,2), mcu2(6,7,8)
    acc_indices = [0, 1, 2, 6, 7, 8]
    # Gyro indices: mcu1(3,4,5), mcu2(9,10,11)
    gyro_indices = [3, 4, 5, 9, 10, 11]
    
    acc_data = processed_window[:, acc_indices]
    gyro_data = processed_window[:, gyro_indices]
    
    acc_mean = np.mean(acc_data)
    acc_std = np.std(acc_data)
    gyro_mean = np.mean(gyro_data)
    gyro_std = np.std(gyro_data)
    
    # Prevent division by zero if completely still
    if acc_std == 0: acc_std = 1e-6
    if gyro_std == 0: gyro_std = 1e-6

    processed_window[:, acc_indices] = (acc_data - acc_mean) / acc_std
    processed_window[:, gyro_indices] = (gyro_data - gyro_mean) / gyro_std
    
    return processed_window


def compute_energy_per_axis(window):
    return np.sum(np.square(window), axis=0)


def extract_live_features(window_matrix):
    feats = []
    feats.extend(np.mean(window_matrix, axis=0))
    feats.extend(np.std(window_matrix, axis=0))
    feats.extend(np.min(window_matrix, axis=0))
    feats.extend(np.max(window_matrix, axis=0))
    feats.extend(compute_energy_per_axis(window_matrix))
    return np.array(feats, dtype=float)


def format_timestamp():
    global timestamp_zero

    now = time.perf_counter()
    if timestamp_zero is None:
        timestamp_zero = now
        return 0

    return int((now - timestamp_zero) * 1000)

# ============================================================
# PART 14: REAL-TIME PREDICTION 
# ============================================================
def run_prediction_if_ready():
    global new_samples_since_last_prediction, risky_counter
    global active_risky_class, safe_counter

    if paired_samples_seen < STABILIZATION_SAMPLES: return
    if len(paired_sample_buffer) < WINDOW_SIZE: return
    if new_samples_since_last_prediction < STRIDE: return

    new_samples_since_last_prediction = 0
    window_matrix = np.array(paired_sample_buffer, dtype=float)
    raw_received_timestamp = format_timestamp()
    
    # --- PREPROCESS DATA TO MATCH TRAINING PIPELINE ---
    cleaned_window = preprocess_live_window(window_matrix)

    # --- EXTRACT FEATURES FROM CLEANED DATA ---
    feature_vector = extract_live_features(cleaned_window)
    feature_extraction_timestamp = format_timestamp()

    # High-Performance NumPy array prediction instead of Pandas DataFrame.
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        features_scaled = scaler.transform(feature_vector.reshape(1, -1))
        prediction = svm_rfe_model.predict(features_scaled)[0]

    model_prediction_timestamp = format_timestamp()

    if prediction in RISKY_ACTIVITIES:
        if prediction == active_risky_class:
            risky_counter += 1
        else:
            active_risky_class = prediction
            risky_counter = 1
        safe_counter = 0
        risk_status = "Risky"
    else:
        if prediction == "standing":
            risky_counter = 0
            active_risky_class = None
            safe_counter = 0
        else:
            safe_counter += 1
            if safe_counter >= SAFE_RESET_WINDOWS:
                risky_counter = 0
                active_risky_class = None
                safe_counter = 0
        risk_status = "Safe"

    current_prediction_is_active_risk = (
        prediction in RISKY_ACTIVITIES
        and prediction == active_risky_class
    )
    alert_triggered = (
        current_prediction_is_active_risk
        and risky_counter == RISKY_CONFIRM_WINDOWS
    )
    beep_triggered = (
        current_prediction_is_active_risk
        and risky_counter > 0
        and risky_counter % RISKY_BEEP_INTERVAL_WINDOWS == 0
    )

    if beep_triggered:
        beep_triggered = play_alert_sound_async()

    if alert_triggered:
        save_risky_event(prediction)

    if current_prediction_is_active_risk and risky_counter >= RISKY_CONFIRM_WINDOWS:
        print(
            f"[raw={raw_received_timestamp}] [features={feature_extraction_timestamp}] "
            f"[model={model_prediction_timestamp}] Activity: {prediction} | "
            f"Status: RISKY EVENT DETECTED | "
            f"Alert: {'Beep' if beep_triggered else 'No'}"
        )
    else:
        print(
            f"[raw={raw_received_timestamp}] [features={feature_extraction_timestamp}] "
            f"[model={model_prediction_timestamp}] Activity: {prediction} | "
            f"Status: {risk_status} | "
            f"Alert: {'Warning beep' if beep_triggered else 'No'}"
        )

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


# ============================================================
# PART 15: PAIR SAMPLES
# ============================================================
def pair_samples_if_ready():
    global pair_seq, expected_seq, new_samples_since_last_prediction, paired_samples_seen

    q1 = sample_queues["XIAO_MG24_Sensor_01"]
    q2 = sample_queues["XIAO_MG24_Sensor_02"]

    # Infinite loop safeguard: prevent locking if queues are severely desynced
    max_iterations = len(q1) + len(q2) + 10
    iters = 0

    while q1 and q2 and iters < max_iterations:
        iters += 1
        s1_head = q1[0]["global_seq"]
        s2_head = q2[0]["global_seq"]

        s1 = s2 = None

        if s1_head == expected_seq and s2_head == expected_seq:
            s1, s2 = q1.popleft(), q2.popleft()
            expected_seq += 1
        elif s1_head > expected_seq and s2_head == expected_seq:
            s2 = q2.popleft()
            expected_seq += 1
        elif s2_head > expected_seq and s1_head == expected_seq:
            s1 = q1.popleft()
            expected_seq += 1
        elif s1_head > expected_seq and s2_head > expected_seq:
            expected_seq = min(s1_head, s2_head)
            continue
        else:
            if s1_head < expected_seq: q1.popleft()
            if s2_head < expected_seq: q2.popleft()
            continue

        pair_seq += 1

        if s1 is not None and s2 is not None:
            paired_row = [
                s1["imu"][0], s1["imu"][1], s1["imu"][2], s1["imu"][3], s1["imu"][4], s1["imu"][5],
                s2["imu"][0], s2["imu"][1], s2["imu"][2], s2["imu"][3], s2["imu"][4], s2["imu"][5],
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
        if len(data) != EXPECTED_NOTIFICATION_BYTES: return

        first_decoded = decode_one_sample(data[0:SAMPLE_SIZE_BYTES])
        if first_decoded is not None and handle_special_packet(device_name, first_decoded):
            return

        for i in range(SAMPLES_PER_NOTIFICATION):
            start = i * SAMPLE_SIZE_BYTES
            decoded = decode_one_sample(data[start:start + SAMPLE_SIZE_BYTES])
            if decoded is None or decoded["header"] != EXPECTED_HEADER[device_name]:
                continue
            decoded["sample_seq"] = decoded["global_seq"]
            sample_queues[device_name].append(decoded)

        # Signal the background task instead of executing heavy ML/CSV writing here.
        if main_event_loop is not None and data_ready_event is not None:
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
    
    main_event_loop = asyncio.get_running_loop()
    data_ready_event = asyncio.Event()
    disconnect_event = asyncio.Event()
    reset_device_connection_state()

    load_ml_objects()
    CALIBRATION_PHASE = "connecting"
    CALIBRATION_MESSAGE = "Searching for both wearable sensors."
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

    if len(targets) < 2:
        missing = [name for name in DEVICE_NAMES if name not in targets]
        raise RuntimeError(f"Could not find both sensors. Missing: {missing}")

    c1 = BleakClient(targets[DEVICE_NAMES[0]], timeout=20, disconnected_callback=make_disconnect_callback(DEVICE_NAMES[0]), services=[SERVICE_UUID])
    c2 = BleakClient(targets[DEVICE_NAMES[1]], timeout=20, disconnected_callback=make_disconnect_callback(DEVICE_NAMES[1]), services=[SERVICE_UUID])
    clients = [c1, c2]
    client_map = get_client_map(clients)

    bg_task = asyncio.create_task(background_processing_task())

    try:
        await connect_client_with_retry(c1, DEVICE_NAMES[0])
        await asyncio.sleep(POST_CONNECT_STABILIZE_SEC)
        await connect_client_with_retry(c2, DEVICE_NAMES[1])
        await asyncio.sleep(POST_CONNECT_STABILIZE_SEC)

        # Subscribe to IMU stream notifications.
        await c1.start_notify(DATA_CHAR_UUID, notification_handler(DEVICE_NAMES[0]))
        await asyncio.sleep(0.3)
        await c2.start_notify(DATA_CHAR_UUID, notification_handler(DEVICE_NAMES[1]))
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

        # Run an automatic calibration sequence (static neutral capture + functional check)
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
