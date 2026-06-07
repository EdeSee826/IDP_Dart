# ============================================================
# PART 1: IMPORT LIBRARIES
# ============================================================
import asyncio
import csv
import os
import pickle
import struct
import time
import warnings
from collections import deque
from datetime import datetime

import numpy as np
from bleak import BleakClient, BleakScanner

try:
    import winsound
    WINDOWS_BEEP_AVAILABLE = True
except ImportError:
    WINDOWS_BEEP_AVAILABLE = False


# ============================================================
# PART 2: BLE CONFIGURATION - MCU2 ONLY
# ============================================================
SERVICE_UUID = "1841"
DATA_CHAR_UUID = "FFF1"
COMMAND_CHAR_UUID = "FFF2"

# Single sensor only: MCU2 / wrist sensor
DEVICE_NAME = "XIAO_MG24_Sensor_02"
EXPECTED_HEADER = "im02"
STATUS_HEADER = "st02"
NEUTRAL_HEADER = "nt02"

SAMPLE_SIZE_BYTES = 36
SAMPLES_PER_NOTIFICATION = 5
EXPECTED_NOTIFICATION_BYTES = SAMPLE_SIZE_BYTES * SAMPLES_PER_NOTIFICATION

CMD_WRITE_WITH_RESPONSE = True
POST_CONNECT_STABILIZE_SEC = 1.0
START_ARM_DELAY_MS = 1200
STOP_GAP_SEC = 0.05
SHUTDOWN_SETTLE_SEC = 3.0


# ============================================================
# PART 3: REAL-TIME ML CONFIGURATION
# ============================================================
EXPECTED_FREQ = 50
WINDOW_SEC = 1
OVERLAP = 0.75
WINDOW_SIZE = int(EXPECTED_FREQ * WINDOW_SEC)          # 50 samples for 1 second
STRIDE = int(WINDOW_SIZE * (1 - OVERLAP))             # 12 samples with 75% overlap

STABILIZATION_SEC = 3.0
STABILIZATION_SAMPLES = int(EXPECTED_FREQ * STABILIZATION_SEC)

RISKY_ACTIVITIES = {"elbow_flexion", "shoulder_adduction"}
RISKY_CONFIRM_WINDOWS = 3

MODEL_PATH = "svm_rfe_model (1).pkl"
SCALER_PATH = "scaler (1).pkl"

INTERPRETATION_CSV = f"single_sensor_interpretation_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"


# ============================================================
# PART 4: GLOBAL STATE VARIABLES
# ============================================================
sample_queue = deque()
window_buffer = deque(maxlen=WINDOW_SIZE)

expected_seq = None
sample_counter = 0
new_samples_since_last_prediction = 0
samples_seen = 0
risky_counter = 0

pc_zero = time.perf_counter()
timestamp_zero = None

neutral_vector = None

scaler = None
svm_rfe_model = None

result_csv_file = None
result_csv_writer = None

main_event_loop = None
data_ready_event = None
disconnect_event = None
intentional_disconnect = False


# ============================================================
# PART 5: LOAD TRAINED ML MODEL FILES
# ============================================================
def load_ml_objects():
    """Load saved scaler and trained SVM-RFE model."""
    global scaler, svm_rfe_model

    if not os.path.exists(SCALER_PATH):
        raise FileNotFoundError(f"Missing file: {SCALER_PATH}")

    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(f"Missing file: {MODEL_PATH}")

    with open(SCALER_PATH, "rb") as f:
        scaler = pickle.load(f)

    with open(MODEL_PATH, "rb") as f:
        svm_rfe_model = pickle.load(f)

    print("ML files loaded successfully.")
    print("Single-sensor model should expect 30 features if using mean, std, min, max, energy.")


# ============================================================
# PART 6: FEATURE DESCRIPTION - MCU2 ONLY
# ============================================================
def generate_feature_names_for_reference():
    """
    This function is only for explanation/reference.
    The model prediction uses NumPy array order directly.
    """
    axes = ["mcu2_ax", "mcu2_ay", "mcu2_az", "mcu2_gx", "mcu2_gy", "mcu2_gz"]
    columns = []

    for stat in ["mean", "std", "min", "max"]:
        for axis in axes:
            columns.append(f"{axis}_{stat}")

    for axis in axes:
        columns.append(f"{axis}_energy")

    return columns


# ============================================================
# PART 7: COMPUTER BEEP ALERT
# ============================================================
def play_alert_sound():
    """Produce a short computer beep alert."""
    if WINDOWS_BEEP_AVAILABLE:
        winsound.Beep(500, 250)
    else:
        print("\a", end="")


# ============================================================
# PART 8: CSV LOGGING
# ============================================================
def init_result_csv():
    """Create CSV file for final interpretation result."""
    global result_csv_file, result_csv_writer

    result_csv_file = open(INTERPRETATION_CSV, "w", newline="", encoding="utf-8")
    result_csv_writer = csv.writer(result_csv_file)

    result_csv_writer.writerow([
        "raw_received_timestamp_ms",
        "feature_extraction_timestamp_ms",
        "model_prediction_timestamp_ms",
        "sample_counter",
        "last_sample_seq",
        "predicted_activity",
        "risk_status",
        "alert_triggered",
        "risky_counter",
        "sensor2_neutral_ax",
        "sensor2_neutral_ay",
        "sensor2_neutral_az",
    ])

    print(f"Interpretation CSV will be saved as: {INTERPRETATION_CSV}")


def get_neutral_values_for_csv():
    """Return neutral calibration values if available."""
    if neutral_vector is None:
        return "", "", ""
    return neutral_vector


def log_prediction(
    raw_received_timestamp,
    feature_extraction_timestamp,
    model_prediction_timestamp,
    sample_counter_value,
    last_sample_seq,
    prediction,
    risk_status,
    alert_triggered,
    counter,
):
    """Save one prediction row into CSV."""
    if result_csv_writer is None:
        return

    n_ax, n_ay, n_az = get_neutral_values_for_csv()

    result_csv_writer.writerow([
        raw_received_timestamp,
        feature_extraction_timestamp,
        model_prediction_timestamp,
        sample_counter_value,
        last_sample_seq,
        prediction,
        risk_status,
        "Yes" if alert_triggered else "No",
        counter,
        n_ax,
        n_ay,
        n_az,
    ])

    result_csv_file.flush()


def close_result_csv():
    """Close CSV safely."""
    global result_csv_file, result_csv_writer

    if result_csv_file is not None:
        result_csv_file.flush()
        result_csv_file.close()
        print(f"Interpretation CSV saved: {INTERPRETATION_CSV}")

    result_csv_file = None
    result_csv_writer = None


# ============================================================
# PART 9: RESET AND TIMESTAMP HELPERS
# ============================================================
def reset_stream_state():
    """Reset buffers and counters before streaming starts."""
    global expected_seq, sample_counter, new_samples_since_last_prediction
    global samples_seen, risky_counter, timestamp_zero

    expected_seq = None
    sample_counter = 0
    new_samples_since_last_prediction = 0
    samples_seen = 0
    risky_counter = 0
    timestamp_zero = None

    sample_queue.clear()
    window_buffer.clear()


def format_timestamp_ms():
    """Return relative timestamp in milliseconds from first prediction."""
    global timestamp_zero

    now = time.perf_counter()

    if timestamp_zero is None:
        timestamp_zero = now
        return 0

    return int((now - timestamp_zero) * 1000)


# ============================================================
# PART 10: PACKET DECODING
# ============================================================
def decode_one_sample(sample_bytes):
    """
    Decode one 36-byte IMU sample.

    Format:
    - 4 bytes header
    - 4 bytes MCU time
    - 4 bytes global sequence
    - 6 floats: ax, ay, az, gx, gy, gz
    """
    if len(sample_bytes) != SAMPLE_SIZE_BYTES:
        return None

    header = sample_bytes[0:4].decode(errors="ignore")
    mcu_time = struct.unpack("<f", sample_bytes[4:8])[0]
    global_seq = struct.unpack("<I", sample_bytes[8:12])[0]
    imu = struct.unpack("<6f", sample_bytes[12:36])
    pc_time = (time.perf_counter() - pc_zero) * 1000.0

    return {
        "header": header,
        "mcu_time": mcu_time,
        "global_seq": global_seq,
        "pc_time": pc_time,
        "imu": imu,
    }


# ============================================================
# PART 11: SPECIAL PACKET HANDLING
# ============================================================
def handle_special_packet(decoded):
    """Handle status and neutral calibration packets."""
    global neutral_vector

    header = decoded["header"]
    imu = decoded["imu"]

    if header == STATUS_HEADER:
        return True

    if header == NEUTRAL_HEADER:
        neutral_vector = (imu[0], imu[1], imu[2])
        print(f"[MCU2][NEUTRAL] ax={imu[0]:.4f}, ay={imu[1]:.4f}, az={imu[2]:.4f}")
        return True

    return False


# ============================================================
# PART 12: STATIC CALIBRATION - MCU2 ONLY
# ============================================================
async def run_static_calibration(client):
    """Run static neutral-pose calibration on MCU2 only."""
    print("\n========== STATIC CALIBRATION: MCU2 ONLY ==========")
    print("Hold the MCU2 wrist sensor still in the standard neutral pose.")

    await send_to_one(client, b"CAL_NEUTRAL")
    await asyncio.sleep(12.0)

    if not client.is_connected:
        raise RuntimeError("MCU2 disconnected during static calibration.")

    await send_to_one(client, b"GET_NEUTRAL")
    await asyncio.sleep(1.0)

    print("Static calibration step completed.\n")


async def optional_static_calibration(client):
    """Ask whether to run static calibration before live prediction."""
    choice = input("Run static neutral-pose calibration before live prediction? (y/n): ").strip().lower()

    if choice == "y":
        await run_static_calibration(client)
    else:
        print("Static calibration skipped.\n")


# ============================================================
# PART 13: PREPROCESSING AND FEATURE EXTRACTION - MCU2 ONLY
# ============================================================
def preprocess_live_window(window_matrix):
    """
    Standardize MCU2 accelerometer and gyroscope groups separately.

    Input shape:
    - 50 samples x 6 axes

    Axis order:
    - ax, ay, az, gx, gy, gz
    """
    processed_window = np.copy(window_matrix)

    acc_indices = [0, 1, 2]
    gyro_indices = [3, 4, 5]

    acc_data = processed_window[:, acc_indices]
    gyro_data = processed_window[:, gyro_indices]

    acc_mean = np.mean(acc_data)
    acc_std = np.std(acc_data)
    gyro_mean = np.mean(gyro_data)
    gyro_std = np.std(gyro_data)

    if acc_std == 0:
        acc_std = 1e-6
    if gyro_std == 0:
        gyro_std = 1e-6

    processed_window[:, acc_indices] = (acc_data - acc_mean) / acc_std
    processed_window[:, gyro_indices] = (gyro_data - gyro_mean) / gyro_std

    return processed_window


def compute_energy_per_axis(window):
    """Compute energy for each of the 6 MCU2 axes."""
    return np.sum(np.square(window), axis=0)


def extract_live_features(window_matrix):
    """
    Extract features from one MCU2-only live window.

    Feature order:
    1. mean for 6 axes
    2. std for 6 axes
    3. min for 6 axes
    4. max for 6 axes
    5. energy for 6 axes

    Total = 30 features.
    """
    feats = []

    feats.extend(np.mean(window_matrix, axis=0))
    feats.extend(np.std(window_matrix, axis=0))
    feats.extend(np.min(window_matrix, axis=0))
    feats.extend(np.max(window_matrix, axis=0))
    feats.extend(compute_energy_per_axis(window_matrix))

    return np.array(feats, dtype=float)


# ============================================================
# PART 14: REAL-TIME PREDICTION
# ============================================================
def run_prediction_if_ready():
    """Run prediction when stabilization, window size, and stride conditions are satisfied."""
    global new_samples_since_last_prediction, risky_counter

    if samples_seen < STABILIZATION_SAMPLES:
        return

    if len(window_buffer) < WINDOW_SIZE:
        return

    if new_samples_since_last_prediction < STRIDE:
        return

    new_samples_since_last_prediction = 0

    raw_received_timestamp = format_timestamp_ms()

    window_matrix = np.array(window_buffer, dtype=float)
    cleaned_window = preprocess_live_window(window_matrix)

    feature_vector = extract_live_features(cleaned_window)
    feature_extraction_timestamp = format_timestamp_ms()

    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        features_scaled = scaler.transform(feature_vector.reshape(1, -1))
        prediction = svm_rfe_model.predict(features_scaled)[0]

    model_prediction_timestamp = format_timestamp_ms()

    if prediction in RISKY_ACTIVITIES:
        risky_counter += 1
        risk_status = "Risky"
    else:
        risky_counter = 0
        risk_status = "Safe"

    alert_triggered = False

    if risky_counter >= RISKY_CONFIRM_WINDOWS:
        alert_triggered = True
        play_alert_sound()
        print(
            f"[raw={raw_received_timestamp} ms] "
            f"[features={feature_extraction_timestamp} ms] "
            f"[model={model_prediction_timestamp} ms] "
            f"Activity: {prediction} | Status: RISKY EVENT DETECTED | Alert: Beep"
        )
    else:
        print(
            f"[raw={raw_received_timestamp} ms] "
            f"[features={feature_extraction_timestamp} ms] "
            f"[model={model_prediction_timestamp} ms] "
            f"Activity: {prediction} | Status: {risk_status} | Alert: No"
        )

    last_sample_seq = sample_counter

    log_prediction(
        raw_received_timestamp,
        feature_extraction_timestamp,
        model_prediction_timestamp,
        sample_counter,
        last_sample_seq,
        prediction,
        risk_status,
        alert_triggered,
        risky_counter,
    )


# ============================================================
# PART 15: PROCESS SINGLE SENSOR SAMPLES
# ============================================================
def process_samples_if_ready():
    """Move decoded MCU2 samples from queue into window buffer and run prediction."""
    global expected_seq, sample_counter, samples_seen, new_samples_since_last_prediction

    while sample_queue:
        sample = sample_queue.popleft()
        seq = sample["global_seq"]

        if expected_seq is None:
            expected_seq = seq

        if seq < expected_seq:
            continue

        if seq > expected_seq:
            expected_seq = seq

        expected_seq += 1
        sample_counter += 1
        samples_seen += 1
        new_samples_since_last_prediction += 1

        imu = sample["imu"]
        row = [imu[0], imu[1], imu[2], imu[3], imu[4], imu[5]]
        window_buffer.append(row)

        if samples_seen == STABILIZATION_SAMPLES:
            print("\nStabilization completed. Real-time prediction starts now.\n")

        run_prediction_if_ready()


# ============================================================
# PART 16: BLE NOTIFICATION HANDLER - MCU2 ONLY
# ============================================================
def notification_handler(sender, data):
    """Receive BLE notification from MCU2 and store decoded samples."""
    if len(data) != EXPECTED_NOTIFICATION_BYTES:
        return

    first_decoded = decode_one_sample(data[0:SAMPLE_SIZE_BYTES])
    if first_decoded is not None and handle_special_packet(first_decoded):
        return

    for i in range(SAMPLES_PER_NOTIFICATION):
        start = i * SAMPLE_SIZE_BYTES
        decoded = decode_one_sample(data[start:start + SAMPLE_SIZE_BYTES])

        if decoded is None:
            continue

        if decoded["header"] != EXPECTED_HEADER:
            continue

        decoded["sample_seq"] = decoded["global_seq"]
        sample_queue.append(decoded)

    if main_event_loop is not None and data_ready_event is not None:
        main_event_loop.call_soon_threadsafe(data_ready_event.set)


# ============================================================
# PART 17: BACKGROUND PROCESSING TASK
# ============================================================
async def background_processing_task():
    """Process queued samples outside the BLE callback to reduce latency."""
    while True:
        await data_ready_event.wait()
        data_ready_event.clear()

        try:
            process_samples_if_ready()
        except Exception as e:
            print(f"Error in background processing loop: {e}")

        await asyncio.sleep(0.001)


# ============================================================
# PART 18: BLE COMMANDS AND SESSION LOGIC
# ============================================================
def make_disconnect_callback():
    """Handle MCU2 disconnection."""
    def _cb(client):
        global intentional_disconnect

        if intentional_disconnect:
            intentional_disconnect = False
            return

        print("[MCU2] BLE disconnected unexpectedly.")
        reset_stream_state()

        if disconnect_event is not None:
            try:
                disconnect_event.set()
            except Exception:
                pass

    return _cb


async def send_to_one(client, cmd: bytes, *, response: bool | None = None):
    """Send command to MCU2."""
    if response is None:
        response = CMD_WRITE_WITH_RESPONSE

    if not client.is_connected:
        raise RuntimeError(f"MCU2 is disconnected before command {cmd!r}")

    try:
        await client.write_gatt_char(COMMAND_CHAR_UUID, cmd, response=response)
    except Exception:
        if response:
            await client.write_gatt_char(COMMAND_CHAR_UUID, cmd, response=False)
        else:
            raise


async def start_stream(client):
    """Start MCU2 streaming."""
    reset_stream_state()

    await send_to_one(client, b"ARM")
    await asyncio.sleep(0.05)

    start_cmd = f"START_AT,{START_ARM_DELAY_MS}".encode("ascii")
    await send_to_one(client, start_cmd, response=False)

    await asyncio.sleep(max(0.25, START_ARM_DELAY_MS / 1000.0 + 0.2))


async def stop_stream(client):
    """Stop MCU2 streaming."""
    if client.is_connected:
        await send_to_one(client, b"STOP")
        await asyncio.sleep(0.3)


async def wait_for_enter():
    """Wait until user presses ENTER to stop."""
    await asyncio.to_thread(input, "Press ENTER to stop real-time interpretation...\n")


async def run_interpretation_session(client):
    """Run the full real-time interpretation session."""
    if not client.is_connected:
        raise RuntimeError("MCU2 is not connected at session start.")

    await optional_static_calibration(client)
    init_result_csv()
    await start_stream(client)

    if disconnect_event is not None:
        enter_task = asyncio.create_task(wait_for_enter())
        disconnect_task = asyncio.create_task(disconnect_event.wait())

        done, pending = await asyncio.wait(
            {enter_task, disconnect_task},
            return_when=asyncio.FIRST_COMPLETED,
        )

        for task in pending:
            task.cancel()

        if disconnect_task in done and disconnect_event.is_set():
            print("Disconnect detected during streaming.")
            return False
    else:
        await wait_for_enter()

    await stop_stream(client)
    close_result_csv()
    return True


async def cleanup_client(client):
    """Stop notification and disconnect MCU2 safely."""
    global intentional_disconnect

    try:
        if client.is_connected:
            await stop_stream(client)
    except Exception:
        pass

    try:
        if client.is_connected:
            await client.stop_notify(DATA_CHAR_UUID)
    except Exception:
        pass

    try:
        if client.is_connected:
            intentional_disconnect = True
            await client.disconnect()
    except Exception:
        intentional_disconnect = False

    await asyncio.sleep(SHUTDOWN_SETTLE_SEC)
    close_result_csv()


# ============================================================
# PART 19: MAIN PROGRAM
# ============================================================
async def main():
    """Main program entry point."""
    global main_event_loop, data_ready_event, disconnect_event

    main_event_loop = asyncio.get_running_loop()
    data_ready_event = asyncio.Event()
    disconnect_event = asyncio.Event()

    load_ml_objects()

    print("Scanning for MCU2 sensor...")
    devices = await BleakScanner.discover(timeout=10.0)

    target_address = None
    for device in devices:
        if device.name:
            print(f"Detected: {device.name} -> {device.address}")

        if device.name == DEVICE_NAME:
            target_address = device.address

    if target_address is None:
        print("ERROR: Could not find MCU2 sensor.")
        return

    client = BleakClient(
        target_address,
        timeout=20,
        disconnected_callback=make_disconnect_callback(),
        services=[SERVICE_UUID],
    )

    bg_task = asyncio.create_task(background_processing_task())

    try:
        await client.connect()
        await asyncio.sleep(POST_CONNECT_STABILIZE_SEC)

        print(f"Connected to MCU2: {client.is_connected}")

        await client.start_notify(DATA_CHAR_UUID, notification_handler)
        await asyncio.sleep(0.3)

        await run_interpretation_session(client)

    finally:
        bg_task.cancel()
        await cleanup_client(client)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Program stopped by user.")
