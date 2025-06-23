import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class VoiceService {
  AudioPlayer? _audioPlayer;
  late String _wsUrl;

  void initTtsWebSocket(String wsUrl) {
    _wsUrl = wsUrl;
    _audioPlayer = AudioPlayer();
  }

  Future<void> speak(String text) async {
    if (_wsUrl.isEmpty) throw Exception('TTS WebSocket URL not initialized');
    if (text.trim().isEmpty) return;
    debugPrint('VoiceService: Sending text to TTS: "$text"');
    final request = {
      'text': text,
      'voice': 'en-US-Wavenet-D',
      'languageCode': 'en-US',
      'speakingRate': 1.0,
      'pitch': 0.0,
      'audioEncoding': 'MP3',
    };
    debugPrint('VoiceService: [TTS API OUT] ${const JsonEncoder().convert(request)}');
    final channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
    channel.sink.add(const JsonEncoder().convert(request));
    List<int> audioBuffer = [];
    late StreamSubscription sub;
    final completer = Completer<void>();
    sub = channel.stream.listen((event) async {
      if (event is List<int>) {
        audioBuffer.addAll(event);
        debugPrint('VoiceService: [TTS API IN] Received ${event.length} bytes of audio');
      } else if (event is String) {
        debugPrint('VoiceService: [TTS API IN] Received string: $event');
        try {
          final msg = jsonDecode(event);
          if (msg['done'] == true) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
            await tempFile.writeAsBytes(audioBuffer, flush: true);
            final fileBytes = await tempFile.readAsBytes();
            if (fileBytes.isEmpty) {
              debugPrint('VoiceService: Audio file is empty, skipping playback.');
              await sub.cancel();
              await channel.sink.close();
              completer.completeError(Exception('TTS audio file is empty.'));
              return;
            }
            try {
              await _audioPlayer?.dispose();
              _audioPlayer = AudioPlayer();
              await _audioPlayer?.setAllowsExternalPlayback(true);
              debugPrint('VoiceService: Audio player (just_audio) prepared, now playing...');
              await _audioPlayer!.setFilePath(tempFile.path);
              await _audioPlayer!.play();
              debugPrint('VoiceService: TTS play() returned');
              // Wait for playback to finish before completing
              await _audioPlayer!.playerStateStream.firstWhere(
                (state) => state.processingState == ProcessingState.completed,
              );
              debugPrint('VoiceService: TTS ProcessingState.completed');
              debugPrint('VoiceService: Playback started and finished.');
            } catch (e) {
              debugPrint('VoiceService: Playback error (just_audio): $e');
            }
            await sub.cancel();
            await channel.sink.close();
            completer.complete();
          } else if (msg['error'] != null) {
            debugPrint('VoiceService: [TTS API IN] Error: ${msg['error']}');
            await sub.cancel();
            await channel.sink.close();
            completer.completeError(Exception('TTS backend error: ${msg['error']}'));
          }
        } catch (e) {
          debugPrint('VoiceService: [TTS API IN] JSON decode error: $e');
        }
      } else {
        debugPrint('VoiceService: [TTS API IN] Unknown event type: ${event.runtimeType}');
      }
    },
    onError: (err) async {
      debugPrint('VoiceService: [TTS API IN] WebSocket stream error: $err');
      await channel.sink.close();
      completer.completeError(Exception('WebSocket stream error: $err'));
    });
    return completer.future;
  }

  void stopPlayback() {
    _audioPlayer?.stop();
    debugPrint('VoiceService: Playback stopped via stopPlayback().');
  }

  void dispose() {
    _audioPlayer?.dispose();
  }
}
