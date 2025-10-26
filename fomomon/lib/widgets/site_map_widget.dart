import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/site.dart';

enum BasemapType { contour, satellite }

enum MapMode { sites, kml }

class SiteMapWidget extends StatefulWidget {
  final Position? userPosition;
  final List<Site> sites;
  final double height;
  final double borderRadius;
  final String? kmlAssetPath;
  final String? geojsonAssetPath;

  const SiteMapWidget({
    super.key,
    required this.userPosition,
    required this.sites,
    this.height = 400,
    this.borderRadius = 16,
    this.kmlAssetPath,
    this.geojsonAssetPath,
  });

  @override
  State<SiteMapWidget> createState() => _SiteMapWidgetState();
}

class _SiteMapWidgetState extends State<SiteMapWidget> {
  BasemapType _currentBasemap = BasemapType.satellite;
  MapMode _currentMode = MapMode.kml;
  List<LatLng> _kmlPoints = [];
  List<List<LatLng>> _kmlPolylines = []; // For LineString geometries
  List<List<LatLng>> _kmlPolygons = []; // For Polygon geometries
  LatLng? _kmlCenter;
  bool _isLoadingKml = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    if (widget.geojsonAssetPath != null || widget.kmlAssetPath != null) {
      _loadKmlData();
    }
  }

  Future<void> _loadKmlData() async {
    if (widget.geojsonAssetPath == null && widget.kmlAssetPath == null) return;

    setState(() => _isLoadingKml = true);

    try {
      // Prefer GeoJSON if available
      if (widget.geojsonAssetPath != null) {
        await _loadGeoJsonData();
      } else {
        print('GeoJSON not available, skipping KML for now');
      }
    } catch (e) {
      print('Error loading data: $e');
      print('Stack trace: ${StackTrace.current}');
    } finally {
      setState(() => _isLoadingKml = false);
    }
  }

  Future<void> _loadGeoJsonData() async {
    print('Loading GeoJSON from: ${widget.geojsonAssetPath}');
    final geojsonString = await rootBundle.loadString(widget.geojsonAssetPath!);
    final geojsonData = json.decode(geojsonString) as Map<String, dynamic>;

    print('GeoJSON loaded successfully');
    print('Type: ${geojsonData['type']}');

    final features = geojsonData['features'] as List?;
    print('Found ${features?.length ?? 0} features');

    final points = <LatLng>[];
    final polylines = <List<LatLng>>[];
    final polygons = <List<LatLng>>[];
    double totalLat = 0;
    double totalLng = 0;
    int totalCoords = 0;

    if (features != null) {
      for (final feature in features) {
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;

        final geoType = geometry['type'] as String?;
        final coordinates = geometry['coordinates'];

        if (geoType == 'Point' &&
            coordinates is List &&
            coordinates.length >= 2) {
          final point = LatLng(coordinates[1], coordinates[0]);
          points.add(point);
          totalLat += point.latitude;
          totalLng += point.longitude;
          totalCoords++;
        } else if (geoType == 'LineString' && coordinates is List) {
          final linePoints = <LatLng>[];
          for (final coord in coordinates) {
            if (coord is List && coord.length >= 2) {
              final point = LatLng(coord[1], coord[0]);
              linePoints.add(point);
              totalLat += point.latitude;
              totalLng += point.longitude;
              totalCoords++;
            }
          }
          if (linePoints.isNotEmpty) {
            polylines.add(linePoints);
          }
        } else if (geoType == 'Polygon' && coordinates is List) {
          // Polygon outer boundary (first ring)
          final outerRing = coordinates[0];
          if (outerRing is List) {
            final polygonPoints = <LatLng>[];
            for (final coord in outerRing) {
              if (coord is List && coord.length >= 2) {
                final point = LatLng(coord[1], coord[0]);
                polygonPoints.add(point);
                totalLat += point.latitude;
                totalLng += point.longitude;
                totalCoords++;
              }
            }
            if (polygonPoints.isNotEmpty) {
              polygons.add(polygonPoints);
            }
          }
        }
      }
    }

    print(
      'Total points: ${points.length}, Total polylines: ${polylines.length}, Total polygons: ${polygons.length}',
    );

    if (totalCoords > 0) {
      final center = LatLng(totalLat / totalCoords, totalLng / totalCoords);
      print(
        'GeoJSON center calculated: ${center.latitude}, ${center.longitude}',
      );

      setState(() {
        _kmlPoints = points;
        _kmlPolylines = polylines;
        _kmlPolygons = polygons;
        _kmlCenter = center;
      });

      if (_currentMode == MapMode.kml) {
        _mapController.move(center, _getMapZoom());
      }
    } else {
      print('No data found in GeoJSON file');
    }
  }

  String _getTileLayerUrl() {
    switch (_currentBasemap) {
      case BasemapType.contour:
        // Dark contour map using CartoDB Dark Matter
        return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
      // case BasemapType.terrain:
      //   // Thunderforest Outdoors map - great for ecological mapping
      //   return 'https://{s}.tile.thunderforest.com/outdoors/{z}/{x}/{y}.png?apikey=c7addce2eb274ae983a2d78f7f70071c';
      case BasemapType.satellite:
        // Satellite imagery
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      // case BasemapType.landscape:
      //   // Thunderforest Landscape map - shows terrain features
      //   return 'https://{s}.tile.thunderforest.com/landscape/{z}/{x}/{y}.png?apikey=c7addce2eb274ae983a2d78f7f70071c';
      // case BasemapType.forest:
      //   // Thunderforest OpenCycleMap - shows cycling routes and terrain
      //   return 'https://{s}.tile.thunderforest.com/cycle/{z}/{x}/{y}.png?apikey=c7addce2eb274ae983a2d78f7f70071c';
    }
  }

  LatLng _getMapCenter() {
    if (_currentMode == MapMode.kml && _kmlCenter != null) {
      return _kmlCenter!;
    } else if (widget.userPosition != null) {
      return LatLng(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
      );
    } else if (widget.sites.isNotEmpty) {
      // Center on sites if no user position
      double totalLat = 0;
      double totalLng = 0;
      for (final site in widget.sites) {
        totalLat += site.lat;
        totalLng += site.lng;
      }
      return LatLng(
        totalLat / widget.sites.length,
        totalLng / widget.sites.length,
      );
    }
    return const LatLng(0, 0);
  }

  double _getMapZoom() {
    if (_currentMode == MapMode.kml && _kmlPoints.isNotEmpty) {
      return 12.0; // Zoom level for KML data
    } else if (widget.userPosition != null) {
      return 15.0; // Zoom level for user position
    }
    return 10.0; // Default zoom level
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_currentMode == MapMode.kml) {
      // Show KML points - subtle dots in a different color
      for (int i = 0; i < _kmlPoints.length; i++) {
        markers.add(
          Marker(
            point: _kmlPoints[i],
            width: 6,
            height: 6,
            builder:
                (ctx) => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700), // Gold/yellow for points
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 0.5),
                  ),
                ),
          ),
        );
      }
    } else {
      // Show site markers - green but subtle
      for (final site in widget.sites) {
        markers.add(
          Marker(
            point: LatLng(site.lat, site.lng),
            width: 10,
            height: 10,
            builder:
                (ctx) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF80), // Green for sites
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
          ),
        );
      }
    }

    // Always show user position if available - subtle blue
    if (widget.userPosition != null) {
      markers.add(
        Marker(
          point: LatLng(
            widget.userPosition!.latitude,
            widget.userPosition!.longitude,
          ),
          width: 12,
          height: 12,
          builder:
              (ctx) => Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(
                    255,
                    3,
                    150,
                    248,
                  ), // Blue for user
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 20, 172, 243).withOpacity(0.25),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(color: const Color(0xFF1A4273)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                center: _getMapCenter(),
                zoom: _getMapZoom(),
                minZoom: 2.0,
                maxZoom: 18.0,
                interactiveFlags: InteractiveFlag.all,
              ),
              children: [
                TileLayer(
                  urlTemplate: _getTileLayerUrl(),
                  userAgentPackageName: 'com.fomomon.app',
                  maxZoom: 18,
                  subdomains: const ['a', 'b', 'c', 'd'],
                ),
                // Add polylines (LineStrings) - blue for transects
                PolylineLayer(
                  polylines:
                      _kmlPolylines
                          .map(
                            (points) => Polyline(
                              points: points,
                              strokeWidth: 1.5,
                              color: const Color.fromARGB(
                                255,
                                3,
                                150,
                                248,
                              ), // Blue
                            ),
                          )
                          .toList(),
                ),
                // Add polygons - purple/indigo with thin borders
                PolygonLayer(
                  polygons:
                      _kmlPolygons
                          .map(
                            (points) => Polygon(
                              points: points,
                              borderStrokeWidth: 0.8,
                              borderColor: const Color.fromARGB(
                                255,
                                138,
                                43,
                                226,
                              ), // Dark violet
                              color: const Color.fromARGB(
                                255,
                                138,
                                43,
                                226,
                              ).withOpacity(0.15),
                            ),
                          )
                          .toList(),
                ),
                // Add markers last so they're on top
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),

            // Control panel overlay
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0E0E).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1A4273)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Basemap switcher
                    _buildBasemapSwitcher(),
                    const SizedBox(height: 8),
                    // Mode switcher
                    _buildModeSwitcher(),
                  ],
                ),
              ),
            ),

            // Loading indicator for KML
            if (_isLoadingKml)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF00FF80)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasemapSwitcher() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Map',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBasemapButton(BasemapType.contour, Icons.terrain),
              const SizedBox(width: 4),
              // _buildBasemapButton(BasemapType.terrain, Icons.landscape),
              // const SizedBox(width: 4),
              // _buildBasemapButton(BasemapType.landscape, Icons.nature),
              // const SizedBox(width: 4),
              // _buildBasemapButton(BasemapType.forest, Icons.park),
              // const SizedBox(width: 4),
              _buildBasemapButton(BasemapType.satellite, Icons.satellite),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBasemapButton(BasemapType type, IconData icon) {
    final isSelected = _currentBasemap == type;
    return GestureDetector(
      onTap: () => setState(() => _currentBasemap = type),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color:
              isSelected
                  ? const Color(0xFF00FF80).withOpacity(0.2)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected
                    ? const Color(0xFF00FF80)
                    : Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: isSelected ? const Color(0xFF00FF80) : Colors.white70,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Data',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeButton(MapMode.kml, 'KML'),
              const SizedBox(width: 4),
              _buildModeButton(MapMode.sites, 'Sites'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(MapMode mode, String label) {
    final isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _currentMode = mode);
        // Center map on the appropriate data
        final center = _getMapCenter();
        final zoom = _getMapZoom();
        _mapController.move(center, zoom);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? const Color(0xFF00FF80).withOpacity(0.2)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected
                    ? const Color(0xFF00FF80)
                    : Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF00FF80) : Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
