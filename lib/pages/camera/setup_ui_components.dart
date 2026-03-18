import 'package:flutter/material.dart';
import 'sensor_logic.dart';

class SetupUI {
  /// Professional top buttons (LENS, ISO, etc.)
  /// Fixed width prevents the 'infinite constraints' crash in horizontal scroll views.
  static Widget buildProButton({
    required String label,
    required String value,
    required bool isActive,
    bool isFixed = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isFixed ? null : onTap,
      child: Container(
        width: 85, 
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label, 
              style: const TextStyle(
                color: Colors.white60, 
                fontSize: 8, 
                fontWeight: FontWeight.w600, 
                letterSpacing: 0.5
              )
            ),
            const SizedBox(height: 4),
            Text(
              value, 
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isFixed ? Colors.orange : (isActive ? Colors.cyanAccent : Colors.white), 
                fontSize: 12, 
                fontWeight: FontWeight.w900
              )
            ),
          ],
        ),
      ),
    );
  }

  /// 6-Axis Telemetry HUD
  /// Displays live structural vibration data from the iPhone 16 Pro IMU.
  static Widget build6AxisHUD(SensorLogic s) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87, 
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "6-AXIS TELEMETRY", 
            style: TextStyle(
              color: Colors.cyanAccent, 
              fontSize: 8, 
              fontWeight: FontWeight.bold, 
              letterSpacing: 1.5
            )
          ),
          const SizedBox(height: 8),
          _buildDataLine("ACC", "${s.a?.x.toStringAsFixed(2)}, ${s.a?.y.toStringAsFixed(2)}, ${s.a?.z.toStringAsFixed(2)}"),
          const SizedBox(height: 4),
          _buildDataLine("GYR", "${s.g?.x.toStringAsFixed(2)}, ${s.g?.y.toStringAsFixed(2)}, ${s.g?.z.toStringAsFixed(2)}"),
        ],
      ),
    );
  }

  static Widget _buildDataLine(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 30, 
          child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold))
        ),
        Text(
          value, 
          style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'monospace')
        ),
      ],
    );
  }

  /// Stability Status Indicator
  static Widget buildStabilityIndicator(bool isStable) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isStable ? Colors.greenAccent.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2), 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isStable ? Colors.greenAccent : Colors.redAccent, width: 1)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isStable ? Icons.check_circle : Icons.warning_amber_rounded, 
            color: Colors.white, 
            size: 12
          ),
          const SizedBox(width: 8),
          Text(
            isStable ? "STABLE - READY" : "STABILIZING...", 
            style: const TextStyle(
              color: Colors.white, 
              fontSize: 10, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 0.5
            )
          ),
        ],
      ),
    );
  }
}
