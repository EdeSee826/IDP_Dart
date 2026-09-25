# Python-First Architecture Documentation

## Overview

This project has been refactored to use a **Python-first architecture** where all backend logic (BLE connectivity, ML predictions, data management) is handled by Python, and Flutter serves as a **UI-only interface**.

## Architecture

### Layer 1: Python Backend (`backend/`)
**Responsibilities:**
- **BLE Connection Management**: Auto-discovers and connects to two IMU sensors (XIAO_MG24_Sensor_01 & XIAO_MG24_Sensor_02)
- **Real-time Data Streaming**: Continuously receives sensor data from BLE devices
- **ML Predictions**: Runs SVM RFE model on incoming sensor data to detect risky activities
- **Database Management**: SQLite database for storing risky events
- **REST API Server**: Flask server on `localhost:5000` providing all functionality to Flutter

**Key Files:**
- `app.py` - Flask REST API server
- `ml_backend.py` - BLE connection, sensor streaming, and ML pipeline
- `requirements.txt` - Python dependencies

**Dependencies:**
```
Flask==2.3.2
Flask-CORS==4.0.0
bleak==0.21.0        # Bluetooth LE library
numpy, pandas, scikit-learn  # ML libraries
```

### Layer 2: Flutter Frontend (`lib/`)
**Responsibilities:**
- **UI Rendering**: Display patient monitoring dashboard, event logs, device status
- **HTTP Communication**: Make REST API calls to Python backend
- **State Management**: Use Riverpod for local UI state
- **User Interactions**: Handle login, streaming control, event viewing

**Structure:**
```
lib/
├── main.dart                 # App entry point
├── services/
│   └── backend_service.dart  # HTTP client for Flask API calls
├── models/
│   ├── patient_state.dart    # Patient data model
│   ├── risk_event.dart       # Risk event model
│   └── sensor_packet.dart    # Sensor data model
├── state/
│   ├── backend_status_provider.dart   # Backend status polling
│   ├── risky_events_provider.dart     # Event retrieval
│   └── patient_controller.dart        # Patient data state
└── ui/
    └── screens/              # All UI screens
```

**Dependencies Removed:**
- `flutter_blue_plus` - No longer needed (BLE handled by Python)

---

## REST API Endpoints

All communication between Flutter and Python goes through these HTTP endpoints:

### Health & Status
- `GET /api/health` - Check if backend is running
- `GET /api/status` - Get device connection status and streaming state

### Session Control
- `POST /api/start` - Start BLE streaming and ML predictions
- `POST /api/stop` - Stop BLE streaming

### Event Retrieval
- `GET /api/events/today` - Fetch today's risky events
- `GET /api/events/all` - Fetch all risky events
- `DELETE /api/events/clear` - Clear all events

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  BLE Devices (XIAO Sensors)                                     │
│       ↓                                                          │
│  Python Backend                                                 │
│  ├─ BLE Manager (bleak): Device discovery, connection           │
│  ├─ Sensor Streaming: Real-time IMU data collection             │
│  ├─ ML Pipeline: SVM RFE predictions                            │
│  └─ Database: SQLite risky_events.db                            │
│       ↓                                                          │
│  Flask REST API (localhost:5000)                                │
│       ↓                                                          │
│  Flutter App                                                    │
│  ├─ BackendService: HTTP client                                │
│  ├─ State Providers: Status polling & event fetching            │
│  └─ UI Screens: Display data & handle user interactions         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## How It Works

### Startup Sequence
1. **Python Backend Starts**: `python app.py`
   - Initializes SQLite database
   - Loads ML models (scaler + SVM model)
   - Starts Flask server on port 5000

2. **Flutter App Starts**: `flutter run`
   - Connects to Python backend
   - Checks `/api/health`
   - Periodically polls `/api/status` for device connection state

3. **User Initiates Monitoring**: 
   - Clicks "Start Streaming" in Flutter UI
   - Flutter calls `POST /api/start`
   - Python backend starts BLE connections:
     - Scans for devices (15-second timeout)
     - Connects to both sensors
     - Starts notifications and ML predictions
   - Risky events are automatically saved to database

### Real-Time Event Detection
- Python receives raw IMU data from sensors (50 Hz)
- Data is buffered and paired from both devices
- Features extracted using sliding window (1 sec window, 0.75 overlap)
- SVM model predicts activity in real-time
- If activity is risky (elbow_flexion, shoulder_adduction) and confirmed for 3+ windows:
  - Alert sound plays on Python backend
  - Event is saved to SQLite database

### Flutter Monitoring
- Displays device connection status from `/api/status`
- Periodically fetches risky events from `/api/events/today`
- Shows event log with timestamps and activity types
- User can stop streaming with `POST /api/stop`

---

## Configuration

### Python Backend Settings
**Location:** `backend/ml_backend.py`

**BLE Configuration:**
```python
SERVICE_UUID = "1841"
DATA_CHAR_UUID = "FFF1"
COMMAND_CHAR_UUID = "FFF2"
DEVICE_NAMES = ["XIAO_MG24_Sensor_01", "XIAO_MG24_Sensor_02"]
```

**ML Configuration:**
```python
EXPECTED_FREQ = 50              # Sensor sampling rate (Hz)
WINDOW_SEC = 1                  # Feature window size (seconds)
OVERLAP = 0.75                  # Window overlap ratio
RISKY_ACTIVITIES = {"elbow_flexion", "shoulder_adduction"}
RISKY_CONFIRM_WINDOWS = 3       # Predictions to confirm risk
```

**Model Files (Required):**
- `svm_rfe_model (1).pkl` - Trained SVM model
- `scaler (1).pkl` - Feature scaler

### Flutter Settings
**Location:** `lib/services/backend_service.dart`

```dart
static const String baseUrl = 'http://localhost:5000/api';
static const Duration timeout = Duration(seconds: 30);
```

---

## Development Workflow

### Running Locally

**Terminal 1 - Start Python Backend:**
```bash
cd backend
pip install -r requirements.txt
python app.py
```

**Terminal 2 - Start Flutter App:**
```bash
flutter run
```

### Testing Connectivity
```bash
# Check if Python backend is running
curl http://localhost:5000/api/health

# Get current status
curl http://localhost:5000/api/status

# Fetch today's events
curl http://localhost:5000/api/events/today
```

---

## Key Advantages of This Architecture

1. **Separation of Concerns**: BLE/ML complexity in Python, UI simplicity in Flutter
2. **Platform Independence**: Flutter can target any platform (iOS, Android, Web, Desktop)
3. **Easier Testing**: HTTP API can be tested independently from UI
4. **Scalability**: Backend can be moved to a server without UI changes
5. **Simplified Dependencies**: Flutter doesn't need platform-specific BLE libraries
6. **Real-time Processing**: Python handles heavy ML computations efficiently

---

## Future Enhancements

1. **Network Deployment**: Move Python backend to a server
   - Update `baseUrl` in Flutter to `http://<server-ip>:5000/api`

2. **Authentication**: Add API key or JWT token to protect endpoints

3. **Data Persistence**: Add patient profiles, session history

4. **Advanced Monitoring**: Real-time charts, device battery tracking

5. **Cloud Sync**: Backup risky events to cloud storage

---

## Troubleshooting

### Python Backend Won't Start
- Check that port 5000 is not in use
- Verify Python 3.8+ is installed
- Install dependencies: `pip install -r requirements.txt`
- Check for model files: `svm_rfe_model (1).pkl` and `scaler (1).pkl`

### Flutter Can't Connect to Backend
- Ensure Python backend is running (`http://localhost:5000/api/health`)
- Check if port 5000 is accessible from your Flutter environment
- On emulator: use `http://10.0.2.2:5000` instead of `localhost`

### BLE Devices Not Found
- Ensure sensors are powered on
- Verify sensor names match: `XIAO_MG24_Sensor_01` and `XIAO_MG24_Sensor_02`
- Check Bluetooth is enabled on machine running Python backend

---

## File Changes Summary

**Removed:**
- `lib/services/ble_service.dart` - All BLE logic moved to Python
- `flutter_blue_plus` dependency from pubspec.yaml

**Modified:**
- `backend/app.py` - Enhanced with better session management
- `backend/ml_backend.py` - No changes needed (already Python-first)
- Flutter state providers already use HTTP only

**Architecture is now 100% Python-first!** 🎉
