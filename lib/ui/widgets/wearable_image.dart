import 'package:flutter/material.dart';

class WearableImage extends StatelessWidget {
  const WearableImage({
    super.key,
    required this.asset,
    this.onMarker1,
    this.onMarker2,
    this.device1Connected = false,
    this.device2Connected = false,
    this.height = 320,
    this.boxFit = BoxFit.contain,
    this.marker1Position = const Offset(0.69, 0.32),
    this.marker2Position = const Offset(0.64, 0.56),
  });

  final String asset;
  final VoidCallback? onMarker1;
  final VoidCallback? onMarker2;
  final bool device1Connected;
  final bool device2Connected;
  final double height;
  final BoxFit boxFit;
  final Offset marker1Position;
  final Offset marker2Position;

  Widget _marker({
    required String label,
    required bool connected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: connected ? const Color(0xFF20B26C) : const Color(0xFFE5484D),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(builder: (context, constraints) {
          final displayHeight = height;
          return SizedBox(
            width: double.infinity,
            height: displayHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  asset,
                  fit: boxFit,
                  width: constraints.maxWidth,
                  height: displayHeight,
                  errorBuilder: (context, error, stackTrace) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFEEF4F6), Color(0xFFDDEBE8)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.accessibility_new_rounded,
                          size: 66, color: Color(0xFF7A8698)),
                    ),
                  ),
                ),
                if (onMarker1 != null)
                  Positioned(
                    left: constraints.maxWidth * marker1Position.dx - 18,
                    top: displayHeight * marker1Position.dy - 18,
                    child: _marker(
                      label: '1',
                      connected: device1Connected,
                      onTap: onMarker1!,
                    ),
                  ),
                if (onMarker2 != null)
                  Positioned(
                    left: constraints.maxWidth * marker2Position.dx - 18,
                    top: displayHeight * marker2Position.dy - 18,
                    child: _marker(
                      label: '2',
                      connected: device2Connected,
                      onTap: onMarker2!,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
