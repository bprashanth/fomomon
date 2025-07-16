import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

import '../models/site.dart';

class CaptureScreen extends StatefulWidget {
  final String captureMode;
  final Site site;
  final String userId;

  const CaptureScreen({
    super.key,
    required this.captureMode,
    required this.site,
    required this.userId,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;
  double _opacity = 0.4;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final backCam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );

    _controller = CameraController(
      backCam,
      ResolutionPreset.max,
      enableAudio: false,
    );
    await _controller!.initialize();
    setState(() => _isCameraReady = true);
  }

  Future<void> _capturePhoto() async {
    if (!_controller!.value.isInitialized) return;

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = '${widget.userId}_${timestamp}_${widget.captureMode}.jpg';
    final filePath = '${tempDir.path}/$filename';

    final file = await _controller!.takePicture();
    await file.saveTo(filePath);

    if (!mounted) return;

    Navigator.of(context).pushNamed(
      '/confirm',
      arguments: {
        'imagePath': filePath,
        'captureMode': widget.captureMode,
        'site': widget.site,
        'userId': widget.userId,
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
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

          if (ghostPath != null)
            Positioned.fill(
              child: Opacity(
                opacity: _opacity,
                child: Image.file(
                  File(ghostPath),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
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
