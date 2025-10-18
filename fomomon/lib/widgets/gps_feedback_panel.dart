import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
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
  double _heading = 0;
  double _pitch = 0;

  @override
  void initState() {
    super.initState();

    FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() => _heading = event.heading ?? 0);
    });

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

    final size = MediaQuery.of(context).size.width * 0.9;

    return Center(
      child: CustomPaint(
        size: Size(size, size),
        painter: _CompassPainter(
          user: widget.user!,
          sites: widget.sites,
          heading: _heading,
          incline: _pitch,
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
  final double incline;

  _CompassPainter({
    required this.user,
    required this.sites,
    required this.heading,
    required this.incline,
  });

  static const double metersPerPixel = 2.0;
  static const Color radarGreen = Color(0xFF00FF80);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // === 1 Pronounced depth bands (green-toned 3D look) ===
    final bandCount = 6;
    final baseColors = [
      const Color(0xFF001509), // deep inner green-black
      const Color(0xFF013d1a), // dark forest
      const Color(0xFF026b31), // mid green
      const Color(0xFF05a150), // bright green
      const Color(0xFF38c985), // pale mint
      const Color.fromARGB(255, 137, 231, 247), // near-white green
    ];

    for (int i = 0; i < bandCount; i++) {
      final innerR = maxR * (i / bandCount) * 0.9;
      final outerR = maxR * ((i + 1) / bandCount) * 0.9;

      // darker inside - lighter outer edge per band
      final shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          baseColors[i].withOpacity(1.0),
          baseColors[i].withOpacity(0.9),
          baseColors[min(i + 1, baseColors.length - 1)].withOpacity(0.7),
          Colors.white.withOpacity(0.08 + i * 0.02),
        ],
        stops: const [0.0, 0.45, 0.85, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerR));

      final bandPaint =
          Paint()
            ..shader = shader
            ..style = PaintingStyle.fill;

      canvas.saveLayer(
        Rect.fromCircle(center: center, radius: outerR),
        Paint(),
      );
      // draw outer
      canvas.drawCircle(center, outerR, bandPaint);
      // erase inner to make ring
      final erase = Paint()..blendMode = BlendMode.clear;
      canvas.drawCircle(center, innerR, erase);
      canvas.restore();
    }

    // === 2. Concentric rings ===
    for (int i = 1; i <= 6; i++) {
      final progress = i / 6;
      final color = Colors.white.withOpacity(0.04 + progress * 0.05);
      canvas.drawCircle(
        center,
        progress * maxR * 0.9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color,
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
      final angle = bearing * pi / 180;
      final r = (distance / metersPerPixel).clamp(0, maxR * 0.9);
      final pos = center + Offset(r * sin(angle), -r * cos(angle));

      // glow + dot
      canvas.drawCircle(
        pos,
        14,
        Paint()
          ..color = radarGreen.withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
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

    // === Light cone (draw last, always on top) ===
    const coneSweep = 40.0; // degrees width
    final conePaint =
        Paint()
          ..color = const Color.fromARGB(255, 3, 150, 248).withOpacity(0.5)
          ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(heading * pi / 180);

    final conePath =
        Path()
          ..moveTo(0, 0)
          ..arcTo(
            Rect.fromCircle(center: Offset.zero, radius: maxR * 0.9),
            -coneSweep / 2 * pi / 180,
            coneSweep * pi / 180,
            false,
          )
          ..close();

    canvas.drawPath(conePath, conePaint);
    canvas.restore();

    // === 6. N / S / E / W marks ===
    _drawCompassMarks(canvas, center, maxR * 0.93, heading);

    // === Thick border band for metrics ===
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
