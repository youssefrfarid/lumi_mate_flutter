// lib/screens/take_picture_screen.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';
import 'display_picture_screen.dart';

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({Key? key, required this.camera}) : super(key: key);
  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final TextEditingController _questionController = TextEditingController();
  bool _isQuestionEmpty = true;
  bool _isTakingPicture = false;

  // Speech-to-text instance and state.
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _currentQuestion = "";

  // Flags to prevent duplicate prompting.
  bool _isAwaitingQuestion = false;
  bool _isAwaitingConfirmation = false;
  bool _hasPromptedForQuestion = false;

  // Create a TTS instance.
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.max);
    _initializeControllerFuture = _controller.initialize();

    // Start the wake-word listener as soon as the screen is loaded.
    _startListening();
  }

  @override
  void dispose() {
    _controller.dispose();
    _questionController.dispose();
    _speech.stop();
    super.dispose();
  }

  // Helper method to speak text using TTS.
  void _speak(String text) async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(text);
  }

  /// Starts continuous listening for the wake phrase "Hey Lumi".
  void _startListening() async {
    print(
      "Initializing continuous speech recognition for wake-word listening.",
    );
    bool available = await _speech.initialize();
    if (available) {
      print("Speech recognition initialized. Listening continuously.");
      setState(() {
        _isListening = true;
      });
      _speech.listen(
        listenFor: const Duration(minutes: 60),
        onResult: (result) {
          String recognized = result.recognizedWords.toLowerCase();
          print("Continuous listener recognized: $recognized");
          if (recognized.contains("hey lumi") && !_hasPromptedForQuestion) {
            print(
              "Wake word detected. Stopping wake-word listener and prompting for question.",
            );
            _hasPromptedForQuestion = true; // Prevent further prompts.
            _speech.stop();
            _promptForQuestion();
          } else if (result.finalResult && !recognized.contains("hey lumi")) {
            print("No wake word detected, clearing recognized text.");
            setState(() {
              _questionController.clear();
            });
          }
        },
      );
    } else {
      print("Speech recognition not available.");
    }
  }

  /// Prompts the user by speaking "Yes, how may I help you?" and then listens for the user's question.
  void _promptForQuestion() {
    _speak("Yes, how may I help you?");
    // Wait enough time for TTS to finish speaking.
    Future.delayed(const Duration(seconds: 3), () {
      _listenForQuestion();
    });
  }

  /// Listens for the user's question.
  void _listenForQuestion() async {
    if (_isAwaitingQuestion) return;
    setState(() {
      _isAwaitingQuestion = true;
    });
    print("Listening for user's question...");
    bool available = await _speech.initialize();
    if (available) {
      _speech.listen(
        listenFor: const Duration(seconds: 10),
        onResult: (result) {
          if (result.finalResult) {
            setState(() {
              _isAwaitingQuestion = false;
            });
            // Remove any leading TTS prompt phrases from the recognized text.
            String question = result.recognizedWords;
            question =
                question
                    .replaceAll(
                      RegExp(
                        r'^(yes,?\s+how may i help you\s*)+',
                        caseSensitive: false,
                      ),
                      '',
                    )
                    .trim();
            print("User's question received after filtering: $question");
            _currentQuestion = question;
            _speech.stop();
            // Reset wake-word flag for next time.
            _hasPromptedForQuestion = false;
            _confirmQuestion();
          }
        },
      );
    } else {
      print("Speech recognition not available for listening to question.");
      setState(() {
        _isAwaitingQuestion = false;
      });
    }
  }

  /// Repeats the captured question for user confirmation.
  void _confirmQuestion() {
    _speak("Did you say: $_currentQuestion? Please say yes or no.");
    // Wait 3 seconds for TTS to finish speaking before listening for confirmation.
    Future.delayed(const Duration(seconds: 3), () {
      _listenForConfirmation();
    });
  }

  /// Listens for confirmation from the user.
  /// If confirmed with "yes", takes a picture.
  /// If the response explicitly starts with "no", clears the question and asks to repeat.
  /// Otherwise, asks for confirmation again.
  void _listenForConfirmation() async {
    if (_isAwaitingConfirmation) return;
    setState(() {
      _isAwaitingConfirmation = true;
    });
    print("Listening for confirmation...");
    bool available = await _speech.initialize();
    if (available) {
      _speech.listen(
        listenFor: const Duration(seconds: 5),
        onResult: (result) {
          if (result.finalResult) {
            setState(() {
              _isAwaitingConfirmation = false;
            });
            String response = result.recognizedWords.toLowerCase().trim();
            print("Confirmation response received: '$response'");
            _speech.stop();
            if (response.startsWith("yes")) {
              _takePicture();
            } else if (response.startsWith("no")) {
              _currentQuestion = "";
              _speak("Okay, please repeat your question.");
              Future.delayed(const Duration(seconds: 3), () {
                _listenForQuestion();
              });
            } else {
              _speak("I didn't catch that. Please say yes or no.");
              Future.delayed(const Duration(seconds: 3), () {
                _listenForConfirmation();
              });
            }
          }
        },
      );
    } else {
      print("Speech recognition not available for confirmation listening.");
      setState(() {
        _isAwaitingConfirmation = false;
      });
    }
  }

  /// Takes a picture, sends it and the confirmed question to the API,
  /// and navigates to the display screen.
  void _takePicture() async {
    if (_isTakingPicture) return; // Prevent overlapping actions.

    setState(() {
      _isTakingPicture = true;
    });

    try {
      print("Attempting to take picture...");
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      print("Picture captured. Sending image and question to API.");
      if (!mounted) return;

      final responseController = StreamController<String>();
      await sendImageAndMessageToAPI(
        image.path,
        responseController,
        _currentQuestion,
      );

      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (context) => DisplayPictureScreen(
                imagePath: image.path,
                responseStream: responseController.stream,
              ),
        ),
      );
    } catch (e) {
      print('Error in _takePicture(): $e');
    } finally {
      setState(() {
        _isTakingPicture = false;
        _currentQuestion = "";
      });
      print("Picture taking process complete. Restarting wake-word listener.");
      _startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take a Picture')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Text input for user question.
            // (The text field remains for manual input if needed,
            // but prompt messages are no longer written into it.)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _questionController,
                decoration: InputDecoration(
                  labelText: 'Enter a question',
                  hintText: 'What do you want to know?',
                  border: OutlineInputBorder(),
                ),
                onChanged: (text) {
                  setState(() {
                    _isQuestionEmpty = text.isEmpty;
                  });
                },
              ),
            ),
            const SizedBox(height: 20),
            // Camera preview.
            FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return CameraPreview(_controller);
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture,
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}
