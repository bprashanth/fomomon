import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/site.dart';
import 'plus_button.dart';

class DistanceInfoPanel extends StatefulWidget {
  final Position? user;
  final List<Site> sites;
  // Triggers pipeline
  final Function(Site) onLaunch;
  // An index into the sorted sites list. Owned by the parent.
  final int currentIndex;
  final VoidCallback onNext;

  const DistanceInfoPanel({
    super.key,
    required this.user,
    required this.sites,
    required this.onLaunch,
    required this.currentIndex,
    required this.onNext,
  });

  @override
  State<DistanceInfoPanel> createState() => _DistanceInfoPanelState();
}

class _DistanceInfoPanelState extends State<DistanceInfoPanel> {
  late List<Site> _sortedSites;

  @override
  void didUpdateWidget(covariant DistanceInfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _computeNearestSites();
  }

  @override
  void initState() {
    super.initState();
    _computeNearestSites();
  }

  void _computeNearestSites() {
    if (widget.user == null) {
      _sortedSites = [];
      return;
    }

    final user = widget.user!;
    _sortedSites = List<Site>.from(widget.sites)..sort((a, b) {
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

  @override
  Widget build(BuildContext context) {
    if (widget.user == null || _sortedSites.isEmpty) {
      return const SizedBox.shrink();
    }

    final current = _sortedSites[widget.currentIndex];
    final distance = Geolocator.distanceBetween(
      widget.user!.latitude,
      widget.user!.longitude,
      current.lat,
      current.lng,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(32, 8, 32, 75),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E).withOpacity(0.9),
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(
              255,
              20,
              172,
              243,
            ).withOpacity(0.25), // near-white green
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(color: const Color(0xFF1A4273)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // --- Left column: site info ---
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Site',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Color(0xFF4FFD73),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      current.id,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- Divider line between columns ---
          Container(
            width: 1,
            height: 35,
            color: Colors.white.withOpacity(0.15),
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),

          // --- Right column: distance info ---
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Distance',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.route, size: 16, color: Color(0xFF4FFD73)),
                        const SizedBox(width: 6),
                        Text(
                          distance >= 1000
                              ? '${(distance / 1000).toStringAsFixed(1)} km'
                              : '${distance.toStringAsFixed(0)} m',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- Forward button ---
          IconButton(
            icon: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 18,
              color: Color(0xFF4FFD73),
            ),
            onPressed: () {
              widget.onNext();
            },
          ),

          // --- Plus button (pipeline launcher) ---
          PlusButton(
            enabled: widget.user != null,
            onPressed: () => widget.onLaunch(current),
          ),
        ],
      ),
    );
  }
}
