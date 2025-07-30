/// home_screen.dart
/// ------------------
/// Displays GPS dot for the user and nearby site markers
/// Highlights "+" button if user is within proximity of a site
/// Taps on "+" trigger the capture workflow

import 'package:flutter/material.dart';
import '../services/gps_service.dart';
import '../services/site_service.dart';
import '../models/site.dart';
import '../widgets/gps_feedback_panel.dart';
import '../widgets/plus_button.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/user_utils.dart';
import '../screens/capture_screen.dart';
import 'dart:async';
import 'dart:ui';
import '../widgets/upload_dial_widget.dart';

class HomeScreen extends StatefulWidget {
  final String name;
  final String email;
  final String org;

  const HomeScreen({
    required this.name,
    required this.email,
    required this.org,
    super.key,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _userPos;
  List<Site> _sites = [];
  // _nearestSite is the site that is closest to the user's position
  // It is used to determine if the "+" button should be enabled
  Site? _nearestSite;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastAcceptedUserPos;

  // Distance threshold is used to filter out positions that are too close to
  // the last accepted position. This is used to avoid updating the nearest
  // site/site marker too often.
  final double _distanceThreshold = 2.0; // meters

  // Accuracy threshold is used to filter out positions that are too inaccurate
  // according to the GPS system itself. Accuracy of 10 is the system saying "I
  // am 68% sure (1SD) that the true location is within 10m of this reported
  // point". Indoors, the value of this accuracy number could be as high as
  // 20-100m.
  final double _accuracyThreshold = 20.0; // meters

  // A note on trigger radius:
  // - Typically, it's 3-5 meters with LocationAccuracy.high
  // - Indoor due to GPS signal attenuation, it's more like 5-10m
  final double triggerRadius = 500.0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final ok = await GpsService.ensurePermission();
    if (!ok) return;

    // Fetch the sites and prefetch the images every home screen load.
    // Typically, all images should have been prefetched at the
    // site_prefetch_screen, on login. So this fetch operation should be
    // incremental, i.e only new reference images, new sites etc.
    //
    // Use async mode to return cached data immediately while fetching fresh
    // data in background.
    final sites = await SiteService.fetchSitesAndPrefetchImages(async: true);
    setState(() => _sites = sites);

    // Listen to the position stream and update the state with the latest
    // position and the closest site. This is a good place to do any
    // geolocation based processing.
    _positionSubscription = GpsService.getPositionStream().listen((userPos) {
      if (!mounted) return;

      // Accuracy filter
      if (userPos.accuracy > _accuracyThreshold) {
        print("home_screen: accuracy: ${userPos.accuracy}, skipping");
        return;
      }

      // Distance threshold filter
      if (_lastAcceptedUserPos != null) {
        final distance = Geolocator.distanceBetween(
          _lastAcceptedUserPos!.latitude,
          _lastAcceptedUserPos!.longitude,
          userPos.latitude,
          userPos.longitude,
        );
        if (distance < _distanceThreshold) {
          print("home_screen: distance: $distance, skipping");
          return;
        }
      }

      final nearby = _getClosestSite(userPos, _sites);
      print("home_screen: userPos: $userPos, nearby: $nearby");
      setState(() {
        _userPos = userPos;
        _nearestSite = nearby;
        _lastAcceptedUserPos = userPos;
      });
    });
  }

  Site? _getClosestSite(Position user, List<Site> sites) {
    for (final site in sites) {
      final d = GpsService.distanceInMeters(
        user.latitude,
        user.longitude,
        site.lat,
        site.lng,
      );
      if (d < triggerRadius) return site;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final gpsTop = screenHeight * 0.40; // 12% from top
          final fomoTop = screenHeight * 0.05; // 4% from top
          final uploadTop = screenHeight * 0.20; // 10% from top

          return Stack(
            children: [
              // FOMO top-center
              Positioned(
                top: fomoTop,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'FOMO',
                    style: TextStyle(
                      color: const Color.fromARGB(255, 199, 220, 237),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'trump',
                    ),
                  ),
                ),
              ),
              // Upload dial widget below FOMO
              Positioned(
                top: uploadTop, // ~below FOMO
                left: 0,
                right: 0,
                child: Center(
                  child: UploadDialWidget(
                    sites: _sites,
                    // No need to pass anything here, the widget will handle it
                  ),
                ),
              ),

              // GPS panel with relative top
              Positioned(
                top: gpsTop,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: GpsFeedbackPanel(user: _userPos, sites: _sites),
                    ),
                  ),
                ),
              ),

              // Floating plus button (still anchored to bottom, which is fine)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 32),
                  child: PlusButton(
                    enabled: _nearestSite != null,
                    onPressed: () {
                      if (_nearestSite != null) {
                        _launchPipeline(
                          context,
                          getUserId(widget.name, widget.email, widget.org),
                          _nearestSite!,
                          widget.name,
                          widget.email,
                          widget.org,
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Utility function to launch the pipeline screen.
void _launchPipeline(
  BuildContext context,
  String userId,
  Site site,
  String name,
  String email,
  String org,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (_) => CaptureScreen(
            captureMode: 'portrait',
            site: site,
            userId: userId,
            name: name,
            email: email,
            org: org,
          ),
    ),
  );
}
