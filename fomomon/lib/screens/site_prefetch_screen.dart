import 'dart:math';

import 'package:flutter/material.dart';
import '../services/site_service.dart';
import '../models/site.dart';
import 'home_screen.dart';

class SitePrefetchScreen extends StatefulWidget {
  final String name;
  final String email;
  final String org;

  const SitePrefetchScreen({
    super.key,
    required this.name,
    required this.email,
    required this.org,
  });

  @override
  State<SitePrefetchScreen> createState() => _SitePrefetchScreenState();
}

class _SitePrefetchScreenState extends State<SitePrefetchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();

    _fetchSites();
  }

  Future<void> _fetchSites() async {
    try {
      // Use synchronous mode for initial prefetch to ensure all data is loaded.
      // Subsequent fetches are done in the homescreen, async.
      await SiteService.fetchSitesAndPrefetchImages(async: false);

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) => HomeScreen(
                  name: widget.name,
                  email: widget.email,
                  org: widget.org,
                ),
          ),
        );
      }
    } catch (e) {
      print('Error fetching sites: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to load site data: $e")));
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildRotatingImage() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final angle = _controller.value * 2 * pi;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..rotateY(angle),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 0),
              borderRadius: BorderRadius.circular(100),
            ),
            clipBehavior: Clip.hardEdge,
            child: Image.asset(
              'assets/images/loading.png',
              fit: BoxFit.scaleDown,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRotatingImage(),
            const SizedBox(height: 24),
            const Text(
              "Preparing site data for offline mode...",
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'Monospace',
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
