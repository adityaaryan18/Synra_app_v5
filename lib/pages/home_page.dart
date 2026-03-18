import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:synra/pages/camera/setup_page.dart';


import 'analysis_page.dart';
import 'video_gallery_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      return 'GOOD MORNING';
    } else if (hour < 17) {
      return 'GOOD AFTERNOON';
    } else {
      return 'GOOD EVENING';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Image.asset(
              'assets/synra_logo.png',
              height: 32,
            ),
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
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 40),

            // -------- SET UP --------
            _SynraButton(
              text: 'SET UP',
              subtitle: "Record a '.mp4' video",
              icon: Icons.videocam,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SetupPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // -------- ANALYSIS --------
            _SynraButton(
              text: 'SHOW PREVIOUS ANALYSIS',
              subtitle: 'View earlier results',
              icon: Icons.analytics,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AnalysisPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // -------- SAVED VIDEOS (NEW) --------
            _SynraButton(
              text: 'SAVED SESSIONS',
              subtitle: 'Browse recorded folder with video',
              icon: Icons.video_library,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SessionGalleryPage(),
                  ),
                );
              },
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