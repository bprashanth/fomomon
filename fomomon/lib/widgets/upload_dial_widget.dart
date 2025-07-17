import 'package:flutter/material.dart';
import '../services/local_session_storage.dart';

class UploadDialWidget extends StatefulWidget {
  const UploadDialWidget({super.key});

  @override
  State<UploadDialWidget> createState() => _UploadDialWidgetState();
}

class _UploadDialWidgetState extends State<UploadDialWidget> {
  int uploaded = 0;
  int total = 0;

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
    // TODDO(prashanth@): UploadService.uploadAll(sessions)
    for (int i = 0; i < total; i++) {
      // Simulate upload
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() => uploaded++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = total == 0 ? '0/0 files' : '$uploaded/$total';

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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap to Upload',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
