import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'camera/camera_logic.dart'; // Ensure path to your camera logic is correct

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _currentPath;

  @override
  void initState() {
    super.initState();
    _loadSavedPath();
  }

  Future<void> _loadSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentPath = prefs.getString('save_path');
    });
  }

  Future<void> _pickDirectory() async {
  // Use getDirectoryPath but ensure we handle the URI persistence
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final prefs = await SharedPreferences.getInstance();
      
      // We must pass the path to Swift immediately while the permission is fresh
      await CameraLogic.channel.invokeMethod('setSaveRoot', {'path': selectedDirectory});

      await prefs.setString('save_path', selectedDirectory);
      setState(() => _currentPath = selectedDirectory);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save location updated successfully')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SETTINGS', style: GoogleFonts.orbitron(fontSize: 18)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'STORAGE CONFIGURATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Session Save Location', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              _currentPath ?? 'Default: App Documents Folder',
              style: TextStyle(color: Colors.blueGrey[600], fontSize: 13),
            ),
            trailing: const Icon(Icons.folder_open),
            onTap: _pickDirectory,
          ),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            'Note: High-speed ProRes recording generates large files. '
            'Selecting an external SSD is recommended for long sessions.',
            style: TextStyle(fontSize: 11, color: Colors.orange),
          ),
        ],
      ),
    );
  }
}