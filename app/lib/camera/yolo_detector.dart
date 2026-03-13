import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';

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

  Future<List<String>> detectObstacles(CameraImage frame) async {
    if (_interpreter == null || _labels == null || _inputShape == null) return [];
    try {
      final int H = _inputShape![1];
      final int W = _inputShape![2];

      // Build flat Float32 input [1, H, W, 3]
      final Float32List input = _yuvToFloat32(frame, W, H);

      // Reshape to [1, H, W, 3] using List structure for tflite_flutter 0.10.x
      final inputReshaped = input.reshape(_inputShape!);

      // Output tensor
      final int outSize = _outputShape!.reduce((a, b) => a * b);
      final outputFlat = List.filled(outSize, 0.0);
      final output = outputFlat.reshape(_outputShape!);

      _interpreter!.run(inputReshaped, output);

      // _outputShape = [1, 84, 2100]
      return _parseOutput(output[0], _outputShape![1], _outputShape![2]);
    } catch (e) {
      print("YOLO inference: $e");
      return [];
    }
  }

  Float32List _yuvToFloat32(CameraImage image, int W, int H) {
    final Float32List out = Float32List(H * W * 3);
    int idx = 0;

    final planeY = image.planes[0];
    final planeU = image.planes[1];
    final planeV = image.planes[2];

    final int yStride = planeY.bytesPerRow;
    final int uvStride = planeU.bytesPerRow;
    final int uvPixStride = planeU.bytesPerPixel ?? 1;

    final double sx = image.width / W;
    final double sy = image.height / H;

    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        final int srcX = (x * sx).toInt();
        final int srcY = (y * sy).toInt();

        final int yI = srcY * yStride + srcX;
        final int uvI = (srcY ~/ 2) * uvStride + (srcX ~/ 2) * uvPixStride;

        if (yI >= planeY.bytes.length || uvI >= planeU.bytes.length) {
          idx += 3;
          continue;
        }

        final int yp = planeY.bytes[yI];
        final int up = planeU.bytes[uvI];
        final int vp = planeV.bytes[uvI];

        out[idx++] = ((yp + 1.402 * (vp - 128)).clamp(0, 255)) / 255.0;
        out[idx++] = ((yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).clamp(0, 255)) / 255.0;
        out[idx++] = ((yp + 1.772 * (up - 128)).clamp(0, 255)) / 255.0;
      }
    }
    return out;
  }

  List<String> _parseOutput(dynamic output, int numRows, int numBoxes) {
    final Set<String> detected = {};
    const double threshold = 0.45;
    const List<String> targets = ['person', 'chair', 'table', 'couch', 'bed', 'toilet', 'bench'];

    for (int i = 0; i < numBoxes; i++) {
      double maxProb = 0;
      int classId = -1;
      for (int c = 4; c < numRows; c++) {
        final double val = (output[c][i] as num).toDouble();
        if (val > maxProb) { maxProb = val; classId = c - 4; }
      }
      if (maxProb > threshold && classId >= 0 && classId < _labels!.length) {
        final label = _labels![classId];
        if (targets.contains(label)) detected.add(label);
      }
    }
    return detected.toList();
  }
}
