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
import 'package:geolocator/geolocator.dart';
import '../utils/user_utils.dart';
import '../screens/capture_screen.dart';
import 'dart:async';
import '../screens/site_selection_screen.dart';
import '../widgets/distance_info_panel.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../widgets/route_advisory.dart';
import '../widgets/online_mode_button.dart';

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
  List<Site> _sortedSites = [];
  // _nearestSite is the site that is closest to the user's position
  // It is used to launch the pipeline regardless of distance
  Site? _nearestSite;
  // _isWithinRange tracks whether the nearest site is within the trigger radius
  // It is used to determine if the "+" button should be enabled
  bool _isWithinRange = false;
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
  // TODO(prashanth@): make this 500 in test mode?
  final double triggerRadius = 30.0;

  // An index into the sites array. Used to indicate which site is currently
  // the focus of various panels like the disntance info panel and the route
  // advisory panel.
  int _currentIndex = 0;

  double _heading = 0.0;

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
      print(
        "[home_screen] userPos: $userPos, nearby: ${nearby.site?.id}, withinRange: ${nearby.isWithinRange} portraitPath: ${nearby.site?.localPortraitPath}, landscapePath: ${nearby.site?.localLandscapePath}",
      );

      setState(() {
        _userPos = userPos;
        _nearestSite = nearby.site;
        _isWithinRange = nearby.isWithinRange;
        _lastAcceptedUserPos = userPos;
        _sortedSites = sortSitesByDistance(userPos, _sites);
      });
    });

    FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() => _heading = event.heading ?? 0);
    });
  }

  ({Site? site, bool isWithinRange}) _getClosestSite(
    Position user,
    List<Site> sites,
  ) {
    if (sites.isEmpty) {
      return (site: null, isWithinRange: false);
    }

    Site? nearestSite;
    double nearestDistance = double.infinity;
    bool isWithinRange = false;

    for (final site in sites) {
      final d = GpsService.distanceInMeters(
        user.latitude,
        user.longitude,
        site.lat,
        site.lng,
      );

      // Track the nearest site regardless of distance
      if (d < nearestDistance) {
        nearestDistance = d;
        nearestSite = site;
      }

      // Check if any site is within trigger radius
      if (d < triggerRadius) {
        isWithinRange = true;
      }
    }

    return (site: nearestSite, isWithinRange: isWithinRange);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final fomoTop = screenHeight * 0.05; // 4% from top

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

              // Route advisory
              Positioned(
                top: screenHeight * 0.15, // just above radar
                left: 0,
                right: 0,
                child:
                    (_sortedSites.isNotEmpty && _userPos != null)
                        ? AdvisoryBanner(
                          user: _userPos,
                          site: _sortedSites[_currentIndex],
                          heading: _heading,
                        )
                        : const SizedBox(),
              ),

              // Fullscreen radar panel (no box or blur)
              Positioned.fill(
                child: Center(
                  child: GpsFeedbackPanel(
                    user: _userPos,
                    sites: _sites,
                    heading: _heading,
                  ),
                ),
              ),
              // --- 1. distance info panel just above bottom edge ---
              Positioned(
                bottom: 45,
                left: 0,
                right: 0,
                child: DistanceInfoPanel(
                  user: _userPos,
                  sortedSites: _sortedSites,
                  currentIndex: _currentIndex,
                  onLaunch: (site) {
                    // These three variables interplay in a slightly
                    // confusing way. UserPos and nearestSite are used to
                    // determine whether gps has been acquired - these two
                    // variables tell us: i know the user's position, and i
                    // know the nearest site. There will always be a nearest
                    // site, as long as we have gps signal.
                    // There will NOT always be a site within range, however.
                    // The range is defined as a threshold radius. Within
                    // this range we auto select the nearest site, outside
                    // this range, we show the site selection screen.
                    if (_userPos != null && _nearestSite != null) {
                      if (_isWithinRange) {
                        // Launch pipeline directly with nearest site
                        _launchPipeline(
                          context,
                          getUserId(widget.name, widget.email, widget.org),
                          _nearestSite!,
                          widget.name,
                          widget.email,
                          widget.org,
                        );
                      } else {
                        // Launch site selection screen
                        _launchSiteSelection(
                          context,
                          getUserId(widget.name, widget.email, widget.org),
                          _sites,
                          _nearestSite,
                          widget.name,
                          widget.email,
                          widget.org,
                        );
                      }
                    } else {
                      // Show toast when GPS is not ready
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Acquiring GPS, please retry in 2s'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  onNext: () {
                    setState(() {
                      _currentIndex = (_currentIndex + 1) % _sortedSites.length;
                    });
                  },
                ),
              ),
              // Online mode button at bottom
              OnlineModeButton(
                userPosition: _userPos,
                sites: _sites,
                name: widget.name,
                email: widget.email,
                org: widget.org,
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
  print("home_screen: launching pipeline for site: ${site.id}");
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

// New utility function to launch the site selection screen
void _launchSiteSelection(
  BuildContext context,
  String userId,
  List<Site> sites,
  Site? nearestSite,
  String name,
  String email,
  String org,
) {
  print("home_screen: launching site selection screen");
  Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (context) => SiteSelectionScreen(
            sites: sites,
            nearestSite: nearestSite,
            userId: userId,
            name: name,
            email: email,
            org: org,
          ),
    ),
  );
}

List<Site> sortSitesByDistance(Position user, List<Site> sites) {
  return List<Site>.from(sites)..sort((a, b) {
    final da = Geolocator.distanceBetween(
      user.latitude,
      user.longitude,
      a.lat,
      a.lng,
    );
    final db = Geolocator.distanceBetween(
      user.latitude,
      user.longitude,
      b.lat,
      b.lng,
    );
    return da.compareTo(db);
  });
}
