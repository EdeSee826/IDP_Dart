import 'package:flutter/material.dart';

class DeviceStatusTile extends StatelessWidget {
  const DeviceStatusTile({
    super.key,
    required this.title,
    required this.connected,
  });

  final String title;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        connected ? const Color(0xFF1E9E58) : const Color(0xFFD14343);
    final statusText = connected ? 'Connected' : 'Disconnected';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: statusColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1F2D),
              ),
            ),
          ),
          Text(
            statusText,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}
