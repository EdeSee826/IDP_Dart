# BLE Connection & Numpy Troubleshooting Guide

## Summary of Fixes Applied

### ✅ Flutter BLE Service Improvements
- **Better error handling**: Connection failures now logged with details instead of silently failing
- **Correct connection status**: Device is only marked as connected AFTER service discovery succeeds
- **Improved scanning**: Scan timeout increased from 4s to 8s for better device discovery
- **Debug logging**: All connection attempts now logged with device IDs and names

### ✅ Python Backend Improvements  
- **Updated numpy**: `1.24.3` → `>=1.26.0,<2.0` (Python 3.11+ compatible)
- **Updated scikit-learn**: `1.3.0` → `>=1.4.0` (better numpy support)
- **Better BLE scanning**: Scanner timeout increased from 10s to 15s
- **Enhanced logging**: Connection stages now clearly logged with device details
- **Error tracebacks**: Full Python traceback on errors for debugging

---

## Quick Start: Test the Connection

### Step 1: Update Python Dependencies
```bash
cd c:\Users\User\Desktop\Vs Codes\flutter_IDP_UI\backend
pip install -r requirements.txt --upgrade
```

### Step 2: Start Backend
```bash
# In backend directory
python app.py
```

**Expected output:**
```
NumPy version: 1.26.x (or higher)
Starting Flask API server on http://localhost:5000
```

### Step 3: Test Backend Health
In PowerShell:
```powershell
Invoke-WebRequest -Method Get -Uri http://localhost:5000/api/health
```

Should return: `{"status":"ok"}`

### Step 4: Run Flutter App
```bash
flutter run -d chrome
# or for Android/iOS
flutter run
```

### Step 5: Click Connect Button
Watch the console output for connection logs:
- **Flutter Console** (VS Code): Look for `[BLE]` messages
- **Backend Console**: Look for `[BLE]` messages showing device discovery and connection

---

## Troubleshooting by Symptom

### ❌ Problem: "Connect button doesn't work / no response"

**Check 1: Is BLE service starting?**
- Run Flutter app and check console
- Look for: `[BLE] Starting scan...` messages
- If not present → BLE not supported on platform (web doesn't support BLE)

**Check 2: Are devices found?**
- In backend console, after running `/api/start`, look for:
  ```
  [BLE] Scanning for devices (15 seconds timeout)...
  [BLE] Found X of 2 target devices
  [BLE] Device: XIAO_MG24_Sensor_01 -> XX:XX:XX:XX:XX:XX
  [BLE] Device: XIAO_MG24_Sensor_02 -> XX:XX:XX:XX:XX:XX
  ```
- If not found:
  1. **Verify device power**: Check if sensors are turned on
  2. **Check device names**: In `ml_backend.py` line ~64, verify:
     ```python
     DEVICE_NAMES = ["XIAO_MG24_Sensor_01", "XIAO_MG24_Sensor_02"]
     ```
  3. **Bluetooth enabled**: Ensure system Bluetooth is on
  4. **Device nearby**: Sensors should be within Bluetooth range (5-10 meters)

**Check 3: Connection errors?**
- Look for `[BLE ERROR]` or `[ERROR]` in console
- If see: `"Could not find both sensors"` → See Check 2 above
- If see: `"Disconnected client(s)"` → Connection lost during operation

---

### ❌ Problem: "Connection works but no data received"

**Check 1: Are notifications enabled?**
- In Flutter console, look for:
  ```
  [BLE] Enabled notifications on characteristic: FFF1
  [BLE] Discovered X services for Device 1
  ```

**Check 2: Backend streaming status?**
```powershell
Invoke-WebRequest -Method Get -Uri http://localhost:5000/api/status | Select-Object -ExpandProperty Content
```

Look for:
```json
{
  "streaming_active": true,
  "stream_running": true,
  "connected_count": 2,
  "devices": [
    {"name": "XIAO_MG24_Sensor_01", "connected": true},
    {"name": "XIAO_MG24_Sensor_02", "connected": true}
  ]
}
```

If `connected_count` is 0 → connection failed, check logs

---

### ❌ Problem: "Python errors about numpy"

**Check 1: Verify numpy update worked**
```bash
cd c:\Users\User\Desktop\Vs Codes\flutter_IDP_UI\backend
python -c "import numpy; print(numpy.__version__)"
```

Should show `1.26.x` or higher (NOT `1.24.3`)

**Check 2: If still wrong version**
```bash
pip uninstall numpy -y
pip install numpy>=1.26.0,<2.0
```

**Check 3: Verify scikit-learn compatibility**
```bash
python -c "import sklearn; print(sklearn.__version__)"
```

Should show `1.4.0` or higher

---

### ❌ Problem: "Port 5000 already in use"

```powershell
# Find process using port 5000
Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue

# Kill the process (replace XXXX with PID)
Stop-Process -Id XXXX -Force

# Then start backend again
python app.py
```

---

### ❌ Problem: "ML model files missing"

Error: `"Missing ML model files: svm_rfe_model (1).pkl"`

**Solution**: Ensure these files exist in backend directory:
- `svm_rfe_model (1).pkl`
- `scaler (1).pkl`

If missing, copy from training output directory or retrain models.

---

## Debug: Reading Connection Logs

### What Good Logs Look Like

**Flutter Console (BLE Service):**
```
[BLE] Starting scan...
[BLE] Matched device by name: Device 1 (XIAO_MG24_Sensor_01)
[BLE] Successfully connected to Device 1 (XX:XX:XX:XX:XX:XX)
[BLE] Discovered 3 services for Device 1
[BLE] Enabled notifications on characteristic: FFF1
```

**Backend Console (ML Backend):**
```
NumPy version: 1.26.x
Scanning for devices (15 seconds timeout)...
[BLE] Found 2 of 2 target devices
[BLE] Device: XIAO_MG24_Sensor_01 -> XX:XX:XX:XX:XX:XX
[BLE] Device: XIAO_MG24_Sensor_02 -> XX:XX:XX:XX:XX:XX
[BLE] Connecting to XIAO_MG24_Sensor_01...
[BLE] Connected to XIAO_MG24_Sensor_01
[BLE] Starting data notifications...
[BLE] Sending command to XIAO_MG24_Sensor_01: b'ARM'
```

### What Bad Logs Look Like

**Silent Failures (Before Fix):**
```
[BLE] Starting scan...
(no more messages - app appears hung)
```

**Connection Errors (After Fix):**
```
[BLE ERROR] Failed to connect to Device 1: Connection timeout
[BLE] Device disconnected: Device 1
```

---

## Testing Checklist

- [ ] Dependencies updated: `pip install -r requirements.txt --upgrade`
- [ ] NumPy version ≥ 1.26.0: `python -c "import numpy; print(numpy.__version__)"`
- [ ] Backend starts: `python app.py` runs without import errors
- [ ] API responds: `/api/health` returns `{"status":"ok"}`
- [ ] Sensors powered on and nearby
- [ ] Flutter app runs on physical device (BLE doesn't work on web)
- [ ] Console shows `[BLE]` messages when clicking connect
- [ ] Backend shows device discovery messages
- [ ] Connection logs show "Successfully connected"

---

## Advanced Debugging

### Enable Verbose Logging

**Add to `lib/services/ble_service.dart` line 1:**
```dart
import 'dart:developer' as developer;
```

**Add at start of `main.dart` before runApp:**
```dart
developer.log('[DEBUG] Starting app', name: 'main');
```

### Check Bluetooth Permissions

**Android:**
```dart
import 'package:permission_handler/permission_handler.dart';

Future<void> _checkBlePermissions() async {
  final status = await Permission.bluetooth.request();
  print('[DEBUG] Bluetooth permission: $status');
}
```

**iOS:**
Check `Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>App needs Bluetooth to connect to sensors</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>App needs Bluetooth to connect to sensors</string>
```

---

## Still Having Issues?

1. **Collect logs from both consoles** (Flutter + Python)
2. **Note the exact error message**
3. **Check device names match** `DEVICE_NAMES` in `ml_backend.py`
4. **Try restarting** both app and backend
5. **Power cycle sensors** (turn off/on)
6. **Check Bluetooth is enabled** on system

---

## Key Files Changed

- [lib/services/ble_service.dart](lib/services/ble_service.dart) - Connection error handling
- [backend/requirements.txt](backend/requirements.txt) - Numpy/sklearn versions  
- [backend/ml_backend.py](backend/ml_backend.py) - Scanner timeout & logging
- [backend/app.py](backend/app.py) - No changes needed

Run `flutter analyze` to verify no syntax errors:
```bash
flutter analyze
```
