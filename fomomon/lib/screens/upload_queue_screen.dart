import 'package:flutter/material.dart';
import '../models/site.dart';
import '../models/captured_session.dart';
import '../widgets/upload_dial_widget.dart';
import '../widgets/upload_gallery_item.dart';
import '../widgets/session_detail_dialog.dart';
import '../services/local_session_storage.dart';

class UploadQueueScreen extends StatefulWidget {
  final List<Site> sites;
  final String name;
  final String email;
  final String org;

  const UploadQueueScreen({
    super.key,
    required this.sites,
    required this.name,
    required this.email,
    required this.org,
  });

  @override
  State<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends State<UploadQueueScreen> {
  List<CapturedSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allSessions = await LocalSessionStorage.loadAllSessions();
      final unuploaded = allSessions.where((s) => !s.isUploaded).toList();
      // Sort by timestamp, newest first
      unuploaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _sessions = unuploaded;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading sessions: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSessionTap(CapturedSession session) {
    showDialog(
      context: context,
      builder:
          (context) => SessionDetailDialog(
            session: session,
            sites: widget.sites,
            onDeleted: () {
              _loadSessions(); // Refresh gallery after deletion
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B22), // Dark background
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final fomoTop = screenHeight * 0.05; // Match home_screen header Y

          return Stack(
            children: [
              // Header row: close button (left) + centered FOMO title
              Positioned(
                top: fomoTop,
                left: 0,
                right: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Fixed-width slot for the close icon on the left
                    SizedBox(
                      width: 48,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Color.fromARGB(255, 199, 220, 237),
                          size: 18,
                        ),
                      ),
                    ),
                    // Center slot that truly centers FOMO, same as home_screen
                    const Expanded(
                      child: Center(
                        child: Text(
                          'FOMO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'trump',
                          ),
                        ),
                      ),
                    ),
                    // Symmetric empty slot on the right to balance the icon
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // Main content (dial + gallery) sits below the header, so the
              // header appears visually fixed across screens.
              Positioned.fill(
                top: fomoTop + 56, // header height + margin
                child: Column(
                  children: [
                    // Upload dial widget
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: UploadDialWidget(
                        key: ValueKey(_sessions.length),
                        sites: widget.sites,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Gallery section
                    Expanded(
                      child:
                          _isLoading
                              ? const Center(
                                child: CircularProgressIndicator(
                                  color: Color.fromARGB(255, 199, 220, 237),
                                ),
                              )
                              : _sessions.isEmpty
                              ? const SizedBox.shrink() // Empty space, message shown in Stack overlay
                              : RefreshIndicator(
                                onRefresh: _loadSessions,
                                color: const Color.fromARGB(255, 199, 220, 237),
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  itemCount: _sessions.length,
                                  itemBuilder: (context, index) {
                                    return UploadGalleryItem(
                                      session: _sessions[index],
                                      onTap:
                                          () => _onSessionTap(_sessions[index]),
                                    );
                                  },
                                ),
                              ),
                    ),
                  ],
                ),
              ),

              // Centered empty state overlay
              if (!_isLoading && _sessions.isEmpty)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E0E0E).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(
                            255,
                            20,
                            172,
                            243,
                          ).withOpacity(0.25),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                      border: Border.all(color: const Color(0xFF1A4273)),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No pending uploads',
                          style: TextStyle(
                            color: Color.fromARGB(255, 199, 220, 237),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'trump',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
