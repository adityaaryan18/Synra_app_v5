import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CsvViewerPage extends StatelessWidget {
  final File file;
  const CsvViewerPage({super.key, required this.file});

  Future<List<String>> _readCsv() async {
    return await file.readAsLines();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = file.path.split('/').last;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          fileName,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            color: Colors.black87,
            onPressed: () async {
              final content = await file.readAsString();
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("CSV copied to clipboard"),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          )
        ],
      ),
      body: FutureBuilder<List<String>>(
        future: _readCsv(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final lines = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  lines[index],
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}