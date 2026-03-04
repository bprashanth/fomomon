/// permission_error_overlay.dart
/// ------------------------------
/// Full-screen overlay shown when a required permission is unavailable.
/// Displays a title, explanatory message, and a button that opens the
/// relevant system settings page. Designed to sit as the last child in a
/// Stack so it covers all other content until the permission is resolved.
///
/// Usage (GPS example):
///   if (_gpsError != null)
///     Positioned.fill(
///       child: PermissionErrorOverlay(
///         title: 'Location services are off',
///         message: 'Enable Location in your phone\'s Settings to use FOMO.',
///         onOpenSettings: () => Geolocator.openLocationSettings(),
///       ),
///     ),

import 'package:flutter/material.dart';

class PermissionErrorOverlay extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onOpenSettings;

  const PermissionErrorOverlay({
    required this.title,
    required this.message,
    required this.onOpenSettings,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1B22),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
                onPressed: onOpenSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
