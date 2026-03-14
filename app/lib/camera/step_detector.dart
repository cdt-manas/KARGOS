import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class StepDetector {
  final Function() onStep;
  StreamSubscription<UserAccelerometerEvent>? _subscription;

  // Simple peak detection parameters
  static const double _stepThreshold = 1.8; // Magnitude threshold for a step
  static const int _stepCooldownMs = 350; // Minimum time between steps

  int _lastStepTime = 0;
  bool _isAboveThreshold = false;

  StepDetector({required this.onStep});

  void start() {
    _subscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      _processEvent(event);
    });
  }

  void _processEvent(UserAccelerometerEvent event) {
    // Calculate magnitude of user acceleration
    final double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    
    final int currentTime = DateTime.now().millisecondsSinceEpoch;

    // Basic peak detection logic
    if (magnitude > _stepThreshold && !_isAboveThreshold) {
      if (currentTime - _lastStepTime > _stepCooldownMs) {
        onStep();
        _lastStepTime = currentTime;
        _isAboveThreshold = true;
      }
    } else if (magnitude < _stepThreshold - 0.4) {
      // Add some hysteresis to avoid multiple triggers for the same peak
      _isAboveThreshold = false;
    }

  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
