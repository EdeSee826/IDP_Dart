import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/backend_service.dart';
import '../../state/backend_status_provider.dart';

class StreamingControlPanel extends ConsumerStatefulWidget {
  const StreamingControlPanel({super.key});

  @override
  ConsumerState<StreamingControlPanel> createState() =>
      _StreamingControlPanelState();
}

class _StreamingControlPanelState extends ConsumerState<StreamingControlPanel> {
  bool _busy = false;
  String? _errorMessage;
  int _countdownSeconds = 15;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _showConnectionCountdown() {
    _countdownSeconds = 15;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (_countdownSeconds > 0) {
              setDialogState(() {
                _countdownSeconds--;
              });
            } else {
              timer.cancel();
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            }
          });

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            contentPadding: const EdgeInsets.all(24),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                const Text(
                  'Connecting XIAO Seeed Sensors...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1F2D),
                  ),
                ),
                const SizedBox(height: 30),
                // Countdown Circle
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0F5BA8).withOpacity(0.1),
                    border: Border.all(
                      color: const Color(0xFF0F5BA8),
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$_countdownSeconds',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F5BA8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Scanning for devices...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF657188),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: _countdownSeconds / 15,
                    backgroundColor: const Color(0xFFE3E8F0),
                    valueColor: AlwaysStoppedAnimation(
                      Color.lerp(
                        const Color(0xFF0F5BA8),
                        const Color(0xFFD14343),
                        1 - (_countdownSeconds / 15),
                      )!,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      _countdownTimer?.cancel();
    });
  }

  Future<void> _startStreaming() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    // Show countdown dialog
    _showConnectionCountdown();

    try {
      final result = await BackendService.startStreaming();
      if (!result.success) {
        _errorMessage = result.message ?? 'Failed to start streaming';
      }
      await ref.read(backendStatusProvider.notifier).refreshStatus();
    } catch (e) {
      _errorMessage = 'Error: $e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _stopStreaming() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final result = await BackendService.stopStreaming();
      if (!result.success) {
        _errorMessage = result.message ?? 'Failed to stop streaming';
      }
      await ref.read(backendStatusProvider.notifier).refreshStatus();
    } catch (e) {
      _errorMessage = 'Error: $e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendStatus = ref.watch(backendStatusProvider);
    final startDisabled = _busy ||
        backendStatus.streamingActive ||
        (!backendStatus.backendReady && backendStatus.errorMessage != null);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BLE Streaming Control',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1F2D),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: startDisabled ? null : _startStreaming,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    'Start',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F5BA8),
                    disabledBackgroundColor: const Color(0xFFCCCCCC),
                    foregroundColor: Colors.white,
                    iconColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || !backendStatus.streamingActive
                      ? null
                      : _stopStreaming,
                  icon: const Icon(Icons.stop),
                  label: const Text(
                    'Stop',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD14343),
                    disabledBackgroundColor: const Color(0xFFCCCCCC),
                    foregroundColor: Colors.white,
                    iconColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: backendStatus.streamingActive
                  ? const Color(0xFFE6F4EA)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: backendStatus.streamingActive
                    ? const Color(0xFF0F7B6C)
                    : const Color(0xFFDDDDDD),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: backendStatus.streamingActive
                        ? const Color(0xFF0F7B6C)
                        : const Color(0xFF999999),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _busy
                        ? 'Processing...'
                        : backendStatus.streamingActive
                            ? 'Streaming Active'
                            : 'Streaming Inactive',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: backendStatus.streamingActive
                          ? const Color(0xFF0F7B6C)
                          : const Color(0xFF666666),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF9CACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Color(0xFFB42318), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFB42318),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (backendStatus.errorMessage != null &&
              backendStatus.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF2C66D)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFB76E00), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      backendStatus.errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF8C4F00),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
