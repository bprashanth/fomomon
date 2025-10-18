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

    final size = MediaQuery.of(context).size.width * 0.9;

    return Center(
      child: CustomPaint(
        size: Size(size, size),
        painter: _CompassPainter(
          user: widget.user!,
          sites: widget.sites,
          heading: _heading ?? 0,
        ),
        child: Center(
          child: PulsingDot(color: const Color(0xFF00FF80), size: 10),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final Position user;
  final List<Site> sites;
  final double heading;

  _CompassPainter({
    required this.user,
    required this.sites,
    required this.heading,
  });

  static const double metersPerPixel = 2.0;
  static const Color radarGreen = Color(0xFF00FF80);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 🌑 1️⃣ Base dark-to-light radial gradient (inner dark → outer lighter)
    final background = RadialGradient(
      center: Alignment.center,
      radius: 1.2,
      colors: [
        const Color(0xFF050505),
        const Color(0xFF0A0F0A),
        const Color(0xFF1B2B1B),
        const Color(0xFF2C3E2C),
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );
    final bgPaint =
        Paint()
          ..shader = background.createShader(
            Rect.fromCircle(center: center, radius: maxRadius),
          );
    canvas.drawCircle(center, maxRadius, bgPaint);

    // 🌀 2️⃣ Concentric circles — darker inside, lighter outside
    final ringCount = 5;
    for (int i = 1; i <= ringCount; i++) {
      final progress = i / ringCount;
      final radius = progress * maxRadius * 0.9;
      final opacity = 0.05 + progress * 0.08; // gradually brighter
      final color = Colors.white.withOpacity(opacity);
      final ringPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = color;
      canvas.drawCircle(center, radius, ringPaint);
    }

    // 🌟 3️⃣ Outer white compass ring (thin bright rim)
    final outerRingPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withOpacity(0.3);
    canvas.drawCircle(center, maxRadius * 0.95, outerRingPaint);

    // ☁️ 4️⃣ Glow ring fading into background (outermost halo)
    final outerGlow = RadialGradient(
      colors: [
        Colors.white.withOpacity(0.15),
        Colors.grey.withOpacity(0.05),
        Colors.black.withOpacity(0.0),
      ],
      stops: const [0.7, 0.9, 1.0],
    );
    final glowPaint =
        Paint()
          ..shader = outerGlow.createShader(
            Rect.fromCircle(center: center, radius: maxRadius),
          );
    canvas.drawCircle(center, maxRadius, glowPaint);

    // 🔺 5️⃣ Direction cone (light wedge)
    const coneSweep = 35.0;
    final conePaint =
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white.withOpacity(0.1), Colors.transparent],
          ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
          ..style = PaintingStyle.fill;
    final conePath =
        Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(
            Rect.fromCircle(center: center, radius: maxRadius * 0.9),
            (-coneSweep / 2 - heading) * pi / 180,
            coneSweep * pi / 180,
            false,
          )
          ..close();
    canvas.drawPath(conePath, conePaint);

    // 🟢 6️⃣ Sites — same green, soft glow
    for (final site in sites) {
      final distance = Geolocator.distanceBetween(
        user.latitude,
        user.longitude,
        site.lat,
        site.lng,
      );
      if (distance > maxRadius * metersPerPixel * 2) continue;

      final bearing = Geolocator.bearingBetween(
        user.latitude,
        user.longitude,
        site.lat,
        site.lng,
      );
      final relativeAngle = ((bearing - heading + 360) % 360) * pi / 180;
      final radius = (distance / metersPerPixel).clamp(0, maxRadius * 0.9);
      final dx = radius * sin(relativeAngle);
      final dy = -radius * cos(relativeAngle);
      final sitePos = center + Offset(dx, dy);

      // glow
      final glowPaint =
          Paint()
            ..color = radarGreen.withOpacity(0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(sitePos, 14, glowPaint);

      // solid dot
      final dotPaint = Paint()..color = radarGreen;
      canvas.drawCircle(sitePos, 9, dotPaint);

      // label
      final tp = TextPainter(
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
      tp.layout();
      tp.paint(canvas, sitePos - Offset(tp.width / 2, 18));
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) =>
      old.heading != heading ||
      old.user.latitude != user.latitude ||
      old.user.longitude != user.longitude ||
      old.sites != sites;
}
