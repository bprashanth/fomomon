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
    final sites = await SiteService.fetchSitesAndPrefetchImages();
    setState(() => _sites = sites);

    // Listen to the position stream and update the state with the latest
    // position and the closest site. This is a good place to do any
    // geolocation based processing.
    _positionSubscription = GpsService.getPositionStream().listen((userPos) {
      if (mounted) {
        final nearby = _getClosestSite(userPos, _sites);
        print("home_screen: userPos: $userPos, nearby: $nearby");
        setState(() {
          _userPos = userPos;
          _nearestSite = nearby;
        });
      }
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
      body: Stack(
        children: [
          GpsFeedbackPanel(user: _userPos, sites: _sites),
          Align(
            alignment: Alignment.bottomCenter,
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
        ],
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
