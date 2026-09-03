# PICC Care Companion

PICC Care Companion is a Flutter app with a Python/Flask backend for patient monitoring, BLE sensor workflows, and risk-event validation.

The Flutter app handles the user interface, state management, and patient workflow screens. The backend in `backend/` provides REST APIs, SQLite storage, BLE integration, and ML / validation utilities.

## Repository Layout

- `lib/` Flutter application code
- `backend/` Flask backend, validation scripts, and generated analysis artifacts
- `images/` app images and assets
- `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/` platform targets

## Requirements

- Flutter SDK 3.3 or newer
- Python 3.10+ for the backend tooling

## Dependencies

Flutter / Dart packages used by the app:

- `fl_chart`
- `intl`
- `flutter_riverpod`
- `shared_preferences`
- `http`

Python packages used by the backend:

- `Flask`
- `Flask-Cors`
- `bleak`
- `numpy`
- `scipy`
- `Pillow`

## Run The App

1. Install Flutter dependencies:

   ```bash
   flutter pub get
   ```

2. Install the backend Python libraries:

   ```bash
   python -m pip install -r backend/requirements-flask.txt
   ```

3. Start the Flutter app:

   ```bash
   flutter run
   ```

4. If you need the backend, run the Flask app in `backend/` after installing the Python libraries.

## Notes

- `lib/main.dart` boots the app and enters the authenticated flow.
- `backend/app.py` is the main Flask entry point.
- `backend/imu_interpretation_code.py` contains the IMU validation logic used by the backend.
