import 'package:camera/camera.dart';
import 'dart:async';

class CameraService {
  late CameraController controller;
  late Future<void> initializeControllerFuture;

  void initialize(CameraDescription camera) {
    controller = CameraController(camera, ResolutionPreset.max);
    initializeControllerFuture = controller.initialize();
  }

  Future<void> get initializeFuture => initializeControllerFuture;

  Future<XFile> takePicture() async {
    await initializeControllerFuture;
    return await controller.takePicture();
  }

  void dispose() {
    controller.dispose();
  }
}
