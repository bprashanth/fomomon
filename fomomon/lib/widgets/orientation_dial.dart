import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// OrientationDial
/// ---------------
/// Shows a simple circular graphic for \"turn to match\" guidance:
/// - Top marker = reference heading (how the original site image was taken)
/// - Moving marker = current device heading
///
/// Used on the first portrait capture screen to help users turn around the
/// site (left/right) to roughly match the original framing. This is about
/// circular turning, not up/down tilt.
///
/// On web/PWA we typically don't have a reliable compass; callers should pass
/// null for [currentHeading] in that case, and the widget will render nothing.
class OrientationDial extends StatelessWidget {
  final double referenceHeading;
  final double? currentHeading;

  const OrientationDial({
    super.key,
    required this.referenceHeading,
    required this.currentHeading,
  });

  @override
  Widget build(BuildContext context) {
    if (currentHeading == null || kIsWeb) {
      // No heading available (or web/PWA) → don't show the dial.
      return const SizedBox.shrink();
    }

    // Compute diff between reference and current heading in [-180, 180].
    double diff = (referenceHeading - currentHeading! + 360) % 360;
    if (diff > 180) diff -= 180 * 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: CustomPaint(
            painter: _OrientationDialPainter(diff: diff),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Turn to match',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _OrientationDialPainter extends CustomPainter {
  final double diff;

  _OrientationDialPainter({required this.diff});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 4;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.7);

    final aligned = diff.abs() < 15;

    // Draw outer circle
    canvas.drawCircle(
      center,
      radius,
      basePaint..color = aligned ? Colors.greenAccent : basePaint.color,
    );

    // Draw reference marker at top (0 degrees)
    final refMarkerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = aligned ? Colors.greenAccent : Colors.white;
    final refAngle = -pi / 2;
    final refOffset = Offset(
      center.dx + radius * cos(refAngle),
      center.dy + radius * sin(refAngle),
    );
    canvas.drawCircle(refOffset, 3, refMarkerPaint);

    // Draw current heading marker: rotate by -diff around the circle so the
    // relative offset shows how much to turn left/right.
    final currentAngle = -pi / 2 - (diff * pi / 180);
    final currentOffset = Offset(
      center.dx + radius * cos(currentAngle),
      center.dy + radius * sin(currentAngle),
    );
    final currentPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = aligned ? Colors.greenAccent : Colors.yellowAccent;
    canvas.drawCircle(currentOffset, 3, currentPaint);
  }

  @override
  bool shouldRepaint(covariant _OrientationDialPainter oldDelegate) {
    return oldDelegate.diff != diff;
  }
}

