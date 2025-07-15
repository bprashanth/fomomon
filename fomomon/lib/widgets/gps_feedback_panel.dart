/// gps_feedback_panel.dart
/// ------------------------
/// Widget that visually displays user's position and nearby sites
/// Does not use an actual map—renders dot offsets relative to user
///
/// Args:
/// - user: Position?
/// - sites: List<Site>
///
/// Renders:
/// - Red dots indicate nearby sites
/// - Yellow dot indicates user's position
///
/// How it works:
/// - The rendering happens by subtracting Geolocator's distanceBetween
///   from the user's position to the site's position
/// - Since we're not using maps, this subtraction is done in degrees
///   and then converted to pixels using a fixed scale factor
/// - The panels has a fixed size of 200x200 pixels. We use a scale factor of
///   0.5 to convert meters to pixels.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/site.dart';

class GpsFeedbackPanel extends StatelessWidget {
  final Position? user;
  final List<Site> sites;

  const GpsFeedbackPanel({super.key, required this.user, required this.sites});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(children: [_buildUserDot(), ..._buildSiteDots()]),
      ),
    );
  }

  Widget _buildUserDot() => const Positioned(
    left: 90,
    top: 90,
    child: Icon(Icons.person_pin_circle, size: 20, color: Colors.yellow),
  );

  List<Widget> _buildSiteDots() {
    if (user == null) return [];

    return sites.map((site) {
      final dx = Geolocator.distanceBetween(
        user!.latitude,
        user!.longitude,
        user!.latitude,
        site.lng,
      );
      final dy = Geolocator.distanceBetween(
        user!.latitude,
        user!.longitude,
        site.lat,
        user!.longitude,
      );

      final left = 90 + dx * (site.lng > user!.longitude ? 1 : -1) * 0.5;
      final top = 90 + dy * (site.lat > user!.latitude ? 1 : -1) * 0.5;

      // The clamp() is used to ensure that the left and top values are within
      // bounds 0-180 pixels. This gives us a range of 360m for sites. Far away
      // sites will appear as dots on the edge of the panel.
      return Positioned(
        left: left.clamp(0, 180),
        top: top.clamp(0, 180),
        child: const Icon(Icons.location_on, size: 20, color: Colors.red),
      );
    }).toList();
  }
}
