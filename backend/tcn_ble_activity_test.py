"""
Standalone BLE test runner for tcn_activity.pt.

This script connects to the same two XIAO IMU sensors used by the main backend,
keeps the same synchronized sample pairing, converts live IMU samples into the
same channel format used during TCN training, sends the window to the model,
to a TCN model, and applies the same warning/confirmation alarm logic:

    - 50 Hz stream
    - model window/stride loaded from tcn_activity.pt when available
    - warning beep every 3 consecutive risky windows
    - confirmed risky event at 6 consecutive risky windows
    - standing resets immediately
    - other safe classes reset after 2 consecutive safe windows

It is intentionally not wired to Flask, Flutter, SQLite, CSV interpretation files,
or the retired feature extraction pipeline.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import os
import struct
import sys
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Any

try:
    import numpy as np
except ImportError as exc:  # pragma: no cover - runtime environment guard
    raise SystemExit("Missing dependency: numpy. Install it in the Python environment used to run this script.") from exc

try:
    import torch
    from torch import nn
except ImportError:  # pragma: no cover - runtime environment guard
    torch = None
    nn = None

try:
    from bleak import BleakClient, BleakScanner
except ImportError:  # pragma: no cover - runtime environment guard
    BleakClient = None
    BleakScanner = None

try:
    import winsound

    WINDOWS_BEEP_AVAILABLE = True
except ImportError:
    winsound = None
    WINDOWS_BEEP_AVAILABLE = False


# BLE configuration copied from the production backend.
SERVICE_UUID = "1841"
DATA_CHAR_UUID = "FFF1"
COMMAND_CHAR_UUID = "FFF2"

DEVICE_NAMES = ["XIAO_MG24_Sensor_01", "XIAO_MG24_Sensor_02"]
EXPECTED_HEADER = {
    "XIAO_MG24_Sensor_01": "im01",
    "XIAO_MG24_Sensor_02": "im02",
}
SPECIAL_HEADERS = {
    "XIAO_MG24_Sensor_01": {"st01", "nt01", "va01", "fp01", "fe01", "fs01"},
    "XIAO_MG24_Sensor_02": {"st02", "nt02", "va02", "fp02", "fe02", "fs02"},
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
SHUTDOWN_SETTLE_SEC = 0.8


# Real-time prediction and alarm configuration copied from the production backend.
EXPECTED_FREQ = 50
WINDOW_SEC = 1
OVERLAP = 0.75
WINDOW_SIZE = int(EXPECTED_FREQ * WINDOW_SEC)
STRIDE = int(WINDOW_SIZE * (1 - OVERLAP))

DEFAULT_STABILIZATION_SEC = 3.0
RISKY_ACTIVITIES = {"elbow_flexion", "shoulder_adduction", "shoulder_abduction_adduction"}
RISKY_BEEP_INTERVAL_WINDOWS = 3
RISKY_CONFIRM_WINDOWS = 6
SAFE_RESET_WINDOWS = 2

DEFAULT_LABELS = [
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
    "mcu1_gyro_rms_05s", "mcu2_gyro_rms_05s",
    "mcu1_acc_jerk", "mcu2_acc_jerk",
]
TRAINING_CHANNELS = RAW_CHANNELS + DERIVED_CHANNELS


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_MODEL_PATH = BASE_DIR.parent / "tcn_activity.pt"


pc_zero = time.perf_counter()
main_event_loop: asyncio.AbstractEventLoop | None = None
data_ready_event: asyncio.Event | None = None
disconnect_event: asyncio.Event | None = None

sample_queues = {name: deque() for name in DEVICE_NAMES}
paired_sample_buffer: deque[list[float]] = deque(maxlen=WINDOW_SIZE)
data_char_by_device: dict[str, Any] = {}
command_char_by_device: dict[str, Any] = {}
rx_byte_buffers = {name: bytearray() for name in DEVICE_NAMES}
notification_stats = {
    name: {
        "notifications": 0,
        "bytes": 0,
        "samples": 0,
        "special_packets": 0,
        "ignored_chunks": 0,
        "last_len": 0,
        "last_header": "",
        "last_at": 0.0,
    }
    for name in DEVICE_NAMES
}

expected_seq = 0
pair_seq = 0
new_samples_since_last_prediction = 0
paired_samples_seen = 0
prediction_count = 0
risky_counter = 0
active_risky_class: str | None = None
safe_counter = 0

model: Any = None
model_labels: list[str] = []
risky_activity_labels: set[str] = set()
model_input_channels: int | None = None
model_channel_names: list[str] | None = None
model_mean: np.ndarray | None = None
model_std: np.ndarray | None = None
active_window_size = WINDOW_SIZE
active_stride = STRIDE
input_layout = "channels_first"
window_zscore = False
use_checkpoint_normalization = True
stabilization_samples = int(DEFAULT_STABILIZATION_SEC * EXPECTED_FREQ)

alert_sound_lock = threading.Lock()
csv_writer: csv.DictWriter[str] | None = None
csv_file_handle: Any = None


def format_timestamp() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


def play_alert_sound() -> None:
    if WINDOWS_BEEP_AVAILABLE and winsound is not None:
        winsound.Beep(500, 100)
    else:
        print("\a", end="", flush=True)


def play_alert_sound_async() -> bool:
    """Play one non-blocking beep and discard overlapping stale beep requests."""
    if not alert_sound_lock.acquire(blocking=False):
        return False

    def _play_and_release() -> None:
        try:
            play_alert_sound()
        finally:
            alert_sound_lock.release()

    threading.Thread(target=_play_and_release, daemon=True).start()
    return True


def normalize_activity_label(label: str) -> str:
    return str(label).strip().lower().replace(" ", "_").replace("-", "_")


def require_runtime_dependencies() -> None:
    missing = []
    if torch is None:
        missing.append("torch")
    if nn is None:
        missing.append("torch.nn")
    if BleakScanner is None or BleakClient is None:
        missing.append("bleak")
    if missing:
        raise RuntimeError(
            "Missing dependency/dependencies: "
            + ", ".join(missing)
            + ". Install them in the Python environment used to run this script."
        )


if nn is not None:
    class Block(nn.Module):
        def __init__(self, width: int, dilation: int) -> None:
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

        def forward(self, x: Any) -> Any:
            return x + self.net(x)


    class TCN(nn.Module):
        def __init__(self, input_channels: int | None = None, output_classes: int = 6) -> None:
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

        def forward(self, x: Any) -> Any:
            return self.head(self.tcn(x).mean(-1))
else:
    TCN = None


def load_tcn_model(model_path: Path) -> Any:
    if torch is None:
        raise RuntimeError("torch is not available.")
    if not model_path.exists():
        raise FileNotFoundError(f"TCN model file not found: {model_path}")

    try:
        loaded_model = torch.jit.load(str(model_path), map_location="cpu")
        loaded_model.eval()
        print(f"[MODEL] Loaded TorchScript model: {model_path}")
        return loaded_model
    except Exception as jit_error:
        try:
            try:
                loaded_model = torch.load(str(model_path), map_location="cpu", weights_only=False)
            except TypeError:
                loaded_model = torch.load(str(model_path), map_location="cpu")
        except Exception as load_error:
            raise RuntimeError(
                "Unable to load tcn_activity.pt as TorchScript or a full PyTorch module. "
                "If this file is only a state_dict, the original TCN class definition is needed."
            ) from load_error

        if isinstance(loaded_model, dict):
            state_dict = loaded_model.get("state_dict") or loaded_model.get("model_state_dict")
            if state_dict is None:
                keys_preview = ", ".join(list(loaded_model.keys())[:6])
                raise RuntimeError(
                    "tcn_activity.pt looks like a dictionary, but it does not contain a state_dict. "
                    f"First keys: {keys_preview}"
                ) from jit_error

            checkpoint_labels = loaded_model.get("labels")
            checkpoint_channels = loaded_model.get("channels")
            output_classes = len(checkpoint_labels) if isinstance(checkpoint_labels, (list, tuple)) and checkpoint_labels else 6
            input_channels = len(checkpoint_channels) if isinstance(checkpoint_channels, (list, tuple)) and checkpoint_channels else None
            if input_channels is None:
                first_weight = state_dict.get("tcn.0.weight") if isinstance(state_dict, dict) else None
                if first_weight is None:
                    first_weight = state_dict.get("module.tcn.0.weight") if isinstance(state_dict, dict) else None
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
                "sample_rate": loaded_model.get("sample_rate"),
                "stride": loaded_model.get("stride"),
            }
            print(f"[MODEL] Rebuilt TCN from checkpoint state_dict: {model_path}")
            return rebuilt_model

        if not callable(loaded_model):
            raise RuntimeError(f"Loaded object is not callable: {type(loaded_model)!r}") from jit_error

        loaded_model.eval()
        print(f"[MODEL] Loaded PyTorch module: {model_path}")
        return loaded_model


def infer_model_input_channels(loaded_model: Any) -> int | None:
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


def infer_model_channel_names(loaded_model: Any) -> list[str] | None:
    metadata = getattr(loaded_model, "tcn_metadata", None)
    if not isinstance(metadata, dict):
        return None
    channels = metadata.get("channels")
    if isinstance(channels, (list, tuple)) and channels:
        return [str(channel) for channel in channels]
    return None


def metadata_array(loaded_model: Any, key: str) -> np.ndarray | None:
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


def metadata_int(loaded_model: Any, key: str) -> int | None:
    metadata = getattr(loaded_model, "tcn_metadata", None)
    if not isinstance(metadata, dict) or metadata.get(key) is None:
        return None
    value = metadata[key]
    if torch is not None and torch.is_tensor(value):
        value = value.item()
    return int(value)


def decode_one_sample(sample_bytes: bytes) -> dict[str, Any] | None:
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


def reset_stream_state() -> None:
    global paired_sample_buffer
    global expected_seq, pair_seq, new_samples_since_last_prediction, paired_samples_seen
    global prediction_count, risky_counter, active_risky_class, safe_counter

    expected_seq = 0
    pair_seq = 0
    new_samples_since_last_prediction = 0
    paired_samples_seen = 0
    prediction_count = 0
    risky_counter = 0
    active_risky_class = None
    safe_counter = 0

    paired_sample_buffer.clear()
    for queue in sample_queues.values():
        queue.clear()
    for buffer in rx_byte_buffers.values():
        buffer.clear()
    for stats in notification_stats.values():
        stats.update(
            {
                "notifications": 0,
                "bytes": 0,
                "samples": 0,
                "special_packets": 0,
                "ignored_chunks": 0,
                "last_len": 0,
                "last_header": "",
                "last_at": 0.0,
            }
        )


def make_disconnect_callback(device_name: str):
    def callback(_client: Any) -> None:
        print(f"[BLE] Disconnected: {device_name}")
        reset_stream_state()
        if disconnect_event is not None:
            disconnect_event.set()

    return callback


def short_uuid_matches(actual_uuid: str, wanted_uuid: str) -> bool:
    actual = actual_uuid.lower()
    wanted = wanted_uuid.lower()
    return actual == wanted or actual.startswith(f"0000{wanted}-")


def print_gatt_summary(client: Any, device_name: str) -> None:
    print(f"[BLE] GATT characteristics discovered for {device_name}:")
    try:
        for service in client.services:
            print(f"  service {service.uuid}")
            for char in service.characteristics:
                props = ",".join(char.properties)
                print(f"    char {char.uuid} [{props}]")
    except Exception as error:
        print(f"  unable to read services: {type(error).__name__}: {error}")


def resolve_characteristic(client: Any, device_name: str, wanted_uuid: str, purpose: str) -> Any:
    for service in client.services:
        for char in service.characteristics:
            if short_uuid_matches(char.uuid, wanted_uuid):
                return char

    print_gatt_summary(client, device_name)
    raise RuntimeError(
        f"{purpose} characteristic {wanted_uuid} was not found on {device_name}. "
        "If you just uploaded new firmware, remove the device from Windows Bluetooth settings, "
        "power-cycle the XIAO board, and scan again so Windows refreshes its cached GATT table."
    )


def build_training_channel_matrix(window_matrix: np.ndarray) -> dict[str, np.ndarray]:
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
            # Match training exactly: relative = x[:, 6:12] - x[:, 0:6],
            # meaning sensor 2 minus sensor 1.
            "rel_ax": window_matrix[:, 6] - window_matrix[:, 0],
            "rel_ay": window_matrix[:, 7] - window_matrix[:, 1],
            "rel_az": window_matrix[:, 8] - window_matrix[:, 2],
            "rel_gx": window_matrix[:, 9] - window_matrix[:, 3],
            "rel_gy": window_matrix[:, 10] - window_matrix[:, 4],
            "rel_gz": window_matrix[:, 11] - window_matrix[:, 5],
        }
    )

    kernel = np.ones(25, dtype=np.float32) / 25.0
    channel_map["mcu1_gyro_rms_05s"] = np.sqrt(np.convolve(channel_map["mcu1_gyro_mag"] ** 2, kernel, mode="same"))
    channel_map["mcu2_gyro_rms_05s"] = np.sqrt(np.convolve(channel_map["mcu2_gyro_mag"] ** 2, kernel, mode="same"))
    channel_map["mcu1_acc_jerk"] = np.r_[0.0, np.linalg.norm(np.diff(mcu1_acc, axis=0), axis=1)]
    channel_map["mcu2_acc_jerk"] = np.r_[0.0, np.linalg.norm(np.diff(mcu2_acc, axis=0), axis=1)]
    return {name: np.asarray(values, dtype=np.float32) for name, values in channel_map.items()}


def expand_raw_to_training_channels(window_matrix: np.ndarray, channel_names: list[str]) -> np.ndarray:
    channel_map = build_training_channel_matrix(window_matrix)
    missing = [name for name in channel_names if name not in channel_map]
    if missing:
        raise RuntimeError(f"Cannot build live TCN channels missing from training map: {missing}")
    return np.column_stack([channel_map[name] for name in channel_names]).astype(np.float32)


def coerce_window_to_model_channels(window_matrix: np.ndarray) -> np.ndarray:
    expected_channels = model_input_channels or window_matrix.shape[1]
    actual_channels = window_matrix.shape[1]

    if actual_channels == expected_channels:
        return window_matrix

    if actual_channels == 12 and expected_channels in {22, 26}:
        channel_names = model_channel_names
        if not channel_names:
            channel_names = TRAINING_CHANNELS[:expected_channels]
        expanded = expand_raw_to_training_channels(window_matrix, channel_names)
        if not getattr(coerce_window_to_model_channels, "_printed_training_notice", False):
            print(
                f"[MODEL] Live input expanded from 12 raw IMU channels to {expected_channels} TCN channels "
                "using the saved training channel order."
            )
            coerce_window_to_model_channels._printed_training_notice = True
        return expanded

    raise RuntimeError(
        f"TCN model expects {expected_channels} channels, but live data has {actual_channels}. "
        "This script currently supports raw 12-channel input or derived 22/26-channel training input."
    )


def prepare_tcn_input(window_matrix: np.ndarray) -> Any:
    if torch is None:
        raise RuntimeError("torch is not available.")

    x = coerce_window_to_model_channels(window_matrix.astype(np.float32, copy=True))

    if use_checkpoint_normalization and model_mean is not None and model_std is not None:
        if model_mean.shape[-1] != x.shape[1] or model_std.shape[-1] != x.shape[1]:
            raise RuntimeError(
                f"Saved normalization has {model_mean.shape[-1]} channels, but live input has {x.shape[1]} channels."
            )
        x = (x - model_mean) / np.where(model_std < 1e-6, 1.0, model_std)
    elif window_zscore:
        mean = x.mean(axis=0, keepdims=True)
        std = x.std(axis=0, keepdims=True)
        x = (x - mean) / np.where(std < 1e-6, 1.0, std)

    if input_layout == "channels_first":
        # TCN convention: batch, channels, time.
        x = x.T[None, :, :]
    elif input_layout == "time_first":
        # Alternative convention: batch, time, channels = 1 x 50 x 12.
        x = x[None, :, :]
    else:
        raise ValueError(f"Unsupported input layout: {input_layout}")

    return torch.from_numpy(x)


def decode_prediction(output: Any) -> tuple[str, int, float | None, str]:
    if torch is None:
        raise RuntimeError("torch is not available.")

    if isinstance(output, (tuple, list)):
        output = output[0]
    if not torch.is_tensor(output):
        output = torch.as_tensor(output)

    output = output.detach().cpu()
    if output.ndim == 3:
        # Some sequence classifiers return batch, classes, time.
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
        label = model_labels[class_index] if class_index < len(model_labels) else f"class_{class_index}"
        top_parts.append(f"{label}:{float(value.item()):.2f}")
    top_summary = ", ".join(top_parts)

    if pred_idx < len(model_labels):
        prediction = model_labels[pred_idx]
    else:
        prediction = f"class_{pred_idx}"

    return prediction, pred_idx, confidence, top_summary


def update_alarm_state(prediction: str) -> tuple[str, bool, bool]:
    global risky_counter, active_risky_class, safe_counter

    normalized_prediction = normalize_activity_label(prediction)

    if normalized_prediction in risky_activity_labels:
        if normalized_prediction == active_risky_class:
            risky_counter += 1
        else:
            active_risky_class = normalized_prediction
            risky_counter = 1
        safe_counter = 0
        risk_status = "Risky"
    else:
        if normalized_prediction == "standing":
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
        normalized_prediction in risky_activity_labels
        and normalized_prediction == active_risky_class
    )
    alert_triggered = (
        current_prediction_is_active_risk and risky_counter == RISKY_CONFIRM_WINDOWS
    )
    beep_triggered = (
        current_prediction_is_active_risk
        and risky_counter > 0
        and risky_counter % RISKY_BEEP_INTERVAL_WINDOWS == 0
    )

    if beep_triggered:
        beep_triggered = play_alert_sound_async()

    return risk_status, beep_triggered, alert_triggered


def run_prediction_if_ready() -> None:
    global new_samples_since_last_prediction, prediction_count

    if paired_samples_seen < stabilization_samples:
        return
    if len(paired_sample_buffer) < active_window_size:
        return
    if new_samples_since_last_prediction < active_stride:
        return

    new_samples_since_last_prediction = 0
    raw_timestamp = format_timestamp()
    window_matrix = np.array(paired_sample_buffer, dtype=np.float32)

    tensor = prepare_tcn_input(window_matrix)
    inference_start = time.perf_counter()
    if torch is None:
        raise RuntimeError("torch is not available.")
    with torch.no_grad():
        output = model(tensor)
    inference_ms = (time.perf_counter() - inference_start) * 1000.0

    prediction, pred_idx, confidence, top_summary = decode_prediction(output)
    prediction_count += 1
    prediction_timestamp = format_timestamp()
    risk_status, beep_triggered, alert_triggered = update_alarm_state(prediction)

    if csv_writer is not None:
        csv_writer.writerow(
            {
                "timestamp": prediction_timestamp,
                "raw_window_timestamp": raw_timestamp,
                "paired_samples_seen": paired_samples_seen,
                "prediction": prediction,
                "prediction_index": pred_idx,
                "confidence": f"{confidence:.4f}" if confidence is not None else "",
                "risk_status": risk_status,
                "active_risky_class": active_risky_class or "",
                "risky_counter": risky_counter,
                "top_predictions": top_summary,
                "beep_triggered": int(beep_triggered),
                "confirmed_risky_event": int(alert_triggered),
                "inference_ms": f"{inference_ms:.3f}",
            }
        )
        if csv_file_handle is not None:
            csv_file_handle.flush()

    if alert_triggered:
        status_text = "RISKY EVENT CONFIRMED"
    elif risk_status == "Risky":
        status_text = f"Risk warning {risky_counter}/{RISKY_CONFIRM_WINDOWS}"
    else:
        status_text = "Safe"

    print(
        f"[{prediction_timestamp}] Activity={prediction} "
        f"(idx={pred_idx}, conf={confidence:.2f}) | "
        f"{status_text} | Counter={risky_counter} | "
        f"ActiveRisk={active_risky_class or '-'} | "
        f"Top=[{top_summary}] | "
        f"Beep={'yes' if beep_triggered else 'no'} | "
        f"Inference={inference_ms:.1f} ms"
    )


def pair_samples_if_ready() -> None:
    global expected_seq, pair_seq, new_samples_since_last_prediction, paired_samples_seen

    q1 = sample_queues["XIAO_MG24_Sensor_01"]
    q2 = sample_queues["XIAO_MG24_Sensor_02"]

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
            if s1_head < expected_seq:
                q1.popleft()
            if s2_head < expected_seq:
                q2.popleft()
            continue

        pair_seq += 1

        if s1 is not None and s2 is not None:
            paired_row = [
                s1["imu"][0],
                s1["imu"][1],
                s1["imu"][2],
                s1["imu"][3],
                s1["imu"][4],
                s1["imu"][5],
                s2["imu"][0],
                s2["imu"][1],
                s2["imu"][2],
                s2["imu"][3],
                s2["imu"][4],
                s2["imu"][5],
            ]
            paired_sample_buffer.append(paired_row)
            paired_samples_seen += 1
            new_samples_since_last_prediction += 1

            if paired_samples_seen == stabilization_samples:
                print("\n[STREAM] Stabilization completed. TCN prediction starts now.\n")

            run_prediction_if_ready()


def notification_handler(device_name: str):
    def handler(_sender: Any, data: bytearray) -> None:
        stats = notification_stats[device_name]
        stats["notifications"] += 1
        stats["bytes"] += len(data)
        stats["last_len"] = len(data)
        stats["last_at"] = time.perf_counter()

        if stats["notifications"] <= 5 or len(data) != EXPECTED_NOTIFICATION_BYTES:
            preview_header = bytes(data[:4]).decode(errors="ignore") if len(data) >= 4 else ""
            print(
                f"[RX] {device_name}: notification #{stats['notifications']} "
                f"len={len(data)} first4={preview_header!r}"
            )

        buffer = rx_byte_buffers[device_name]
        buffer.extend(data)
        appended = 0

        while len(buffer) >= SAMPLE_SIZE_BYTES:
            chunk = bytes(buffer[:SAMPLE_SIZE_BYTES])
            del buffer[:SAMPLE_SIZE_BYTES]
            decoded = decode_one_sample(chunk)
            if decoded is None:
                stats["ignored_chunks"] += 1
                continue
            stats["last_header"] = decoded["header"]
            if decoded["header"] in SPECIAL_HEADERS[device_name]:
                stats["special_packets"] += 1
                # Your Arduino sends special packets as a 180-byte payload with
                # one real 36-byte record and four zero-padded records.
                if len(data) == EXPECTED_NOTIFICATION_BYTES and len(buffer) >= EXPECTED_NOTIFICATION_BYTES - SAMPLE_SIZE_BYTES:
                    del buffer[: EXPECTED_NOTIFICATION_BYTES - SAMPLE_SIZE_BYTES]
                continue
            if decoded["header"] != EXPECTED_HEADER[device_name]:
                stats["ignored_chunks"] += 1
                continue
            decoded["sample_seq"] = decoded["global_seq"]
            sample_queues[device_name].append(decoded)
            stats["samples"] += 1
            appended += 1

        if appended and main_event_loop is not None and data_ready_event is not None:
            main_event_loop.call_soon_threadsafe(data_ready_event.set)

    return handler


async def background_processing_task() -> None:
    if data_ready_event is None:
        raise RuntimeError("data_ready_event was not initialized.")

    while True:
        await data_ready_event.wait()
        data_ready_event.clear()
        try:
            pair_samples_if_ready()
        except Exception as error:
            print(f"[ERROR] Background processing failed: {type(error).__name__}: {error}")
        await asyncio.sleep(0.001)


async def stream_monitor_task() -> None:
    while True:
        await asyncio.sleep(2.0)
        age_parts = []
        now = time.perf_counter()
        for name in DEVICE_NAMES:
            stats = notification_stats[name]
            last_at = float(stats["last_at"])
            age = (now - last_at) if last_at else None
            age_text = f"{age:.1f}s ago" if age is not None else "never"
            age_parts.append(
                f"{name}: notif={stats['notifications']} samples={stats['samples']} "
                f"special={stats['special_packets']} ignored={stats['ignored_chunks']} last_len={stats['last_len']} "
                f"last_header={stats['last_header'] or '-'} last={age_text}"
            )
        print(
            "[STREAM] "
            f"paired={paired_samples_seen} predictions={prediction_count} "
            f"window={len(paired_sample_buffer)}/{active_window_size} "
            f"new_since_pred={new_samples_since_last_prediction}/{active_stride} "
            f"q1={len(sample_queues[DEVICE_NAMES[0]])} q2={len(sample_queues[DEVICE_NAMES[1]])}"
        )
        for part in age_parts:
            print(f"[STREAM] {part}")


async def connect_client_with_retry(client: Any, device_name: str) -> None:
    last_error = None
    for attempt in range(1, BLE_CONNECT_RETRIES + 1):
        try:
            print(f"[BLE] Connecting {device_name} (attempt {attempt}/{BLE_CONNECT_RETRIES})...")
            await client.connect()
            if client.is_connected:
                print(f"[BLE] Connected {device_name}.")
                return
        except Exception as error:
            last_error = error
            print(f"[BLE] {device_name} connection attempt failed: {type(error).__name__}: {error}")
            try:
                if client.is_connected:
                    await client.disconnect()
            except Exception:
                pass
        if attempt < BLE_CONNECT_RETRIES:
            await asyncio.sleep(BLE_CONNECT_RETRY_DELAY_SEC)

    raise RuntimeError(f"Unable to connect {device_name} after {BLE_CONNECT_RETRIES} attempts") from last_error


async def send_to_one(client: Any, device_name: str, cmd: bytes, *, response: bool | None = None) -> None:
    if response is None:
        response = CMD_WRITE_WITH_RESPONSE
    command_char = command_char_by_device.get(device_name, COMMAND_CHAR_UUID)
    try:
        await client.write_gatt_char(command_char, cmd, response=response)
    except Exception:
        if response:
            await client.write_gatt_char(command_char, cmd, response=False)
        else:
            raise


async def send_to_all(client_map: dict[str, Any], cmd: bytes, *, gap_sec: float = COMMAND_GAP_SEC) -> None:
    for device_name in [name for name in DEVICE_NAMES if name in client_map]:
        await send_to_one(client_map[device_name], device_name, cmd)
        if gap_sec > 0:
            await asyncio.sleep(gap_sec)


async def send_to_all_parallel(client_map: dict[str, Any], cmd: bytes) -> None:
    tasks = [
        send_to_one(client_map[name], name, cmd, response=False)
        for name in DEVICE_NAMES
        if name in client_map
    ]
    await asyncio.gather(*tasks)


async def start_stream_synchronized(client_map: dict[str, Any]) -> None:
    reset_stream_state()
    print("[BLE] Sending ARM_START to both sensors...")
    await send_to_all(client_map, b"ARM_START", gap_sec=COMMAND_GAP_SEC)
    await asyncio.sleep(START_ARM_DELAY_MS / 1000.0)
    print("[BLE] Sending FIRE_START to both sensors...")
    # Your firmware accepts BLEWriteWithoutResponse, so fire both sensors in
    # parallel to reduce start-time skew. Fall back to acknowledged writes for
    # compatibility with older firmware builds.
    try:
        await send_to_all_parallel(client_map, b"FIRE_START")
    except Exception as error:
        print(f"[BLE] Parallel FIRE_START failed, falling back to acknowledged writes: {error}")
        await send_to_all(client_map, b"FIRE_START", gap_sec=COMMAND_GAP_SEC)
    await asyncio.sleep(0.3)


async def stop_stream(client_map: dict[str, Any]) -> None:
    connected = {name: client for name, client in client_map.items() if client.is_connected}
    if connected:
        print("[BLE] Sending STOP...")
        await send_to_all(connected, b"STOP", gap_sec=STOP_GAP_SEC)
        await asyncio.sleep(0.3)


async def cleanup_clients(clients: list[Any], client_map: dict[str, Any]) -> None:
    try:
        await stop_stream(client_map)
    except Exception as error:
        print(f"[BLE] STOP skipped: {error}")

    for client, name in zip(clients, DEVICE_NAMES):
        try:
            if client.is_connected:
                data_char = data_char_by_device.get(name, DATA_CHAR_UUID)
                await client.stop_notify(data_char)
        except Exception:
            pass
        try:
            if client.is_connected:
                await client.disconnect()
                print(f"[BLE] Disconnected {name}.")
        except Exception:
            pass

    await asyncio.sleep(SHUTDOWN_SETTLE_SEC)


async def scan_and_connect(scan_timeout: float) -> tuple[list[Any], dict[str, Any]]:
    if BleakScanner is None or BleakClient is None:
        raise RuntimeError("bleak is not available.")

    print(f"[BLE] Scanning for target sensors for {scan_timeout:.1f} s...")
    devices = await BleakScanner.discover(timeout=scan_timeout)
    targets = {device.name: device for device in devices if device.name in DEVICE_NAMES}

    print("[BLE] Found target sensors: " + (", ".join(sorted(targets)) if targets else "none"))
    if len(targets) < 2:
        missing = [name for name in DEVICE_NAMES if name not in targets]
        raise RuntimeError(f"Could not find both sensors. Missing: {missing}")

    clients = [
        BleakClient(
            targets[DEVICE_NAMES[0]],
            timeout=20,
            disconnected_callback=make_disconnect_callback(DEVICE_NAMES[0]),
            services=[SERVICE_UUID],
        ),
        BleakClient(
            targets[DEVICE_NAMES[1]],
            timeout=20,
            disconnected_callback=make_disconnect_callback(DEVICE_NAMES[1]),
            services=[SERVICE_UUID],
        ),
    ]
    client_map = dict(zip(DEVICE_NAMES, clients))

    await connect_client_with_retry(clients[0], DEVICE_NAMES[0])
    await asyncio.sleep(POST_CONNECT_STABILIZE_SEC)
    await connect_client_with_retry(clients[1], DEVICE_NAMES[1])
    await asyncio.sleep(POST_CONNECT_STABILIZE_SEC)

    for client, name in zip(clients, DEVICE_NAMES):
        data_char_by_device[name] = resolve_characteristic(client, name, DATA_CHAR_UUID, "IMU data notify")
        command_char_by_device[name] = resolve_characteristic(client, name, COMMAND_CHAR_UUID, "command write")
        await client.start_notify(data_char_by_device[name], notification_handler(name))
        print(f"[BLE] Subscribed to IMU notifications from {name}.")
        await asyncio.sleep(0.3)

    return clients, client_map


def open_log_file(log_dir: Path) -> Path:
    global csv_writer, csv_file_handle

    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"tcn_ble_activity_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    csv_file_handle = log_path.open("w", newline="", encoding="utf-8")
    csv_writer = csv.DictWriter(
        csv_file_handle,
        fieldnames=[
            "timestamp",
            "raw_window_timestamp",
            "paired_samples_seen",
            "prediction",
            "prediction_index",
            "confidence",
            "risk_status",
            "active_risky_class",
            "risky_counter",
            "top_predictions",
            "beep_triggered",
            "confirmed_risky_event",
            "inference_ms",
        ],
    )
    csv_writer.writeheader()
    return log_path


async def run(args: argparse.Namespace) -> None:
    global paired_sample_buffer
    global main_event_loop, data_ready_event, disconnect_event
    global model, model_labels, risky_activity_labels, model_input_channels, model_channel_names
    global model_mean, model_std, active_window_size, active_stride
    global input_layout, window_zscore, use_checkpoint_normalization, stabilization_samples

    require_runtime_dependencies()

    model_labels = [label.strip() for label in args.labels.split(",") if label.strip()]
    risky_activity_labels = {
        normalize_activity_label(label)
        for label in args.risky_labels.split(",")
        if label.strip()
    }
    input_layout = args.input_layout
    window_zscore = args.window_zscore
    use_checkpoint_normalization = not args.no_checkpoint_normalization
    stabilization_samples = int(args.stabilization_sec * EXPECTED_FREQ)

    print("[CONFIG] Labels: " + ", ".join(model_labels))
    print("[CONFIG] Risky labels: " + ", ".join(sorted(risky_activity_labels)))
    print(f"[CONFIG] Input layout: {input_layout}")
    model = load_tcn_model(Path(args.model).resolve())
    checkpoint_metadata = getattr(model, "tcn_metadata", None)
    if isinstance(checkpoint_metadata, dict) and checkpoint_metadata.get("labels"):
        model_labels = [str(label) for label in checkpoint_metadata["labels"]]
        print("[CONFIG] Labels from checkpoint: " + ", ".join(model_labels))
    model_input_channels = infer_model_input_channels(model)
    model_channel_names = infer_model_channel_names(model)
    model_mean = metadata_array(model, "mean")
    model_std = metadata_array(model, "std")
    active_window_size = metadata_int(model, "window") or WINDOW_SIZE
    active_stride = metadata_int(model, "stride") or STRIDE
    paired_sample_buffer = deque(maxlen=active_window_size)
    print(f"[CONFIG] TCN expected input channels: {model_input_channels or 'unknown'}")
    if model_channel_names:
        print("[CONFIG] TCN channel names from checkpoint: " + ", ".join(model_channel_names))
    print(
        f"[CONFIG] Window={active_window_size} paired samples, stride={active_stride}, "
        f"stabilization={stabilization_samples} paired samples"
    )
    print(
        "[CONFIG] Normalization: "
        + (
            "checkpoint mean/std"
            if use_checkpoint_normalization and model_mean is not None and model_std is not None
            else ("live per-window z-score" if window_zscore else "none")
        )
    )
    log_path = open_log_file(Path(args.log_dir).resolve())
    print(f"[LOG] Writing predictions to {log_path}")
    if not args.no_beep_test:
        print("[ALARM] Beep test: you should hear one short beep now.")
        beep_ok = play_alert_sound_async()
        print(f"[ALARM] Beep test request accepted: {'yes' if beep_ok else 'no'}")

    main_event_loop = asyncio.get_running_loop()
    data_ready_event = asyncio.Event()
    disconnect_event = asyncio.Event()

    clients: list[Any] = []
    client_map: dict[str, Any] = {}
    bg_task = asyncio.create_task(background_processing_task())
    monitor_task = asyncio.create_task(stream_monitor_task())

    try:
        clients, client_map = await scan_and_connect(args.scan_timeout)
        await start_stream_synchronized(client_map)

        print("[RUN] TCN BLE test is running. Press Ctrl+C to stop.")
        if args.duration > 0:
            try:
                await asyncio.wait_for(disconnect_event.wait(), timeout=args.duration)
            except asyncio.TimeoutError:
                print(f"[RUN] Duration reached: {args.duration:.1f} s")
        else:
            await disconnect_event.wait()
    finally:
        bg_task.cancel()
        monitor_task.cancel()
        try:
            await bg_task
        except asyncio.CancelledError:
            pass
        try:
            await monitor_task
        except asyncio.CancelledError:
            pass
        await cleanup_clients(clients, client_map)
        if csv_file_handle is not None:
            csv_file_handle.close()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Standalone two-sensor BLE test runner for tcn_activity.pt."
    )
    parser.add_argument(
        "--model",
        default=str(DEFAULT_MODEL_PATH),
        help="Path to the TCN .pt model. Default: ../tcn_activity.pt",
    )
    parser.add_argument(
        "--labels",
        default=",".join(DEFAULT_LABELS),
        help="Comma-separated class labels ordered exactly like the model output neurons.",
    )
    parser.add_argument(
        "--risky-labels",
        default=",".join(sorted(RISKY_ACTIVITIES)),
        help="Comma-separated labels that should trigger the same risky alarm logic.",
    )
    parser.add_argument(
        "--no-beep-test",
        action="store_true",
        help="Disable the startup beep test.",
    )
    parser.add_argument(
        "--input-layout",
        choices=["channels_first", "time_first"],
        default="channels_first",
        help="channels_first gives the model 1x12x50 input; time_first gives 1x50x12 input.",
    )
    parser.add_argument(
        "--window-zscore",
        action="store_true",
        help="Apply per-window z-score normalization to the raw 12-channel sequence before TCN inference.",
    )
    parser.add_argument(
        "--no-checkpoint-normalization",
        action="store_true",
        help="Disable saved training mean/std normalization from tcn_activity.pt.",
    )
    parser.add_argument(
        "--stabilization-sec",
        type=float,
        default=DEFAULT_STABILIZATION_SEC,
        help="Seconds of paired samples to ignore before predictions start.",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=0.0,
        help="Run duration in seconds. Use 0 to run until a sensor disconnects or Ctrl+C is pressed.",
    )
    parser.add_argument(
        "--scan-timeout",
        type=float,
        default=10.0,
        help="BLE scan timeout in seconds.",
    )
    parser.add_argument(
        "--log-dir",
        default=str(BASE_DIR),
        help="Directory for the standalone prediction CSV log.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        print("\n[RUN] Stopped by user.")
        return 0
    except Exception as error:
        print(f"[ERROR] {type(error).__name__}: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
