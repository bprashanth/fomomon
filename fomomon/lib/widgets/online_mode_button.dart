import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/site.dart';
import '../screens/online_map_screen.dart';

class OnlineModeButton extends StatefulWidget {
  final Position? userPosition;
  final List<Site> sites;
  final String name;
  final String email;
  final String org;

  const OnlineModeButton({
    super.key,
    required this.userPosition,
    required this.sites,
    required this.name,
    required this.email,
    required this.org,
  });

  @override
  State<OnlineModeButton> createState() => _OnlineModeButtonState();
}

class _OnlineModeButtonState extends State<OnlineModeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTap() {
    _animationController.forward().then((_) {
      _animationController.reverse();
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => OnlineMapScreen(
              userPosition: widget.userPosition,
              sites: widget.sites,
              name: widget.name,
              email: widget.email,
              org: widget.org,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: GestureDetector(
                onTap: _onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF1A2024,
                    ).withOpacity(0.9), // Dark grey panel background
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.keyboard_arrow_up,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
