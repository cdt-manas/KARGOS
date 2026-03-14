import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class YoloDetector {
  Interpreter? _interpreter;
  List<String>? _labels;
  List<int>? _inputShape;
  List<int>? _outputShape;

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(
        'assets/yolov8n.tflite',
        options: options,
      );
      final labelsData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelsData
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;
      print("YOLOv8 loaded. Input: $_inputShape  Output: $_outputShape");
    } catch (e) {
      print("YOLO load failed: $e");
    }
  }

  Future<List<String>> detectObstacles(CameraImage frame, InputImageRotation rotation) async {
    if (_interpreter == null || _labels == null || _inputShape == null) return [];
    try {
      final int H = _inputShape![1];
      final int W = _inputShape![2];

      final input = _prepareInput(frame, W, H, rotation);

      // YOLOv8 output: [1, 84, 2100]
      // We need a 3D list: [ [ [2100 values], [2100 values], ... 84 times ] ]
      final List<List<List<double>>> output = List.generate(
        1,
        (i) => List.generate(
          _outputShape![1], // 84 (4 coords + 80 labels)
          (j) => List<double>.filled(_outputShape![2], 0.0), // 2100 boxes
        ),
      );

      _interpreter!.run(input, output);

      return _parseOutput(output[0], _outputShape![1], _outputShape![2]);
    } catch (e) {
      print("YOLO Inference Error: $e");
      return [];
    }
  }

  /// Converts YUV CameraImage to List<List<List<List<double>>>> [1, H, W, 3] with Rotation & Letterboxing
  List<List<List<List<double>>>> _prepareInput(CameraImage image, int targetW, int targetH, InputImageRotation rotation) {
    final List<List<List<double>>> imgData = List.generate(targetH, (y) => List.generate(targetW, (x) => List.filled(3, 128 / 255.0))); // Fill with gray padding

    final planeY = image.planes[0];
    final planeU = image.planes[1];
    final planeV = image.planes[2];

    final int srcW = image.width;
    final int srcH = image.height;
    final int yStride = planeY.bytesPerRow;
    final int uvStride = planeU.bytesPerRow;
    final int uvPixStride = planeU.bytesPerPixel ?? 1;

    // Determine scale and padding for letterboxing
    double scale;
    int padX = 0;
    int padY = 0;
    
    // After rotation, effective src dimensions flip if 90/270
    bool isRotated = (rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg);
    int effectiveW = isRotated ? srcH : srcW;
    int effectiveH = isRotated ? srcW : srcH;

    if (effectiveW > effectiveH) {
      scale = targetW / effectiveW;
      padY = ((targetH - (effectiveH * scale)) / 2).toInt();
    } else {
      scale = targetH / effectiveH;
      padX = ((targetW - (effectiveW * scale)) / 2).toInt();
    }

    for (int y = 0; y < (effectiveH * scale).toInt() && (y + padY) < targetH; y++) {
      for (int x = 0; x < (effectiveW * scale).toInt() && (x + padX) < targetW; x++) {
        // Map target pixel back to rotated source pixel
        int rotX = (x / scale).toInt();
        int rotY = (y / scale).toInt();

        // Map rotated source pixel back to raw buffer pixel
        int srcX, srcY;
        if (rotation == InputImageRotation.rotation90deg) {
          srcX = srcW - 1 - rotY;
          srcY = rotX;
        } else if (rotation == InputImageRotation.rotation180deg) {
          srcX = srcW - 1 - rotX;
          srcY = srcH - 1 - rotY;
        } else if (rotation == InputImageRotation.rotation270deg) {
          srcX = rotY;
          srcY = srcH - 1 - rotX;
        } else {
          srcX = rotX;
          srcY = rotY;
        }

        final int yI = srcY * yStride + srcX;
        final int uvI = (srcY ~/ 2) * uvStride + (srcX ~/ 2) * uvPixStride;

        if (yI >= planeY.bytes.length || uvI >= planeU.bytes.length) continue;

        final int yp = planeY.bytes[yI];
        final int up = planeU.bytes[uvI];
        final int vp = planeV.bytes[uvI];

        // RGB Conversion Optimized
        imgData[y + padY][x + padX][0] = ((yp + 1.402 * (vp - 128)).clamp(0, 255)) / 255.0;
        imgData[y + padY][x + padX][1] = ((yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).clamp(0, 255)) / 255.0;
        imgData[y + padY][x + padX][2] = ((yp + 1.772 * (up - 128)).clamp(0, 255)) / 255.0;
      }
    }
    return [imgData];
  }

  List<String> _parseOutput(List<dynamic> output, int numRows, int numBoxes) {
    final Set<String> detected = {};
    const double threshold = 0.60;

    for (int i = 0; i < numBoxes; i++) {
       double maxProb = 0;
       int classId = -1;
       for (int c = 4; c < numRows; c++) {
         final double val = (output[c][i] as num).toDouble();
         if (val > maxProb) {
           maxProb = val;
           classId = c - 4;
         }
       }
       if (maxProb > threshold && classId >= 0 && classId < _labels!.length) {
         final label = _labels![classId];
         detected.add(label);
       }
    }
    return detected.toList();
  }
}
