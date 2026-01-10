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
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              enabled
                  ? const Color(0xFF4FFD73).withOpacity(0.1) // faint green fill
                  : Colors.transparent,
          border: Border.all(
            color:
                enabled
                    ? const Color(0xFF4FFD73).withOpacity(0.9)
                    : Colors.grey.shade700,
            width: 4.5,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.add,
            size: 34,
            color: enabled ? const Color(0xFF4FFD73) : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
