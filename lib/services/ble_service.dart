import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/sensor_packet.dart';

class DeviceTarget {
  const DeviceTarget({
    required this.slot,
    required this.label,
    this.deviceId,
  });

  final DeviceSlot slot;
  final String label;
  final String? deviceId;
}

class DeviceConnectionUpdate {
  const DeviceConnectionUpdate({
    required this.slot,
    required this.connected,
    required this.label,
  });

  final DeviceSlot slot;
  final bool connected;
  final String label;
}

class BleService {
  BleService({
    List<DeviceTarget>? targets,
  }) : _targets = targets ??
            const [
              DeviceTarget(slot: DeviceSlot.device1, label: 'Device 1'),
              DeviceTarget(slot: DeviceSlot.device2, label: 'Device 2'),
            ];

  final List<DeviceTarget> _targets;
  final StreamController<SensorPacket> _sensorController =
      StreamController.broadcast();
  final StreamController<DeviceConnectionUpdate> _connectionController =
      StreamController.broadcast();

  final Map<DeviceSlot, BluetoothDevice> _activeDevices = {};
  final Map<DeviceSlot, List<StreamSubscription<dynamic>>> _subscriptions = {};
  final Set<DeviceSlot> _connectingSlots = {};

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _scanTimer;
  Timer? _reconnectTimer;
  Timer? _mockDataTimer;
  bool _started = false;

  Stream<SensorPacket> get sensorStream => _sensorController.stream;

  Stream<DeviceConnectionUpdate> get connectionStream =>
      _connectionController.stream;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    for (final target in _targets) {
      _emitConnection(target.slot, false, target.label);
    }

    if (!_isBleRuntimeSupported) {
      _startMockMode();
      return;
    }

    try {
      await _startBleMode();
    } on UnsupportedError {
      _startMockMode();
    }
  }

  Future<void> _startBleMode() async {
    _scanSubscription = FlutterBluePlus.scanResults.listen(_onScanResults);

    _scanTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _startScanning();
    });

    _reconnectTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _attemptReconnectForDisconnectedSlots();
    });

    await _startScanning();
  }

  Future<void> _startScanning() async {
    bool supported = false;
    try {
      supported = await FlutterBluePlus.isSupported;
    } on UnsupportedError {
      _startMockMode();
      return;
    }

    if (!supported) {
      _startMockMode();
      return;
    }

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    } catch (_) {
      // Keep periodic retries alive.
    }
  }

  Future<void> _attemptReconnectForDisconnectedSlots() async {
    for (final target in _targets) {
      if (_activeDevices[target.slot] == null) {
        if (target.deviceId != null && target.deviceId!.isNotEmpty) {
          final device = BluetoothDevice.fromId(target.deviceId!);
          await _connectDeviceToSlot(device, target.slot, target.label);
        }
      }
    }
  }

  Future<void> connectSlot(DeviceSlot slot) async {
    final target = _targets.firstWhere(
      (candidate) => candidate.slot == slot,
      orElse: () => DeviceTarget(
          slot: slot,
          label: slot == DeviceSlot.device1 ? 'Device 1' : 'Device 2'),
    );

    if (!_isBleRuntimeSupported) {
      _emitConnection(target.slot, true, target.label);
      return;
    }

    if (target.deviceId != null && target.deviceId!.isNotEmpty) {
      final device = BluetoothDevice.fromId(target.deviceId!);
      await _connectDeviceToSlot(device, target.slot, target.label);
      return;
    }

    await _startScanning();
  }

  Future<void> _onScanResults(List<ScanResult> results) async {
    for (final result in results) {
      final matchedTarget = _matchTarget(result.device);
      if (matchedTarget == null) {
        continue;
      }
      if (_activeDevices[matchedTarget.slot] != null) {
        continue;
      }
      await _connectDeviceToSlot(
          result.device, matchedTarget.slot, matchedTarget.label);
    }
  }

  DeviceTarget? _matchTarget(BluetoothDevice device) {
    for (final target in _targets) {
      final idMatches = target.deviceId != null &&
          target.deviceId!.isNotEmpty &&
          device.remoteId.str == target.deviceId;
      final nameMatches = device.platformName.isNotEmpty &&
          device.platformName
              .toLowerCase()
              .contains(target.label.toLowerCase());
      if (idMatches || nameMatches) {
        return target;
      }
    }
    return null;
  }

  Future<void> _connectDeviceToSlot(
    BluetoothDevice device,
    DeviceSlot slot,
    String label,
  ) async {
    if (_connectingSlots.contains(slot)) {
      return;
    }
    _connectingSlots.add(slot);

    try {
      await device.connect(timeout: const Duration(seconds: 10));
    } catch (_) {
      // Ignore duplicate or intermittent connect failures.
    }

    _activeDevices[slot] = device;
    _emitConnection(slot, true, label);

    _subscriptions[slot]?.forEach((sub) => sub.cancel());
    _subscriptions[slot] = [];

    final stateSub = device.connectionState.listen((connectionState) {
      final connected = connectionState == BluetoothConnectionState.connected;
      _emitConnection(slot, connected, label);
      if (!connected) {
        _activeDevices.remove(slot);
      }
    });

    _subscriptions[slot]!.add(stateSub);

    await _discoverAndSubscribe(device, slot, label);
    _connectingSlots.remove(slot);
  }

  Future<void> _discoverAndSubscribe(
    BluetoothDevice device,
    DeviceSlot slot,
    String label,
  ) async {
    try {
      final services = await device.discoverServices();
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (!characteristic.properties.notify &&
              !characteristic.properties.indicate) {
            continue;
          }

          await characteristic.setNotifyValue(true);
          final packetSub = characteristic.lastValueStream.listen((rawBytes) {
            final packet = SensorPacket.fromBlePayload(
              slot: slot,
              deviceLabel: label,
              payload: rawBytes,
            );
            _sensorController.add(packet);
          });
          _subscriptions[slot]!.add(packetSub);
        }
      }
    } catch (_) {
      // Keep reconnect strategy active.
    }
  }

  void _startMockMode() {
    _scanTimer?.cancel();
    _reconnectTimer?.cancel();

    for (final target in _targets) {
      _emitConnection(target.slot, true, target.label);
    }

    final random = Random();
    _mockDataTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      for (final target in _targets) {
        final accX = random.nextDouble() * 2 - 1;
        final accY = random.nextDouble() * 2 - 1;
        final accZ = 0.8 + random.nextDouble() * 1.4;
        final gyroX = random.nextDouble() * 4 - 2;
        final gyroY = random.nextDouble() * 4 - 2;
        final gyroZ = random.nextDouble() * 4 - 2;
        final risk = random.nextInt(20) == 0;

        _sensorController.add(
          SensorPacket(
            slot: target.slot,
            deviceLabel: target.label,
            timestamp: DateTime.now(),
            accX: accX,
            accY: accY,
            accZ: accZ,
            gyroX: gyroX,
            gyroY: gyroY,
            gyroZ: gyroZ,
            riskFlag: risk,
          ),
        );
      }
    });
  }

  bool get _isBleRuntimeSupported {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  void _emitConnection(DeviceSlot slot, bool connected, String label) {
    _connectionController.add(
      DeviceConnectionUpdate(
        slot: slot,
        connected: connected,
        label: label,
      ),
    );
  }

  Future<void> dispose() async {
    _scanTimer?.cancel();
    _reconnectTimer?.cancel();
    _mockDataTimer?.cancel();
    await _scanSubscription?.cancel();

    for (final slotSubscriptions in _subscriptions.values) {
      for (final subscription in slotSubscriptions) {
        await subscription.cancel();
      }
    }

    for (final device in _activeDevices.values) {
      try {
        await device.disconnect();
      } catch (_) {
        // Ignore disconnect failures during shutdown.
      }
    }

    await _sensorController.close();
    await _connectionController.close();
  }
}
