import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/site.dart';
import '../widgets/site_map_widget.dart';
import '../widgets/upload_dial_widget.dart';

class OnlineMapScreen extends StatelessWidget {
  final Position? userPosition;
  final List<Site> sites;
  final String name;
  final String email;
  final String org;

  const OnlineMapScreen({
    super.key,
    required this.userPosition,
    required this.sites,
    required this.name,
    required this.email,
    required this.org,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: Colors.black,
      backgroundColor: const Color(0xFF0D1B22), // Dark background
      body: SafeArea(
        child: Column(
          children: [
            // Header with close button - matching home screen styling
            Container(
              padding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Center(
                    child: const Text(
                      'FOMO',
                      style: TextStyle(
                        color: Color.fromARGB(255, 199, 220, 237),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'trump',
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Color.fromARGB(255, 199, 220, 237),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Upload dial widget
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: UploadDialWidget(sites: sites),
            ),
            const SizedBox(height: 16),

            // Enhanced map widget with KML support
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: SiteMapWidget(
                  userPosition: userPosition,
                  sites: sites,
                  height: double.infinity,
                  geojsonAssetPath: 'assets/maps/sites.geojson', // GeoJSON file
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Info panel with matching theme
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E0E).withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(
                      255,
                      20,
                      172,
                      243,
                    ).withOpacity(0.25),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(color: const Color(0xFF1A4273)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Map Legend',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color.fromARGB(255, 3, 150, 248), // Blue
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Transect',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFD700), // Gold
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Sites',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color.fromARGB(
                            255,
                            138,
                            43,
                            226,
                          ), // Dark violet
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Block',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  // const SizedBox(height: 8),
                  // const Text(
                  //   '• Switch between KML and Sites data\n• Choose from Contour, Terrain, or Satellite maps\n• All maps optimized for dark mode',
                  //   style: TextStyle(color: Colors.white54, fontSize: 12),
                  // ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
