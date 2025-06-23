import 'dart:async';
import 'package:flutter/foundation.dart';

class ProductSummaryService {
  String _buffer = "";
  final List<String> _sentenceQueue = [];
  bool _isSpeaking = false;
  late Future<void> Function(String) speakSentence;

  void accumulateResponse(String chunk) {
    if (chunk == '[DONE]') {
      return;
    }
    _buffer += chunk;
    // Split by full stop (sentence end)
    final sentences = _buffer.split('.');
    // All except last are complete sentences
    for (int i = 0; i < sentences.length - 1; i++) {
      final sentence = sentences[i].trim();
      if (sentence.isNotEmpty) {
        _sentenceQueue.add('$sentence.');
      }
    }
    // The last part is either empty or incomplete
    _buffer = sentences.last;
    _processQueue();
  }

  void _processQueue() async {
    if (_isSpeaking || _sentenceQueue.isEmpty) return;
    _isSpeaking = true;
    while (_sentenceQueue.isNotEmpty) {
      final sentence = _sentenceQueue.removeAt(0);
      debugPrint('ProductSummaryService: Speaking sentence: "$sentence"');
      await speakSentence(sentence);
    }
    _isSpeaking = false;
  }

  void dispose() {
    _sentenceQueue.clear();
    _buffer = "";
    _isSpeaking = false;
  }
}
