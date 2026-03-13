import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:typed_data';

class QRDetector {
  final _barcodeScanner = BarcodeScanner();

  Future<void> processFrame(
    CameraImage frame,
    InputImageRotation rotation,
    Function(String) onDetected,
  ) async {
    try {
      final bytes = _buildNV21(frame);
      final metadata = InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: frame.width,
      );
      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);
      final barcodes = await _barcodeScanner.processImage(inputImage);
      for (final barcode in barcodes) {
        if (barcode.rawValue != null) onDetected(barcode.rawValue!);
      }
    } catch (_) {
      // Silently skip bad frames
    }
  }

  /// Convert YUV_420_888 CameraImage to NV21 byte array.
  /// NV21 = Y plane followed by interleaved V,U bytes (chroma in VU order).
  Uint8List _buildNV21(CameraImage image) {
    final int w = image.width;
    final int h = image.height;
    final int uvW = w ~/ 2;
    final int uvH = h ~/ 2;
    final Uint8List nv21 = Uint8List(w * h + uvW * uvH * 2);

    final planeY = image.planes[0];
    final planeU = image.planes[1]; // Cb
    final planeV = image.planes[2]; // Cr

    final int yStride = planeY.bytesPerRow;
    final int uStride = planeU.bytesPerRow;
    final int vStride = planeV.bytesPerRow;
    final int uPixelStride = planeU.bytesPerPixel ?? 1;
    final int vPixelStride = planeV.bytesPerPixel ?? 1;

    // Copy Y plane row by row, stripping padding
    int offset = 0;
    for (int row = 0; row < h; row++) {
      nv21.setRange(offset, offset + w, planeY.bytes, row * yStride);
      offset += w;
    }

    // Interleave V, U (NV21 = VU order)
    for (int row = 0; row < uvH; row++) {
      for (int col = 0; col < uvW; col++) {
        nv21[offset++] = planeV.bytes[row * vStride + col * vPixelStride];
        nv21[offset++] = planeU.bytes[row * uStride + col * uPixelStride];
      }
    }

    return nv21;
  }

  void dispose() => _barcodeScanner.close();
}
