import 'package:flutter/material.dart';

class HistogramPainter extends CustomPainter {
  final List<int> data;
  final Color color;

  HistogramPainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Find max value for normalization
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final path = Path();
    path.moveTo(0, size.height);

    for (int i = 0; i < data.length; i++) {
      double x = (i / data.length) * size.width;
      // Calculate height (inverted for canvas coordinates)
      double y = size.height - (data[i] / maxVal) * size.height;
      path.lineTo(x, y);
    }

    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(HistogramPainter oldDelegate) => true;
}