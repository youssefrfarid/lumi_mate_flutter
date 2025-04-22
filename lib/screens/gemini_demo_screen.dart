import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';

class GeminiDemoScreen extends StatefulWidget {
  const GeminiDemoScreen({Key? key}) : super(key: key);

  @override
  State<GeminiDemoScreen> createState() => _GeminiDemoScreenState();
}

class _GeminiDemoScreenState extends State<GeminiDemoScreen> {
  String? _description;
  bool _loading = false;
  File? _imageFile;
  late CameraService _cameraService;
  late Future<void> _initializeCameraFuture;
  CameraDescription? _camera;
  final VoiceService _voiceService = VoiceService();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    setState(() {
      _camera = cameras.first;
      _cameraService = CameraService();
      _cameraService.initialize(_camera!);
      _initializeCameraFuture = _cameraService.initializeFuture;
    });
  }

  Future<void> _takePhotoAndDescribe() async {
    setState(() {
      _loading = true;
      _description = null;
      _imageFile = null;
    });
    try {
      await _initializeCameraFuture;
      final picture = await _cameraService.takePicture();
      setState(() {
        _imageFile = File(picture.path);
      });
      final description = await getGeminiSceneDescriptionViaBackend(
        backendUrl: 'http://192.168.1.124:8080/gemini',
        imagePath: picture.path,
      );
      setState(() {
        _description = description;
      });
      await _voiceService.speak(description);
    } catch (e) {
      setState(() {
        _description = 'Error: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _voiceService.dispose();
    if (_cameraService != null) {
      _cameraService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Scene Description Demo')),
      body: FutureBuilder<void>(
        future: _initializeCameraFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && _cameraService.controller.value.isInitialized) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: _imageFile == null
                        ? CameraPreview(_cameraService.controller)
                        : Image.file(_imageFile!, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: Text(_loading ? 'Processing...' : 'Take Photo and Describe'),
                    onPressed: _loading ? null : _takePhotoAndDescribe,
                  ),
                  const SizedBox(height: 24),
                  if (_loading) const CircularProgressIndicator(),
                  if (_description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(
                        _description!,
                        style: const TextStyle(fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
