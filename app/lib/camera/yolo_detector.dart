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
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRAToImage(image);
    } else {
      // Fallback for other formats
      return img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: image.planes[0].bytes.buffer,
        format: img.Format.uint8,
      );
    }
  }

  img.Image _convertBGRAToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    const int targetSize = 640;
    final img.Image buffer = img.Image(width: targetSize, height: targetSize);

    final double skipX = width / targetSize;
    final double skipY = height / targetSize;

    final plane = image.planes[0];
    final int bytesPerRow = plane.bytesPerRow;
    final Uint8List bytes = plane.bytes;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final int srcX = (x * skipX).toInt();
        final int srcY = (y * skipY).toInt();

        // BGRA: 4 bytes per pixel, but respect bytesPerRow
        final int index = (srcY * bytesPerRow) + (srcX * 4);

        if (index + 2 >= bytes.length) continue;

        final int b = bytes[index];
        final int g = bytes[index + 1];
        final int r = bytes[index + 2];

        buffer.setPixelRgb(x, y, r, g, b);
      }
    }
    return buffer;
  }

  img.Image _convertYUV420ToImage(CameraImage image) {
    const int targetSize = 640;
    final img.Image buffer = img.Image(width: targetSize, height: targetSize);

    final int width = image.width;
    final int height = image.height;

    final planeY = image.planes[0];
    final planeU = image.planes[1];
    final planeV = image.planes[2];

    final int yRowStride = planeY.bytesPerRow;
    final int uvRowStride = planeU.bytesPerRow;
    final int uvPixelStride = planeU.bytesPerPixel!;

    final double skipX = width / targetSize;
    final double skipY = height / targetSize;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final int srcX = (x * skipX).toInt();
        final int srcY = (y * skipY).toInt();

        // Handle Y plane with row stride
        final int yIndex = srcY * yRowStride + srcX;
        
        // Handle UV planes with row stride and pixel stride (chroma subsampling 2x2)
        final int uvX = srcX ~/ 2;
        final int uvY = srcY ~/ 2;
        final int uvIndex = (uvY * uvRowStride) + (uvX * uvPixelStride);

        if (yIndex >= planeY.bytes.length || uvIndex >= planeU.bytes.length) continue;

        final int yp = planeY.bytes[yIndex];
        final int up = planeU.bytes[uvIndex];
        final int vp = planeV.bytes[uvIndex];

        int r = (yp + 1.402 * (vp - 128)).toInt();
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).toInt();
        int b = (yp + 1.772 * (up - 128)).toInt();

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
