import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'screens/take_picture_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize cameras before running the app
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumi Mate Flutter',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: TakePictureScreen(camera: cameras.first),
    );
  }
}
