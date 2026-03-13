import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';

class QRDetector {
  final _barcodeScanner = BarcodeScanner();

  Future<void> processFrame(CameraImage frame, InputImageRotation rotation, Function(String) onDetected) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in frame.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(frame.width.toDouble(), frame.height.toDouble()),
      rotation: rotation,
      format: InputImageFormatValue.fromRawValue(frame.format.raw) ?? InputImageFormat.yuv420,
      bytesPerRow: frame.planes[0].bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);

    final List<Barcode> barcodes = await _barcodeScanner.processImage(inputImage);

    for (Barcode barcode in barcodes) {
      if (barcode.rawValue != null) {
        onDetected(barcode.rawValue!);
      }
    }
  }

  void dispose() {
    _barcodeScanner.close();
  }
}
