import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraView extends StatelessWidget {
  final CameraController? controller;

  const CameraView({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Container(color: Colors.black, child: const Center(child: CircularProgressIndicator()));
    }
    return CameraPreview(controller!);
  }
}
