// lib/screens/take_picture_screen.dart
import 'package:flutter/material.dart';
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
    _voiceService.initTtsWebSocket('ws://192.168.1.124:8080/ws');
    _sceneDescriptionService = SceneDescriptionService();
    _sceneDescriptionService.speakSentence = (sentence) => _voiceService.speak(sentence);
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
    // Initialize speech recognition before TTS prompt
    _speechService.initialize().then((available) {
      debugPrint('SpeechService: initialize() returned: $available');
      // Prompt user on startup after initialization
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _voiceService.speak("Say 'Hey Lumi' to get started.").then((_) {
          _startListening();
        });
      });
    });
  }

  /// Generic listening function for both wake word and command phases.
  void _listenAndProcess({
    required String promptOnNoMatch,
    required String Function(String recognizedText, {required bool isFinal}) processResult,
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

  void _listenForStopDuringSceneDescription(VoidCallback onStop) {
    debugPrint("Listening for stop command during scene description...");
    _speechService.listenForSpeech(
      onResult: (recognizedText, isFinal) {
        String command = recognizedText.toLowerCase().trim();
        debugPrint("Scene description stop listener recognized: $command (final: $isFinal)");
        if (isFinal && (command.contains("stop") || command.contains("end scene description") || command.contains("stop scene"))) {
          debugPrint("Stop command detected during scene description.");
          _speechService.stopListening();
          onStop();
        }
      },
      onError: (error) {
        debugPrint("Scene description stop listener error: $error");
      },
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(milliseconds: 500),
      partialResults: true,
    );
  }

  void _listenForCommand() {
    _listenAndProcess(
      promptOnNoMatch: "Please say a command like 'Describe scene' or 'Who is this?'",
      processResult: (command, {required bool isFinal}) {
        command = command.toLowerCase().trim();

        // Face recognition
        if (command == "who is this") {
          _speechService.stopListening();
          _handleFaceRecognition();
          return 'handled';
        }

        // Face registration
        if (command.startsWith("yes, this is ")) {
          final name = command.replaceFirst("yes, this is ", "").trim();
          if (_lastFaceImagePath != null && name.isNotEmpty) {
            _speechService.stopListening();
            _handleFaceRegistration(name);
          } else {
            _voiceService.speak("No face image available for registration. Please try again.");
          }
          return 'handled';
        }

        // ...existing commands...

        const startCommands = [
          "start scene description",
          "start scene",
          "scene description"
        ];
        const stopCommands = [
          "stop scene description",
          "stop scene",
          "end scene description"
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
            _voiceService.speak("Starting scene description.").then((_) {
              // Removed AirPod/media button stop functionality
            });
            // Optionally, keep _listenForStopDuringSceneDescription for voice stop
            _listenForStopDuringSceneDescription(() {
              _sceneDescriptionService.stopSceneDescription();
              _voiceService.speak("Stopping scene description.").then((_) {
                _startListening();
              });
            });
            return 'handled';
          }
          if (stopCommands.any((c) => command.contains(c))) {
            _speechService.stopListening();
            _sceneDescriptionService.stopSceneDescription();
            _voiceService.speak("Stopping scene description.").then((_) {
              _startListening();
            });
            return 'handled';
          }
          _speechService.stopListening();
          _voiceService.speak("Sorry, I didn't recognize that command.").then((_) {
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

  Future<void> _handleFaceRecognition() async {
    final picture = await _cameraService.takePicture();
    _lastFaceImagePath = picture.path;

    final name = await recognizeFace(
      apiUrl: 'http://192.168.1.124:4000/recognize',
      imagePath: picture.path,
    );

    if (name != 'Unknown Person' && name != 'No faces detected') {
      await _voiceService.speak("This is $name.");
    } else if (name == 'No faces detected') {
      await _voiceService.speak("No faces detected in the image.");
    } else {
      await _voiceService.speak(
        "I don't recognize this person. If you know them, say 'Yes, this is' followed by their name to register."
      );
      // The app will continue listening for the registration command
    }
  }

  Future<void> _handleFaceRegistration(String name) async {
    if (_lastFaceImagePath == null) {
      await _voiceService.speak("No image available to register. Please try again.");
      return;
    }
    final success = await registerFace(
      apiUrl: 'http://192.168.1.124:4000/register',
      imagePath: _lastFaceImagePath!,
      name: name,
    );
    if (success) {
      await _voiceService.speak("Face registered as $name.");
    } else {
      await _voiceService.speak("Failed to register face.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lumi Mate'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: _cameraService.initializeFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return CameraPreview(_cameraService.controller);
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
          // Scene description status indicator
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _sceneDescriptionService.isActive ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    _sceneDescriptionService.isActive
                        ? Icons.record_voice_over
                        : Icons.mic_off,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _sceneDescriptionService.isActive ? 'Active' : 'Inactive',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          // Response stream listener
          StreamBuilder<String>(
            stream: _sceneDescriptionService.responseStream,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha((0.7 * 255).toInt()),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: StreamBuilder<String>(
                      stream: _sceneDescriptionService.responseStream,
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data ?? '',
                          style: const TextStyle(color: Colors.white),
                        );
                      },
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
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
