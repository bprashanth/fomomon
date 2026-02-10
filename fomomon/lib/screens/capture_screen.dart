import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../models/site.dart';
import '../models/confirm_screen_args.dart';
import '../screens/confirm_screen.dart';

class CaptureScreen extends StatefulWidget {
  final String captureMode;
  final Site site;
  final String userId;
  // The use of these fields is a little tricky. Depending on which comes first
  // in the pipeline, portrait or landscape, that field will be populated. So
  // they both start off as null, but through the following cycle:
  // 1. Capture a portrait image.
  // 2. Pass it into the confirm screen.
  // 3. The confirm screen will invoke this screen again for the landscape
  //    image, with the image set to portraitImagePath.
  // 4. This screen will capture the landscape image, and pass both landscape
  //    and portrait images into the confirm screen.

  final String? landscapeImagePath;
  final String? portraitImagePath;
  final String name;
  final String email;
  final String org;

  const CaptureScreen({
    super.key,
    required this.captureMode,
    required this.site,
    required this.userId,
    this.landscapeImagePath,
    this.portraitImagePath,
    required this.name,
    required this.email,
    required this.org,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraReady = false;
  double _opacity = 0.2;
  bool _isCapturing = false;
  late AnimationController _shutterController;
  late Animation<double> _shutterScale;

  @override
  void initState() {
    super.initState();

    _shutterController = AnimationController(
      duration: const Duration(milliseconds: 140),
      vsync: this,
    );
    _shutterScale = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _shutterController, curve: Curves.easeOutCubic),
    );

    // Set the orientation based on the captureMode
    if (widget.captureMode == 'portrait') {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return; // Check if widget is still mounted

      final backCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );

      _controller = CameraController(
        backCam,
        ResolutionPreset.max,
        enableAudio: false,
      );

      if (!mounted) return; // Check again before initializing

      await _controller!.initialize();

      // Ensure flash is always off (no auto-flash in low light).
      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        print("Failed to set flash mode off: $e");
      }

      // Enable continuous autofocus during preview so camera is pre-focused
      // when user taps, reducing the focus-lock delay during capture.
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (e) {
        print("Failed to set focus mode: $e");
        // Not critical - camera will still work, just might be slower
      }

      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      print("Camera initialization failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize camera. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (!_controller!.value.isInitialized || !mounted) return;

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = '${widget.userId}_${timestamp}_${widget.captureMode}.jpg';
    final filePath = '${tempDir.path}/$filename';

    try {
      // Shutter feedback: quick scale animation on tap + capturing overlay
      setState(() => _isCapturing = true);
      _shutterController.forward().then((_) => _shutterController.reverse());

      final start = DateTime.now();
      final file = await _controller!.takePicture();
      final elapsed = DateTime.now().difference(start);
      print("capture_screen: takePicture() took ${elapsed.inMilliseconds} ms");

      if (!mounted) return; // Check if still mounted after capture

      await file.saveTo(filePath);

      if (!mounted) return;

      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder:
                  (_) => ConfirmScreen(
                    args: ConfirmScreenArgs(
                      landscapeImagePath:
                          widget.captureMode == 'landscape'
                              ? filePath
                              : widget.landscapeImagePath,
                      portraitImagePath:
                          widget.captureMode == 'portrait'
                              ? filePath
                              : widget.portraitImagePath,
                      captureMode: widget.captureMode,
                      site: widget.site,
                      userId: widget.userId,
                      name: widget.name,
                      email: widget.email,
                      org: widget.org,
                    ),
                  ),
            ),
          )
          .whenComplete(() {
            // Clear capturing state when user returns from confirm screen
            if (mounted) {
              setState(() => _isCapturing = false);
            }
          });
    } catch (e) {
      print("Capture failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture photo. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _shutterController.dispose();
    // Properly dispose the camera controller asynchronously
    _controller
        ?.dispose()
        .then((_) {
          // Camera disposed successfully
        })
        .catchError((error) {
          // Log any disposal errors but don't crash
          print("Camera disposal error: $error");
        });

    // We don't touch orientation in dispose because it could mess with the
    // next screens enforced orientation.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ghostPath =
        widget.captureMode == 'portrait'
            ? widget.site.localPortraitPath
            : widget.site.localLandscapePath;

    print(
      "[CaptureScreen] ghostPath: $ghostPath, localPortraitPath: ${widget.site.localPortraitPath}, localLandscapePath: ${widget.site.localLandscapePath}",
    );

    // Camera stacking order:
    // - CameraPreview
    // - GhostOverlay
    // - Gridlines
    // - OpacitySlider
    // - CaptureButton
    // The stacking order is important, eg we want to show the gridlines
    // overlaid above the camera preview and ghost image, but not occluding the
    // opacity slider.
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),

          // Top overlay with site id so user knows which site this capture is for
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  widget.site.id,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

          if (ghostPath != null)
            Positioned.fill(
              child: Opacity(
                opacity: _opacity,
                child: Image.file(File(ghostPath), fit: BoxFit.cover),
              ),
            ),

          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Color.fromARGB(166, 255, 255, 255),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Color.fromARGB(166, 255, 255, 255),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),

          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height * 0.3,
            bottom: MediaQuery.of(context).size.height * 0.3,
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: _opacity,
                onChanged: (val) => setState(() => _opacity = val),
                min: 0.0,
                max: 1.0,
              ),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ScaleTransition(
                scale: _shutterScale,
                child: GestureDetector(
                  onTap: _isCapturing ? null : _capturePhoto,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(width: 4, color: Colors.grey.shade800),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_isCapturing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.25),
                alignment: Alignment.center,
                child: const Text(
                  'Capturing...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
