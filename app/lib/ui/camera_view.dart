import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraView extends StatelessWidget {
  final MobileScannerController controller;
  final Function(BarcodeCapture) onDetect;

  const CameraView({
    Key? key,
    required this.controller,
    required this.onDetect,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: controller,
      onDetect: onDetect,
      errorBuilder: (context, error, child) {
         return Center(
           child: Text("Camera error: ${error.errorCode}"),
         );
      },
      fit: BoxFit.cover,
    );
  }
}
