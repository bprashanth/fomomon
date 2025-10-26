import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/site.dart';
import 'pulsing_dot.dart';

class GpsFeedbackPanel extends StatefulWidget {
  final Position? user;
  final List<Site> sites;
  final double heading;

  const GpsFeedbackPanel({
    super.key,
    required this.user,
    required this.sites,
    required this.heading,
  });

  @override
  State<GpsFeedbackPanel> createState() => _GpsFeedbackPanelState();
}

class _GpsFeedbackPanelState extends State<GpsFeedbackPanel> {
  double _pitch = 0;

  @override
  void initState() {
    super.initState();

    accelerometerEvents.listen((e) {
      if (!mounted) return;
      final newPitch = atan2(-e.x, sqrt(e.y * e.y + e.z * e.z)) * 180 / pi;
      // simple moving average to stabilize
      _pitch = (_pitch * 0.9) + (newPitch * 0.1);
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user == null) {
      return const Center(
        child: Text(
          "Acquiring GPS...",
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final size = MediaQuery.of(context).size.width;

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // --- radar canvas ---
            CustomPaint(
              size: Size(size, size),
              painter: _CompassPainter(
                user: widget.user!,
                sites: widget.sites,
                heading: widget.heading,
                incline: _pitch,
              ),
              child: Center(
                child: PulsingDot(color: const Color(0xFF7CFF8F), size: 10),
              ),
            ),

            // --- distance legend at bottom ---
            Positioned(
              right: size * 0.05, // tweak until it visually aligns
              bottom: 0,
              child: _DistanceLegend(metersPerPixel: 2.0, maxR: size / 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final Position user;
  final List<Site> sites;
  final double heading;
  final double incline;

  _CompassPainter({
    required this.user,
    required this.sites,
    required this.heading,
    required this.incline,
  });

  static const double metersPerPixel = 2.0;
  static const Color radarGreen = Color(0xFF7CFF8F); // Site dots color

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // === 1. Pronounced depth bands with visible separation ===
    final bandCount = 6;

    // Revised color palette (cooler & more contrast with visible bands)
    final baseColors = [
      const Color(0xFF6B8BA6), // innermost — bright blue-gray
      const Color(0xFF557489), // light-medium transition
      const Color(0xFF3F5D73), // medium blue-gray
      const Color(0xFF29485E), // deep cool tone
      const Color(0xFF1A3647), // very dark edge
      const Color(0xFF0D1F2F), // outermost — deepest blue-gray
    ];

    for (int i = 0; i < bandCount; i++) {
      final innerR = maxR * (i / bandCount) * 0.9;
      final outerR = maxR * ((i + 1) / bandCount) * 0.9;

      // create a gradient with slightly inverted light direction (inner darker, outer lighter)
      final shader = RadialGradient(
        center: const Alignment(0.0, -0.3), // top-light effect
        radius: 1.0,
        colors: [
          baseColors[i].withOpacity(1.0), // main tone
          baseColors[i].withOpacity(0.9),
          baseColors[min(i + 1, baseColors.length - 1)].withOpacity(
            0.6 + (i * 0.05),
          ), // outer light edge
          Colors.white.withOpacity(0.06 + i * 0.02), // faint light catch
        ],
        stops: const [0.0, 0.55, 0.85, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerR));

      final bandPaint =
          Paint()
            ..shader = shader
            ..style = PaintingStyle.fill;

      canvas.saveLayer(
        Rect.fromCircle(center: center, radius: outerR),
        Paint(),
      );
      // outer circle
      canvas.drawCircle(center, outerR, bandPaint);

      // add subtle soft shadow on the inner edge (enhances 3D feel)
      final shadowPaint =
          Paint()
            ..color = Colors.black.withOpacity(0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 6);
      canvas.drawCircle(center, innerR, shadowPaint);

      // erase inside to form the ring
      final erase = Paint()..blendMode = BlendMode.clear;
      canvas.drawCircle(center, innerR, erase);
      canvas.restore();
    }

    // === 2. Fine concentric ring strokes ===
    for (int i = 1; i <= bandCount; i++) {
      final progress = i / bandCount;
      final strokeColor = Colors.white.withOpacity(0.05 + progress * 0.04);
      canvas.drawCircle(
        center,
        progress * maxR * 0.9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = strokeColor,
      );
    }

    // === 3. Outer glow ===
    final halo = RadialGradient(
      colors: [
        Colors.white.withOpacity(0.15),
        Colors.grey.withOpacity(0.05),
        Colors.black.withOpacity(0.0),
      ],
      stops: const [0.7, 0.9, 1.0],
    );
    canvas.drawCircle(
      center,
      maxR,
      Paint()
        ..shader = halo.createShader(
          Rect.fromCircle(center: center, radius: maxR),
        ),
    );

    // === 4. Sites (world-fixed) ===
    for (final site in sites) {
      final distance = Geolocator.distanceBetween(
        user.latitude,
        user.longitude,
        site.lat,
        site.lng,
      );
      if (distance > maxR * metersPerPixel * 2) continue;

      final bearing = Geolocator.bearingBetween(
        user.latitude,
        user.longitude,
        site.lat,
        site.lng,
      );
      // Rotate opposite to heading to maintain world-fixed positions (same as compass marks)
      final angle = (bearing - heading) * pi / 180;
      final r = (distance / metersPerPixel).clamp(0, maxR * 0.9);
      final pos = center + Offset(r * sin(angle), -r * cos(angle));

      // dot without glow
      canvas.drawCircle(pos, 8, Paint()..color = radarGreen);

      // label above each dot
      final tp = TextPainter(
        text: TextSpan(
          text: site.id,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, 18));
    }

    // === 4. Light cone (draw last, always on top) ===
    const coneSweep = 60.0; // degrees width
    final conePaint =
        Paint()
          ..color = const Color(0xFF00FFFF).withOpacity(
            0.5,
          ) // Cyan/light blue-green
          ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(heading * pi / 180);

    final conePath =
        Path()
          ..moveTo(0, 0)
          ..arcTo(
            Rect.fromCircle(center: Offset.zero, radius: maxR * 0.9),
            90 * pi / 180 -
                coneSweep /
                    2 *
                    pi /
                    180, // start at 90° (down) minus half cone width
            coneSweep * pi / 180, // sweep the cone width
            false,
          )
          ..close();

    canvas.drawPath(conePath, conePaint);
    canvas.restore();

    // === 5. N / S / E / W marks ===
    _drawCompassMarks(canvas, center, maxR * 0.93, heading);

    // === 6. Thick border band for metrics ===
    // Outer darker ring
    final outerBandPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF000000).withOpacity(0.7);
    canvas.drawCircle(center, maxR * 0.85, outerBandPaint);

    // Inner cut-out to create thickness (erase inner part)
    final innerBandPaint =
        Paint()..blendMode = BlendMode.clear; // subtract inner circle
    canvas.saveLayer(Rect.fromCircle(center: center, radius: maxR), Paint());
    canvas.drawCircle(center, maxR * 0.85, outerBandPaint);
    canvas.drawCircle(center, maxR * 0.65, innerBandPaint);
    canvas.restore();

    final bandGlow =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withOpacity(0.1);
    canvas.drawCircle(center, maxR * 0.75, bandGlow);

    // === 7. Curved ring text ===
    _drawCurvedText(
      canvas,
      center,
      maxR * 0.75,
      "ELEV ${user.altitude.toStringAsFixed(0)} m",
      210,
      270,
    );
    _drawCurvedText(
      canvas,
      center,
      maxR * 0.75,
      "INCL ${incline.toStringAsFixed(1)}°",
      290,
      350,
    );
    _drawCurvedText(
      canvas,
      center,
      maxR * 0.75,
      "LAT ${user.latitude.toStringAsFixed(2)}",
      30,
      90,
    );
    _drawCurvedText(
      canvas,
      center,
      maxR * 0.75,
      "LON ${user.longitude.toStringAsFixed(2)}",
      110,
      170,
    );
  }

  // --- compass marks rotate opposite heading ---
  void _drawCompassMarks(Canvas canvas, Offset c, double r, double heading) {
    final labels = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < 4; i++) {
      final baseAngle = (i * 90) - heading; // rotate opposite
      final angle = baseAngle * pi / 180;
      final pos = Offset(c.dx + r * sin(angle), c.dy - r * cos(angle));

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: i == 0 ? Colors.white : Colors.white70,
            fontSize: i == 0 ? 14 : 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  // --- draw text following arc between startDeg and endDeg ---
  void _drawCurvedText(
    Canvas canvas,
    Offset c,
    double r,
    String text,
    double startDeg,
    double endDeg,
  ) {
    final span = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();

    final sweep = (endDeg - startDeg) * pi / 180;
    final textArcLength = tp.width / r;
    final offsetAngle = (sweep - textArcLength) / 2 + startDeg * pi / 180;
    final anglePerChar = textArcLength / text.length;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final charTp = TextPainter(
        text: TextSpan(text: char, style: span.style),
        textDirection: TextDirection.ltr,
      )..layout();
      final theta = offsetAngle + i * anglePerChar;
      final x = c.dx + r * cos(theta);
      final y = c.dy + r * sin(theta);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(theta + pi / 2);
      charTp.paint(canvas, Offset(-charTp.width / 2, -charTp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      old.heading != heading ||
      old.incline != incline ||
      old.user.latitude != user.latitude ||
      old.user.longitude != user.longitude ||
      old.sites != sites;
}

// Indicates the distance of 1 ring in meters.
class _DistanceLegend extends StatelessWidget {
  final double metersPerPixel;
  final double maxR;

  const _DistanceLegend({required this.metersPerPixel, required this.maxR});

  @override
  Widget build(BuildContext context) {
    // total range represented by the radar's radius
    final visibleMeters = (maxR * metersPerPixel).toInt();
    final ringCount = 5; // same as your painter rings
    final ringSpacing = (visibleMeters / ringCount).round();
    final color = Colors.white.withOpacity(0.6);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- line with end caps ---
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 2, height: 10, color: color),
            Container(width: 60, height: 2, color: color),
            Container(width: 2, height: 10, color: color),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '1 ring ≈ $ringSpacing m',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
