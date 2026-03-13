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
    
    // QR every 5 frames
    if (_frameCount % 5 == 0) {
       await qrDetector.processFrame(frame, rotation, (qr) {
         onQrDetected(qr);
       });
    }

    // YOLO every 15 frames (heavy lifting)
    if (_frameCount % 15 == 0) {
       List<String> obstacles = await yoloDetector.detectObstacles(frame);
       if (obstacles.isNotEmpty) {
         onObstacleDetected(obstacles);
       }
    }
  }
}
