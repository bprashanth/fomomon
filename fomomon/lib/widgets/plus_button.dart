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
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 70,
        height: 70,
        child: Center(
          child: Icon(
            Icons.add_circle_outline_rounded,
            size: 50,
            color: enabled ? const Color(0xFF4FFD73) : Colors.grey.shade800,
          ),
        ),
      ),
    );
  }
}
