import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../models/site.dart';
import 'pulsing_dot.dart';

class GpsFeedbackPanel extends StatefulWidget {
  final Position? user;
  final List<Site> sites;

  const GpsFeedbackPanel({super.key, required this.user, required this.sites});

  @override
  State<GpsFeedbackPanel> createState() => _GpsFeedbackPanelState();
}

class _GpsFeedbackPanelState extends State<GpsFeedbackPanel> {
  double? _heading;

  @override
  void initState() {
    super.initState();
    // Listen to compass heading
    FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() => _heading = event.heading ?? 0);
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

    final size = MediaQuery.of(context).size.width * 0.9; // nearly full width

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            radius: 0.9,
            colors: [
              Color(0xFF00111F), // dark center
              Color(0xFF002A3E),
              Color(0xFF003D54),
              Color(0xFF005E72),
            ],
            stops: [0.1, 0.4, 0.7, 1.0],
          ),
        ),
        child: CustomPaint(
          painter: _RadarPainter(
            user: widget.user!,
            sites: widget.sites,
            heading: _heading ?? 0,
          ),
          child: Center(
            child: PulsingDot(
              color: const Color.fromARGB(255, 0, 255, 128),
              size: 10,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws radar rings and site dots relative to user
class _RadarPainter extends CustomPainter {
  final Position user;
  final List<Site> sites;
  final double heading;
  static const double metersPerPixel = 2.0; // scale factor

  _RadarPainter({
    required this.user,
    required this.sites,
    required this.heading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 1️⃣ Draw concentric rings
    final ringPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withOpacity(0.08)
          ..strokeWidth = 1.0;

    for (double r = maxRadius / 4; r <= maxRadius; r += maxRadius / 4) {
      canvas.drawCircle(center, r, ringPaint);
    }

    // 2️⃣ Draw semi-transparent gradient overlay to make shading smoother
    final ringGradient = RadialGradient(
      colors: [Colors.white.withOpacity(0.02), Colors.white.withOpacity(0.0)],
      stops: const [0.8, 1.0],
    );
    final rect = Rect.fromCircle(center: center, radius: maxRadius);
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()..shader = ringGradient.createShader(rect),
    );

    // 3️⃣ Draw each site relative to user
    for (final site in sites) {
      final distance = Geolocator.distanceBetween(
        user.latitude,
        user.longitude,
        site.lat,
        site.lng,
      );

      if (distance > maxRadius * metersPerPixel * 2) continue; // too far, skip

      final bearing = Geolocator.bearingBetween(
        user.latitude,
        user.longitude,
        site.lat,
        site.lng,
      );

      // Convert to radians and adjust for device heading
      final relativeAngle = ((bearing - heading + 360) % 360) * pi / 180;

      // Distance to pixel radius (capped to ring edge)
      final radius = (distance / metersPerPixel).clamp(0, maxRadius);

      final dx = radius * sin(relativeAngle);
      final dy = -radius * cos(relativeAngle);
      final sitePos = center + Offset(dx, dy);

      // Draw glowing dot
      final siteColor = const Color(0xFF00FFB2);
      final glowPaint =
          Paint()
            ..color = siteColor.withOpacity(0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(sitePos, 12, glowPaint);

      final dotPaint = Paint()..color = siteColor;
      canvas.drawCircle(sitePos, 8, dotPaint);

      // Optional: site label
      final textPainter = TextPainter(
        text: TextSpan(
          text: site.id,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, sitePos - Offset(textPainter.width / 2, 16));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.heading != heading ||
        oldDelegate.user.latitude != user.latitude ||
        oldDelegate.user.longitude != user.longitude ||
        oldDelegate.sites != sites;
  }
}
