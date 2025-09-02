/// site_selection_screen.dart
/// ---------------------------
/// Screen for selecting an existing site or creating a new local site
/// when the user is not within range of any existing sites

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/site.dart';
import '../services/gps_service.dart';
import '../services/local_site_storage.dart';
import '../screens/capture_screen.dart';

class SiteSelectionScreen extends StatefulWidget {
  final List<Site> sites;
  final Site? nearestSite;
  final String userId;
  final String name;
  final String email;
  final String org;

  const SiteSelectionScreen({
    super.key,
    required this.sites,
    required this.nearestSite,
    required this.userId,
    required this.name,
    required this.email,
    required this.org,
  });

  @override
  State<SiteSelectionScreen> createState() => _SiteSelectionScreenState();
}

class _SiteSelectionScreenState extends State<SiteSelectionScreen> {
  String? _selectedSiteId;
  final TextEditingController _newSiteController = TextEditingController();
  bool _isCreatingNewSite = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _newSiteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Site'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        // Add this wrapper
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how to proceed:',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Option A: Choose from existing sites
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Choose Existing Site',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Select from sites in your area:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedSiteId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Select Site',
                      ),
                      items:
                          widget.sites
                              .map(
                                (site) => DropdownMenuItem(
                                  value: site.id,
                                  child: Text(site.id),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedSiteId = value;
                          _isCreatingNewSite = false;
                          _newSiteController.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Option B: Create new site
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.add_location, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Create New Site',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enter a new site ID to create a local site:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newSiteController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Site ID',
                        hintText: 'e.g., new_site_001',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _isCreatingNewSite = value.trim().isNotEmpty;
                          if (_isCreatingNewSite) {
                            _selectedSiteId = null;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32), // Add some bottom padding
            // Continue button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canProceed() && !_isLoading ? _proceed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child:
                    _isLoading
                        ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Creating Site...'),
                          ],
                        )
                        : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    return _selectedSiteId != null || _newSiteController.text.trim().isNotEmpty;
  }

  void _proceed() async {
    if (!_canProceed()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Site selectedSite;

      if (_isCreatingNewSite) {
        // Create new local site
        final newSiteId = _newSiteController.text.trim();

        // Get current GPS position
        final position = await GpsService.getCurrentPosition();

        // Copy survey questions from nearest site or use empty list
        final surveyQuestions = widget.nearestSite?.surveyQuestions ?? [];

        // Use bucket root from nearest site or empty string
        final bucketRoot = widget.nearestSite?.bucketRoot ?? '';

        selectedSite = Site.createLocalSite(
          id: newSiteId,
          lat: position.latitude,
          lng: position.longitude,
          bucketRoot: bucketRoot,
          surveyQuestions: surveyQuestions,
        );

        // Save to local storage
        await LocalSiteStorage.saveLocalSite(selectedSite);

        print(
          'Created new local site: $newSiteId at ${position.latitude}, ${position.longitude}',
        );
      } else {
        // Use existing site
        selectedSite = widget.sites.firstWhere((s) => s.id == _selectedSiteId);
        print('Selected existing site: ${selectedSite.id}');
      }

      // Launch pipeline
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) => CaptureScreen(
                  captureMode: 'portrait',
                  site: selectedSite,
                  userId: widget.userId,
                  name: widget.name,
                  email: widget.email,
                  org: widget.org,
                ),
          ),
        );
      }
    } catch (e) {
      print('Error in site selection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
