import 'dart:convert'; // For JSON decoding/encoding
import 'dart:io';
import 'dart:typed_data'; // For image manipulation
import 'dart:async'; // For StreamController
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart'; // Import flutter_tts package
import 'package:speech_to_text/speech_to_text.dart'
    as stt; // Import speech_to_text package
import 'package:http/http.dart' as http;

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({super.key, required this.camera});

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final TextEditingController _questionController =
      TextEditingController(); // Text controller for user input
  bool _isQuestionEmpty =
      true; // To check if the question field is empty or not

  // Initialize Speech to Text
  final stt.SpeechToText _speech = stt.SpeechToText();
  final bool _isListening = false;
  bool _isTakingPicture =
      false; // To track if the picture-taking process is in progress

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.max);
    _initializeControllerFuture = _controller.initialize();

    // Start listening to speech for "Hey Lumi"
    //_startListening();
  }

  @override
  void dispose() {
    _controller.dispose();
    _questionController.dispose(); // Dispose the controller when done
    super.dispose();
  }

  // Start the speech recognition and listen for "Hey Lumi"
  // void _startListening() async {
  //   bool available = await _speech.initialize();
  //   if (available) {
  //     _speech.listen(
  //       onResult: (result) {
  //         print(result.recognizedWords);
  //         if (result.recognizedWords.toLowerCase().contains("hey lumi")) {
  //           // Start listening for the next part of the speech (the user's question)
  //           print("Got hey lumi");
  //           _speech.stop(); // Stop listening for "Hey Lumi"
  //           _listenForQuestion(); // Start listening for the question
  //         }
  //       },
  //     );
  //   }
  // }

  // // Listen for the user's question after "Hey Lumi"
  // void _listenForQuestion() async {
  //   _speech.listen(
  //     onResult: (result) {
  //       if (result.recognizedWords.isNotEmpty) {
  //         // Set the recognized speech as the question in the text field
  //         setState(() {
  //           _questionController.text = result.recognizedWords;
  //         });

  //         // Start taking picture after the question is recognized
  //         _takePicture();
  //       }
  //     },
  //   );
  // }

  // Modified function to accept a StreamController parameter.
  Future<void> sendImageAndMessageToAPI(
    String imagePath,
    StreamController<String> controller,
    String? userQuestion,
  ) async {
    try {
      File imageFile = File(imagePath);
      Uint8List imageBytes = await imageFile.readAsBytes();
      String base64Image = base64Encode(imageBytes);

      var url = Uri.parse('http://192.168.1.156:1234/v1/chat/completions');
      var headers = {'Content-Type': 'application/json'};

      var messages = [
        {
          "role": "system",
          "content":
              "You are a helpful assistant for visually impaired users, the images that will be provided are their POV. Describe their scene focusing on things like objects placement relative to them, dangerous scenarios and any signs. Answer in a way to talk to the user not simple describe the image saying this image shows.",
        },
        {
          "role": "user",
          "content": [
            {
              "type": "image_url", // Image part of the user message
              "image_url": {
                "url": "data:image/jpeg;base64,$base64Image",
                "detail": "high",
              },
            },
          ],
        },
      ];

      if (userQuestion != null && userQuestion.isNotEmpty) {
        messages.add({
          "role": "system",
          "content":
              "Answer in a way to talk to the user and only answer his question keep it simple and short.",
        });
        messages.add({
          "role": "user",
          "content": [
            {"type": "text", "text": userQuestion},
            {
              "type": "image_url", // Image part of the user message
              "image_url": {
                "url": "data:image/jpeg;base64,$base64Image",
                "detail": "high",
              },
            },
          ],
        });
      }

      var body = jsonEncode({
        "model": "minicpm-o-2_6", // Replace with the actual model name
        "messages": messages,
        "temperature": 0.3,
        "max_tokens": -1,
        "stream": true,
      });

      var client = http.Client();
      var request =
          http.Request('POST', url)
            ..headers.addAll(headers)
            ..body = body;

      var streamedResponse = await client.send(request);
      print('geit hena');
      streamedResponse.stream.listen(
        (List<int> chunk) {
          String chunkStr = utf8.decode(chunk);
          if (chunkStr.startsWith('data: ')) {
            chunkStr = chunkStr.replaceFirst('data: ', '');
          }

          try {
            Map<String, dynamic> parsedChunk = jsonDecode(chunkStr);
            var content = parsedChunk['choices'][0]['delta']['content'];
            if (content != null) {
              controller.add(content);
            }
          } catch (e) {
            print('Error parsing chunk: $e');
          }
        },
        onError: (error) {
          print('Error while streaming response: $error');
        },
        onDone: () {
          print('Stream closed');
          controller.close();
        },
      );
    } catch (e) {
      print('Error sending image and message to API: $e');
    }
  }

  // Function to take the picture automatically after question is recognized
  void _takePicture() async {
    if (_isTakingPicture) {
      return; // Prevent taking picture if already in progress
    }
    setState(() {
      _isTakingPicture = true;
    });

    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();

      if (!context.mounted) return;

      final responseController = StreamController<String>();
      await sendImageAndMessageToAPI(
        image.path,
        responseController,
        _questionController.text,
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (context) => DisplayPictureScreen(
                imagePath: image.path,
                responseStream: responseController.stream,
              ),
        ),
      );
    } catch (e) {
      print(e);
    } finally {
      setState(() {
        _isTakingPicture = false; // Allow taking pictures again
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take a picture')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Text box for user to enter a question
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
            // Camera preview
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

class DisplayPictureScreen extends StatefulWidget {
  final String imagePath;
  final Stream<String> responseStream;

  const DisplayPictureScreen({
    super.key,
    required this.imagePath,
    required this.responseStream,
  });

  @override
  _DisplayPictureScreenState createState() => _DisplayPictureScreenState();
}

class _DisplayPictureScreenState extends State<DisplayPictureScreen> {
  String accumulatedText = "";
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.responseStream.listen((chunk) {
      setState(() {
        accumulatedText += chunk;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Image.file(File(widget.imagePath)),
            const SizedBox(height: 20),
            Text(
              accumulatedText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
