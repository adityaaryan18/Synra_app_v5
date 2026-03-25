import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for MethodChannel
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';

class LidarVideoPage extends StatefulWidget {
  const LidarVideoPage({super.key});

  @override
  State<LidarVideoPage> createState() => _LidarVideoPageState();
}

class _LidarVideoPageState extends State<LidarVideoPage> {
  // 1. Define the Bridge to Swift LidarCameraManager
  static const platform = MethodChannel('com.synra.highspeed/camera');
  
  bool _isRecording = false;
  Timer? _timer;
  int _seconds = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _seconds++);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  // 2. Logic to Trigger Swift Lidar Manager
  Future<void> _toggleLidarRecording() async {
    try {
      if (!_isRecording) {
        // Calling Swift LidarCameraManager.startCapture
        await platform.invokeMethod('startLidarOnly');
        _startTimer();
      } else {
        // Calling Swift LidarCameraManager.stopCapture
        await platform.invokeMethod('stopLidarOnly');
        _stopTimer();
      }

      setState(() {
        _isRecording = !_isRecording;
      });
    } on PlatformException catch (e) {
      debugPrint("LiDAR Hardware Error: ${e.message}");
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Hardware Error: ${e.message}")),
      );
    }
  }

  String _formatTime(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$mins:$secs";
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isRecording) {
          // Prevent leaving while recording to avoid corrupting the .mov
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Stop recording before leaving")),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('LiDAR CAPTURE', 
            style: GoogleFonts.orbitron(color: Colors.white, fontSize: 18)
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Stack(
          children: [
            // 1. Placeholder for Depth Stream
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sensors, 
                    size: 80, 
                    color: _isRecording ? Colors.red.withOpacity(0.5) : Colors.white10
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isRecording ? "DEPTH STREAMING..." : "HARDWARE STANDBY", 
                    style: GoogleFonts.orbitron(
                      color: Colors.white24, 
                      letterSpacing: 2,
                      fontSize: 12
                    )
                  ),
                ],
              ),
            ),
            
            // 2. Control UI
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 60.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isRecording)
                      Text(
                        _formatTime(_seconds),
                        style: const TextStyle(
                          color: Colors.red, 
                          fontSize: 24, 
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      _isRecording ? "RECORDING DEPTH DATA" : "TAP TO START SESSION",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 30),
                    
                    // The Capture Button
                    GestureDetector(
                      onTap: _toggleLidarRecording,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 85,
                        width: 85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isRecording ? Colors.red : Colors.white, 
                            width: 5
                          ),
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: _isRecording ? 35 : 65,
                            width: _isRecording ? 35 : 65,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(_isRecording ? 8 : 40),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}