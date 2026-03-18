import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'setup_page.dart';
import 'camera_logic.dart';
import 'sensor_logic.dart';

abstract class SetupPageLogic extends State<SetupPage> {
  final CameraLogic c = CameraLogic();
  final SensorLogic s = SensorLogic();
  double baseZoom = 1.0;
  int? textureId;
  bool isLocked = false;

  @override
    void initState() {
      super.initState();
      // CHANGE THIS: Allow all orientations so the hardware can auto-rotate
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      
      CameraLogic.channel.setMethodCallHandler((call) async {
        if (call.method == "onFocusChanged") {
          setState(() {
            c.selectedFocus = (call.arguments as num).toDouble();
          });
        }
      });

      initNativeCamera();
      initIMU();
    }

  Future<void> initNativeCamera() async {
    try {
      final int id = await CameraLogic.channel.invokeMethod('initializePreview');
      setState(() {
        textureId = id;
        c.cameraReady = true;
      });
    } catch (e) {
      debugPrint("Native Camera Init Error: $e");
    }
  }

  void initIMU() {
    s.aSub = accelerometerEvents.listen((e) {
      s.a = e;
      setState(() => s.isStable = s.updateStability());
    });
    
    s.gSub = gyroscopeEvents.listen((e) { 
      s.g = e; 
      // FIXED: Changed _s to s
      s.updateStability(); 
      setState(() {}); 
    });
    
  }

  Future<void> toggle() async {
      if (!s.isStable || c.isProcessing) return;
      HapticFeedback.mediumImpact();
      
      if (!c.recording) {
        setState(() { c.isProcessing = true; c.activeSetting = null; });
        // Updated the dialog text to reflect the new speed
        c.showProcessingDialog(context, "Initializing 4K 120FPS ProRes Session..."); 
        try {
          await CameraLogic.channel.invokeMethod('getLidarProfile');
          await Future.delayed(const Duration(milliseconds: 300));
          
          // CHANGE THIS LINE: 240 -> 120
          await CameraLogic.channel.invokeMethod('start', {'fps': 120}); 
          
          await CameraLogic.channel.invokeMethod('setLock', true);
          
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
          c.startTimer(() => setState(() {}));
          setState(() { 
            c.recording = true; 
            c.isProcessing = false;
            isLocked = true; 
          });
        } catch (e) {
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
          setState(() => c.isProcessing = false);
        }
      } else {
      setState(() { c.isProcessing = true; });
      try {
        await CameraLogic.channel.invokeMethod('stop');
        await CameraLogic.channel.invokeMethod('setLock', false);
        c.stopTimer();
        setState(() { 
          c.recording = false; 
          c.isProcessing = false;
          isLocked = false;
        });
      } catch (e) { 
        setState(() => c.isProcessing = false); 
      }
    }
  }

  void updateActive(String label) {
    if (isLocked) return; 
    HapticFeedback.lightImpact();
    setState(() => c.activeSetting = (c.activeSetting == label) ? null : label);
  }

  Widget buildLockButton() {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.heavyImpact();
        bool nextState = !isLocked;
        await CameraLogic.channel.invokeMethod('setLock', nextState);
        setState(() => isLocked = nextState);
      },
      child: Column(
        children: [
          Icon(
            isLocked ? Icons.lock : Icons.lock_open,
            color: isLocked ? Colors.redAccent : Colors.white70,
            size: 20,
          ),
          const Text("LOCK", style: TextStyle(color: Colors.white54, fontSize: 9)),
        ],
      ),
    );
  }

  Widget buildContextualSlider() {
    if (c.activeSetting == "FOCUS") {
      return Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          children: [
            Slider(
              value: c.selectedFocus.clamp(0.0, 1.0),
              activeColor: isLocked ? Colors.redAccent : Colors.cyanAccent,
              inactiveColor: Colors.white12,
              onChanged: isLocked ? null : (val) {
                setState(() => c.selectedFocus = val);
                c.updateHardwareFocus();
              },
            ),
            Text(
              isLocked ? "LENS POSITION LOCKED" : "LENS POSITION: ${c.selectedFocus.toStringAsFixed(2)}",
              style: TextStyle(
                color: isLocked ? Colors.redAccent : Colors.cyanAccent, 
                fontSize: 10, 
                fontWeight: FontWeight.bold
              ),
            ),
          ],
        ),
      );
    }

    List<dynamic> currentOptions = [];
    if (c.activeSetting == "ISO") currentOptions = c.isoValues;
    else if (c.activeSetting == "SHUTTER") currentOptions = c.shutters;
    else if (c.activeSetting == "LENS") currentOptions = c.lenses;
    else if (c.activeSetting == "WB") currentOptions = c.wbValues;

    return Container(
      height: 55, margin: const EdgeInsets.only(top: 15),
      decoration: BoxDecoration(color: Colors.white10, border: const Border.symmetric(horizontal: BorderSide(color: Colors.white10))),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: currentOptions.length,
        itemBuilder: (context, index) {
          var opt = currentOptions[index];
          bool isSel = opt.toString() == (c.activeSetting == "ISO" ? c.selectedISO.toString() : 
                        c.activeSetting == "SHUTTER" ? c.selectedShutter : 
                        c.activeSetting == "LENS" ? c.selectedLens : c.selectedWB);
          return GestureDetector(
            onTap: () {
              if (isLocked) return;
              HapticFeedback.selectionClick();
              setState(() {
                if (c.activeSetting == "ISO") { c.selectedISO = opt; c.updateHardwareISO(); }
                if (c.activeSetting == "SHUTTER") { c.selectedShutter = opt; c.updateHardwareShutter(); }
                if (c.activeSetting == "WB") { c.selectedWB = opt; c.updateHardwareWB(); }
              });
            },
            child: Container(
              alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(opt.toString(), style: TextStyle(color: isSel ? Colors.cyanAccent : Colors.white70, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
            ),
          );
        },
      ),
    );
  }

  Widget buildRecordButton() {
    return GestureDetector(
      onTap: toggle,
      child: Container(
        height: 75, width: 75,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3.5)),
        child: Center(
          child: c.isProcessing 
            ? const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)
            : AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: c.recording ? 32 : 58, height: c.recording ? 32 : 58,
                decoration: BoxDecoration(color: c.recording ? Colors.redAccent : Colors.white, borderRadius: BorderRadius.circular(c.recording ? 6 : 50)),
              ),
        ),
      ),
    );
  }

  @override
  void dispose() { 
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    s.dispose(); 
    c.stopTimer(); 
    super.dispose(); 
  }
}