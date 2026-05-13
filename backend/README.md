# Flask Backend Setup

## Prerequisites

- Python 3.8+
- pip package manager

## Installation

1. Navigate to the backend directory:
```bash
cd backend
```

2. Install backend dependencies:
```bash
pip install -r requirements-flask.txt
```

If you already have the generated environment, you can also reuse the existing `requirements.txt` file. The smaller `requirements-flask.txt` file is the safer setup path for a clean install.

3. Add your ML model files to this directory:
   - `svm_rfe_model (1).pkl`
   - `scaler (1).pkl`

## Running the Backend

```bash
python run.py
```

The Flask server will start on `http://localhost:5000`

You can also run the app directly with `python app.py`, but `run.py` keeps the Flask bootstrap path explicit.

## API Endpoints

### Health Check
- `GET /api/health` - Check if the backend is running

### Session Control
- `POST /api/start` - Start BLE streaming and ML prediction
- `POST /api/stop` - Stop BLE streaming

### Event Retrieval
- `GET /api/events/today` - Fetch risky events from today (YYYY-MM-DD HH:MM:SS format)
- `GET /api/events/all` - Fetch all risky events
- `DELETE /api/events/clear` - Clear all events (admin only)

## Database

The backend automatically creates `risky_events.db` in the backend directory.

Only risky events (when `risky_counter >= RISKY_CONFIRM_WINDOWS`) are saved to the database:
- `id` - Event ID
- `event_type` - Activity type (e.g., "elbow_flexion", "shoulder_adduction")
- `timestamp` - Full timestamp in format YYYY-MM-DD HH:MM:SS
- `risk_level` - Always "Risky" for stored events
- `created_at` - Database creation timestamp
