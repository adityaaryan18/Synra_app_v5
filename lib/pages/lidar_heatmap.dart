import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class LidarHeatmapViewer extends StatelessWidget {
  final File file;
  const LidarHeatmapViewer({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("LiDAR Depth Map")),
      body: FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          // Assuming standard iPad LiDAR resolution of 256x192
          // If your resolution is different, adjust these numbers.
          return Center(
            child: InteractiveViewer( // Allows pinching to zoom into the image
              child: CustomPaint(
                size: const Size(256, 192), 
                painter: LidarPainter(snapshot.data!),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LidarPainter extends CustomPainter {
  final Uint8List rawBytes;
  LidarPainter(this.rawBytes);

  @override
  void paint(Canvas canvas, Size size) {
   
    final data = rawBytes.buffer.asUint16List();
    final paint = Paint();

    const int width = 300;
    const int height = 192;

    double cellWidth = size.width / width;
    double cellHeight = size.height / height;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int index = y * width + x;
        if (index >= data.length) break;

        double depth = data[index].toDouble(); 
        
        // Convert depth (0-5000mm) to a color
        // Red = Close, Blue = Far
        if (depth == 0) {
          paint.color = Colors.black; // No data
        } else {
          double hue = (depth / 5000 * 240).clamp(0, 240); 
          paint.color = HSVColor.fromAHSV(1.0, 240 - hue, 1.0, 1.0).toColor();
        }

        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth + 0.5, cellHeight + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}