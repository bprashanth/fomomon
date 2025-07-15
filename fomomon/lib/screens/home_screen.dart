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

class HomeScreen extends StatefulWidget {
  final String name;
  final String email;
  final String org;
  final String bucketName;

  const HomeScreen({
    required this.name,
    required this.email,
    required this.org,
    required this.bucketName,
    super.key,
  });

  String getBucketRoot() => "https://$bucketName.s3.amazonaws.com/$org/";

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _userPos;
  List<Site> _sites = [];
  // _nearestSite is the site that is closest to the user's position
  // It is used to determine if the "+" button should be enabled
  Site? _nearestSite;

  // A note on trigger radius:
  // - Typically, it's 3-5 meters with LocationAccuracy.high
  // - Indoor due to GPS signal attenuation, it's more like 5-10m
  final double triggerRadius = 10.0;
  String? bucketRoot;

  @override
  void initState() {
    super.initState();
    bucketRoot = widget.getBucketRoot();
    _init();
  }

  Future<void> _init() async {
    final ok = await GpsService.ensurePermission();
    if (!ok) return;

    final sites = await SiteService.fetchSites(bucketRoot!);
    setState(() => _sites = sites);

    // Listen to the position stream and update the state with the latest
    // position and the closest site. This is a good place to do any
    // geolocation based processing.
    GpsService.getPositionStream().listen((userPos) {
      final nearby = _getClosestSite(userPos, _sites);
      setState(() {
        _userPos = userPos;
        _nearestSite = nearby;
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
      body: Stack(
        children: [
          GpsFeedbackPanel(user: _userPos, sites: _sites),
          Align(
            alignment: Alignment.bottomCenter,
            child: PlusButton(
              enabled: _nearestSite != null,
              onPressed: () {
                // navigate to pipeline
              },
            ),
          ),
        ],
      ),
    );
  }
}
