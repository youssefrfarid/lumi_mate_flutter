// lib/services/minicpm_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:camera/camera.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'webrtc_client.dart';

class MiniCPMService {
  // Server URL for WebRTC connection
  String? _serverUrl;
  bool _isConnected = false;
  bool _isNarrating = false;
  bool _isSpeaking = false;

  // WebRTC client for video streaming and data communication
  WebRTCClient? _webrtc;

  // Stream for UI updates
  final StreamController<String> _narrationController =
      StreamController<String>.broadcast();

  // Audio components
  FlutterSoundRecorder? _recorder;
  final List<String> _narrationQueue = [];

  // Speech functionality
  late Future<void> Function(String) _speakSentence;

  // Callbacks to control speech recognition while narrating
  Function()? onBeforeSpeakNarration;
  Function()? onAfterSpeakNarration;

  // Set the TTS function from outside
  set speakSentenceFunction(Future<void> Function(String) fn) {
    _speakSentence = fn;
  }

  // Camera controller reference
  CameraController? _cameraController;

  // Public getters
  Stream<String> get narrationStream => _narrationController.stream;
  bool get isNarrating => _isNarrating;
  bool get isConnected => _isConnected;

  // Expose WebRTC renderer for preview
  RTCVideoRenderer? get localVideoRenderer => _webrtc?.localRenderer;

  // Constructor
  MiniCPMService() {
    _initRecorder();
  }

  // Initialize audio recorder
  Future<void> _initRecorder() async {
    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
  }

  // Set the camera controller
  void setCameraController(CameraController controller) {
    _cameraController = controller;
  }

  // Connect to the MiniCPM server (URL validation only)
  // Actual WebRTC connection happens during startNarration
  Future<bool> connect(String serverUrl) async {
    if (_isConnected && _serverUrl == serverUrl) {
      debugPrint('MiniCPMService: Already set to use server at $serverUrl');
      return true;
    }

    // Reset any existing WebRTC connection if server URL changes or if we are re-connecting
    if (_webrtc != null) {
      await stopNarration(
        informServer: false,
      ); // Ensure existing WebRTC is cleaned up
      _webrtc = null;
    }

    debugPrint('MiniCPMService: Setting server URL to $serverUrl');

    try {
      // Just validate URL format
      Uri.parse(serverUrl);
      _serverUrl = serverUrl;
      // _isConnected here means the service is configured with a server URL.
      // Actual WebRTC connection state is managed by _webrtc.
      _isConnected = true;
      debugPrint(
        'MiniCPMService: Server URL set to $serverUrl. Ready to start narration.',
      );
      return true;
    } catch (e) {
      debugPrint('MiniCPMService: Invalid server URL format: $e');
      _serverUrl = null;
      _isConnected = false;
      return false;
    }
  }

  // Start live narration
  Future<bool> startNarration() async {
    if (!_isConnected || _cameraController == null) {
      debugPrint(
        'MiniCPMService: Cannot start narration - not connected or camera not ready.',
      );
      _narrationController.addError('Not connected or camera not ready.');
      return false;
    }
    if (_isNarrating) {
      debugPrint('MiniCPMService: Narration already active.');
      return true;
    }

    _isNarrating = true;

    // ─── WebRTC video streaming path ─────────────────────────────
    if (_serverUrl == null) {
      debugPrint('MiniCPMService: serverUrl unavailable – cannot start WebRTC');
      _isNarrating = false;
      return false;
    }

    try {
      _webrtc = WebRTCClient(serverUrl: _serverUrl!);

      // Set up message handler for WebRTC data channel
      _webrtc!.onMessage = _handleWebRTCMessage;
      _webrtc!.onDataChannelStateChange = _handleDataChannelStateChange;

      await _webrtc!.initialize();
      await _webrtc!.connect();

      // Wait for data channel to be ready
      await _webrtc!.onDataChannelOpen.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Data channel setup timeout'),
      );

      // Send start narration message
      final success = await _webrtc!.sendMessage({
        'type': 'start_narration',
        'client_id': 'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
      });

      if (!success) {
        debugPrint('MiniCPMService: Failed to send start_narration message.');
        _isNarrating = false;
        // Optionally, clean up WebRTC connection here or throw an error
        return false;
      }

      debugPrint('MiniCPMService: WebRTC streaming and data channel started');
    } catch (e) {
      debugPrint('MiniCPMService: Failed to start WebRTC: $e');
      _isNarrating = false;
      return false;
    }

    debugPrint(
      '🎬 MiniCPMService: Narration started with WebRTC video streaming.',
    );
    return true;
  } // Process the queue of narrations for TTS

  void _processNarrationQueue() async {
    if (_isSpeaking || _narrationQueue.isEmpty) return;
    _isSpeaking = true;

    while (_narrationQueue.isNotEmpty) {
      final narration = _narrationQueue.removeAt(0);
      await speakSentence(narration);
    }

    _isSpeaking = false;
  }

  // Speak a single sentence with wake word control
  Future<void> speakSentence(String sentence) async {
    if (sentence.isEmpty) return Future.value();

    // Pause wake word listening before speech
    onBeforeSpeakNarration?.call();

    try {
      await _speakSentence(sentence);
    } finally {
      // Resume wake word listening after speech
      onAfterSpeakNarration?.call();
    }
  }

  // Handle messages from WebRTC data channel
  void _handleWebRTCMessage(dynamic message) {
    if (message is String) {
      // Handle plain text messages (fallback)
      debugPrint('MiniCPMService: Received text message: $message');
      _narrationController.add(message);
      _narrationQueue.add(message);
      _processNarrationQueue();
      return;
    }

    try {
      // Handle JSON messages
      final Map<String, dynamic> data = message as Map<String, dynamic>;
      final String type = data['type'] as String? ?? 'unknown';

      switch (type) {
        case 'narration':
          // Try to get text from either full_text or text field
          String narrationText = data['full_text'] as String? ?? data['text'] as String? ?? '';
          
          if (narrationText.isNotEmpty) {
            debugPrint('MiniCPMService: Received narration: $narrationText');
            _narrationController.add(narrationText);

            // Add narration to the queue for TTS playback
            _narrationQueue.add(narrationText.trim());
            _processNarrationQueue();
          }
          break;

        case 'token':
          // Legacy support for token-based streaming (in case server still sends tokens)
          final String token = data['token'] as String? ?? '';
          final bool isFinal = data['is_final'] as bool? ?? false;

          if (token.isNotEmpty) {
            _narrationController.add(token);

            // If this is a complete sentence, add to TTS queue
            if (isFinal) {
              _narrationQueue.add(token.trim());
              _processNarrationQueue();
            }
          }
          break;

        case 'error':
          final String error = data['message'] as String? ?? 'Unknown error';
          debugPrint('MiniCPMService: Error from server: $error');
          _narrationController.addError(error);
          break;

        default:
          debugPrint('MiniCPMService: Unknown message type: $type');
          debugPrint('Message content: $data');
      }
    } catch (e) {
      debugPrint('MiniCPMService: Error processing message: $e');
      debugPrint('Raw message: $message');
    }
  }

  // Handle WebRTC data channel state changes
  void _handleDataChannelStateChange(RTCDataChannelState state) {
    debugPrint('MiniCPMService: Data channel state: $state');

    switch (state) {
      case RTCDataChannelState.RTCDataChannelOpen:
        debugPrint(
          'MiniCPMService: Data channel open - ready for communication',
        );
        break;

      case RTCDataChannelState.RTCDataChannelClosed:
      case RTCDataChannelState.RTCDataChannelClosing:
        debugPrint('MiniCPMService: Data channel closing/closed');
        // If channel closes unexpectedly during narration, stop narration
        if (_isNarrating) {
          stopNarration();
        }
        break;

      default:
        // Other states like connecting - no special handling needed
        break;
    }
  }

  // Stop live narration
  Future<void> stopNarration({bool informServer = true}) async {
    if (!_isNarrating) return;

    _isNarrating = false;
    _isSpeaking = false;

    debugPrint('🎬 MiniCPMService: Stopping narration');

    // Clear narration queue
    _narrationQueue.clear();

    // Stop WebRTC streaming + clean up resources
    if (_webrtc != null) {
      // Send end stream request through data channel instead of WebSocket
      try {
        await _webrtc!.sendMessage({'type': 'end_stream'});
        debugPrint('MiniCPMService: End stream request sent via data channel');
      } catch (e) {
        debugPrint('MiniCPMService: Error sending end stream request: $e');
      }

      // Wait a brief moment for the message to be sent before disposing
      await Future.delayed(const Duration(milliseconds: 500));

      // Dispose of WebRTC resources
      _webrtc?.dispose();
      _webrtc = null;
    }

    debugPrint('MiniCPMService: Narration stopped.');
  }

  // Ask a question about the scene
  Future<void> askQuestion(String question) async {
    if (_webrtc == null) {
      // Check WebRTC client
      debugPrint(
        'MiniCPMService: Cannot ask question - WebRTC client not initialized.',
      );
      _narrationController.addError('Not connected to server (WebRTC).');
      return;
    }

    final success = await _webrtc!.sendMessage({
      // Use WebRTC data channel
      'type': 'question',
      'text': question,
    });
    if (success) {
      debugPrint('MiniCPMService: Sent question via data channel: $question');
    } else {
      debugPrint('MiniCPMService: Failed to send question via data channel.');
      _narrationController.addError(
        'Failed to send question. Check connection.',
      );
    }
  }

  // Disconnect from server
  // Disconnect from server (primarily means stopping WebRTC and narration)
  Future<void> disconnect() async {
    // Made async due to stopNarration
    await stopNarration(informServer: true); // This handles WebRTC cleanup

    _isConnected =
        false; // Reflects that we are not actively trying to narrate/connect
    _serverUrl = null; // Clear server URL
    debugPrint(
      'MiniCPMService: Disconnected. WebRTC resources released via stopNarration.',
    );
  }

  // Dispose resources
  Future<void> dispose() async {
    // Made async due to stopNarration
    await stopNarration(
      informServer: true,
    ); // This handles WebRTC cleanup and queue clearing

    _narrationController.close();
    _recorder?.closeRecorder();
    _recorder = null;
    debugPrint('MiniCPMService: Disposed.');
  }
}
