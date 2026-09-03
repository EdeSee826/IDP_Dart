import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backend_service.dart';
import '../../state/backend_status_provider.dart';
import '../../state/language_controller.dart';
import '../../state/session_controller.dart';
import 'wearable_image.dart';
import 'device_status_tile.dart';

class SensorConnectionPanel extends ConsumerStatefulWidget {
  const SensorConnectionPanel({
    super.key,
    this.showContinueButton = false,
    this.continueLabel = 'Continue',
    this.onContinue,
    this.onSensorTap1,
    this.showImage = true,
  });

  final bool showContinueButton;
  final String continueLabel;
  final VoidCallback? onContinue;
  final VoidCallback? onSensorTap1;
  final bool showImage;

  @override
  ConsumerState<SensorConnectionPanel> createState() =>
      _SensorConnectionPanelState();
}

class _SensorConnectionPanelState extends ConsumerState<SensorConnectionPanel> {
  bool _busy = false;
  bool _retryingCalibration = false;
  String? _errorMessage;

  Future<bool> _waitForSensor() async {
    final deadline = DateTime.now().add(const Duration(seconds: 35));

    while (mounted && DateTime.now().isBefore(deadline)) {
      await ref.read(backendStatusProvider.notifier).refreshStatus();
      final status = ref.read(backendStatusProvider);

      if (status.device1Connected) {
        return true;
      }
      if (status.errorMessage != null) {
        _errorMessage = status.errorMessage;
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    _errorMessage = ref
        .read(appStringsProvider)
        .text('The wearable sensor was not found. Check that it is powered on.');
    return false;
  }

  Future<void> _showCalibrationGuide({
    required bool enrollBaseline,
  }) async {
    BuildContext? dialogContext;
    var refreshInProgress = false;
    final timer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (refreshInProgress) return;
      refreshInProgress = true;
      await ref.read(backendStatusProvider.notifier).refreshStatus();
      refreshInProgress = false;

      final status = ref.read(backendStatusProvider);
      final shouldClose = status.calibrationPhase == 'complete' ||
          status.errorMessage != null ||
          !status.streamingActive;
      final currentContext = dialogContext;
      if (shouldClose &&
          currentContext != null &&
          currentContext.mounted &&
          Navigator.of(currentContext).canPop()) {
        Navigator.of(currentContext).pop();
      }
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        dialogContext = dialogCtx;
        return Consumer(
          builder: (context, ref, _) {
            final status = ref.watch(backendStatusProvider);
            final strings = ref.watch(appStringsProvider);
            final phase = status.calibrationPhase;
            final isReadyToStand = phase == 'ready_to_stand';
            final hasFailedCalibration = phase == 'static_failed';
            final color = hasFailedCalibration
                ? const Color(0xFFD97706)
                : const Color(0xFF0F7B6C);
            final remaining = status.calibrationRemainingSeconds;
            const totalSeconds = 5;
            final calibrationMessage = phase == 'static_failed'
                ? strings.text(
                    'Static calibration differs from your initial baseline. Check that the sensor marker points down toward the earth.',
                  )
                : isReadyToStand
                    ? strings.text(
                        'The wearable sensor is connected. Stand comfortably with your PICC arm relaxed beside your body, then tap I understand to begin calibration.',
                      )
                    : status.calibrationMessage ??
                        strings.text(
                          'Preparing calibration after the sensor connects.',
                        );

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              contentPadding: const EdgeInsets.all(24),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.accessibility_new_rounded,
                      color: color,
                      size: 38,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      phase == 'static_failed'
                          ? strings.text('Check sensor orientation')
                          : isReadyToStand
                              ? strings.text('Stand before calibration')
                              : strings.text('Static calibration'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1F2D),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      calibrationMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF667085),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _calibrationGuideImage(
                      assetPath: 'images/standing.png',
                      fallback: _staticCalibrationFallback,
                    ),
                    if (hasFailedCalibration || isReadyToStand) ...[
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _retryingCalibration
                              ? null
                              : () => _acknowledgeCalibrationFailure(),
                          style: FilledButton.styleFrom(
                            backgroundColor: color,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: _retryingCalibration
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(strings.text('I understand')),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 26),
                      Container(
                        width: 116,
                        height: 116,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.10),
                          border: Border.all(color: color, width: 3),
                        ),
                        child: Center(
                          child: remaining == null
                              ? CircularProgressIndicator(color: color)
                              : Text(
                                  '$remaining',
                                  style: const TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A1F2D),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: remaining == null
                              ? null
                              : (remaining / totalSeconds).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: const Color(0xFFD7E6EB),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    timer.cancel();

    if (!mounted) return;
    final status = ref.read(backendStatusProvider);
    if (status.calibrationPhase == 'complete') {
      if (enrollBaseline) {
        await ref
            .read(sessionControllerProvider.notifier)
            .completeSensorBaseline();
      } else {
        await _showCalibrationResultWarnings(status);
      }
      if (!mounted) return;
      final hasFailedCheck =
          !enrollBaseline && status.staticCalibrationPassed == false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            hasFailedCheck
                ? ref.read(appStringsProvider).text(
                      'Static calibration failed. Check that the sensor marker points down toward the earth.',
                    )
                : ref
                    .read(appStringsProvider)
                    .text('Calibration complete. Monitoring is starting.'),
          ),
        ),
      );
    } else if (status.errorMessage != null) {
      _errorMessage = status.errorMessage;
    }
  }

  Future<void> _acknowledgeCalibrationFailure() async {
    if (_retryingCalibration) return;
    setState(() => _retryingCalibration = true);

    final result = await BackendService.retryCalibration();
    if (result.success) {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ref.read(backendStatusProvider.notifier).refreshStatus();
        final phase = ref.read(backendStatusProvider).calibrationPhase;
        if (phase != 'ready_to_stand' &&
            phase != 'static_failed') {
          break;
        }
      }
    } else {
      await ref.read(backendStatusProvider.notifier).refreshStatus();
    }

    if (!mounted) return;
    setState(() {
      _retryingCalibration = false;
      if (!result.success) {
        _errorMessage = result.message;
      }
    });
  }

  Future<void> _showCalibrationResultWarnings(
    BackendStatusState status,
  ) async {
    if (status.staticCalibrationPassed == false) {
      await _showPlacementWarning(
        title: 'Check sensor orientation',
        message:
            'The static neutral reading differs from the initial reading saved when this account was created. Check that the sensor marker points down toward the earth.',
        icon: Icons.explore_rounded,
        color: const Color(0xFFD97706),
      );
    }
  }

  Future<void> _showPlacementWarning({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final strings = ref.read(appStringsProvider);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.10),
                ),
                child: Icon(icon, color: color, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                strings.text(title),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1F2D),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                strings.text(message),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF667085),
                  height: 1.45,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(backgroundColor: color),
              child: Text(strings.text('I understand')),
            ),
          ],
        );
      },
    );
  }

  Widget _staticCalibrationFallback() {
    final strings = ref.watch(appStringsProvider);

    return Container(
      width: 360,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF8F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFE3DB)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('Stand still for calibration'),
            style: const TextStyle(
              color: Color(0xFF0F5F56),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(strings.text('1. Stand comfortably with the PICC arm relaxed.')),
          Text(strings.text('2. Keep the arm still beside the body.')),
          Text(strings.text('3. Make sure the sensor marker points down.')),
        ],
      ),
    );
  }

  Widget _calibrationGuideImage({
    required String assetPath,
    required Widget Function() fallback,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        width: 360,
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }

  Future<void> _connectSensors() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final session = ref.read(sessionControllerProvider);
      final enrollBaseline = !session.sensorBaselineCompleted;
      final result = await BackendService.startStreaming(
        enrollBaseline: enrollBaseline,
        accountId: session.email ?? 'default',
      );
      await ref.read(backendStatusProvider.notifier).refreshStatus();
      if (!result.success) {
        _errorMessage = result.message ??
            ref
                .read(appStringsProvider)
                .text('Unable to connect the sensor right now.');
      } else if (mounted) {
        final sensorConnected = await _waitForSensor();
        if (sensorConnected && mounted) {
          await _showCalibrationGuide(enrollBaseline: enrollBaseline);
        }
        await ref.read(backendStatusProvider.notifier).refreshStatus();
      }
    } catch (e) {
      _errorMessage = ref
          .read(appStringsProvider)
          .text('Unable to connect the sensor right now.');
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
        _errorMessage = result.message ??
            ref
                .read(appStringsProvider)
                .text('Unable to pause monitoring right now.');
      }
    } catch (e) {
      _errorMessage = ref
          .read(appStringsProvider)
          .text('Unable to pause monitoring right now.');
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
            asset: 'images/image_2.png',
            height: 520,
            boxFit: BoxFit.contain,
            device1Connected: backendStatus.device1Connected,
            onMarker1: widget.onSensorTap1,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backendStatus = ref.watch(backendStatusProvider);
    final session = ref.watch(sessionControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final connectedCount = backendStatus.device1Connected ? 1 : 0;
    final allConnected = backendStatus.device1Connected;
    final monitoringActive = backendStatus.streamingActive && allConnected;
    final connecting = backendStatus.calibrationPhase == 'connecting';
    final calibrating = backendStatus.calibrationPhase == 'static' ||
        backendStatus.calibrationPhase == 'ready_to_stand' ||
        backendStatus.calibrationPhase == 'static_failed';
    final calibrationComplete = backendStatus.calibrationPhase == 'complete' &&
        session.sensorBaselineCompleted;
    final actionLabel = backendStatus.streamingActive
        ? strings.text('Disconnect')
        : (connectedCount > 0
            ? strings.text('Reconnect Sensor')
            : strings.text('Connect Sensor'));

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
          Text(
            strings.text('Wearable Sensor'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: Color(0xFF1D2738),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            connecting
                ? strings.text('Connecting sensor...')
                : calibrating
                    ? strings.text('Calibrating sensor...')
                    : monitoringActive
                        ? strings.text('Monitoring active')
                        : strings.text('Monitoring paused'),
            style: TextStyle(
              color: monitoringActive
                  ? const Color(0xFF13795B)
                  : const Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          DeviceStatusTile(
            title: strings.text('Sensor 2: Wrist Sensor'),
            connected: backendStatus.device1Connected,
          ),
          const SizedBox(height: 10),
          Text(
            '${strings.text('Connected sensor')}: $connectedCount / 1',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.showContinueButton) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  calibrationComplete
                      ? Icons.verified_rounded
                      : Icons.pending_actions_rounded,
                  size: 18,
                  color: calibrationComplete
                      ? const Color(0xFF13795B)
                      : const Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    calibrationComplete
                        ? strings.text('Static calibration complete')
                        : calibrating
                            ? strings.text('Calibration in progress')
                            : strings.text('Static calibration required'),
                    style: TextStyle(
                      color: calibrationComplete
                          ? const Color(0xFF13795B)
                          : const Color(0xFF8A4B08),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      _busy ? null : () => _handlePrimaryAction(backendStatus),
                  icon: Icon(
                    backendStatus.streamingActive
                        ? Icons.link_off_rounded
                        : Icons.link_rounded,
                  ),
                  label: Text(
                    _busy ? strings.text('Checking sensor...') : actionLabel,
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
                onPressed: allConnected && calibrationComplete && !_busy
                    ? widget.onContinue
                    : null,
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
