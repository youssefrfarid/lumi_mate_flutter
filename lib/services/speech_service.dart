import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/foundation.dart';

/// Handles all speech recognition logic.
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  /// Initializes the speech recognizer.
  Future<bool> initialize() async {
    return await _speech.initialize();
  }

  /// Listens for speech and calls [onResult] with recognized text.
  /// Returns true if listening started successfully.
  Future<bool> listenForSpeech({
    required void Function(String recognizedText, bool isFinal) onResult,
    void Function(String error)? onError,
    Duration listenFor = const Duration(seconds: 60),
    Duration pauseFor = const Duration(seconds: 3),
    bool partialResults = true,
  }) async {
    if (!_speech.isAvailable) {
      if (onError != null) onError('Speech recognition not available.');
      return false;
    }
    _isListening = true;
    _speech.listen(
      listenFor: listenFor,
      pauseFor: pauseFor,
      onResult: (result) {
        debugPrint('SpeechService: Recognized: "${result.recognizedWords}" (final: ${result.finalResult})');
        onResult(result.recognizedWords, result.finalResult);
      },
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: false,
        partialResults: partialResults,
      ),
      onSoundLevelChange: (level) {
        // Optionally handle sound level changes for UI feedback
      },
    );
    // Attach error handler using the plugin's onError stream
    _speech.errorListener = (error) {
      debugPrint('SpeechService: Error: ${error.errorMsg}');
      if (onError != null) onError(error.errorMsg);
    };
    return true;
  }

  /// Stops listening.
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }

  /// Cancels listening.
  Future<void> cancelListening() async {
    if (_isListening) {
      await _speech.cancel();
      _isListening = false;
    }
  }

  /// Whether the speech recognizer is currently listening.
  bool get isListening => _isListening;

  /// Releases any resources used by the speech recognizer.
  void dispose() {
    stopListening();
  }
}
