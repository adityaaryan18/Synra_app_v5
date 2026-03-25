import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/* ─────────────────────────────────────────────────────────────
   DROPBOX SERVICE
   ───────────────────────────────────────────────────────────── */
class DropboxService {
  final String clientId = "26to6hl1uhekjtl";
  final String clientSecret = "jpba0y24qk1r4k8";
  
  // PASTE YOUR NEW REFRESH TOKEN HERE AFTER RUNNING THE CURL COMMAND
  final String refreshToken = "BcEM90FhOq8AAAAAAAAAAR7l7Cr71GboZTWTMV8wrO7f51c7L7MJu_arD4GQikB3";

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
      } else {
        debugPrint("Auth Error: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("Network Error: $e");
      return null;
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

  // Generates a public link for the folder
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
    } else if (data['error']['.tag'] == 'shared_link_already_exists') {
      // If link already exists, Dropbox returns an error; we can usually find the URL in the error metadata
      return data['error']['shared_link_already_exists']['metadata']['url'];
    }
    return null;
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

  Future<void> _uploadSession(Directory folder) async {
    final folderName = folder.path.split('/').last;
    final files = folder.listSync().whereType<File>().toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text("Uploading $folderName...")),
          ],
        ),
      ),
    );

    int count = 0;
    String remoteFolderPath = "/SYNRA ipad App Data/$folderName";

    for (var file in files) {
      final fileName = file.path.split('/').last;
      bool ok = await _dropbox.uploadFile(
        file,
        "$remoteFolderPath/$fileName",
      );
      if (ok) count++;
    }

    // Try to get a shared link now that upload is done
    String? sharedUrl = await _dropbox.getSharedLink(remoteFolderPath);

    Navigator.pop(context); // Close loading dialog

    if (sharedUrl != null) {
      _showShareSuccessDialog(folderName, sharedUrl);
    } else {
      _showSnackBar("Uploaded $count/${files.length} files to Dropbox.");
    }
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
          : ListView.builder(
              itemCount: _sessions.length,
              itemBuilder: (ctx, i) {
                final folder = _sessions[i];
                final name = folder.path.split('/').last;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: const Icon(Icons.folder, color: Colors.amber, size: 36),
                    title: Text(name),
                    subtitle: const Text("Includes LiDAR, Video, IMU"),
                    trailing: IconButton(
                      icon: const Icon(Icons.cloud_upload, color: Colors.blue),
                      onPressed: () => _uploadSession(folder),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => FileBrowserPage(directory: folder)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/* ─────────────────────────────────────────────────────────────
   FILE BROWSER PAGE
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

          return ListTile(
            leading: Icon(
              isVideo ? Icons.play_circle_fill : Icons.insert_drive_file,
              color: isVideo ? Colors.red : Colors.blueGrey,
            ),
            title: Text(fileName),
            subtitle: Text("${(file.lengthSync() / 1024).toStringAsFixed(1)} KB"),
          );
        },
      ),
    );
  }
}