import asyncio
import json
from datetime import datetime
from pathlib import Path

from bleak import BleakClient, BleakScanner


DEVICE_NAMES = ["XIAO_MG24_Sensor_01", "XIAO_MG24_Sensor_02"]
MAX_TEST_SECONDS = 20 * 60
POLL_SECONDS = 0.25
STATUS_SECONDS = 5
CONNECT_RETRIES = 3
RESULT_PATH = Path(__file__).with_name("ble_connection_only_result.json")


def now():
    return datetime.now().isoformat(timespec="milliseconds")


async def main():
    result = {
        "test": "Independent BLE connection-only observation",
        "started_at": now(),
        "devices": {},
        "first_disconnect": None,
        "events": [],
    }
    disconnect_queue = asyncio.Queue()
    intentional_disconnects = set()

    def disconnect_callback(name):
        def callback(_client):
            if name in intentional_disconnects:
                return
            event = {"device": name, "timestamp": now(), "source": "bleak_disconnect_callback"}
            result["events"].append(event)
            disconnect_queue.put_nowait(event)
            print(f"[PHYSICAL DISCONNECT] {name} at {event['timestamp']}", flush=True)

        return callback

    print("Scanning for both sensors...", flush=True)
    discovered = await BleakScanner.discover(timeout=10)
    targets = {device.name: device for device in discovered if device.name in DEVICE_NAMES}
    missing = [name for name in DEVICE_NAMES if name not in targets]
    if missing:
        result["completed_at"] = now()
        result["outcome"] = "scan_failed"
        result["missing_devices"] = missing
        RESULT_PATH.write_text(json.dumps(result, indent=2), encoding="utf-8")
        raise RuntimeError(f"Could not find: {missing}")

    clients = {}
    try:
        for name in DEVICE_NAMES:
            result["devices"][name] = {"connection_attempts": []}
            for attempt in range(1, CONNECT_RETRIES + 1):
                client = BleakClient(targets[name], disconnected_callback=disconnect_callback(name), timeout=20)
                try:
                    await client.connect()
                    clients[name] = client
                    result["devices"][name]["connection_attempts"].append(
                        {"attempt": attempt, "timestamp": now(), "outcome": "connected"}
                    )
                    result["devices"][name]["connected_at"] = now()
                    print(f"[CONNECTED] {name} at {result['devices'][name]['connected_at']}", flush=True)
                    break
                except Exception as exc:
                    result["devices"][name]["connection_attempts"].append(
                        {
                            "attempt": attempt,
                            "timestamp": now(),
                            "outcome": "failed",
                            "error": f"{type(exc).__name__}: {exc}",
                        }
                    )
                    print(f"[CONNECT FAILED {attempt}/{CONNECT_RETRIES}] {name}: {type(exc).__name__}: {exc}", flush=True)
                    try:
                        await client.disconnect()
                    except Exception:
                        pass
                    await asyncio.sleep(2)
            else:
                result["outcome"] = "connection_failed"
                result["failed_device"] = name
                return

        loop = asyncio.get_running_loop()
        start = loop.time()
        next_status = 0
        while loop.time() - start < MAX_TEST_SECONDS:
            elapsed = loop.time() - start
            if elapsed >= next_status:
                states = {name: client.is_connected for name, client in clients.items()}
                print(f"[STATUS {elapsed:7.2f}s] {states}", flush=True)
                next_status += STATUS_SECONDS

            try:
                first = await asyncio.wait_for(disconnect_queue.get(), timeout=POLL_SECONDS)
                first["elapsed_seconds"] = round(loop.time() - start, 3)
                result["first_disconnect"] = first
                result["outcome"] = "disconnect_observed"
                break
            except asyncio.TimeoutError:
                pass
        else:
            result["outcome"] = "no_disconnect_within_test_duration"

    finally:
        result["completed_at"] = now()
        for name, client in clients.items():
            result["devices"].setdefault(name, {})["connected_before_cleanup"] = client.is_connected
            if client.is_connected:
                intentional_disconnects.add(name)
                await client.disconnect()
        RESULT_PATH.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(f"Result saved to {RESULT_PATH}", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
