import 'package:camera/camera.dart';

class CameraFrameStream {
  CameraController? controller;
  bool isStreaming = false;

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    controller = CameraController(
      cameras.first, // Usually back camera
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller!.initialize();
  }

  void startStream(Function(CameraImage) onFrame) {
    if (controller != null && !isStreaming) {
      isStreaming = true;
      controller!.startImageStream((CameraImage image) {
        onFrame(image);
      });
    }
  }

  void stopStream() {
    if (controller != null && isStreaming) {
      isStreaming = false;
      controller!.stopImageStream();
    }
  }
}
