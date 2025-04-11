// api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> sendImageToApi(String imagePath) async {
  final uri = Uri.parse("http://127.0.0.1:1234/v1/chat/completions");
  final file = File(imagePath);
  final request = await HttpClient().postUrl(uri);
  request.headers.set(HttpHeaders.contentTypeHeader, "image/jpeg");
  final bytes = await file.readAsBytes();
  request.add(bytes);

  final response = await request.close();

  final completer = Completer<void>();
  response
      .transform(utf8.decoder)
      .listen(
        (data) {
          print("Streamed chunk: $data");
          // Update your UI or state here as needed.
        },
        onDone: () {
          print("Streaming complete");
          completer.complete();
        },
        onError: (e) {
          print("Streaming error: $e");
          completer.completeError(e);
        },
      );
  await completer.future;
}
