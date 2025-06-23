// lib/screens/take_picture_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/voice_service.dart';
import '../services/camera_service.dart';
import '../services/scene_description_service.dart';
import '../services/api_service.dart';
import '../services/speech_service.dart';
import '../services/product_summary_service.dart';
import '../services/minicpm_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  late ProductSummaryService _productSummaryService;
  late MiniCPMService _miniCPMService;

  // Add private flags to prevent double triggers and unwanted listening
  late bool _isProcessingWakeWord;
  late bool _isProcessingCommand;
  bool _isMiniCPMActive = false;
  String _minicpmServerUrl = '';

  String? _lastFaceImagePath;

  @override
  void initState() {
    super.initState();
    _isProcessingWakeWord = false;
    _isProcessingCommand = false;
    _miniCPMService = MiniCPMService();
    _cameraService = CameraService();
    _cameraService.initialize(widget.camera);
    _voiceService = VoiceService();
    _voiceService.initTtsWebSocket('ws://192.168.1.100:8000/ws');
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
          "You are on the main screen. There are six large buttons from top to bottom: Describe Scene, Who is this, Register Face, Stop Scene Description, Give me details on the product, and Live Video Narration. You can tap a button or say 'Hey Lumi' at any time to use voice commands. Listening for 'Hey Lumi' now.",
        );
        _startListening();
      });
    });
    _productSummaryService = ProductSummaryService();
    _productSummaryService.speakSentence =
        (sentence) => _voiceService.speak(sentence);

    // Initialize MiniCPM service
    _miniCPMService = MiniCPMService();
    _miniCPMService.speakSentenceFunction =
        (sentence) => _voiceService.speak(sentence);

    // Set up wake word listener control callbacks
    _miniCPMService.onBeforeSpeakNarration = () {
      // Pause wake word listening while TTS is playing
      _speechService.stopListening();
      debugPrint(
        'TakePictureScreen: Paused wake word listening during narration',
      );
    };

    _miniCPMService.onAfterSpeakNarration = () {
      // Resume wake word listening after TTS playback completed
      _startListening();
      debugPrint(
        'TakePictureScreen: Resumed wake word listening after narration',
      );
    };
  }

  /// Generic listening function for both wake word and command phases.
  void _listenAndProcess({
    required String promptOnNoMatch,
    required String Function(String recognizedText, {required bool isFinal})
    processResult,
    Duration listenFor = const Duration(minutes: 60),
    Duration pauseFor = const Duration(seconds: 100),
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
        _listenAndProcess(
          promptOnNoMatch: promptOnNoMatch,
          processResult: processResult,
          listenFor: listenFor,
          pauseFor: pauseFor,
        );
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
      apiUrl: 'http://192.168.1.125:4000/recognize',
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
            apiUrl: 'http://192.168.1.125:4000/register',
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

  void _onProductDetails() async {
    _pauseListening();
    HapticFeedback.mediumImpact();
    final picture = await _cameraService.takePicture();
    await _voiceService.speak("Analyzing product. Please wait.");
    try {
      // Step 1: Call vision_backend for findings
      final uri = Uri.parse('http://192.168.1.125:8001/analyze-product/');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('image', picture.path));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = (data['text'] as List).join('. ');
        final labels = (data['labels'] as List).join(', ');
        final webEntities = (data['web_entities'] as List).join(', ');
        final findings =
            'Extracted text: $text\nLabels: $labels\nWeb info: $webEntities';

        // Step 2: Send image and findings to VLM (product summary API)
        final controller = StreamController<String>();
        getProductSummaryWithFindings(picture.path, findings, controller);
        await for (final chunk in controller.stream) {
          _productSummaryService.accumulateResponse(chunk);
        }
      } else {
        await _voiceService.speak("Sorry, I couldn't get product details.");
      }
    } catch (e) {
      await _voiceService.speak("Sorry, I couldn't get product details.");
    }
    _startListening();
  }

  void _pauseListening() {
    debugPrint(
      'TakePictureScreenState: Pausing listening, stopping TTS, and resetting processing flags...',
    );
    _speechService.stopListening();
    _voiceService.stopPlayback(); // Correctly stop ongoing TTS
    _isProcessingWakeWord = false;
    _isProcessingCommand = false;
  }

  @override
  void _listenForWakeWord() {
    _listenAndProcess(
      promptOnNoMatch: "",
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
          "Please say a command like 'Describe scene', 'Who is this?', or 'Start live narration'",
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
        const questionCommands = [
          "ask a question",
          "ask question",
          "question about scene",
          "question about the scene",
        ];
        const liveVideoCommands = [
          "start live video narration",
          "start live narration",
          "live video narration",
          "live narration",
        ];
        const stopLiveVideoCommands = [
          "stop live video narration",
          "stop live narration",
          "end live narration",
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

          // Handle question asking during MiniCPM narration
          if (_isMiniCPMActive &&
              questionCommands.any((c) => command.contains(c))) {
            _speechService.stopListening();
            _listenForMiniCPMQuestion();
            return 'handled';
          }

          // Handle live video narration commands
          if (liveVideoCommands.any((c) => command.contains(c))) {
            debugPrint("Starting live video narration via voice command.");
            _speechService.stopListening();
            _onLiveVideoNarration();
            return 'handled';
          }

          // Handle stop live video narration commands
          if (_isMiniCPMActive &&
              stopLiveVideoCommands.any((c) => command.contains(c))) {
            debugPrint("Stopping live video narration via voice command.");
            _speechService.stopListening();
            _onLiveVideoNarration(); // This toggles, so it will stop if already active
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
      body: Stack(
        children: [
          // Main UI buttons
          Column(
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
                      child: Text(
                        'Describe Scene',
                        textAlign: TextAlign.center,
                      ),
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
              Expanded(
                child: Semantics(
                  label: 'Give me details on the product',
                  button: true,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _onProductDetails,
                    child: const Center(
                      child: Text(
                        'Give me details on the product',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Semantics(
                  label: 'Live Video Narration',
                  button: true,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _onLiveVideoNarration,
                    child: Center(
                      child: Text(
                        _isMiniCPMActive
                            ? 'Stop Live Narration'
                            : 'Live Video Narration',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // WebRTC Preview overlay when live narration is active
          if (_isMiniCPMActive)
            Positioned(
              top: 10,
              right: 10,
              width: 120,
              height: 160,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.teal, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child:
                    _miniCPMService.localVideoRenderer != null
                        ? RTCVideoView(
                          _miniCPMService.localVideoRenderer!,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                        : const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // Method to handle Live Video Narration button
  // Method to listen for a question during MiniCPM narration
  Future<void> _listenForMiniCPMQuestion() async {
    await _voiceService.speak('What would you like to ask about the scene?');

    // Listen for the question (no need to pause video stream - it continues automatically)
    _speechService.listenForSpeech(
      onResult: (recognizedText, isFinal) {
        if (isFinal && recognizedText.isNotEmpty) {
          debugPrint('MiniCPM Question: $recognizedText');

          // Ask the question
          _miniCPMService.askQuestion(recognizedText);

          // Stop listening for more questions
          _speechService.stopListening();

          // Resume listening for wake word after a delay
          Future.delayed(const Duration(seconds: 5), () {
            if (_isMiniCPMActive) {
              _startListening();
            }
          });
        }
      },
      listenFor: const Duration(seconds: 10),
    );
  }

  Future<void> _onLiveVideoNarration() async {
    // Pause listening and stop any current TTS to prevent interruptions
    _pauseListening();
    // _speechService.stopListening(); // This is already called by _pauseListening()

    if (_isMiniCPMActive) {
      // Stop MiniCPM narration
      _miniCPMService.stopNarration();
      _isMiniCPMActive = false;
      await _voiceService.speak('Live video narration stopped');
    } else {
      // Start MiniCPM narration
      await _voiceService.speak('Starting live video narration.');

      _minicpmServerUrl = 'http://34.41.19.230:8123'; // External VM IP

      // Set camera controller for the MiniCPM service
      _miniCPMService.setCameraController(_cameraService.controller);

      // Connect to MiniCPM server
      bool connected = await _miniCPMService.connect(_minicpmServerUrl);

      if (connected) {
        // Start narration via WebRTC path
        bool started = await _miniCPMService.startNarration();
        if (started) {
          // Force UI to rebuild to show the WebRTC preview
          setState(() {
            _isMiniCPMActive = true;
          });
          await _voiceService.speak('Live video narration started');
        } else {
          // Narration didn't start, MiniCPMService would have logged the reason.
          await _voiceService.speak(
            'Could not start live video narration. Please try again.',
          );
          _isMiniCPMActive = false;
        }
      } else {
        await _voiceService.speak(
          'Failed to connect to video narration service.',
        );
        _isMiniCPMActive = false;
      }
    }
    // Resume listening for voice commands
    _startListening();
  }

  @override
  void dispose() {
    _sceneDescriptionService.dispose();
    _voiceService.dispose();
    _cameraService.dispose();
    _speechService.stopListening();
    _productSummaryService.dispose();
    _miniCPMService.dispose();
    super.dispose();
  }
}
