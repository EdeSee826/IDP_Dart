# IDP Risk Event Detection System - Complete Setup Guide

## Overview

The system consists of two main components:
1. **Python Flask Backend** - Handles BLE streaming, ML prediction, and database management
2. **Flutter UI** - Displays risky events and provides Start/Stop streaming controls

## Backend Setup (Python)

### Prerequisites
- Python 3.8+
- pip package manager
- The two ML model files:
  - `svm_rfe_model (1).pkl`
  - `scaler (1).pkl`

### Installation Steps

1. **Navigate to backend directory**:
   ```bash
   cd backend
   ```

2. **Create a Python virtual environment** (recommended):
   ```bash
   python -m venv venv
   venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Add ML model files**:
   Place the following files in the `backend/` directory:
   - `svm_rfe_model (1).pkl`
   - `scaler (1).pkl`

5. **Run the backend**:
   ```bash
   python app.py
   ```

   The server will start on `http://localhost:5000`

### Backend API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/start` | POST | Start BLE streaming & ML prediction |
| `/api/stop` | POST | Stop BLE streaming |
| `/api/events/today` | GET | Fetch risky events from today |
| `/api/events/all` | GET | Fetch all risky events |
| `/api/events/clear` | DELETE | Clear all events |

### Database

The backend automatically creates `risky_events.db` in the backend folder.

**Schema**:
```sql
CREATE TABLE risky_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    timestamp TEXT NOT NULL,  -- Format: YYYY-MM-DD HH:MM:SS
    risk_level TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
)
```

## Flutter Setup

### Prerequisites
- Flutter SDK 3.3.0+
- Android SDK (for Android testing) or Xcode (for iOS)

### Installation Steps

1. **Install dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run the app**:
   ```bash
   flutter run
   ```

## How to Use

### Starting the System

1. **Start the Python backend**:
   ```bash
   cd backend
   python app.py
   ```
   Wait until you see: `Starting Flask API server on http://localhost:5000`

2. **Run the Flutter app**:
   ```bash
   flutter run
   ```

3. **Use the UI**:
   - Navigate to the **Dashboard** tab
   - You'll see a new "BLE Streaming Control" panel at the top
   - Click **Start** to begin BLE streaming and ML prediction
   - The app will automatically fetch risky events from the database
   - Click **Stop** to end the session

### Viewing Risky Events

- Go to the **Event Log** tab
- Events are displayed with:
  - Event type (e.g., "elbow_flexion", "shoulder_adduction")
  - Full timestamp (YYYY-MM-DD HH:MM:SS 24-hour format)
  - Risk level
- Pull down to refresh the event list manually

## Key Features

### Real-Time Processing
- **ML Pipeline**: Data is processed in real-time with feature extraction, normalization, and SVM classification
- **Risky Event Detection**: Only events where `risky_counter >= 3` are saved to the database
- **Database-First**: All risky events are persisted for later review

### Data Flow
1. BLE devices send sensor data
2. Python backend processes with ML model
3. Risky events are saved to SQLite database
4. Flutter UI fetches events from database every 2 seconds
5. Events are displayed with full timestamps and activity types

### Timestamps
- Format: `YYYY-MM-DD HH:MM:SS` (24-hour clock)
- Automatically captured when risky events are detected
- No manual date/time entry required

## Troubleshooting

### Backend Won't Start
- Ensure Python 3.8+ is installed: `python --version`
- Verify all dependencies: `pip list | grep -i flask`
- Check that port 5000 is not in use

### Flutter Can't Connect to Backend
- Ensure backend is running on `http://localhost:5000`
- Check that both are on the same machine or same network
- On Android emulator, use `10.0.2.2` instead of `localhost`

### No Events Showing
- Verify the backend is running and accepting requests
- Check that BLE devices are detected and connected
- Ensure risky events are actually being triggered (risky_counter >= 3)
- Check `risky_events.db` file permissions in the backend folder

### ML Model Files Missing
- The backend will show: `FileNotFoundError: Missing file: svm_rfe_model (1).pkl`
- Place both model files in the `backend/` directory
- Restart the backend after adding files

## Architecture Details

### Backend (ml_backend.py)
- Handles BLE streaming from two XIAO MG24 sensors
- Runs real-time ML predictions on sensor fusion data
- Only saves risky events to database (not all predictions)
- Thread-safe async/await architecture

### Flutter UI
- `backend_service.dart`: HTTP communication with Flask API
- `streaming_control_panel.dart`: Start/Stop controls
- `event_log_screen.dart`: Display risky events from database
- Auto-refreshes events every 2 seconds when streaming

## File Structure

```
flutter_IDP_UI/
├── backend/
│   ├── app.py                 # Flask server & API
│   ├── ml_backend.py          # ML processing engine
│   ├── requirements.txt       # Python dependencies
│   └── risky_events.db        # SQLite database (auto-created)
├── lib/
│   ├── services/
│   │   └── backend_service.dart      # HTTP client for API
│   ├── ui/
│   │   ├── screens/
│   │   │   └── event_log_screen.dart # Events display
│   │   └── widgets/
│   │       └── streaming_control_panel.dart # Start/Stop UI
│   ├── state/
│   │   └── risky_events_provider.dart # Event fetching provider
│   └── main.dart
└── pubspec.yaml
```

## Performance Notes

- ML predictions run every ~200ms (sliding window with 75% overlap)
- Events are saved to database only when confirmed (3+ consecutive risky predictions)
- Flutter UI refreshes every 2 seconds from database
- Network latency: <100ms typical for localhost API calls

## Future Enhancements

- [ ] Add event filtering by date range
- [ ] Export events as CSV
- [ ] Add event details/drill-down view
- [ ] Implement background service for backend
- [ ] Add real-time notifications
- [ ] Support for multiple patients
