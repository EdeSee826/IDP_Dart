import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backend_service.dart';
import '../../state/backend_status_provider.dart';
import 'wearable_image.dart';
import 'device_status_tile.dart';

class SensorConnectionPanel extends ConsumerStatefulWidget {
  const SensorConnectionPanel({
    super.key,
    this.showContinueButton = false,
    this.continueLabel = 'Continue',
    this.onContinue,
    this.onSensorTap1,
    this.onSensorTap2,
    this.showImage = true,
  });

  final bool showContinueButton;
  final String continueLabel;
  final VoidCallback? onContinue;
  final VoidCallback? onSensorTap1;
  final VoidCallback? onSensorTap2;
  final bool showImage;

  @override
  ConsumerState<SensorConnectionPanel> createState() =>
      _SensorConnectionPanelState();
}

class _SensorConnectionPanelState extends ConsumerState<SensorConnectionPanel> {
  bool _busy = false;
  String? _errorMessage;
  int _countdownSeconds = 15;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _showConnectionCountdown() async {
    _countdownTimer?.cancel();
    _countdownSeconds = 15;
    StateSetter? dialogSetState;
    BuildContext? dialogContext;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 0) {
        _countdownSeconds--;
        dialogSetState?.call(() {});
        return;
      }

      timer.cancel();
      final currentContext = dialogContext;
      if (mounted && currentContext != null && Navigator.of(currentContext).canPop()) {
        Navigator.of(currentContext).pop();
      }
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        dialogContext = dialogCtx;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            dialogSetState = setStateDialog;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              contentPadding: const EdgeInsets.all(24),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 6),
                  const Text(
                    'Connecting your wearable sensors...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1F2D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Checking nearby sensors...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF667085),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE8F4F1),
                      border: Border.all(
                        color: const Color(0xFF2D8E90),
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$_countdownSeconds',
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D8E90),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: _countdownSeconds / 15,
                        backgroundColor: const Color(0xFFD7E6EB),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF2D8E90),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> _connectSensors() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    _showConnectionCountdown();

    try {
      final result = await BackendService.startStreaming();
      await ref.read(backendStatusProvider.notifier).refreshStatus();
      if (!result.success) {
        _errorMessage = result.message ?? 'Unable to connect sensors right now.';
      }
    } catch (e) {
      _errorMessage = 'Unable to connect sensors right now.';
      await ref.read(backendStatusProvider.notifier).refreshStatus();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _pauseMonitoring() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final result = await BackendService.stopStreaming();
      await ref.read(backendStatusProvider.notifier).refreshStatus();
      if (!result.success) {
        _errorMessage = result.message ?? 'Unable to pause monitoring right now.';
      }
    } catch (e) {
      _errorMessage = 'Unable to pause monitoring right now.';
      await ref.read(backendStatusProvider.notifier).refreshStatus();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _handlePrimaryAction(BackendStatusState backendStatus) {
    if (backendStatus.streamingActive) {
      _pauseMonitoring();
    } else {
      _connectSensors();
    }
  }

  Widget _connectionImage(BackendStatusState backendStatus) {
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: WearableImage(
            asset: 'image_2.png',
            height: 520,
            boxFit: BoxFit.contain,
            device1Connected: backendStatus.device1Connected,
            device2Connected: backendStatus.device2Connected,
            onMarker1: widget.onSensorTap1,
            onMarker2: widget.onSensorTap2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backendStatus = ref.watch(backendStatusProvider);
    final connectedCount = backendStatus.connectedCount.clamp(0, 2);
    final allConnected = backendStatus.device1Connected && backendStatus.device2Connected;
    final monitoringActive = backendStatus.streamingActive && allConnected;
    final actionLabel = backendStatus.streamingActive
        ? 'Pause Monitoring'
        : (connectedCount > 0 ? 'Reconnect Sensors' : 'Connect Sensors');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F5BA8),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Wearable Sensors',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: Color(0xFF1D2738),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            monitoringActive ? 'Monitoring active' : 'Monitoring paused',
            style: TextStyle(
              color: monitoringActive ? const Color(0xFF13795B) : const Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          DeviceStatusTile(
            title: 'Sensor 1: Upper Arm Sensor',
            connected: backendStatus.device1Connected,
          ),
          const SizedBox(height: 8),
          DeviceStatusTile(
            title: 'Sensor 2: Wrist Sensor',
            connected: backendStatus.device2Connected,
          ),
          const SizedBox(height: 10),
          Text(
            'Connected sensors: $connectedCount / 2',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _handlePrimaryAction(backendStatus),
                  icon: Icon(
                    backendStatus.streamingActive
                        ? Icons.pause_circle_outline_rounded
                        : Icons.link_rounded,
                  ),
                  label: Text(
                    _busy ? 'Checking sensors...' : actionLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D8E90),
                    disabledBackgroundColor: const Color(0xFFB8C8D1),
                    foregroundColor: Colors.white,
                    iconColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: Color(0xFFD14343),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (widget.showContinueButton) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: allConnected && !_busy ? widget.onContinue : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F7B6C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(widget.continueLabel),
              ),
            ),
          ],
          if (widget.showImage) ...[
            const SizedBox(height: 14),
            _connectionImage(backendStatus),
          ],
        ],
      ),
    );
  }
}