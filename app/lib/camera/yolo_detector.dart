import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

class YoloDetector {
  Interpreter? _interpreter;
  List<String>? _labels;

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset('assets/yolov8n.tflite', options: options);
      String labelsData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelsData.split('\n').map((s) => s.trim()).toList();
      print("YOLOv8 Model Loaded Successfully");
    } catch (e) {
      print("Failed to load model: $e");
    }
  }

  /// Processes a CameraImage and returns a list of detected obstacle labels
  Future<List<String>> detectObstacles(CameraImage frame) async {
    if (_interpreter == null || _labels == null) return [];

    try {
      // 1. Convert YUV420 to RGB directly into a 640x640 buffer
      final resizedImage = _convertCameraImage(frame);

      // 2. Prepare Input Tensor [1, 640, 640, 3]
      var input = _imageToByteListFloat32(resizedImage, 640);

      // 3. Prepare Output Tensor [1, 84, 8400]
      // YOLOv8n output: 84 rows (4 box coords + 80 classes), 8400 candidate boxes
      var output = List.filled(1 * 84 * 8400, 0.0).reshape([1, 84, 8400]);

      // 4. Run Inference
      _interpreter!.run(input, output);

      // 5. Post-process (filtering by confidence and interesting classes)
      return _parseOutput(output[0]);
    } catch (e) {
      print("Inference error: $e");
      return [];
    }
  }

  img.Image _convertCameraImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.yuv420) {
      return _convertYUV420ToImage(image);
    } else {
      // BGRA or other formats for iOS
      return img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: image.planes[0].bytes.buffer,
        format: img.Format.uint8,
      );
    }
  }

  img.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    
    // Target 640x640 directly to avoid full conversion followed by resize
    const int targetSize = 640;
    final img.Image buffer = img.Image(width: targetSize, height: targetSize);

    final double skipX = width / targetSize;
    final double skipY = height / targetSize;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final int srcX = (x * skipX).toInt();
        final int srcY = (y * skipY).toInt();

        final int uvIndex = (srcY ~/ 2) * (width ~/ 2) + (srcX ~/ 2);
        final int index = srcY * width + srcX;

        // Safety checks for buffer bounds
        if (index >= image.planes[0].bytes.length || uvIndex >= image.planes[1].bytes.length) continue;

        final int yp = image.planes[0].bytes[index];
        final int up = image.planes[1].bytes[uvIndex];
        final int vp = image.planes[2].bytes[uvIndex];

        int r = (yp + 1.402 * (vp - 128)).toInt();
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).toInt();
        int b = (yp + 1.772 * (up - 128)).toInt();

        // Direct write to resized buffer
        buffer.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
      }
    }
    return buffer;
  }

  Float32List _imageToByteListFloat32(img.Image image, int size) {
    var convertedBytes = Float32List(1 * size * size * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;
    for (int i = 0; i < size; i++) {
        for (int j = 0; j < size; j++) {
            var pixel = image.getPixel(j, i);
            buffer[pixelIndex++] = pixel.r / 255.0;
            buffer[pixelIndex++] = pixel.g / 255.0;
            buffer[pixelIndex++] = pixel.b / 255.0;
        }
    }
    return convertedBytes;
  }

  List<String> _parseOutput(List<List<double>> output) {
    Set<String> detected = {};
    const double confidenceThreshold = 0.45;

    // Output shape is [84, 8400]
    // 0,1,2,3 are box coords
    // 4..83 are class probabilities
    for (int i = 0; i < 8400; i++) {
      double maxProb = 0;
      int classId = -1;

      for (int c = 4; c < 84; c++) {
        if (output[c][i] > maxProb) {
          maxProb = output[c][i];
          classId = c - 4;
        }
      }

      if (maxProb > confidenceThreshold) {
        String label = _labels![classId];
        // Filter for specific obstacles relevant to indoor navigation
        if (["person", "chair", "table", "couch", "bed", "toilet"].contains(label)) {
          detected.add(label);
        }
      }
    }
    return detected.toList();
  }
}
