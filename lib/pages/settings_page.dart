import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'camera/camera_logic.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _currentPath;
  bool _allowVibration = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentPath = prefs.getString('save_path');
      _allowVibration = prefs.getBool('allow_vibration') ?? false;
    });
  }

  Future<void> _toggleStability(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await CameraLogic.channel.invokeMethod('setStabilityIgnore', value);
    } catch (e) {
      debugPrint("Stability update error: $e");
    }
    await prefs.setBool('allow_vibration', value);
    setState(() => _allowVibration = value);
  }

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      final prefs = await SharedPreferences.getInstance();
      await CameraLogic.channel.invokeMethod('setSaveRoot', {'path': selectedDirectory});
      await prefs.setString('save_path', selectedDirectory);
      setState(() => _currentPath = selectedDirectory);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Save location updated'),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // UI adjusted for Light Theme (White background, dark text)
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'SETTINGS', 
          style: GoogleFonts.orbitron(
            fontSize: 18, 
            color: Colors.black, 
            fontWeight: FontWeight.bold
          )
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // --- STORAGE SECTION ---
          _buildSectionHeader('STORAGE CONFIGURATION'),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Session Save Location', 
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)
            ),
            subtitle: Text(
              _currentPath ?? 'Default: App Documents Folder',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            trailing: const Icon(Icons.folder_open, color: Colors.blueAccent),
            onTap: _pickDirectory,
          ),
          Divider(color: Colors.grey[200]),
          
          const SizedBox(height: 32),

          // --- STABILITY SECTION ---
          _buildSectionHeader('STABILITY CONFIGURATION'),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Allow Phone Vibration', 
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)
            ),
            subtitle: Text(
              _allowVibration 
                ? 'Recording will CONTINUE during phone movements' 
                : 'Recording will STOP if significant movement is detected',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            value: _allowVibration,
            activeColor: Colors.orange,
            onChanged: _toggleStability,
          ),
          
          const SizedBox(height: 24),
          
          // --- WARNING NOTE ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.2))
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Note: High-speed ProRes requires a stable connection to storage. '
                    'Excessive vibration may cause dropped frames.',
                    style: TextStyle(fontSize: 11, color: Colors.brown),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: Colors.grey[400],
        letterSpacing: 1.5,
      ),
    );
  }
}