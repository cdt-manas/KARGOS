import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

class YoloDetector {
  Interpreter? _interpreter;
  List<String>? _labels;
  List<int>? _inputShape;
  List<int>? _outputShape;

  Future<void> loadModel() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset('assets/yolov8n.tflite', options: options);
      String labelsData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelsData.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      // Log actual model shapes for debugging
      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;
      print("YOLOv8 Model Loaded Successfully");
      print("  Input shape: $_inputShape");
      print("  Output shape: $_outputShape");
      print("  Labels count: ${_labels!.length}");
    } catch (e) {
      print("Failed to load model: $e");
    }
  }

  /// Processes a CameraImage and returns a list of detected obstacle labels
  Future<List<String>> detectObstacles(CameraImage frame) async {
    if (_interpreter == null || _labels == null || _inputShape == null) return [];

    try {
      // Get expected input dimensions from model
      final int inputH = _inputShape![1];
      final int inputW = _inputShape![2];

      // 1. Convert camera frame to RGB image at model's expected size
      final resizedImage = _convertCameraImage(frame, inputW, inputH);

      // 2. Prepare Input Tensor [1, H, W, 3]
      var input = _imageToByteListFloat32(resizedImage, inputW, inputH);

      // 3. Prepare Output Tensor based on actual model shape
      final outputSize = _outputShape!.reduce((a, b) => a * b);
      var outputFlat = List.filled(outputSize, 0.0);
      var output = outputFlat.reshape(_outputShape!);

      // 4. Run Inference
      _interpreter!.run(input, output);

      // 5. Post-process
      return _parseOutput(output[0], _outputShape!);
    } catch (e) {
      print("Inference error: $e");
      return [];
    }
  }

  img.Image _convertCameraImage(CameraImage image, int targetW, int targetH) {
    if (image.format.group == ImageFormatGroup.yuv420) {
      return _convertYUV420ToImage(image, targetW, targetH);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRAToImage(image, targetW, targetH);
    } else {
      return img.Image(width: targetW, height: targetH);
    }
  }

  img.Image _convertBGRAToImage(CameraImage image, int targetW, int targetH) {
    final int width = image.width;
    final int height = image.height;
    final img.Image buffer = img.Image(width: targetW, height: targetH);

    final double skipX = width / targetW;
    final double skipY = height / targetH;

    final plane = image.planes[0];
    final int bytesPerRow = plane.bytesPerRow;
    final Uint8List bytes = plane.bytes;

    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        final int srcX = (x * skipX).toInt();
        final int srcY = (y * skipY).toInt();
        final int index = (srcY * bytesPerRow) + (srcX * 4);

        if (index + 2 >= bytes.length) continue;

        buffer.setPixelRgb(x, y, bytes[index + 2], bytes[index + 1], bytes[index]);
      }
    }
    return buffer;
  }

  img.Image _convertYUV420ToImage(CameraImage image, int targetW, int targetH) {
    final img.Image buffer = img.Image(width: targetW, height: targetH);

    final int width = image.width;
    final int height = image.height;

    final planeY = image.planes[0];
    final planeU = image.planes[1];
    final planeV = image.planes[2];

    final int yRowStride = planeY.bytesPerRow;
    final int uvRowStride = planeU.bytesPerRow;
    final int uvPixelStride = planeU.bytesPerPixel ?? 1;

    final double skipX = width / targetW;
    final double skipY = height / targetH;

    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        final int srcX = (x * skipX).toInt();
        final int srcY = (y * skipY).toInt();

        final int yIndex = srcY * yRowStride + srcX;

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

  Float32List _imageToByteListFloat32(img.Image image, int width, int height) {
    var convertedBytes = Float32List(1 * height * width * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;
    for (int i = 0; i < height; i++) {
        for (int j = 0; j < width; j++) {
            var pixel = image.getPixel(j, i);
            buffer[pixelIndex++] = pixel.r / 255.0;
            buffer[pixelIndex++] = pixel.g / 255.0;
            buffer[pixelIndex++] = pixel.b / 255.0;
        }
    }
    return convertedBytes;
  }

  List<String> _parseOutput(List<dynamic> output, List<int> shape) {
    Set<String> detected = {};
    const double confidenceThreshold = 0.45;

    // YOLOv8 output is [84, 8400] or [numClasses+4, numBoxes]
    // Rows 0-3: box coords, rows 4+: class probabilities
    final int numRows = shape[1]; // 84
    final int numBoxes = shape[2]; // 8400
    final int numClasses = numRows - 4;

    for (int i = 0; i < numBoxes; i++) {
      double maxProb = 0;
      int classId = -1;

      for (int c = 4; c < numRows; c++) {
        double val = (output[c][i] as num).toDouble();
        if (val > maxProb) {
          maxProb = val;
          classId = c - 4;
        }
      }

      if (maxProb > confidenceThreshold && classId >= 0 && classId < _labels!.length) {
        String label = _labels![classId];
        if (["person", "chair", "table", "couch", "bed", "toilet", "door", "bench"].contains(label)) {
          detected.add(label);
        }
      }
    }
    return detected.toList();
  }
}
