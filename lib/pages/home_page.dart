import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this
import 'package:synra/pages/camera/setup_page.dart';
import 'package:synra/pages/settings_page.dart';
import 'package:synra/pages/camera/camera_logic.dart'; // Add this

import 'analysis_page.dart';
import 'video_gallery_page.dart';

class HomePage extends StatefulWidget { // Changed to StatefulWidget
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  
  @override
  void initState() {
    super.initState();
    _syncSavePathWithNative();
    _performFullAppReset();
  }

  Future<void> _performFullAppReset() async {
    try {
      await CameraLogic.channel.invokeMethod('stop'); 
      // 1. Restore folder permissions (Your existing logic)
      await CameraLogic.channel.invokeMethod('restorePermission');
      debugPrint("SYNRA: Full App Reset Performed");
    } catch (e) {
      debugPrint("SYNRA: Reset Error: $e");
    }
  }

  Future<void> _syncSavePathWithNative() async {
    try {
      // Tell Swift: "Check your own internal UserDefaults for the security bookmark"
      await CameraLogic.channel.invokeMethod('restorePermission');
      
      
      // Keep your existing log if you want
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('save_path');
      debugPrint("SYNRA: Attempted Bookmark Restoration for $savedPath");
    } catch (e) {
      debugPrint("SYNRA: Sync Error: $e");
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Image.asset('assets/synra_logo.png', height: 32),
            const SizedBox(width: 10),
            Text(
              'SYNRA',
              style: GoogleFonts.orbitron(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: Colors.black,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getGreeting(),
              style: GoogleFonts.orbitron(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Welcome to SYNRA',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),

            _SynraButton(
              text: 'SET UP',
              subtitle: "Record a '.mp4' video",
              icon: Icons.videocam,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupPage())),
            ),
            const SizedBox(height: 24),

            _SynraButton(
              text: 'SHOW PREVIOUS ANALYSIS',
              subtitle: 'View earlier results',
              icon: Icons.analytics,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalysisPage())),
            ),
            const SizedBox(height: 24),

            _SynraButton(
              text: 'SAVED SESSIONS',
              subtitle: 'Browse recorded folder with video',
              icon: Icons.video_library,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionGalleryPage())),
            ),
          ],
        ),
      ),
    );
  }
}

class _SynraButton extends StatelessWidget {
  final String text;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SynraButton({
    required this.text,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 36),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}