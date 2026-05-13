"""
Flask Backend for IDP Risk Event Detection
Pure Python backend handling BLE, ML prediction, and event storage.
Flutter is UI-only and communicates via REST API.
"""

import asyncio
import os
import sqlite3
import threading
import signal
import importlib
from datetime import datetime, timedelta
from flask import Flask, jsonify, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Database configuration
DB_PATH = "risky_events.db"
RETENTION_DAYS = 7

# Background thread management
ml_thread = None
ml_thread_stop_event = threading.Event()


def get_ml_backend():
    return importlib.import_module("ml_backend")


def set_backend_session_active(active):
    """Sync Flask and ML backend session state."""
    ml_backend = get_ml_backend()
    ml_backend.SESSION_ACTIVE = active
    
    if not active:
        # Signal disconnect event to gracefully stop BLE
        if getattr(ml_backend, "disconnect_event", None) is not None:
            try:
                ml_backend.disconnect_event.set()
            except Exception:
                pass


# ============================================================
# DATABASE INITIALIZATION
# ============================================================
def init_database():
    """Create risky_events table if it doesn't exist"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS risky_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            risk_level TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()
    cleanup_old_risky_events()


def cleanup_old_risky_events():
    """Remove risky events older than the retention window."""
    cutoff = (datetime.now() - timedelta(days=RETENTION_DAYS)).strftime("%Y-%m-%d %H:%M:%S")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM risky_events WHERE timestamp < ?", (cutoff,))
    conn.commit()
    conn.close()


def fetch_risky_events_today():
    """Fetch all risky events from today"""
    today = datetime.now().strftime("%Y-%m-%d")
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, event_type, timestamp, risk_level
        FROM risky_events
        WHERE timestamp LIKE ?
        ORDER BY timestamp DESC
    """, (f"{today}%",))
    
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


def fetch_all_risky_events():
    """Fetch all risky events"""
    cutoff = (datetime.now() - timedelta(days=RETENTION_DAYS)).strftime("%Y-%m-%d %H:%M:%S")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, event_type, timestamp, risk_level
        FROM risky_events
        WHERE timestamp >= ?
        ORDER BY timestamp DESC
    """, (cutoff,))
    
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


@app.route("/api/status", methods=["GET"])
def status():
    """Return backend streaming and device connection status"""
    try:
        ml_backend = get_ml_backend()
        runtime_status = ml_backend.get_runtime_status()
        return jsonify(
            {
                "backend_ready": True,
                "session_active": runtime_status["streaming_active"],
                "streaming_active": runtime_status["stream_running"],
                "connected_count": runtime_status["connected_count"],
                "error_message": runtime_status.get("error_message"),
                "devices": runtime_status["devices"],
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
                    {"name": "XIAO_MG24_Sensor_01", "connected": False},
                    {"name": "XIAO_MG24_Sensor_02", "connected": False},
                ],
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
        ), 500


# ============================================================
# API ENDPOINTS - Session Control
# ============================================================

@app.route("/api/start", methods=["POST"])
def start_stream():
    """Start BLE streaming and ML prediction in background"""
    global ml_thread
    ml_backend = get_ml_backend()
    
    if ml_backend.SESSION_ACTIVE:
        return jsonify({"error": "Session already active"}), 400

    # Check for required ML model files
    try:
        required_files = ["scaler (1).pkl", "svm_rfe_model (1).pkl"]
        missing_files = [
            filename for filename in required_files 
            if ml_backend.resolve_model_file(filename) is None
        ]
        if missing_files:
            return jsonify({
                "error": "Missing ML model files",
                "missing_files": missing_files
            }), 400
    except Exception as e:
        return jsonify({"error": f"Model check failed: {str(e)}"}), 500
    
    # Mark session as active and start background thread
    set_backend_session_active(True)
    
    try:
        ml_thread_stop_event.clear()
        ml_thread = threading.Thread(target=run_ml_backend, daemon=True)
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
    """Stop BLE streaming and ML prediction"""
    ml_backend = get_ml_backend()
    
    if not ml_backend.SESSION_ACTIVE:
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


# ============================================================
# API ENDPOINTS - Event Retrieval
# ============================================================

@app.route("/api/events/today", methods=["GET"])
def get_events_today():
    """Fetch risky events from today"""
    try:
        events = fetch_risky_events_today()
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
        events = fetch_all_risky_events()
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
        cursor.execute("DELETE FROM risky_events")
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
        data = request.get_json()
        title = data.get("title", "Medical Appointment")
        start_time = data.get("start_time")
        location = data.get("location", "")
        
        if not start_time:
            return jsonify({"error": "start_time is required"}), 400
        
        # TODO: Implement actual Teams Graph API integration
        # This is a placeholder that logs the appointment
        print(f"[APPOINTMENT] Title: {title}, Time: {start_time}, Location: {location}")
        
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

def run_ml_backend():
    """
    Run the ML backend in a separate thread.
    Manages BLE connections, sensor streaming, and ML predictions.
    """
    try:
        ml_backend = get_ml_backend()
        print("[Flask] Starting ML backend thread...")
        # Run the async ML loop
        asyncio.run(ml_backend.main())
    except Exception as e:
        print(f"[Flask] ML Backend Error: {e}")
        ml_backend.LAST_ERROR = str(e)
    finally:
        print("[Flask] ML backend thread shutting down...")
        set_backend_session_active(False)


# ============================================================
# GRACEFUL SHUTDOWN
# ============================================================

def handle_shutdown(signum, frame):
    """Handle shutdown signals"""
    print("[Flask] Shutdown signal received, cleaning up...")
    set_backend_session_active(False)
    if ml_thread is not None and ml_thread.is_alive():
        ml_thread.join(timeout=5)
    print("[Flask] Shutdown complete")


# ============================================================
# APPLICATION INITIALIZATION & MAIN
# ============================================================

if __name__ == "__main__":
    try:
        # Initialize database
        init_database()
        print("[Flask] Database initialized")
        
        # Load ML models once on startup
        try:
            ml_backend = get_ml_backend()
            ml_backend.load_ml_objects()
            print("[Flask] ML models loaded successfully")
        except Exception as e:
            print(f"[Flask] Warning: Could not preload ML models: {e}")
            print("[Flask] Models will be loaded when streaming starts")
        
        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, handle_shutdown)
        signal.signal(signal.SIGTERM, handle_shutdown)
        
        print("[Flask] Starting Flask API server on http://localhost:5000")
        print("[Flask] Press Ctrl+C to stop")
        
        app.run(debug=False, host="localhost", port=5000, threaded=True)
    except KeyboardInterrupt:
        handle_shutdown(None, None)
    except Exception as e:
        print(f"[Flask] Fatal error: {e}")
        raise
