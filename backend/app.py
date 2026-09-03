"""
Flask Backend for IDP Risk Event Detection
Pure Python backend handling BLE streaming, calibration, and event storage.
Flutter is UI-only and communicates via REST API.
"""

import asyncio
import os
import sqlite3
import threading
import signal
import importlib.util
import secrets
from datetime import datetime, timedelta
from flask import Flask, jsonify, request
from flask_cors import CORS
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)
CORS(app)

# Database configuration
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "risky_events.db")
RETENTION_DAYS = 7

# Background thread management
ml_thread = None
ml_thread_stop_event = threading.Event()
imu_module = None
caregiver_sessions = {}


def get_imu_interpretation_code():
    return get_imu_backend()


def get_imu_backend():
    global imu_module
    if imu_module is not None:
        return imu_module

    module_path = os.path.join(
        os.path.dirname(__file__),
        "imu_interpretation_code.py",
    )
    spec = importlib.util.spec_from_file_location("imu_interpretation", module_path)
    if spec is None or spec.loader is None:
        raise ImportError("Unable to load IMU backend module")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    imu_module = module
    return imu_module


def get_battery_status():
    try:
        module = get_imu_backend()
        return module.get_battery_snapshot()
    except Exception:
        return {
            "sensor1": {
                "raw_adc": None,
                "voltage": None,
                "battery_percent": None,
                "last_updated": None,
                "connected": False,
            },
        }


def get_static_placement_status():
    """Attempt to read static placement validation from the IMU interpretation module if present."""
    try:
        module = get_imu_backend()

        # Read validation_results and neutral_vectors if available
        static_results = {}
        vr = getattr(module, "validation_results", None)
        nv = getattr(module, "neutral_vectors", None)
        if vr is None:
            return None

        for name in vr:
            entry = vr.get(name)
            if entry is None:
                static_results[name] = {"passed": None, "interpretation": None}
            else:
                static_results[name] = {
                    "passed": bool(entry.get("passed")),
                    "angle_passed": entry.get("angle_passed"),
                    "marker_down": entry.get("marker_down"),
                    "interpretation": entry.get("interpretation"),
                }

        return static_results
    except Exception:
        return None


def set_backend_session_active(active):
    """Sync Flask and ML backend session state."""
    imu_interpretation = get_imu_interpretation_code()
    imu_interpretation.SESSION_ACTIVE = active

    if not active:
        # Signal disconnect event to gracefully stop BLE
        if getattr(imu_interpretation, "disconnect_event", None) is not None:
            try:
                imu_interpretation.disconnect_event.set()
            except Exception:
                pass


# ============================================================
# DATABASE INITIALIZATION
# ============================================================
def init_database():
    """Create account and patient-data tables if they do not exist."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS accounts (
            email TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            onboarding_completed INTEGER NOT NULL DEFAULT 0,
            baseline_completed INTEGER NOT NULL DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
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
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS family_access_permissions (
            owner_email TEXT PRIMARY KEY,
            family_email TEXT,
            token_hash TEXT,
            enabled INTEGER NOT NULL DEFAULT 0,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (owner_email) REFERENCES accounts(email)
        )
    """)
    columns = {
        row[1] for row in cursor.execute("PRAGMA table_info(risky_events)").fetchall()
    }
    if "account_id" not in columns:
        cursor.execute(
            "ALTER TABLE risky_events ADD COLUMN account_id TEXT NOT NULL DEFAULT 'legacy'"
        )
    family_columns = {
        row[1]
        for row in cursor.execute(
            "PRAGMA table_info(family_access_permissions)"
        ).fetchall()
    }
    if "token_hash" not in family_columns:
        cursor.execute(
            "ALTER TABLE family_access_permissions ADD COLUMN token_hash TEXT"
        )
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_risky_events_account_timestamp
        ON risky_events (account_id, timestamp)
    """)
    conn.commit()
    conn.close()
    cleanup_old_risky_events()


def normalize_email(value):
    return str(value or "").strip().lower()


def account_payload(row):
    return {
        "email": row[0],
        "name": row[1],
        "onboarding_completed": bool(row[2]),
        "baseline_completed": bool(row[3]),
    }


def risk_level_for_event_count(count):
    if count > 50:
        return "high"
    if count > 20:
        return "medium"
    return "low"


def family_patient_summaries(conn, family_email, owner_email=None):
    owner_filter = " AND p.owner_email = ?" if owner_email else ""
    parameters = (family_email, owner_email) if owner_email else (family_email,)
    patients = conn.execute(
        f"""
        SELECT a.email, a.name
        FROM family_access_permissions p
        JOIN accounts a ON a.email = p.owner_email
        WHERE p.enabled = 1 AND p.family_email = ?
        {owner_filter}
        ORDER BY a.name COLLATE NOCASE, a.email
        """,
        parameters,
    ).fetchall()

    today = datetime.now().strftime("%Y-%m-%d")
    cutoff = (datetime.now() - timedelta(days=RETENTION_DAYS)).strftime(
        "%Y-%m-%d %H:%M:%S"
    )
    summaries = []
    for patient_email, patient_name in patients:
        rows = conn.execute(
            """
            SELECT id, event_type, timestamp, risk_level
            FROM risky_events
            WHERE account_id = ? AND timestamp >= ?
            ORDER BY timestamp DESC
            """,
            (patient_email, cutoff),
        ).fetchall()
        events = [
            {
                "id": row[0],
                "event_type": row[1],
                "timestamp": row[2],
                "risk_level": row[3],
            }
            for row in rows
        ]
        today_events = [
            event for event in events if event["timestamp"].startswith(today)
        ]
        summaries.append(
            {
                "email": patient_email,
                "name": patient_name,
                "today_event_count": len(today_events),
                "weekly_event_count": len(events),
                "risk_level": risk_level_for_event_count(len(today_events)),
                "latest_event": events[0] if events else None,
                "events": events,
            }
        )
    return summaries


def cleanup_old_risky_events():
    """Remove risky events older than the retention window."""
    cutoff = (datetime.now() - timedelta(days=RETENTION_DAYS)).strftime("%Y-%m-%d %H:%M:%S")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM risky_events WHERE timestamp < ?", (cutoff,))
    conn.commit()
    conn.close()


def fetch_risky_events_today(account_id):
    """Fetch all risky events from today"""
    today = datetime.now().strftime("%Y-%m-%d")
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, event_type, timestamp, risk_level
        FROM risky_events
        WHERE account_id = ? AND timestamp LIKE ?
        ORDER BY timestamp DESC
    """, (account_id, f"{today}%"))
    
    rows = cursor.fetchall()
    conn.close()
    
    events = [
        {
            "id": row[0],
            "event_type": row[1],
            "timestamp": row[2],
            "risk_level": row[3]
        }
        for row in rows
    ]
    
    return events


def fetch_all_risky_events(account_id):
    """Fetch all risky events"""
    cutoff = (datetime.now() - timedelta(days=RETENTION_DAYS)).strftime("%Y-%m-%d %H:%M:%S")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, event_type, timestamp, risk_level
        FROM risky_events
        WHERE account_id = ? AND timestamp >= ?
        ORDER BY timestamp DESC
    """, (account_id, cutoff))
    
    rows = cursor.fetchall()
    conn.close()
    
    events = [
        {
            "id": row[0],
            "event_type": row[1],
            "timestamp": row[2],
            "risk_level": row[3]
        }
        for row in rows
    ]
    
    return events



def group_events_by_day(events):
    """Group events by calendar day and add a per-day counter."""
    grouped = {}
    day_order = []

    for event in events:
        day_key = event["timestamp"][:10]
        if day_key not in grouped:
            grouped[day_key] = []
            day_order.append(day_key)

        grouped[day_key].append(event)

    grouped_events = []
    for day_key in day_order:
        day_events = []
        for index, event in enumerate(grouped[day_key], start=1):
            day_events.append({
                **event,
                "daily_counter": index,
                "date": day_key,
            })

        grouped_events.append({
            "date": day_key,
            "label": datetime.strptime(day_key, "%Y-%m-%d").strftime("%A, %B %d, %Y"),
            "count": len(day_events),
            "events": day_events,
        })

    return grouped_events


# ============================================================
# API ENDPOINTS - Health & Status
# ============================================================

@app.route("/api/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({"status": "ok", "timestamp": datetime.now().isoformat()}), 200


@app.route("/api/accounts/register", methods=["POST"])
def register_account():
    body = request.get_json(silent=True) or {}
    name = str(body.get("name") or "").strip()
    email = normalize_email(body.get("email"))
    password = str(body.get("password") or "")

    if not name or not email or "@" not in email or len(password) < 6:
        return jsonify({"error": "Valid name, email, and password are required"}), 400

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            """
            INSERT INTO accounts (email, name, password_hash)
            VALUES (?, ?, ?)
            """,
            (email, name, generate_password_hash(password)),
        )
        conn.commit()
    except sqlite3.IntegrityError:
        return jsonify({"error": "An account with this email already exists"}), 409
    finally:
        conn.close()

    return jsonify({
        "account": {
            "email": email,
            "name": name,
            "onboarding_completed": False,
            "baseline_completed": False,
        }
    }), 201


@app.route("/api/accounts/login", methods=["POST"])
def login_account():
    body = request.get_json(silent=True) or {}
    email = normalize_email(body.get("email"))
    password = str(body.get("password") or "")

    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute(
            """
            SELECT email, name, onboarding_completed, baseline_completed,
                   password_hash
            FROM accounts
            WHERE email = ?
            """,
            (email,),
        ).fetchone()
    finally:
        conn.close()

    if row is None:
        return jsonify({"error": "Account not found. Please create an account first."}), 404
    if not check_password_hash(row[4], password):
        return jsonify({"error": "Incorrect password"}), 401

    return jsonify({"account": account_payload(row)}), 200


@app.route("/api/accounts/state", methods=["PATCH"])
def update_account_state():
    body = request.get_json(silent=True) or {}
    email = normalize_email(body.get("email"))
    if not email:
        return jsonify({"error": "Account email is required"}), 400

    updates = []
    values = []
    if "name" in body and str(body["name"]).strip():
        updates.append("name = ?")
        values.append(str(body["name"]).strip())
    if "onboarding_completed" in body:
        updates.append("onboarding_completed = ?")
        values.append(int(bool(body["onboarding_completed"])))
    if "baseline_completed" in body:
        updates.append("baseline_completed = ?")
        values.append(int(bool(body["baseline_completed"])))
    if not updates:
        return jsonify({"error": "No account fields were provided"}), 400

    updates.append("updated_at = CURRENT_TIMESTAMP")
    values.append(email)
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.execute(
            f"UPDATE accounts SET {', '.join(updates)} WHERE email = ?",
            values,
        )
        conn.commit()
        if cursor.rowcount == 0:
            return jsonify({"error": "Account not found"}), 404
        row = conn.execute(
            """
            SELECT email, name, onboarding_completed, baseline_completed
            FROM accounts WHERE email = ?
            """,
            (email,),
        ).fetchone()
    finally:
        conn.close()

    return jsonify({"account": account_payload(row)}), 200


@app.route("/api/accounts/privacy", methods=["GET"])
def get_account_privacy():
    owner_email = normalize_email(request.args.get("email"))
    if not owner_email:
        return jsonify({"error": "Account email is required"}), 400

    conn = sqlite3.connect(DB_PATH)
    try:
        account_exists = conn.execute(
            "SELECT 1 FROM accounts WHERE email = ?",
            (owner_email,),
        ).fetchone()
        if account_exists is None:
            return jsonify({"error": "Account not found"}), 404
        row = conn.execute(
            """
            SELECT enabled, family_email
            FROM family_access_permissions
            WHERE owner_email = ?
            """,
            (owner_email,),
        ).fetchone()
    finally:
        conn.close()

    return jsonify({
        "family_access_enabled": bool(row[0]) if row else False,
        "family_email": row[1] if row else None,
    }), 200


@app.route("/api/accounts/privacy", methods=["PUT"])
def update_account_privacy():
    body = request.get_json(silent=True) or {}
    owner_email = normalize_email(body.get("email"))
    enabled = bool(body.get("family_access_enabled", False))
    family_email = normalize_email(body.get("family_email"))

    if not owner_email:
        return jsonify({"error": "Account email is required"}), 400
    if enabled and (not family_email or "@" not in family_email):
        return jsonify({"error": "A valid family email address is required"}), 400
    if enabled and family_email == owner_email:
        return jsonify({"error": "Family email must be different from your email"}), 400

    invitation_token = secrets.token_urlsafe(9) if enabled else None
    token_hash = generate_password_hash(invitation_token) if enabled else None
    conn = sqlite3.connect(DB_PATH)
    try:
        account_exists = conn.execute(
            "SELECT 1 FROM accounts WHERE email = ?",
            (owner_email,),
        ).fetchone()
        if account_exists is None:
            return jsonify({"error": "Account not found"}), 404
        conn.execute(
            """
            INSERT INTO family_access_permissions (
                owner_email, family_email, token_hash, enabled, updated_at
            ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(owner_email) DO UPDATE SET
                family_email = excluded.family_email,
                token_hash = excluded.token_hash,
                enabled = excluded.enabled,
                updated_at = CURRENT_TIMESTAMP
            """,
            (
                owner_email,
                family_email if enabled else None,
                token_hash,
                int(enabled),
            ),
        )
        conn.commit()
    finally:
        conn.close()

    return jsonify({
        "family_access_enabled": enabled,
        "family_email": family_email if enabled else None,
        "invitation_token": invitation_token,
    }), 200


@app.route("/api/family/login", methods=["POST"])
def login_family_caregiver():
    body = request.get_json(silent=True) or {}
    email = normalize_email(body.get("email"))
    invitation_token = str(body.get("token") or "").strip()
    if not email or not invitation_token:
        return jsonify({"error": "Caregiver email and token are required"}), 400

    conn = sqlite3.connect(DB_PATH)
    try:
        permissions = conn.execute(
            """
            SELECT owner_email, token_hash
            FROM family_access_permissions
            WHERE family_email = ? AND enabled = 1
            """,
            (email,),
        ).fetchall()
        owner_email = next(
            (
                row[0]
                for row in permissions
                if row[1] and check_password_hash(row[1], invitation_token)
            ),
            None,
        )
        if owner_email is None:
            return jsonify({"error": "Invalid caregiver email or token"}), 401
        patients = family_patient_summaries(conn, email, owner_email)
    finally:
        conn.close()

    access_token = secrets.token_urlsafe(32)
    caregiver_sessions[access_token] = {
        "email": email,
        "owner_email": owner_email,
    }

    return jsonify({
        "account": {
            "email": email,
            "name": "Family Caregiver",
            "onboarding_completed": True,
            "baseline_completed": False,
        },
        "patients": patients,
        "access_token": access_token,
    }), 200


@app.route("/api/family/dashboard", methods=["GET"])
def get_family_dashboard():
    caregiver_email = normalize_email(request.args.get("email"))
    if not caregiver_email:
        return jsonify({"error": "Caregiver email is required"}), 400
    authorization = request.headers.get("Authorization", "")
    access_token = authorization.removeprefix("Bearer ").strip()
    caregiver_session = caregiver_sessions.get(access_token)
    if not caregiver_session or caregiver_session["email"] != caregiver_email:
        return jsonify({"error": "Caregiver session is invalid or expired"}), 401

    conn = sqlite3.connect(DB_PATH)
    try:
        patients = family_patient_summaries(
            conn,
            caregiver_email,
            caregiver_session["owner_email"],
        )
    finally:
        conn.close()

    return jsonify({"patients": patients}), 200


@app.route("/api/status", methods=["GET"])
def status():
    """Return backend streaming and device connection status"""
    try:
        imu_interpretation = get_imu_interpretation_code()
        runtime_status = imu_interpretation.get_runtime_status()
        battery_status = get_battery_status()
        static_status = get_static_placement_status()
        return jsonify(
            {
                "backend_ready": True,
                "session_active": runtime_status["streaming_active"],
                "streaming_active": runtime_status["stream_running"],
                "connected_count": runtime_status["connected_count"],
                "error_message": runtime_status.get("error_message"),
                "devices": runtime_status["devices"],
                "calibration_phase": runtime_status.get("calibration_phase"),
                "calibration_message": runtime_status.get("calibration_message"),
                "calibration_remaining_seconds": runtime_status.get("calibration_remaining_seconds"),
                "calibration_validation": runtime_status.get("calibration_validation"),
                "battery": battery_status,
                "static_placement": static_status,
                "timestamp": datetime.now().isoformat()
            }
        ), 200
    except Exception as e:
        return jsonify(
            {
                "backend_ready": False,
                "streaming_active": False,
                "session_active": False,
                "connected_count": 0,
                "devices": [
                    {"name": "XIAO_MG24_Sensor_02", "connected": False},
                ],
                "battery": get_battery_status(),
                "static_placement": None,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
        ), 500


# ============================================================
# API ENDPOINTS - Session Control
# ============================================================

@app.route("/api/start", methods=["POST"])
def start_stream():
    """Start BLE streaming in background."""
    global ml_thread
    imu_interpretation_code = get_imu_interpretation_code()
    
    if imu_interpretation_code.SESSION_ACTIVE:
        return jsonify({"error": "Session already active"}), 400

    bleak_error = getattr(imu_interpretation_code, "BLEAK_IMPORT_ERROR", None)
    if bleak_error is not None:
        return jsonify({
            "error": "Missing Python dependency 'bleak'",
            "details": "Install backend dependencies with: pip install -r requirements-flask.txt"
        }), 500

    # Mark session as active and start background thread
    body = request.get_json(silent=True) or {}
    imu_interpretation_code.LAST_ERROR = None
    imu_interpretation_code.CALIBRATION_PHASE = "connecting"
    imu_interpretation_code.CALIBRATION_MESSAGE = "Searching for the wearable sensor."
    imu_interpretation_code.CALIBRATION_DEADLINE = None
    imu_interpretation_code.CALIBRATION_RETRY_REQUESTED = False
    account_id = str(body.get("account_id") or "default").strip().lower()
    imu_interpretation_code.CALIBRATION_ACCOUNT_ID = account_id
    imu_interpretation_code.CALIBRATION_ENROLL_BASELINE = bool(body.get("enroll_baseline", False))
    set_backend_session_active(True)
    
    try:
        ml_thread_stop_event.clear()
        ml_thread = threading.Thread(target=run_imu_interpretation_code, daemon=True)
        ml_thread.start()
        
        return jsonify({
            "status": "streaming_started",
            "timestamp": datetime.now().isoformat()
        }), 200
    except Exception as e:
        set_backend_session_active(False)
        return jsonify({"error": f"Failed to start stream: {str(e)}"}), 500


@app.route("/api/stop", methods=["POST"])
def stop_stream():
    """Stop BLE streaming and IMU interpretation"""
    imu_interpretation = get_imu_interpretation_code()
    
    if not imu_interpretation.SESSION_ACTIVE:
        return jsonify({"error": "No active session"}), 400
    
    try:
        set_backend_session_active(False)
        ml_thread_stop_event.set()
        
        # Wait briefly for thread to clean up
        if ml_thread is not None and ml_thread.is_alive():
            ml_thread.join(timeout=5)
        
        return jsonify({
            "status": "streaming_stopped",
            "timestamp": datetime.now().isoformat()
        }), 200
    except Exception as e:
        return jsonify({"error": f"Failed to stop stream: {str(e)}"}), 500


@app.route("/api/calibration/retry", methods=["POST"])
def retry_calibration():
    """Continue calibration after the patient acknowledges guidance."""
    try:
        imu_interpretation = get_imu_interpretation_code()
        if not imu_interpretation.SESSION_ACTIVE:
            return jsonify({"error": "No active sensor session"}), 400
        if not imu_interpretation.request_calibration_retry():
            return jsonify({"error": "Calibration is not waiting for acknowledgement"}), 409
        return jsonify({
            "status": "calibration_retry_requested",
            "timestamp": datetime.now().isoformat(),
        }), 200
    except Exception as e:
        return jsonify({"error": f"Failed to retry calibration: {str(e)}"}), 500


@app.route("/api/calibration/bypass", methods=["POST"])
def bypass_calibration():
    """Bypass calibration for an explicitly requested validation-only session."""
    try:
        imu_interpretation = get_imu_interpretation_code()
        if not imu_interpretation.SESSION_ACTIVE:
            return jsonify({"error": "No active sensor session"}), 400
        if not imu_interpretation.request_calibration_bypass():
            return jsonify({"error": "Calibration cannot be bypassed in the current phase"}), 409
        return jsonify({
            "status": "calibration_bypass_requested",
            "warning": "Monitoring results from this session are uncalibrated.",
            "timestamp": datetime.now().isoformat(),
        }), 200
    except Exception as e:
        return jsonify({"error": f"Failed to bypass calibration: {str(e)}"}), 500


# ============================================================
# API ENDPOINTS - Event Retrieval
# ============================================================

@app.route("/api/events/today", methods=["GET"])
def get_events_today():
    """Fetch risky events from today"""
    try:
        account_id = request.args.get("account_id", "default").strip().lower()
        events = fetch_risky_events_today(account_id)
        return jsonify({
            "events": events,
            "grouped_events": group_events_by_day(events),
            "count": len(events),
            "timestamp": datetime.now().isoformat()
        }), 200
    except Exception as e:
        return jsonify({"error": f"Failed to fetch events: {str(e)}"}), 500


@app.route("/api/events/all", methods=["GET"])
def get_all_events():
    """Fetch all risky events"""
    try:
        account_id = request.args.get("account_id", "default").strip().lower()
        events = fetch_all_risky_events(account_id)
        return jsonify({
            "events": events,
            "grouped_events": group_events_by_day(events),
            "count": len(events),
            "timestamp": datetime.now().isoformat()
        }), 200
    except Exception as e:
        return jsonify({"error": f"Failed to fetch events: {str(e)}"}), 500


@app.route("/api/events/clear", methods=["DELETE"])
def clear_events():
    """Clear all risky events (admin only)"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        account_id = request.args.get("account_id", "default").strip().lower()
        cursor.execute("DELETE FROM risky_events WHERE account_id = ?", (account_id,))
        conn.commit()
        conn.close()
        
        return jsonify({
            "status": "events_cleared",
            "timestamp": datetime.now().isoformat()
        }), 200
    except Exception as e:
        return jsonify({"error": f"Failed to clear events: {str(e)}"}), 500


# ============================================================
# API ENDPOINTS - Teams Calendar Integration
# ============================================================

@app.route("/api/appointment/sync-teams", methods=["POST"])
def sync_appointment_to_teams():
    """
    Sync appointment to Teams calendar.
    Currently returns success response. 
    TODO: Integrate with Microsoft Graph API for actual Teams calendar sync.
    
    Request body:
    {
        "title": "Medical Appointment",
        "start_time": "2024-05-15T10:30:00",
        "location": "Clinic A"
    }
    """
    try:
        data = request.get_json(silent=True) or {}
        title = data.get("title", "Medical Appointment")
        start_time = data.get("start_time")
        location = data.get("location", "")
        
        if not start_time:
            return jsonify({"error": "start_time is required"}), 400
        
        # TODO: Implement actual Teams Graph API integration
        # This is a placeholder that logs the appointment
        app.logger.info(f"[APPOINTMENT] Title: {title}, Time: {start_time}, Location: {location}")
        
        return jsonify({
            "status": "appointment_sync_queued",
            "message": "Appointment queued for Teams calendar sync",
            "appointment": {
                "title": title,
                "start_time": start_time,
                "location": location
            },
            "timestamp": datetime.now().isoformat()
        }), 200
    except Exception as e:
        return jsonify({"error": f"Failed to sync appointment: {str(e)}"}), 500



# ============================================================
# BACKGROUND ML/BLE RUNNER
# ============================================================

def run_imu_interpretation_code():
    """
    Run the IMU interpretation code in a separate thread.
    Manages BLE connections, calibration, and sensor streaming.
    """
    try:
        imu_interpretation = get_imu_interpretation_code()
        app.logger.info("[Flask] Starting IMU interpretation thread...")
        # Run the async IMU interpretation loop
        asyncio.run(imu_interpretation.main())
    except Exception as e:
        app.logger.exception("[Flask] IMU Interpretation Error")
        imu_interpretation.LAST_ERROR = str(e)
        imu_interpretation.CALIBRATION_PHASE = "error"
        imu_interpretation.CALIBRATION_MESSAGE = str(e)
        imu_interpretation.CALIBRATION_DEADLINE = None
    finally:
        app.logger.info("[Flask] IMU interpretation thread shutting down...")
        set_backend_session_active(False)


# ============================================================
# GRACEFUL SHUTDOWN
# ============================================================

def handle_shutdown(signum, frame):
    """Handle shutdown signals"""
    app.logger.info("[Flask] Shutdown signal received, cleaning up...")
    set_backend_session_active(False)
    if ml_thread is not None and ml_thread.is_alive():
        ml_thread.join(timeout=5)
    app.logger.info("[Flask] Shutdown complete")


# ============================================================
# APPLICATION INITIALIZATION & MAIN
# ============================================================

if __name__ == "__main__":
    try:
        # Initialize database
        init_database()
        app.logger.info("[Flask] Database initialized")
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, handle_shutdown)
        signal.signal(signal.SIGTERM, handle_shutdown)
        
        app.logger.info("[Flask] Starting Flask API server on http://localhost:5000")
        app.logger.info("[Flask] Press Ctrl+C to stop")
        
        app.run(debug=False, host="localhost", port=5000, threaded=True)
    except KeyboardInterrupt:
        handle_shutdown(None, None)
    except Exception as e:
        app.logger.exception("[Flask] Fatal error")
        raise
