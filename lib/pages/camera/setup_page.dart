import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:synra/pages/camera/histogram_painter.dart';
import 'setup_page_logic.dart'; 
import 'setup_ui_components.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends SetupPageLogic {
  @override
  Widget build(BuildContext context) {
    if (!c.cameraReady || textureId == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onScaleStart: (details) {
          if (isLocked) return;
          baseZoom = c.zoomFactor;
        },
        onScaleUpdate: (details) {
          if (isLocked) return;
          setState(() {
            c.zoomFactor = (baseZoom * details.scale).clamp(1.0, 10.0);
            c.updateHardwareZoom(c.zoomFactor);
            if (c.zoomFactor < 1.0) c.selectedLens = "ULTRA";
            else if (c.zoomFactor >= 3.0) c.selectedLens = "TELE";
            else c.selectedLens = "WIDE";
          });
        },
        child: Stack(
          children: [
            // 1. NATIVE PREVIEW (Fixed Aspect Ratio)
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: isLandscape ? 16 / 9 : 9 / 16,
                  child: Texture(textureId: textureId!),
                ),
              ),
            ),

            // 2. PRORES 4K 120FPS BADGE
            Positioned(
              top: isLandscape ? 20 : 55,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "4K 120 PRORES",
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            // 3. ZOOM MINI-MAP
            if (c.zoomFactor > 1.2)
              Positioned(
                top: isLandscape ? 80 : 160,
                right: 20,
                child: _buildMiniMap(),
              ),

            // 4. TOP CONTROLS (Includes Focus Tab)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black.withOpacity(0.5),
                padding: EdgeInsets.only(top: isLandscape ? 15 : 45, bottom: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 55, 
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 15),
                            SetupUI.buildProButton(label: "LENS", value: c.selectedLens, isActive: c.activeSetting == "LENS", onTap: () => updateActive("LENS")),
                            buildLockButton(),
                            SetupUI.buildProButton(label: "SHUTTER", value: c.selectedShutter, isActive: c.activeSetting == "SHUTTER", onTap: () => updateActive("SHUTTER")),
                            SetupUI.buildProButton(label: "ISO", value: "${c.selectedISO}", isActive: c.activeSetting == "ISO", onTap: () => updateActive("ISO")),
                            SetupUI.buildProButton(label: "WB", value: c.selectedWB, isActive: c.activeSetting == "WB", onTap: () => updateActive("WB")),
                            SetupUI.buildProButton(label: "FOCUS", value: c.selectedFocus.toStringAsFixed(2), isActive: c.activeSetting == "FOCUS", onTap: () => updateActive("FOCUS")),
                            const SizedBox(width: 15),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.formatDuration(),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2)
                    ),
                    if (c.activeSetting != null) buildContextualSlider(),
                  ],
                ),
              ),
            ),

            // 5. IMU DATA HUD
            Positioned(
              bottom: isLandscape ? 20 : 125, 
              right: 20, 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // --- Visual Analysis Section ---
                  _buildHistogramBox("EXP / SATURATION", brightnessData, Colors.white70),
                  const SizedBox(height: 8),
                  _buildHistogramBox("FOCUS / EDGES", edgeData, Colors.cyanAccent),
                  const SizedBox(height: 15),
                  
                  // Existing IMU HUD
                  SetupUI.build6AxisHUD(s),
                ],
              )
            ),

            // 6. RECORDING TRIGGER
            Positioned(
              bottom: isLandscape ? 20 : 45, 
              left: isLandscape ? 20 : 0, 
              right: isLandscape ? null : 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SetupUI.buildStabilityIndicator(s.isStable),
                  const SizedBox(height: 15),
                  buildRecordButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistogramBox(String label, List<int> data, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          width: 120, 
          height: 35,
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white10, width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(
              painter: HistogramPainter(data, color.withOpacity(0.5)),
            ),
          ),
        ),
      ],
    );
  }

Widget _buildMiniMap() {
    const double mapWidth = 100.0;
    const double mapHeight = 140.0;
    
    const double indicatorWidth = 30.0;
    const double indicatorHeight = 42.0;

    return Container(
      width: mapWidth,
      height: mapHeight,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
        borderRadius: BorderRadius.circular(12),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. BACKGROUND FEED
            Positioned.fill(
              child: Opacity(
                opacity: 0.5,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: mapWidth,
                    height: mapHeight,
                    child: Texture(textureId: textureId!),
                  ),
                ),
              ),
            ),

            // 2. FIXED RED BOX (No Squeezing)
            Container(
              width: indicatorWidth,
              height: indicatorHeight,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.redAccent, width: 2.0),
              ),
            ),

            // 3. ZOOM LEVEL TEXT OVERLAY
            // Positioned at the bottom of the Mini-Map
            Positioned(
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "${c.zoomFactor.toStringAsFixed(1)}x",
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Center Point
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
