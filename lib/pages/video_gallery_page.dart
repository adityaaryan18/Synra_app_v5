import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:synra/pages/lidar_heatmap.dart';
import 'package:synra/pages/video_player_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

/* ─────────────────────────────────────────────────────────────
   DROPBOX SERVICE (Updated with Chunked Upload Sessions)
   ───────────────────────────────────────────────────────────── */

class DropboxService {
  static final DropboxService _instance = DropboxService._internal();
  factory DropboxService() => _instance;
  DropboxService._internal();

  final String clientId = "26to6hl1uhekjtl";
  final String clientSecret = "jpba0y24qk1r4k8";
  final String refreshToken = "BcEM90FhOq8AAAAAAAAAAR7l7Cr71GboZTWTMV8wrO7f51c7L7MJu_arD4GQikB3";

  final ValueNotifier<Map<String, double>> uploadProgress = ValueNotifier({});
  final Map<String, bool> _cancelRequests = {};

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
      return null;
    } catch (e) {
      return null;
    }
  }

Future<void> uploadSession(
  Directory folder, {
  required Function(String url) onComplete,
  required Function(String error) onError,
}) async {
  final folderName = folder.path.split('/').last;
  
  // CHANGE: Set recursive to true to find files in the 'snapshots' folder
  final allEntities = folder.listSync(recursive: true);
  final files = allEntities.whereType<File>().toList();
  
  if (files.isEmpty) {
    onError("Folder is empty");
    return;
  }

  _cancelRequests[folderName] = false;
  _updateProgress(folderName, 0.0);

  String remoteRootPath = "/SYNRA ipad App Data/$folderName";
  
  int totalBytes = 0;
  for (var f in files) {
    totalBytes += f.lengthSync();
  }
  int totalBytesSent = 0;

  for (var file in files) {
    if (_cancelRequests[folderName] == true) {
      _cleanup(folderName);
      onError("Upload cancelled");
      return;
    }

    // CHANGE: Calculate the relative path to preserve the 'snapshots/' folder structure
    // This turns '.../Session_1/snapshots/image.jpg' into 'snapshots/image.jpg'
    String relativePath = file.path.split(folderName).last; 
    String remoteFilePath = "$remoteRootPath$relativePath";
    
    bool ok = await _uploadFileInChunks(
      file, 
      remoteFilePath, 
      (bytesSentInFile) {
        double overallProgress = (totalBytesSent + bytesSentInFile) / totalBytes;
        _updateProgress(folderName, overallProgress);
      }
    );

    if (ok) {
      totalBytesSent += file.lengthSync();
    } else {
      debugPrint("Failed to upload: ${file.path}");
    }
  }

  // Generate link for the main folder
  String? sharedUrl = await getSharedLink(remoteRootPath);
  _cleanup(folderName);
  
  if (sharedUrl != null) {
    onComplete(sharedUrl);
  } else {
    onError("Uploaded files but failed to generate sharing link.");
  }
}

  /// New Method: Handles Large Files via start/append/finish sessions
  Future<bool> _uploadFileInChunks(File file, String remotePath, Function(int) onProgress) async {
    final token = await _getAccessToken();
    if (token == null) return false;

    final int fileSize = file.lengthSync();
    final int chunkSize = 4 * 1024 * 1024; // 4MB chunks
    final reader = file.openSync();

    try {
      // 1. Start Session
      String sessionId = "";
      List<int> firstChunk = reader.readSync(chunkSize);
      
      final startUrl = Uri.parse("https://content.dropboxapi.com/2/files/upload_session/start");
      final startRes = await http.post(
        startUrl,
        headers: {
          "Authorization": "Bearer $token",
          "Dropbox-API-Arg": jsonEncode({"close": false}),
          "Content-Type": "application/octet-stream",
        },
        body: firstChunk,
      );

      if (startRes.statusCode != 200) return false;
      sessionId = jsonDecode(startRes.body)['session_id'];
      
      int uploadedBytes = firstChunk.length;
      onProgress(uploadedBytes);

      // 2. Append Middle Chunks
      while (uploadedBytes < fileSize - chunkSize) {
        List<int> chunk = reader.readSync(chunkSize);
        final appendUrl = Uri.parse("https://content.dropboxapi.com/2/files/upload_session/append_v2");
        
        final appendRes = await http.post(
          appendUrl,
          headers: {
            "Authorization": "Bearer $token",
            "Dropbox-API-Arg": jsonEncode({
              "cursor": {"session_id": sessionId, "offset": uploadedBytes},
              "close": false
            }),
            "Content-Type": "application/octet-stream",
          },
          body: chunk,
        );

        if (appendRes.statusCode != 200) return false;
        uploadedBytes += chunk.length;
        onProgress(uploadedBytes);
      }

      // 3. Finish Session
      List<int> finalChunk = reader.readSync(fileSize - uploadedBytes);
      final finishUrl = Uri.parse("https://content.dropboxapi.com/2/files/upload_session/finish");
      
      final finishRes = await http.post(
        finishUrl,
        headers: {
          "Authorization": "Bearer $token",
          "Dropbox-API-Arg": jsonEncode({
            "cursor": {"session_id": sessionId, "offset": uploadedBytes},
            "commit": {
              "path": remotePath,
              "mode": "overwrite",
              "mute": true,
              "autorename": true
            }
          }),
          "Content-Type": "application/octet-stream",
        },
        body: finalChunk,
      );

      onProgress(fileSize);
      return finishRes.statusCode == 200;
    } catch (e) {
      debugPrint("Chunk Upload Error: $e");
      return false;
    } finally {
      reader.closeSync();
    }
  }

  // Deprecated single-file upload (kept for interface compatibility if needed elsewhere)
  Future<bool> uploadFile(File file, String remotePath) async {
    return _uploadFileInChunks(file, remotePath, (p) {});
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

  void _updateProgress(String key, double value) {
    final current = Map<String, double>.from(uploadProgress.value);
    current[key] = value.clamp(0.0, 1.0);
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
  final DropboxService _dropbox = DropboxService();
  final Map<String, String> _completedUrls = {};

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadSavedLinks(); // Load links from storage on startup
  }

  // NEW: Load saved links from phone storage
  Future<void> _loadSavedLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    setState(() {
      for (String key in keys) {
        if (key.startsWith('link_')) {
          _completedUrls[key.replaceFirst('link_', '')] = prefs.getString(key) ?? "";
        }
      }
    });
  }

  // NEW: Save link to phone storage
  Future<void> _saveLink(String folderName, String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('link_$folderName', url);
    setState(() {
      _completedUrls[folderName] = url;
    });
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

  void _startUpload(Directory folder) {
    final name = folder.path.split('/').last;
    
    _dropbox.uploadSession(
      folder,
      onComplete: (sharedUrl) async {
        await _saveLink(name, sharedUrl); // Save persistently
        if (mounted) {
          _showShareSuccessDialog(name, sharedUrl);
        }
      },
      onError: (error) {
        if (mounted) _showSnackBar(error);
      },
    );
  }

  Future<void> _openDropboxUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar("Could not open link");
    }
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
                    
                    final isUploading = activeUploads.containsKey(name);
                    final progress = activeUploads[name] ?? 0.0;
                    final finishedUrl = _completedUrls[name];

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      clipBehavior: Clip.antiAlias,
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
                                : (finishedUrl != null)
                                    ? ElevatedButton.icon(
                                        onPressed: () => _openDropboxUrl(finishedUrl),
                                        icon: const Icon(Icons.open_in_new, size: 16),
                                        label: const Text("Dropbox"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                        ),
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

  void _showShareSuccessDialog(String folderName, String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Upload Complete"),
        content: const Text("Folder is now on Dropbox and ready to share."),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              _showSnackBar("Link copied!");
            },
            child: const Text("Copy Link"),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
          
          final isVideo = fileName.toLowerCase().endsWith('.mov') || 
                          fileName.toLowerCase().endsWith('.mp4');
          final isLidar = fileName.toLowerCase().endsWith('.raw'); // Detect LiDAR

          return ListTile(
            leading: Icon(
              isLidar ? Icons.image : (isVideo ? Icons.play_circle_fill : Icons.insert_drive_file),
              color: isLidar ? Colors.purple : (isVideo ? Colors.red : Colors.blueGrey),
            ),
            title: Text(fileName),
            subtitle: Text("${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB"),
            onTap: () {
              if (isLidar) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LidarHeatmapViewer(file: file),
                  ),
                );
              } else if (isVideo) {
                // Navigate to your VideoPlayerPage
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerPage(videoFile: file),
                  ),
                );
              } else if (isVideo) {
                // Navigate to your VideoPlayerPage
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerPage(videoFile: file),
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