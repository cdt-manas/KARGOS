import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';

class QRDetector {
  final _barcodeScanner = BarcodeScanner();

  Future<void> processFrame(CameraImage frame, InputImageRotation rotation, Function(String) onDetected) async {
    try {
      final bytes = _packYUV420Planes(frame);
      
      final InputImageMetadata metadata = InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.yuv420, // Packed YUV
        bytesPerRow: frame.width, // We've removed the padding
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final List<Barcode> barcodes = await _barcodeScanner.processImage(inputImage);
      
      for (Barcode barcode in barcodes) {
        if (barcode.rawValue != null) {
          onDetected(barcode.rawValue!);
        }
      }
    } catch (e) {
      print("QR Error: $e");
    }
  }

  Uint8List _packYUV420Planes(CameraImage image) {
    final width = image.width;
    final int height = image.height;
    final int bufferSize = width * height + 2 * (width ~/ 2) * (height ~/ 2);
    final Uint8List buffer = Uint8List(bufferSize);
    int offset = 0;

    // Pack Y plane
    final planeY = image.planes[0];
    final int yBytesPerRow = planeY.bytesPerRow;
    if (yBytesPerRow == width) {
      buffer.setRange(0, width * height, planeY.bytes);
      offset = width * height;
    } else {
      for (int y = 0; y < height; y++) {
        buffer.setRange(offset, offset + width, planeY.bytes.sublist(y * yBytesPerRow, y * yBytesPerRow + width));
        offset += width;
      }
    }

    // Pack U and V planes (chroma subsampled 2x2)
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    for (int planeIndex = 1; planeIndex <= 2; planeIndex++) {
      final plane = image.planes[planeIndex];
      final int bytesPerRow = plane.bytesPerRow;
      final int pixelStride = plane.bytesPerPixel ?? 1;

      for (int y = 0; y < uvHeight; y++) {
        for (int x = 0; x < uvWidth; x++) {
          buffer[offset++] = plane.bytes[y * bytesPerRow + x * pixelStride];
        }
      }
    }
    return buffer;
  }

  void dispose() {
    _barcodeScanner.close();
  }
}
