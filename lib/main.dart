import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'screens/take_picture_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MaterialApp(home: TakePictureScreen(camera: firstCamera)));
}
