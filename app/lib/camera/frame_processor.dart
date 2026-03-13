import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

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

  Future<void> processNewFrame(CameraImage frame, InputImageRotation rotation, Function(List<String> obstacles) onObstacleDetected, Function(String qrResult) onQrDetected) async {
    _frameCount++;
    
    // Throttle frame processing to optimize mobile performance
    if (_frameCount % processEveryNFrames == 0) {
       // Run YOLO
       List<String> obstacles = await yoloDetector.detectObstacles(frame);
       if (obstacles.isNotEmpty) {
         onObstacleDetected(obstacles);
       }
       
       // Run QR
       await qrDetector.processFrame(frame, rotation, (qr) {
         onQrDetected(qr);
       });
    }
  }
}
