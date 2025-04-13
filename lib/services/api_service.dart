// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

Future<void> sendImageAndMessageToAPI(
  String imagePath,
  StreamController<String> controller,
  String? userQuestion,
) async {
  try {
    File imageFile = File(imagePath);
    Uint8List imageBytes = await imageFile.readAsBytes();
    String base64Image = base64Encode(imageBytes);

    var url = Uri.parse('http://172.20.10.2:1234/v1/chat/completions');
    var headers = {'Content-Type': 'application/json'};

    var messages = [
      {
        "role": "system",
        "content":
            "You are a helpful assistant for visually impaired users. The images provided represent their point of view. Describe the scene by focusing on objects' placements relative to the user, potential dangers, and any visible signs. Speak directly to the user rather than merely stating what the image shows.",
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

    if (userQuestion != null && userQuestion.isNotEmpty) {
      messages.add({
        "role": "system",
        "content":
            "Answer in a way that talks directly to the user and only answers the question simply and briefly.",
      });
      messages.add({
        "role": "user",
        "content": [
          {"type": "text", "text": userQuestion},
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/jpeg;base64,$base64Image",
              "detail": "high",
            },
          },
        ],
      });
    }

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
        controller.close();
      },
    );
  } catch (e) {
    print('Error sending image and message to API: $e');
  }
}
