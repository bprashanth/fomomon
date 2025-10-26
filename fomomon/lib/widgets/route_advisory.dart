import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/site.dart';

class AdvisoryBanner extends StatelessWidget {
  final Position? user;
  final Site site;
  final double heading;

  const AdvisoryBanner({
    super.key,
    required this.user,
    required this.site,
    required this.heading,
  });

  @override
  Widget build(BuildContext context) {
    if (user == null) return const SizedBox();

    final bearing = Geolocator.bearingBetween(
      user!.latitude,
      user!.longitude,
      site.lat,
      site.lng,
    );

    final message = advisoryFromBearing(bearing, heading);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(
            0xFF1A2024,
          ).withOpacity(0.9), // Dark grey panel background
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFF9F8F4),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

String advisoryFromBearing(double bearing, double heading) {
  double diff = (bearing - heading + 360) % 360;
  if (diff > 180) diff -= 360;

  if (diff.abs() < 15) return "You're facing the site";
  if (diff > 15 && diff <= 45) return "Turn slightly right";
  if (diff < -15 && diff >= -45) return "Turn slightly left";
  if (diff > 45 && diff <= 135) return "Turn right";
  if (diff < -45 && diff >= -135) return "Turn left";
  if (diff.abs() > 135) return "Turn around";

  return "Head ${bearingToCompass(bearing)}";
}

String bearingToCompass(double bearing) {
  const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return dirs[((bearing % 360) / 45).round() % 8];
}
