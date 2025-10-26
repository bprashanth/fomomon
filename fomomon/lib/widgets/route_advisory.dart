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
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            // BoxShadow(
            //   color: Colors.greenAccent.withOpacity(0.3),
            //   blurRadius: 6,
            //   spreadRadius: 1,
            // ),
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.3),
              // color: const Color.fromARGB(
              //   255,
              //   20,
              //   172,
              //   243,
              // ).withOpacity(0.25), // near-white green
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF4FFD73),
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
