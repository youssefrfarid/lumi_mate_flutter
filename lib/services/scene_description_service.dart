import 'dart:async';
import 'package:flutter/foundation.dart';

class SceneDescriptionService {
  Timer? sceneDescriptionTimer;
  bool isSceneDescriptionActive = false;
  String _buffer = "";
  Timer? responseTimer;
  Completer<void>? currentDescriptionCompleter;
  final StreamController<String> responseController = StreamController<String>.broadcast();
  final List<String> _sentenceQueue = [];
  bool _isSpeaking = false;
  VoidCallback? onQueueEmpty;
  late Future<void> Function(String) speakSentence;
  Future<void> Function()? takePictureAndSendToApi;
  VoidCallback? _onSceneDescriptionComplete;

  bool get isActive => isSceneDescriptionActive;
  Stream<String> get responseStream => responseController.stream;

  void accumulateResponse(String chunk) {
    if (chunk == '[DONE]') {
      // Start the 8-second timer for the next loop
      sceneDescriptionTimer?.cancel();
      if (onQueueEmpty != null) {
        sceneDescriptionTimer = Timer(const Duration(seconds: 8), onQueueEmpty!);
      }
      return;
    }
    _buffer += chunk;
    // Split by full stop (sentence end)
    final sentences = _buffer.split('.');
    // All except last are complete sentences
    for (int i = 0; i <sentences.length - 1; i++) {
      final sentence = sentences[i].trim();
      if (sentence.isNotEmpty) {
        _sentenceQueue.add('$sentence.');
      }
    }
    // The last part is either empty or incomplete
    _buffer = sentences.last;
    // Notify UI (optional: can be removed if not needed)
    if (_sentenceQueue.isNotEmpty) {
      responseController.add(_sentenceQueue.join(' '));
    }
    // Start speaking if not already
    _processQueue();
  }

  void _processQueue() async {
    if (_isSpeaking || _sentenceQueue.isEmpty) return;
    _isSpeaking = true;
    while (_sentenceQueue.isNotEmpty) {
      final sentence = _sentenceQueue.removeAt(0);
      debugPrint('SceneDescriptionService: Speaking sentence: "$sentence"');
      await speakSentence(sentence);
    }
    _isSpeaking = false;
    // When queue is empty, start 8s timer for next action
    sceneDescriptionTimer?.cancel();
    sceneDescriptionTimer = Timer(const Duration(seconds: 8), onQueueEmpty!);
  }

  void startSceneDescription({VoidCallback? onComplete}) {
    isSceneDescriptionActive = true;
    _onSceneDescriptionComplete = onComplete;
    // Immediately trigger the first picture + API call if callback is set
    takePictureAndSendToApi?.call();
  }

  void stopSceneDescription() {
    isSceneDescriptionActive = false;
    sceneDescriptionTimer?.cancel();
    _sentenceQueue.clear();
    _buffer = "";
    _isSpeaking = false;
    // Call the onComplete callback if set
    _onSceneDescriptionComplete?.call();
    _onSceneDescriptionComplete = null;
  }

  void dispose() {
    responseController.close();
    currentDescriptionCompleter?.complete();
    sceneDescriptionTimer?.cancel();
    responseTimer?.cancel();
  }

  set speakSentenceCallback(Future<void> Function(String) callback) {
    speakSentence = callback;
  }
}
