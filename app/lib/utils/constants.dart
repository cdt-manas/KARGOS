class AppConstants {
  static const String appName = 'Indoor Navigation';
  static const int throttleFrames = 3; // YOLO detection every 3 frames
  static const String ttsLanguage = 'en-US';
}

class YoloConfig {
  static const String modelPath = 'assets/yolov8n.tflite';
  static const String labelsPath = 'assets/labels.txt';
  static const double minimumConfidence = 0.5;
}
