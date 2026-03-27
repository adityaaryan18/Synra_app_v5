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
  String expName = "Unnamed Experiment";
  String expDesc = "";
  List<int> brightnessData = [];
  List<int> edgeData = [];

  // --- NEW: Warning Properties ---
  String? errorMessage;
  bool showStabilityWarning = false;

  @override
  void initState() {
    super.initState();
    // Keep UI in Portrait only
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Trigger the memo dialog immediately upon entering the page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMemoDialog();
    });
    
    CameraLogic.channel.setMethodCallHandler((call) async {
      if (call.method == "onFocusChanged") {
        setState(() => c.selectedFocus = (call.arguments as num).toDouble());
      } 
      // --- NEW: Handle Histogram Data ---
      else if (call.method == "onHistogramUpdate") {
        // --- DEBUG PRINT 3: Check Dart Reception ---
        final Map<dynamic, dynamic> args = call.arguments;
        final List<dynamic>? bright = args['brightness'];
        
        if (bright != null && bright.isNotEmpty) {
          // Find the highest peak in the histogram to see if it's changing
          int peakValue = 0;
          for (var val in bright) {
            if ((val as int) > peakValue) peakValue = val;
          }
          
          debugPrint("DART: Received Histogram. Bin Count: ${bright.length}, Peak Value: $peakValue");
          
          setState(() {
            brightnessData = bright.cast<int>();
            edgeData = (args['edges'] as List<dynamic>).cast<int>();
          });
        } else {
          debugPrint("DART ERROR: Received histogram call but data was NULL or EMPTY");
        }
      }
    });

    initNativeCamera();
    initIMU();
  }

  Future<void> _showMemoDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false, // Force them to provide a name
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Experiment Setup", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Experiment Name", labelStyle: TextStyle(color: Colors.cyanAccent)),
              onChanged: (val) => expName = val,
            ),
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Description (Optional)"),
              onChanged: (val) => expDesc = val,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              if (expName.isNotEmpty) Navigator.pop(context);
            }, 
            child: const Text("SAVE MEMO"),
          ),
        ],
      ),
    );
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
      setState(() => errorMessage = "DEVICE INCOMPATIBLE: Camera failed.");
    }
  }

  void initIMU() {
    s.aSub = accelerometerEvents.listen((e) {
      s.a = e;
      bool currentlyStable = s.updateStability();
      
      // AUTO-STOP LOGIC: If recording and motion is extremely unstable
      if (c.recording && !currentlyStable) {
        if (!showStabilityWarning) {
          setState(() => showStabilityWarning = true);
          // Force stop the recording if it's too shaky
          toggle(); 
        }
      }
      
      setState(() => s.isStable = currentlyStable);
    });
    
    s.gSub = gyroscopeEvents.listen((e) { 
      s.g = e; 
      s.updateStability(); 
      setState(() {}); 
    });
  }

  // NEW: Warning Overlay Widget
  Widget buildWarningOverlay() {
    if (errorMessage != null) {
      return Container(
        color: Colors.black.withOpacity(0.9),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
              const SizedBox(height: 20),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => setState(() => errorMessage = null),
                child: const Text("DISMISS"),
              )
            ],
          ),
        ),
      );
    }

    if (showStabilityWarning) {
      return Positioned(
        top: 120, left: 20, right: 20,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "RECORDING STOPPED\nDevice too unstable. Please hold steady.",
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => showStabilityWarning = false),
                child: const Icon(Icons.close, color: Colors.white),
              )
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> toggle() async {
    if ((!s.isStable && !c.recording) || c.isProcessing) return;
    HapticFeedback.mediumImpact();
    
    if (!c.recording) {
      setState(() { 
        c.isProcessing = true; 
        c.activeSetting = null; 
        showStabilityWarning = false;
        errorMessage = null;
      });
      c.showProcessingDialog(context, "Initializing 4K 120FPS ProRes..."); 
      try {
        await CameraLogic.channel.invokeMethod('updateMetadata', {
        'name': expName, 
        'desc': expDesc,
        });
        await CameraLogic.channel.invokeMethod('getLidarProfile');
        await Future.delayed(const Duration(milliseconds: 300));
        
        // This will throw an error if the device doesn't support 120fps
        await CameraLogic.channel.invokeMethod('start', {
          'fps': 120,
          'name': expName, 
          'desc': expDesc,
        });
        
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
        setState(() {
          c.isProcessing = false;
          errorMessage = "HARDWARE NOT COMPATIBLE\n4K 120FPS is not supported on this device.";
        });
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
          Icon(isLocked ? Icons.lock : Icons.lock_open, color: isLocked ? Colors.redAccent : Colors.white70, size: 20),
          const Text("LOCK", style: TextStyle(color: Colors.white54, fontSize: 9)),
        ],
      ),
    );
  }

  Widget buildContextualSlider() {
    if (c.activeSetting == "FOCUS") {
      return Container(
        height: 70, padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          children: [
            Slider(
              value: c.selectedFocus.clamp(0.0, 1.0),
              activeColor: isLocked ? Colors.redAccent : Colors.cyanAccent,
              onChanged: isLocked ? null : (val) { setState(() => c.selectedFocus = val); c.updateHardwareFocus(); },
            ),
            Text(isLocked ? "LENS LOCKED" : "LENS: ${c.selectedFocus.toStringAsFixed(2)}", style: const TextStyle(color: Colors.cyanAccent, fontSize: 10)),
          ],
        ),
      );
    }
    List<dynamic> currentOptions = [];
    if (c.activeSetting == "ISO") currentOptions = c.isoValues;
    else if (c.activeSetting == "SHUTTER") currentOptions = c.shutters;
    else if (c.activeSetting == "WB") currentOptions = c.wbValues;

    return Container(
      height: 55, margin: const EdgeInsets.only(top: 15),
      child: ListView.builder(
        scrollDirection: Axis.horizontal, itemCount: currentOptions.length,
        itemBuilder: (context, index) {
          var opt = currentOptions[index];
          return GestureDetector(
            onTap: () {
              if (isLocked) return;
              setState(() {
                if (c.activeSetting == "ISO") { c.selectedISO = opt; c.updateHardwareISO(); }
                if (c.activeSetting == "SHUTTER") { c.selectedShutter = opt; c.updateHardwareShutter(); }
                if (c.activeSetting == "WB") { c.selectedWB = opt; c.updateHardwareWB(); }
              });
            },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 28), child: Text(opt.toString(), style: const TextStyle(color: Colors.white70))),
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
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    s.dispose(); 
    c.stopTimer(); 
    super.dispose(); 
  }
}