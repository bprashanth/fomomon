/// plus_button.dart
/// ------------------
/// Floating circular "+" button that becomes active when user is near a site
/// Triggers the capture pipeline

import 'package:flutter/material.dart';

class PlusButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const PlusButton({super.key, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 48.0),
      child: GestureDetector(
        // TODO(prashanth@): do we want to guard this with enabled?
        // We should take a non-enabled press as "add site"?
        onTap: onPressed,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? Colors.amber : Colors.grey.shade800,
            border: Border.all(
              color: enabled ? Colors.yellowAccent : Colors.transparent,
              width: 5,
            ),
          ),
          child: const Center(
            child: Icon(Icons.add, size: 40, color: Colors.black),
          ),
        ),
      ),
    );
  }
}
