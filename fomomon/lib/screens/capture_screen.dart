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

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;
  double _opacity = 0.2;

  @override
  void initState() {
    super.initState();

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
      final file = await _controller!.takePicture();

      if (!mounted) return; // Check if still mounted after capture

      await file.saveTo(filePath);

      if (!mounted) return;

      Navigator.of(context).push(
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
      );
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
              child: GestureDetector(
                onTap: _capturePhoto,
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
        ],
      ),
    );
  }
}
