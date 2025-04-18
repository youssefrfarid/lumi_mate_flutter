// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Scene description specific function
Future<void> sendSceneDescriptionToAPI(
  String imagePath,
  StreamController<String> controller,
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
        "content": """You are a helpful assistant for visually impaired users. 
        You will receive images from their point of view. 
        Your task is to describe the scene in a natural, conversational way that helps them understand their surroundings.
        
        Focus on:
        1. Important objects and their relative positions
        2. Potential obstacles or hazards
        3. Notable environmental features
        4. Any text or signs that might be important
        
        Speak directly to the user as if you're their eyes, using phrases like "In front of you" or "To your left".
        Keep descriptions concise but informative.
        If you notice any potential dangers, mention them first.
        """,
      },
      {
        "role": "user",
        "content": [
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/jpeg;base64,$base64Image",
              "detail": "high",
            },
          },
        ],
      },
    ];

    var body = jsonEncode({
      "model": "minicpm-o-2_6",
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
    streamedResponse.stream.listen(
      (List<int> chunk) {
        String chunkStr = utf8.decode(chunk).trim();
        if (chunkStr == '[DONE]') {
          controller.add('[DONE]');
          return;
        }
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
          debugPrint('Error parsing chunk: $e');
        }
      },
      onError: (error) {
        debugPrint('Error while streaming response: $error');
      },
      onDone: () {
        controller.close();
      },
    );
  } catch (e) {
    debugPrint('Error sending scene description to API: $e');
  }
}

// Original function for question-based queries
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
        "content": """You are a helpful assistant for visually impaired users. 
        You will receive images from their point of view along with their questions.
        Your task is to answer their questions based on what you see in the image.
        
        Guidelines:
        1. Answer directly and concisely
        2. Focus on what's relevant to their question
        3. Use clear, simple language
        4. If you can't see something they're asking about, say so
        """,
      },
      {
        "role": "user",
        "content": [
          {"type": "text", "text": userQuestion ?? ""},
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/jpeg;base64,$base64Image",
              "detail": "high",
            },
          },
        ],
      },
    ];

    var body = jsonEncode({
      "model": "minicpm-o-2_6",
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
    streamedResponse.stream.listen(
      (List<int> chunk) {
        String chunkStr = utf8.decode(chunk).trim();
        if (chunkStr == '[DONE]') {
          controller.add('[DONE]');
          return;
        }
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
          debugPrint('Error parsing chunk: $e');
        }
      },
      onError: (error) {
        debugPrint('Error while streaming response: $error');
      },
      onDone: () {
        controller.close();
      },
    );
  } catch (e) {
    debugPrint('Error sending image and message to API: $e');
  }
}
