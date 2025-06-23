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

    var url = Uri.parse('http://192.168.1.125:1234/v1/chat/completions');
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
        
        Speak directly to the user as if you're their eyes, using phrases like 'In front of you' or 'To your left'.
        
        Keep descriptions concise (ideally 2-3 sentences), focusing only on the most important objects, hazards, and features. Avoid excessive detail or long descriptions unless there is a danger present.
        If you notice any potential dangers, mention them first.""",
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
      "model": "openbmb/minicpm-o-2_6",
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

    var url = Uri.parse('http://192.168.1.125:1234/v1/chat/completions');
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
      "model": "openbmb/minicpm-o-2_6",
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

// Gemini multimodal scene description using Vertex AI
Future<String> getGeminiSceneDescription({
  required String accessToken,
  required String projectId,
  required String imagePath,
  String location = 'us-central1',
}) async {
  final url =
      'https://$location-aiplatform.googleapis.com/v1/projects/$projectId/locations/$location/publishers/google/models/gemini-2.0-flash-001:generateContent';

  final imageBytes = await File(imagePath).readAsBytes();
  final imageBase64 = base64Encode(imageBytes);

  final requestBody = {
    'contents': [
      {
        'role': 'user',
        'parts': [
          {
            'text':
                "Describe this scene for a visually impaired user in 2-3 concise sentences. Focus on important objects, hazards, and features. Avoid unnecessary detail unless there is a danger.",
          },
          {
            'inlineData': {'mimeType': 'image/jpeg', 'data': imageBase64},
          },
        ],
      },
    ],
    'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 256},
  };

  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    },
    body: jsonEncode(requestBody),
  );

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    final description =
        decoded['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
        'No description found.';
    return description;
  } else {
    throw Exception(
      'Gemini API error: ${response.statusCode} ${response.body}',
    );
  }
}

// Gemini multimodal scene description using FastAPI backend
Future<String> getGeminiSceneDescriptionViaBackend({
  required String backendUrl,
  required String imagePath,
  String prompt =
      "Describe this scene for a visually impaired user in 2-3 concise sentences. Focus on important objects, hazards, and features. Avoid unnecessary detail unless there is a danger.",
}) async {
  final imageBytes = await File(imagePath).readAsBytes();
  final imageBase64 = base64Encode(imageBytes);

  final response = await http.post(
    Uri.parse(backendUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'text': prompt, 'image_base64': imageBase64}),
  );

  if (response.statusCode == 200) {
    final decoded = jsonDecode(response.body);
    final description = decoded['result'] ?? 'No description found.';
    return description;
  } else {
    throw Exception(
      'Backend Gemini API error: ${response.statusCode} ${response.body}',
    );
  }
}

// Recognize face using AWS Rekognition API
Future<String> recognizeFace({
  required String apiUrl,
  required String imagePath,
}) async {
  var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
  request.files.add(await http.MultipartFile.fromPath('image', imagePath));

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode == 200) {
    final Map<String, dynamic> data = jsonDecode(response.body);
    final results = data['results'] as List<dynamic>?;
    if (results != null && results.isNotEmpty) {
      final firstResult = results.first;
      final name = firstResult['name'] ?? 'Unknown Person';
      return name;
    } else {
      return 'No faces detected';
    }
  } else {
    throw Exception(
      'Face recognition API error: ${response.statusCode} ${response.body}',
    );
  }
}

// Register face using AWS Rekognition API
Future<bool> registerFace({
  required String apiUrl,
  required String imagePath,
  required String name,
}) async {
  var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
  request.files.add(await http.MultipartFile.fromPath('image', imagePath));
  request.fields['name'] = name;

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode == 200) {
    final Map<String, dynamic> data = jsonDecode(response.body);
    return data['message'] != null &&
        data['message'].toString().contains('registered successfully');
  } else {
    throw Exception(
      'Face registration API error: ${response.statusCode} ${response.body}',
    );
  }
}

// Product summary with findings (image + findings to VLM)
Future<void> getProductSummaryWithFindings(
  String imagePath,
  String findings,
  StreamController<String> controller,
) async {
  try {
    File imageFile = File(imagePath);
    Uint8List imageBytes = await imageFile.readAsBytes();
    String base64Image = base64Encode(imageBytes);

    var url = Uri.parse(
      'http://192.168.1.125:1234/v1/chat/completions',
    ); // Use your VLM endpoint
    var headers = {'Content-Type': 'application/json'};

    var messages = [
      {
        "role": "system",
        "content":
            "You are a helpful assistant for visually impaired users. You will receive product images and extracted findings (text, labels, web info). Use both the image and findings to identify the product. Your response must be in a purely conversational, natural language form suitable for text-to-speech, without any markdown, markup, or formatting symbols. Do not use headings, lists, or special characters—just plain sentences. Limit your response to 2-3 concise sentences. Focus on what the product is and only the most important details, such as name, type, flavor, weight, and any special or limited edition information. Do not include unnecessary information or long explanations. If you cannot identify the product, say so. If the image is blurry or unclear, mention that as well. Avoid using phrases like 'I see' or 'I can tell you that'. Keep it withing 2-3 sentences. If you notice any potential dangers, mention them first.",
      },
      {
        "role": "user",
        "content": [
          {"type": "text", "text": findings},
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
      "model": "openbmb/minicpm-o-2_6",
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
    debugPrint('Error sending product summary to VLM: $e');
  }
}
