import 'package:flutter/material.dart';

class ScanGuideOverlay extends StatelessWidget {
  final double width;
  final double height;
  final String label;

  const ScanGuideOverlay({
    super.key,
    required this.width,
    required this.height,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            // Subtly darkened overlay is REMOVED to keep it "box-free"
            
            // 4 Minimal Corner Markers (L-Shapes)
            _buildCorners(),
            
            // Alignment Label
            Positioned(
              bottom: -40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorners() {
    const double cornerSize = 24.0;
    const double thickness = 2.0;
    const Color cornerColor = Colors.white;

    Widget corner(double? t, double? b, double? l, double? r, bool isVertical) {
      return Positioned(
        top: t, bottom: b, left: l, right: r,
        child: Container(
          width: isVertical ? thickness : cornerSize,
          height: isVertical ? cornerSize : thickness,
          decoration: BoxDecoration(
            color: cornerColor,
            borderRadius: BorderRadius.circular(thickness / 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, spreadRadius: 0.5)
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Top Left
        corner(0, null, 0, null, false), corner(0, null, 0, null, true),
        // Top Right
        corner(0, null, null, 0, false), corner(0, null, null, 0, true),
        // Bottom Left
        corner(null, 0, 0, null, false), corner(null, 0, 0, null, true),
        // Bottom Right
        corner(null, 0, null, 0, false), corner(null, 0, null, 0, true),
      ],
    );
  }
}
