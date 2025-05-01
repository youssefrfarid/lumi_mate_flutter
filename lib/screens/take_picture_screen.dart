// lib/screens/take_picture_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../services/voice_service.dart';
import '../services/camera_service.dart';
import '../services/scene_description_service.dart';
import '../services/api_service.dart';
import '../services/speech_service.dart';
import 'dart:async';

class TakePictureScreen extends StatefulWidget {
  final CameraDescription camera;
  const TakePictureScreen({super.key, required this.camera});

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  // Services
  late CameraService _cameraService;
  late VoiceService _voiceService;
  late SceneDescriptionService _sceneDescriptionService;
  late SpeechService _speechService;

  // Add private flags to prevent double triggers and unwanted listening
  late bool _isProcessingWakeWord;
  late bool _isProcessingCommand;

  String? _lastFaceImagePath;

  @override
  void initState() {
    super.initState();
    _isProcessingWakeWord = false;
    _isProcessingCommand = false;
    _cameraService = CameraService();
    _cameraService.initialize(widget.camera);
    _voiceService = VoiceService();
    _voiceService.initTtsWebSocket('ws://172.20.10.2:8000/ws');
    _sceneDescriptionService = SceneDescriptionService();
    _sceneDescriptionService.speakSentence =
        (sentence) => _voiceService.speak(sentence);
    _sceneDescriptionService.onQueueEmpty = () async {
      final picture = await _cameraService.takePicture();
      sendSceneDescriptionToAPI(
        picture.path,
        StreamController<String>()
          ..stream.listen((chunk) {
            _sceneDescriptionService.accumulateResponse(chunk);
          }),
      );
    };
    _sceneDescriptionService.takePictureAndSendToApi = () async {
      final picture = await _cameraService.takePicture();
      sendSceneDescriptionToAPI(
        picture.path,
        StreamController<String>()
          ..stream.listen((chunk) {
            _sceneDescriptionService.accumulateResponse(chunk);
          }),
      );
    };
    _speechService = SpeechService();
    _speechService.initialize().then((available) {
      debugPrint('SpeechService: initialize() returned: $available');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _voiceService.speak(
          "You are on the main screen. There are four large buttons from top to bottom: Describe Scene, Who is this, Register Face, and Stop Scene Description. You can tap a button or say 'Hey Lumi' at any time to use voice commands. Listening for 'Hey Lumi' now.",
        );
        _startListening();
      });
    });
  }

  /// Generic listening function for both wake word and command phases.
  void _listenAndProcess({
    required String promptOnNoMatch,
    required String Function(String recognizedText, {required bool isFinal})
    processResult,
    Duration listenFor = const Duration(minutes: 60),
    Duration pauseFor = const Duration(seconds: 3),
  }) {
    _speechService.listenForSpeech(
      onResult: (recognizedText, isFinal) {
        String processed = processResult(recognizedText, isFinal: isFinal);
        if (processed == 'handled') {
          // Do nothing, handled in callback
        } else if (isFinal) {
          debugPrint("No match detected, prompting user to try again.");
          _voiceService.speak(promptOnNoMatch).then((_) {
            _listenAndProcess(
              promptOnNoMatch: promptOnNoMatch,
              processResult: processResult,
              listenFor: listenFor,
              pauseFor: pauseFor,
            );
          });
        }
      },
      onError: (error) {
        debugPrint("SpeechService error: $error");
        _voiceService.speak(promptOnNoMatch).then((_) {
          _listenAndProcess(
            promptOnNoMatch: promptOnNoMatch,
            processResult: processResult,
            listenFor: listenFor,
            pauseFor: pauseFor,
          );
        });
      },
      listenFor: listenFor,
      pauseFor: pauseFor,
      partialResults: true,
    );
  }

  void _startListening() {
    debugPrint("Entering wake-word listening phase.");
    _isProcessingWakeWord = false;
    _isProcessingCommand = false;
    _listenForWakeWord();
  }

  void _onDescribeScene() {
    _pauseListening();
    HapticFeedback.mediumImpact();
    _sceneDescriptionService.startSceneDescription(
      onComplete: () {
        _voiceService.speak("Scene description finished.");
        _startListening(); // Resume listening after action
      },
    );
    _voiceService.speak("Starting scene description.");
  }

  void _onWhoIsThis() async {
    _pauseListening();
    HapticFeedback.mediumImpact();
    final picture = await _cameraService.takePicture();
    _lastFaceImagePath = picture.path;
    final name = await recognizeFace(
      apiUrl: 'http://172.20.10.2:4000/recognize',
      imagePath: picture.path,
    );
    if (name != 'Unknown Person' && name != 'No faces detected') {
      await _voiceService.speak("This is $name.");
    } else if (name == 'No faces detected') {
      await _voiceService.speak("No faces detected in the image.");
    } else {
      await _voiceService.speak(
        "I don't recognize this person. If you know them, tap Register Face or say 'Register Face' to add them.",
      );
    }
    _startListening(); // Resume listening after action
  }

  void _onRegisterFace() async {
    _pauseListening();
    HapticFeedback.mediumImpact();
    final picture = await _cameraService.takePicture();
    _lastFaceImagePath = picture.path;
    await _voiceService.speak("Who is this?");
    _listenAndProcess(
      promptOnNoMatch: "Please say the name to register.",
      processResult: (recognized, {required bool isFinal}) {
        if (isFinal && recognized.trim().isNotEmpty) {
          final name = recognized.trim();
          _speechService.stopListening();
          registerFace(
            apiUrl: 'http://172.20.10.2:4000/register',
            imagePath: _lastFaceImagePath!,
            name: name,
          ).then((success) async {
            if (success) {
              await _voiceService.speak("Face registered.");
            } else {
              await _voiceService.speak("Failed to register face.");
            }
            _startListening();
          });
          return 'handled';
        }
        return '';
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
    );
  }

  void _onStopSceneDescription() {
    _pauseListening();
    HapticFeedback.mediumImpact();
    _sceneDescriptionService.stopSceneDescription();
    _voiceService.speak("Stopping scene description.");
    _startListening();
  }

  void _pauseListening() {
    _speechService.stopListening();
    _isProcessingWakeWord = false;
    _isProcessingCommand = false;
  }

  @override
  void _listenForWakeWord() {
    _listenAndProcess(
      promptOnNoMatch: "I didn't catch that. Please say 'Hey Lumi' to begin.",
      processResult: (recognized, {required bool isFinal}) {
        String rec = recognized.toLowerCase();
        debugPrint("Wake-word listener recognized: $rec (final: $isFinal)");
        if (!_isProcessingWakeWord && rec.contains("hey lumi") && isFinal) {
          _isProcessingWakeWord = true;
          debugPrint("Wake word detected. Transitioning to command phase.");
          _speechService.stopListening();
          _voiceService.speak("Yes, how may I help you?").then((_) {
            _listenForCommand();
          });
          return 'handled';
        }
        return '';
      },
      listenFor: const Duration(minutes: 60),
      pauseFor: const Duration(seconds: 4),
    );
  }

  void _listenForCommand() {
    _listenAndProcess(
      promptOnNoMatch:
          "Please say a command like 'Describe scene' or 'Who is this?'",
      processResult: (command, {required bool isFinal}) {
        command = command.toLowerCase().trim();

        // Face recognition
        if (command == "who is this") {
          _speechService.stopListening();
          _onWhoIsThis();
          return 'handled';
        }

        // Face registration
        if (command.startsWith("yes, this is ")) {
          final name = command.replaceFirst("yes, this is ", "").trim();
          if (_lastFaceImagePath != null && name.isNotEmpty) {
            _speechService.stopListening();
            // You may want to call a registration handler here
            _voiceService.speak(
              "Registering $name is not fully implemented in this button flow.",
            );
          } else {
            _voiceService.speak(
              "No face image available for registration. Please try again.",
            );
          }
          return 'handled';
        }

        // Scene description
        const startCommands = [
          "start scene description",
          "start scene",
          "scene description",
        ];
        const stopCommands = [
          "stop scene description",
          "stop scene",
          "end scene description",
        ];

        if (!_isProcessingCommand && command.isNotEmpty && isFinal) {
          _isProcessingCommand = true;
          if (startCommands.any((c) => command.contains(c))) {
            debugPrint("Starting scene description.");
            _speechService.stopListening();
            _sceneDescriptionService.startSceneDescription(
              onComplete: () {
                _voiceService.speak("Scene description finished.").then((_) {
                  _startListening();
                });
              },
            );
            HapticFeedback.mediumImpact();
            _voiceService.speak("Starting scene description.");
            return 'handled';
          }
          if (stopCommands.any((c) => command.contains(c))) {
            _speechService.stopListening();
            _sceneDescriptionService.stopSceneDescription();
            HapticFeedback.mediumImpact();
            _voiceService.speak("Stopping scene description.").then((_) {
              _startListening();
            });
            return 'handled';
          }
          _speechService.stopListening();
          _voiceService.speak("Sorry, I didn't recognize that command.").then((
            _,
          ) {
            _startListening();
          });
          return 'handled';
        }
        return '';
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lumi Mate', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: Semantics(
              label: 'Describe Scene',
              button: true,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _onDescribeScene,
                child: const Center(
                  child: Text('Describe Scene', textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              label: 'Who is this',
              button: true,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _onWhoIsThis,
                child: const Center(
                  child: Text('Who is this?', textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              label: 'Register Face',
              button: true,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _onRegisterFace,
                child: const Center(
                  child: Text('Register Face', textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              label: 'Stop Scene Description',
              button: true,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _onStopSceneDescription,
                child: const Center(
                  child: Text(
                    'Stop Scene Description',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sceneDescriptionService.dispose();
    _voiceService.dispose();
    _cameraService.dispose();
    _speechService.stopListening();
    super.dispose();
  }
}
