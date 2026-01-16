import 'package:flutter/material.dart';
import '../services/site_service.dart';
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

class _SitePrefetchScreenState extends State<SitePrefetchScreen> {
  @override
  void initState() {
    super.initState();
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

  Widget _buildLoadingIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 20, 172, 243).withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CircularProgressIndicator(
        strokeWidth: 4,
        valueColor: const AlwaysStoppedAnimation<Color>(
          Color.fromARGB(255, 20, 172, 243),
        ),
        backgroundColor: const Color(0xFF1A4273).withOpacity(0.3),
      ),
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
            _buildLoadingIcon(),
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
