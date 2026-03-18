import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class SensorLogic {
  AccelerometerEvent? a;
  GyroscopeEvent? g;
  StreamSubscription<AccelerometerEvent>? aSub;
  StreamSubscription<GyroscopeEvent>? gSub;

  final List<double> accelBuffer = [];
  static const int bufferSize = 20;
  bool isStable = false;

  bool updateStability() {
    if (a == null || g == null) return isStable;

    final accelMag = sqrt(a!.x * a!.x + a!.y * a!.y + a!.z * a!.z) - 9.81;

    accelBuffer.add(accelMag);
    if (accelBuffer.length > bufferSize) {
      accelBuffer.removeAt(0);
    }

    if (accelBuffer.length == bufferSize) {
      final mean = accelBuffer.reduce((a, b) => a + b) / bufferSize;
      final variance = accelBuffer
              .map((e) => pow(e - mean, 2))
              .reduce((a, b) => a + b) /
          bufferSize;

      final gyroMag = sqrt(g!.x * g!.x + g!.y * g!.y + g!.z * g!.z);

      isStable = variance < 0.02 && gyroMag < 0.02;
    }
    return isStable;
  }

  void dispose() {
    aSub?.cancel();
    gSub?.cancel();
  }
}
