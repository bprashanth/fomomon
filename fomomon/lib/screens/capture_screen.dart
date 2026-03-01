import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../models/site.dart';
import '../models/confirm_screen_args.dart';
import '../screens/confirm_screen.dart';
import '../services/local_image_storage.dart';
import '../utils/camera_permission.dart';
import '../widgets/orientation_dial.dart';

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
  double? _currentHeading;
  StreamSubscription<CompassEvent>? _compassSub;

  // Ghost image bytes, pre-loaded in initState from LocalImageStorage.
  // On native: readBytes() reads from disk (synchronous).
  // On web: readBytes() reads from in-memory store — bytes were fetched with
  //   auth by site_service._ensureCachedImage and stored as 'web_img:ghost_*'.
  //   Null if the network fetch failed or the site has no reference images.
  Uint8List? _ghostBytes;

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

    // Start a compass stream only for the first (portrait) capture step, and
    // only when the site has a reference heading to compare against.
    // No magnetometer in browser — skip on web.
    if (!kIsWeb &&
        widget.captureMode == 'portrait' &&
        widget.site.referenceHeading != null) {
      _compassSub = FlutterCompass.events?.listen((event) {
        if (!mounted) return;
        setState(() {
          _currentHeading = event.heading;
        });
      });
    }

    // Pre-load ghost image bytes so build() can use Image.memory.
    // localPortraitPath / localLandscapePath are:
    //   Native — absolute file paths written by _ensureCachedImage.
    //   Web    — 'web_img:ghost_{siteId}_{orientation}' keys written to the
    //            in-memory store by _ensureCachedImage (fetched with auth).
    // readBytes() is synchronous on both platforms.
    final ghostPath =
        widget.captureMode == 'portrait'
            ? widget.site.localPortraitPath
            : widget.site.localLandscapePath;
    if (ghostPath != null) {
      _ghostBytes = LocalImageStorage.readBytes(ghostPath);
    }
  }

  Future<void> _initCamera() async {
    try {
      // On web, getUserMedia() must be called before enumerateDevices() to
      // trigger the browser permission dialog. requestCameraPermission() does
      // this and is a no-op on native where the camera plugin handles it.
      await requestCameraPermission();
      final cameras = await availableCameras();
      if (!mounted) return;

      final backCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCam,
        ResolutionPreset.max,
        enableAudio: false,
      );

      if (!mounted) return;

      await _controller!.initialize();

      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        print("Failed to set flash mode off: $e");
      }

      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (e) {
        print("Failed to set focus mode: $e");
      }

      if (mounted) {
        setState(() => _isCameraReady = true);
      }
    } catch (e) {
      print("Camera initialization failed: $e");
      if (mounted) {
        final msg = e.toString().contains('NotAllowedError') ||
                e.toString().contains('permissionDenied') ||
                e.toString().contains('cameraPermission')
            ? 'Camera permission denied. Go to browser Site Settings for this URL and allow Camera, then reopen the app.'
            : 'Failed to initialize camera. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (!_controller!.value.isInitialized || !mounted) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final key = '${widget.userId}_${timestamp}_${widget.captureMode}.jpg';

    try {
      setState(() => _isCapturing = true);
      _shutterController.forward().then((_) => _shutterController.reverse());

      final start = DateTime.now();
      final xfile = await _controller!.takePicture();
      final elapsed = DateTime.now().difference(start);
      print("capture_screen: takePicture() took ${elapsed.inMilliseconds} ms");

      if (!mounted) return;

      // Read bytes from XFile (cross-platform) and persist via LocalImageStorage.
      // On native: saved to {docsDir}/images/{key}; returns file path.
      // On web:    stored in-memory under 'web_img:{key}'; returns that key.
      final bytes = await xfile.readAsBytes();
      final filePath = await LocalImageStorage.saveImage(bytes, key);

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
            if (mounted) {
              setState(() => _isCapturing = false);
            }
          });
    } catch (e) {
      print("Capture failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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
    _compassSub?.cancel();
    _controller
        ?.dispose()
        .then((_) {})
        .catchError((error) {
          print("Camera disposal error: $error");
        });
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

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),

          // Top overlay with site id
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
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
                  // Compass dial: only shown on native (no magnetometer on web)
                  if (!kIsWeb &&
                      widget.captureMode == 'portrait' &&
                      widget.site.referenceHeading != null &&
                      _currentHeading != null) ...[
                    const SizedBox(height: 8),
                    OrientationDial(
                      referenceHeading: widget.site.referenceHeading!,
                      currentHeading: _currentHeading,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Ghost image overlay — unified across native and web.
          // Bytes are pre-loaded in initState via LocalImageStorage.readBytes().
          // Null if the site has no reference images or the network fetch failed.
          if (_ghostBytes != null)
            Positioned.fill(
              child: Opacity(
                opacity: _opacity,
                child: Image.memory(_ghostBytes!, fit: BoxFit.cover),
              ),
            ),

          // Gridlines
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

          // Opacity slider
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

          // Capture button
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
