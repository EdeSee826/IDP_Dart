import json
import sqlite3
import time
import urllib.request
from collections import Counter
from datetime import datetime
from pathlib import Path


DURATION_SECONDS = 15 * 60
ACCOUNT_ID = "validation-test"
BASE_URL = "http://127.0.0.1:5000/api/status"
DB_PATH = Path(__file__).with_name("risky_events.db")
OUTPUT_PATH = Path(__file__).with_name("long_duration_validation_result.json")


def fetch_status():
    with urllib.request.urlopen(BASE_URL, timeout=5) as response:
        return json.load(response)


def database_boundaries():
    connection = sqlite3.connect(DB_PATH)
    try:
        prediction_id = connection.execute(
            "SELECT COALESCE(MAX(id), 0) FROM prediction_readings WHERE account_id = ?",
            (ACCOUNT_ID,),
        ).fetchone()[0]
        event_id = connection.execute(
            "SELECT COALESCE(MAX(id), 0) FROM risky_events WHERE account_id = ?",
            (ACCOUNT_ID,),
        ).fetchone()[0]
        return prediction_id, event_id
    finally:
        connection.close()


def collect_results(start_prediction_id, start_event_id):
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    try:
        predictions = connection.execute(
            """
            SELECT recorded_at, predicted_activity, risk_status, alert_triggered
            FROM prediction_readings
            WHERE account_id = ? AND id > ?
            ORDER BY id
            """,
            (ACCOUNT_ID, start_prediction_id),
        ).fetchall()
        events = connection.execute(
            """
            SELECT id, event_type, timestamp, risk_level
            FROM risky_events
            WHERE account_id = ? AND id > ?
            ORDER BY id
            """,
            (ACCOUNT_ID, start_event_id),
        ).fetchall()
    finally:
        connection.close()

    activity_counts = Counter(row["predicted_activity"] for row in predictions)
    gaps = []
    previous = None
    for row in predictions:
        current = datetime.fromisoformat(row["recorded_at"])
        if previous is not None:
            gap = (current - previous).total_seconds()
            if gap > 2:
                gaps.append(round(gap, 3))
        previous = current

    return {
        "prediction_count": len(predictions),
        "activity_counts": dict(activity_counts),
        "risky_prediction_count": sum(row["risk_status"] == "Risky" for row in predictions),
        "confirmed_alert_count": sum(bool(row["alert_triggered"]) for row in predictions),
        "prediction_gaps_over_2_seconds": gaps,
        "new_events": [dict(row) for row in events],
    }


def main():
    start_prediction_id, start_event_id = database_boundaries()
    started_at = datetime.now()
    samples = []

    for elapsed in range(0, DURATION_SECONDS + 1, 30):
        if elapsed:
            time.sleep(30)
        try:
            status = fetch_status()
            samples.append(
                {
                    "elapsed_seconds": elapsed,
                    "timestamp": status.get("timestamp"),
                    "connected_count": status.get("connected_count"),
                    "session_active": status.get("session_active"),
                    "streaming_active": status.get("streaming_active"),
                    "error_message": status.get("error_message"),
                    "battery": status.get("battery"),
                }
            )
        except Exception as error:
            samples.append(
                {
                    "elapsed_seconds": elapsed,
                    "timestamp": datetime.now().isoformat(),
                    "status_error": str(error),
                }
            )

    result = {
        "test": "15-minute long-duration monitoring validation",
        "account_id": ACCOUNT_ID,
        "started_at": started_at.isoformat(),
        "completed_at": datetime.now().isoformat(),
        "duration_seconds": DURATION_SECONDS,
        "start_prediction_id": start_prediction_id,
        "start_event_id": start_event_id,
        "status_samples": samples,
        "status_summary": {
            "samples": len(samples),
            "both_sensors_connected_samples": sum(
                sample.get("connected_count") == 2 for sample in samples
            ),
            "streaming_active_samples": sum(
                sample.get("streaming_active") is True for sample in samples
            ),
            "samples_with_errors": sum(
                bool(sample.get("status_error") or sample.get("error_message"))
                for sample in samples
            ),
        },
        "prediction_summary": collect_results(start_prediction_id, start_event_id),
    }
    OUTPUT_PATH.write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
