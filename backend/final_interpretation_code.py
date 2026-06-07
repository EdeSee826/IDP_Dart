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
import pandas as pd
from bleak import BleakClient, BleakScanner

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

SAMPLE_SIZE_BYTES = 36
SAMPLES_PER_NOTIFICATION = 5
EXPECTED_NOTIFICATION_BYTES = SAMPLE_SIZE_BYTES * SAMPLES_PER_NOTIFICATION

CMD_WRITE_WITH_RESPONSE = True
COMMAND_GAP_SEC = 0.15
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
WINDOW_SIZE = int(EXPECTED_FREQ * WINDOW_SEC)          
STRIDE = int(WINDOW_SIZE * (1 - OVERLAP))             

STABILIZATION_SEC = 3.0
STABILIZATION_SAMPLES = int(EXPECTED_FREQ * STABILIZATION_SEC)

RISKY_ACTIVITIES = {"elbow_flexion", "shoulder_adduction"}
RISKY_CONFIRM_WINDOWS = 3

MODEL_PATH = "svm_rfe_model (1).pkl"
SCALER_PATH = "scaler (1).pkl"

INTERPRETATION_CSV = f"interpretation_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"


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

paired_sample_buffer = deque(maxlen=WINDOW_SIZE)
new_samples_since_last_prediction = 0
paired_samples_seen = 0
risky_counter = 0

scaler = None
svm_rfe_model = None

timestamp_zero = None

result_csv_file = None
result_csv_writer = None

main_event_loop = None
data_ready_event = None


# ============================================================
# PART 5: LOAD TRAINED ML MODEL FILES
# ============================================================
def load_ml_objects():
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
def play_alert_sound():
    if WINDOWS_BEEP_AVAILABLE:
        winsound.Beep(500, 250)
    else:
        print("\a", end="")


# ============================================================
# PART 8: CSV LOGGING
# ============================================================
def init_result_csv():
    global result_csv_file, result_csv_writer
    result_csv_file = open(INTERPRETATION_CSV, "w", newline="", encoding="utf-8")
    result_csv_writer = csv.writer(result_csv_file)
    result_csv_writer.writerow([
        "raw_received_timestamp_ms", "feature_extraction_timestamp_ms", "model_prediction_timestamp_ms",
        "pair_seq", "predicted_activity", "risk_status",
        "alert_triggered", "risky_counter", "sensor1_neutral_ax", "sensor1_neutral_ay",
        "sensor1_neutral_az", "sensor2_neutral_ax", "sensor2_neutral_ay", "sensor2_neutral_az",
    ])

def get_neutral_values_for_csv():
    """FIXED: Explicitly handles NoneType if static calibration is skipped."""
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
    if result_csv_writer is None: return
    n1, n2 = get_neutral_values_for_csv()
    result_csv_writer.writerow([
        raw_received_timestamp,
        feature_extraction_timestamp,
        model_prediction_timestamp,
        pair_seq_value,
        prediction,
        risk_status,
        "Yes" if alert_triggered else "No", counter,
        n1[0], n1[1], n1[2], n2[0], n2[1], n2[2],
    ])
    result_csv_file.flush()

def close_result_csv():
    global result_csv_file, result_csv_writer
    if result_csv_file is not None:
        result_csv_file.flush()
        result_csv_file.close()
    result_csv_file = None
    result_csv_writer = None


# ============================================================
# PART 9: BLE CLIENT HELPER FUNCTIONS
# ============================================================
def get_client_map(clients):
    return {name: client for name, client in zip(DEVICE_NAMES, clients)}

def get_connected_client_map(clients):
    return {name: client for name, client in get_client_map(clients).items() if client.is_connected}

def handle_disconnect(name):
    disconnected_devices.add(name)
    reset_stream_state()
    if disconnect_event is not None:
        try: disconnect_event.set()
        except Exception: pass

def reset_stream_state():
    global expected_seq, pair_seq, prev_mcu_diff, first_signed_mcu_diff
    global new_samples_since_last_prediction, paired_samples_seen, risky_counter
    global timestamp_zero

    expected_seq = pair_seq = 0
    prev_mcu_diff = first_signed_mcu_diff = None
    new_samples_since_last_prediction = paired_samples_seen = risky_counter = 0
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
    return False


# ============================================================
# PART 12: STATIC CALIBRATION
# ============================================================
async def run_static_calibration(client_map):
    print("\n========== STATIC CALIBRATION ==========")
    await send_to_all(client_map, b"CAL_NEUTRAL")
    await asyncio.sleep(12.0)
    await ensure_clients_connected(client_map, stage="static calibration")
    await send_to_all(client_map, b"GET_NEUTRAL")
    await asyncio.sleep(1.0)
    print("Static calibration step completed.\n")

async def optional_static_calibration(client_map):
    choice = input("Run static neutral-pose calibration before live prediction? (y/n): ").strip().lower()
    if choice == "y": await run_static_calibration(client_map)


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
            f"[raw={raw_received_timestamp}] [features={feature_extraction_timestamp}] "
            f"[model={model_prediction_timestamp}] Activity: {prediction} | "
            f"Status: RISKY EVENT DETECTED | Alert: Beep"
        )
    else:
        print(
            f"[raw={raw_received_timestamp}] [features={feature_extraction_timestamp}] "
            f"[model={model_prediction_timestamp}] Activity: {prediction} | "
            f"Status: {risk_status} | Alert: No"
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
    await send_to_all(client_map, b"ARM", gap_sec=COMMAND_GAP_SEC)
    await asyncio.sleep(0.05)
    await send_to_all_parallel(client_map, f"START_AT,{START_ARM_DELAY_MS}".encode("ascii"))
    await asyncio.sleep(max(0.25, START_ARM_DELAY_MS / 1000.0 + 0.2))

async def stop_stream(client_map):
    connected = {name: client for name, client in client_map.items() if client.is_connected}
    if connected:
        await send_to_all(connected, b"STOP", gap_sec=STOP_GAP_SEC)
        await asyncio.sleep(0.3)

async def wait_for_enter():
    await asyncio.to_thread(input, "Press ENTER to stop real-time interpretation...\n")

async def run_interpretation_session(client_map):
    await ensure_clients_connected(client_map, stage="start")
    await optional_static_calibration(client_map)
    init_result_csv()
    await start_stream_synchronized(client_map)

    if disconnect_event is not None:
        enter_task = asyncio.create_task(wait_for_enter())
        disconnect_task = asyncio.create_task(disconnect_event.wait())
        done, pending = await asyncio.wait({enter_task, disconnect_task}, return_when=asyncio.FIRST_COMPLETED)
        for task in pending: task.cancel()
        if disconnect_task in done and disconnect_event.is_set():
            print(f"Disconnect detected: {sorted(disconnected_devices)}")
            return False
    else:
        await wait_for_enter()

    await stop_stream(client_map)
    close_result_csv()
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
            if client.is_connected:
                intentional_disconnects.add(name)
                await client.disconnect()
        except Exception: pass

    await asyncio.sleep(SHUTDOWN_SETTLE_SEC)
    close_result_csv()


# ============================================================
# PART 21: MAIN PROGRAM
# ============================================================
async def main():
    global disconnect_event, main_event_loop, data_ready_event
    
    main_event_loop = asyncio.get_running_loop()
    data_ready_event = asyncio.Event()
    disconnect_event = asyncio.Event()

    load_ml_objects()
    print("Scanning for devices...")
    devices = await BleakScanner.discover(timeout=10.0)
    targets = {d.name: d.address for d in devices if d.name in DEVICE_NAMES}

    if len(targets) < 2:
        print("ERROR: Could not find both sensors.")
        return

    c1 = BleakClient(targets[DEVICE_NAMES[0]], timeout=20, disconnected_callback=make_disconnect_callback(DEVICE_NAMES[0]), services=[SERVICE_UUID])
    c2 = BleakClient(targets[DEVICE_NAMES[1]], timeout=20, disconnected_callback=make_disconnect_callback(DEVICE_NAMES[1]), services=[SERVICE_UUID])
    clients = [c1, c2]
    client_map = get_client_map(clients)

    bg_task = asyncio.create_task(background_processing_task())

    try:
        await c1.connect()
        await asyncio.sleep(POST_CONNECT_STABILIZE_SEC)
        await c2.connect()
        await asyncio.sleep(POST_CONNECT_STABILIZE_SEC)

        await c1.start_notify(DATA_CHAR_UUID, notification_handler(DEVICE_NAMES[0]))
        await asyncio.sleep(0.3)
        await c2.start_notify(DATA_CHAR_UUID, notification_handler(DEVICE_NAMES[1]))
        await asyncio.sleep(0.3)

        await run_interpretation_session(client_map)
    finally:
        bg_task.cancel()
        await cleanup_clients(clients)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Program stopped by user.")