import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:synra/pages/lidar_heatmap.dart';

/* ─────────────────────────────────────────────────────────────
   DROPBOX SERVICE
   ───────────────────────────────────────────────────────────── */

class DropboxService {
  // Singleton pattern to ensure the same instance is used across the app
  static final DropboxService _instance = DropboxService._internal();
  factory DropboxService() => _instance;
  DropboxService._internal();

  final String clientId = "26to6hl1uhekjtl";
  final String clientSecret = "jpba0y24qk1r4k8";
  final String refreshToken = "BcEM90FhOq8AAAAAAAAAAR7l7Cr71GboZTWTMV8wrO7f51c7L7MJu_arD4GQikB3";

  // --- PROGRESS TRACKING ---
  // Key: Folder Name, Value: Progress (0.0 to 1.0)
  final ValueNotifier<Map<String, double>> uploadProgress = ValueNotifier({});
  
  // Track active cancel tokens
  final Map<String, bool> _cancelRequests = {};

  /// Call this to stop an ongoing upload
  void cancelUpload(String folderName) {
    _cancelRequests[folderName] = true;
  }

  Future<String?> _getAccessToken() async {
    final url = Uri.parse("https://api.dropboxapi.com/oauth2/token");
    try {
      final response = await http.post(url, body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
        'client_secret': clientSecret,
      });

      if (response.statusCode == 200) {
        return jsonDecode(response.body)['access_token'];
      }
      debugPrint("Auth Error: ${response.body}");
      return null;
    } catch (e) {
      debugPrint("Network Error: $e");
      return null;
    }
  }

  /// High-level method to upload an entire directory with progress
  Future<void> uploadSession(
    Directory folder, {
    required Function(String url) onComplete,
    required Function(String error) onError,
  }) async {
    final folderName = folder.path.split('/').last;
    final files = folder.listSync().whereType<File>().toList();
    
    if (files.isEmpty) {
      onError("Folder is empty");
      return;
    }

    // Initialize state
    _cancelRequests[folderName] = false;
    _updateProgress(folderName, 0.0);

    int uploadedCount = 0;
    String remoteFolderPath = "/SYNRA ipad App Data/$folderName";

    for (var file in files) {
      // Check for cancellation before each file upload
      if (_cancelRequests[folderName] == true) {
        _cleanup(folderName);
        onError("Upload cancelled");
        return;
      }

      final fileName = file.path.split('/').last;
      bool ok = await uploadFile(file, "$remoteFolderPath/$fileName");

      if (ok) {
        uploadedCount++;
        _updateProgress(folderName, uploadedCount / files.length);
      } else {
        // If a single file fails, you can choose to continue or abort. 
        // Here we continue but log it.
        debugPrint("Failed to upload: $fileName");
      }
    }

    // Generate shared link after all files are done
    String? sharedUrl = await getSharedLink(remoteFolderPath);
    
    _cleanup(folderName);
    
    if (sharedUrl != null) {
      onComplete(sharedUrl);
    } else {
      onError("Uploaded files but failed to generate sharing link.");
    }
  }

  Future<bool> uploadFile(File file, String remotePath) async {
    final token = await _getAccessToken();
    if (token == null) return false;

    final url = Uri.parse("https://content.dropboxapi.com/2/files/upload");
    final bytes = await file.readAsBytes();

    final response = await http.post(
      url,
      headers: {
        "Authorization": "Bearer $token",
        "Dropbox-API-Arg": jsonEncode({
          "path": remotePath,
          "mode": "overwrite",
          "mute": true
        }),
        "Content-Type": "application/octet-stream",
      },
      body: bytes,
    );

    return response.statusCode == 200;
  }

  Future<String?> getSharedLink(String folderPath) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    final url = Uri.parse("https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings");
    
    final response = await http.post(
      url,
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "path": folderPath,
        "settings": {"requested_visibility": "public"}
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data['url'];
    } else if (data['error']?['.tag'] == 'shared_link_already_exists') {
      return data['error']['shared_link_already_exists']['metadata']['url'];
    }
    return null;
  }

  // --- INTERNAL HELPERS ---

  void _updateProgress(String key, double value) {
    final current = Map<String, double>.from(uploadProgress.value);
    current[key] = value;
    uploadProgress.value = current;
  }

  void _cleanup(String key) {
    final current = Map<String, double>.from(uploadProgress.value);
    current.remove(key);
    uploadProgress.value = current;
    _cancelRequests.remove(key);
  }
}

class SessionGalleryPage extends StatefulWidget {
  const SessionGalleryPage({super.key});

  @override
  State<SessionGalleryPage> createState() => _SessionGalleryPageState();
}

class _SessionGalleryPageState extends State<SessionGalleryPage> {
  List<Directory> _sessions = [];
  bool _loading = true;
  // Use the Singleton instance
  final DropboxService _dropbox = DropboxService();

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    final appDocDir = await getApplicationDocumentsDirectory();
    final entities = await appDocDir.list().toList();

    final folders = entities
        .whereType<Directory>()
        .where((dir) {
          final name = dir.path.split('/').last;
          return name.startsWith('Session_') || name.startsWith('TestSession_');
        })
        .toList();

    folders.sort((a, b) => b.path.compareTo(a.path));
    setState(() {
      _sessions = folders;
      _loading = false;
    });
  }

  // Refactored to use the new non-blocking service method
  void _startUpload(Directory folder) {
    final name = folder.path.split('/').last;
    
    _dropbox.uploadSession(
      folder,
      onComplete: (sharedUrl) {
        if (mounted) {
          _showShareSuccessDialog(name, sharedUrl);
        }
      },
      onError: (error) {
        if (mounted) {
          _showSnackBar(error);
        }
      },
    );
  }

  void _showShareSuccessDialog(String folderName, String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Upload Complete"),
        content: Text("Folder '$folderName' is now on Dropbox and ready to share."),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              _showSnackBar("Link copied to clipboard!");
            },
            child: const Text("Copy Link"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Synra Sessions"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSessions)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<Map<String, double>>(
              valueListenable: _dropbox.uploadProgress,
              builder: (context, activeUploads, child) {
                return ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (ctx, i) {
                    final folder = _sessions[i];
                    final name = folder.path.split('/').last;
                    
                    // Check if this specific folder is currently uploading
                    final isUploading = activeUploads.containsKey(name);
                    final progress = activeUploads[name] ?? 0.0;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      clipBehavior: Clip.antiAlias, // Ensures progress bar corners match card
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.folder, color: Colors.amber, size: 36),
                            title: Text(name),
                            subtitle: Text(isUploading 
                                ? "Uploading... ${(progress * 100).toInt()}%" 
                                : "Includes LiDAR, Video, IMU"),
                            trailing: isUploading
                                ? IconButton(
                                    icon: const Icon(Icons.cancel, color: Colors.red),
                                    onPressed: () => _dropbox.cancelUpload(name),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.cloud_upload, color: Colors.blue),
                                    onPressed: () => _startUpload(folder),
                                  ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => FileBrowserPage(directory: folder)),
                            ),
                          ),
                          // The Persistent Progress Bar
                          if (isUploading)
                            LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                              minHeight: 4,
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

/* ─────────────────────────────────────────────────────────────
   FILE BROWSER PAGE
   ───────────────────────────────────────────────────────────── */
/* ─────────────────────────────────────────────────────────────
   FILE BROWSER PAGE (Updated)
   ───────────────────────────────────────────────────────────── */
class FileBrowserPage extends StatelessWidget {
  final Directory directory;
  const FileBrowserPage({super.key, required this.directory});

  @override
  Widget build(BuildContext context) {
    final files = directory.listSync().whereType<File>().toList();
    final folderName = directory.path.split('/').last;

    return Scaffold(
      appBar: AppBar(title: Text(folderName)),
      body: ListView.builder(
        itemCount: files.length,
        itemBuilder: (ctx, i) {
          final file = files[i];
          final fileName = file.path.split('/').last;
          
          final isVideo = fileName.endsWith('.mov') || fileName.endsWith('.mp4');
          final isLidar = fileName.endsWith('.raw'); // Detect LiDAR

          return ListTile(
            leading: Icon(
              isLidar ? Icons.image : (isVideo ? Icons.play_circle_fill : Icons.insert_drive_file),
              color: isLidar ? Colors.purple : (isVideo ? Colors.red : Colors.blueGrey),
            ),
            title: Text(fileName),
            subtitle: Text("${(file.lengthSync() / 1024).toStringAsFixed(1)} KB"),
            onTap: () {
              if (isLidar) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LidarHeatmapViewer(file: file),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}