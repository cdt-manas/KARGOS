import 'package:camera/camera.dart';

import 'qr_detector.dart';
import 'yolo_detector.dart';

class FrameProcessorPipeline {
  final QRDetector qrDetector;
  final YoloDetector yoloDetector;
  
  int _frameCount = 0;
  final int processEveryNFrames = 3;

  FrameProcessorPipeline({
    required this.qrDetector,
    required this.yoloDetector,
  });

  void processNewFrame(CameraImage frame, Function(List<String> obstacles) onObstacleDetected, Function(String qrResult) onQrDetected) {
    _frameCount++;
    
    // Throttle frame processing to optimize mobile performance
    if (_frameCount % processEveryNFrames == 0) {
       // Run YOLO
       List<String> obstacles = yoloDetector.detectObstacles(frame);
       if (obstacles.isNotEmpty) {
         onObstacleDetected(obstacles);
       }
       
       // Run QR (if manual parsing was active)
       qrDetector.processFrame(frame, (qr) {
         onQrDetected(qr);
       });
    }
  }
}
