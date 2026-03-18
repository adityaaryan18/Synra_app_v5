import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class CameraLogic {
  static const MethodChannel channel = MethodChannel('synra/camera');

  CameraController? cameraController;
  bool cameraReady = false;
  bool recording = false;
  bool isProcessing = false;

  String? activeSetting;

  final List<String> lenses = ["Wide", "Tele", "Ultra"];
  
  // UPDATED: Added ISO 50 and 64 for cleaner ProRes footage
  final List<int> isoValues = [50, 100, 200, 400, 800, 1200, 1600]; 
  
  // UPDATED: Added 1/125, 1/250, and 1/500 to align with 120 FPS recording
  final List<String> shutters = ["1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000"];
  
  final List<String> wbValues = ["3200K", "4500K", "5500K", "6500K"];
  double zoomFactor = 1.0;

  String selectedLens = "Wide";
  int selectedISO = 100; // Default to lower ISO for better ProRes quality
  String selectedShutter = "1/250"; // Default to ~180 degree shutter for 120fps
  String selectedWB = "5500K";
  double selectedFocus = 0.50;

  // --- Bridge Methods to Swift (Updated) ---

  Future<void> updateHardwareZoom(double factor) async {
    try {
      await channel.invokeMethod('updateZoom', factor);
    } catch (e) {
      debugPrint("Zoom error: $e");
    }
  }

  Future<void> updateHardwareISO() async {
    // iPhone 16 Pro ProRes handles low ISOs beautifully
    await channel.invokeMethod('updateISO', selectedISO.toDouble());
  }

  Future<void> updateHardwareShutter() async {
    await channel.invokeMethod('updateShutter', selectedShutter);
  }

  Future<void> updateHardwareFocus() async {
    await channel.invokeMethod('updateFocus', selectedFocus);
  }

  Future<void> updateHardwareWB() async {
    await channel.invokeMethod('updateWB', selectedWB);
  }

  Future<void> updateHardwareLens() async {
    await channel.invokeMethod('updateLens', selectedLens);
  }

  // --- Timer & Dialog Logic ---
  Duration recordDuration = Duration.zero;
  Timer? timer;

  void startTimer(Function onTick) {
    recordDuration = Duration.zero;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      recordDuration += const Duration(seconds: 1);
      onTick();
    });
  }

  void stopTimer() {
    timer?.cancel();
    timer = null; // Clean up the reference
    recordDuration = Duration.zero;
  }

  String formatDuration() {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(recordDuration.inHours)}:${twoDigits(recordDuration.inMinutes.remainder(60))}:${twoDigits(recordDuration.inSeconds.remainder(60))}";
  }

  void showProcessingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        content: Row(
          children: [
            const CircularProgressIndicator(color: Colors.cyanAccent),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message, 
                style: const TextStyle(color: Colors.white, fontSize: 14)
              )
            ),
          ],
        ),
      ),
    );
  }
}