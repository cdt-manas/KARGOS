import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:typed_data';

class QRDetector {
  final _barcodeScanner = BarcodeScanner();

  Uint8List? _nv21Buffer;

  Future<void> processFrame(
    CameraImage frame,
    InputImageRotation rotation,
    Function(String) onDetected,
  ) async {
    try {
      final int w = frame.width;
      final int h = frame.height;
      final int ySize = w * h;
      final int uvSize = (ySize / 2).floor();
      final int totalSize = ySize + uvSize;
      
      if (_nv21Buffer == null || _nv21Buffer!.length != totalSize) {
        _nv21Buffer = Uint8List(totalSize);
        _nv21Buffer!.fillRange(ySize, totalSize, 128); // Neutral chrome
      }
      
      // Copy Y plane row-by-row to STRIP PADDING
      final planeY = frame.planes[0];
      final int stride = planeY.bytesPerRow;
      for (int row = 0; row < h; row++) {
        _nv21Buffer!.setRange(row * w, (row * w) + w, planeY.bytes, row * stride);
      }

      final metadata = InputImageMetadata(
        size: Size(w.toDouble(), h.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: w, // No padding in our buffer
      );
      
      final inputImage = InputImage.fromBytes(bytes: _nv21Buffer!, metadata: metadata);
      final barcodes = await _barcodeScanner.processImage(inputImage);
      for (final barcode in barcodes) {
        if (barcode.rawValue != null) onDetected(barcode.rawValue!);
      }
    } catch (e) {
      print("QR Frame Error: $e");
    }
  }

  void dispose() => _barcodeScanner.close();
}
