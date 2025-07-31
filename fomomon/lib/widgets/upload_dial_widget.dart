import 'package:flutter/material.dart';
import '../services/upload_service.dart';
import '../services/local_session_storage.dart';
import '../models/site.dart';

class UploadDialWidget extends StatefulWidget {
  const UploadDialWidget({super.key, required this.sites});
  final List<Site> sites;

  @override
  State<UploadDialWidget> createState() => _UploadDialWidgetState();
}

class _UploadDialWidgetState extends State<UploadDialWidget> {
  int uploaded = 0;
  int total = 0;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final sessions = await LocalSessionStorage.loadAllSessions();
    final unuploaded = sessions.where((s) => !s.isUploaded).toList();

    setState(() {
      uploaded = 0;
      total = unuploaded.length;
    });
  }

  void _onUploadPressed() async {
    setState(() {
      hasError = false;
    });
    try {
      await UploadService.instance.uploadAllSessions(
        sites: widget.sites,
        onProgress: () {
          setState(() => uploaded++);
        },
      );
    } catch (e) {
      print("upload_dial_widget: error: $e");
      setState(() {
        hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = total == 0 ? '0/0 files' : '$uploaded/$total';
    final buttonText = hasError ? 'Tap to Retry' : 'Tap to Upload';
    final buttonTitleTextColor = hasError ? Colors.redAccent : Colors.white70;
    final buttonTextColor = hasError ? Colors.redAccent : Colors.white;

    return GestureDetector(
      onTap: total == 0 ? null : _onUploadPressed,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: total == 0 ? 1.0 : uploaded / total,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.yellowAccent,
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: buttonTextColor,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            buttonText,
            style: TextStyle(
              color: buttonTitleTextColor,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
