// lib/services/webrtc_client.dart
// Lightweight wrapper around flutter_webrtc to stream the phone camera to the
// unified omni_server.py backend via WebRTC.
//
// Usage:
//   final webrtc = WebRTCClient(serverUrl: "http://<SERVER-IP>:8123");
//   await webrtc.initialize();            // request camera / mic & open PC
//   await webrtc.connect();               // exchanges SDP with server
//   //  Optionally bind webrtc.localRenderer to a RTCVideoView widget for preview
//   ...
//   webrtc.dispose();
//
// The omni_server uses aiortc and a single /offer HTTP endpoint that expects a
// JSON body of {"sdp": "...", "type": "offer"}.  It returns the answer in the
// same structure.  No trickle-ICE; we wait for ICE gathering to complete before
// posting.

import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Needed for HttpHeaders, HttpException
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
// import 'package:path_provider/path_provider.dart'; // No longer needed
import 'dart:typed_data'; // Still needed for Uint8List
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart'; // For frame hashing

class WebRTCClient {
  WebRTCClient({required this.serverUrl});

  final String serverUrl; // e.g. "http://10.0.2.2:8123"
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCDataChannel? _dataChannel;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  // Callback for data channel messages
  Function(dynamic)? onMessage;
  // Callback for data channel state changes
  Function(RTCDataChannelState)? onDataChannelStateChange;

  // Completer to signal data channel readiness
  final Completer<void> _dataChannelOpenCompleter = Completer<void>();
  Future<void> get onDataChannelOpen => _dataChannelOpenCompleter.future;

  // Frame debugging variables
  String? _lastFrameHash;
  int _frameCount = 0;
  int _duplicateFrameCount = 0;
  Timer? _frameDebugTimer;

  Future<void> initialize() async {
    await localRenderer.initialize();

    // Request camera (video only) — mic not needed for narration.
    final Map<String, dynamic> mediaConstraints = {
      'audio': false,
      'video': {
        'facingMode': 'environment',
        // iPhone-compatible resolution - step down from 480x640
        'width': {'ideal': 360, 'max': 360},
        'height': {'ideal': 480, 'max': 480},
        'frameRate': {'ideal': 30, 'max': 30},
      },
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = _localStream;

    // Create peer connection
    final Map<String, dynamic> pcConfig = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    _pc = await createPeerConnection(pcConfig);

    // Set up data channel event listener
    _pc!.onDataChannel = _handleDataChannel; // Add the camera track
    for (var track in _localStream!.getTracks()) {
      debugPrint('WebRTCClient: Adding track kind=${track.kind}');
      await _pc!.addTrack(track, _localStream!);
    }

    // Create data channel from client side
    await _createDataChannel();
  }

  // Create a data channel for communication
  Future<void> _createDataChannel() async {
    if (_pc == null) return;

    final RTCDataChannelInit dataChannelInit = RTCDataChannelInit();
    dataChannelInit.ordered = true; // Ensure messages arrive in order

    _dataChannel = await _pc!.createDataChannel('narration', dataChannelInit);
    _setupDataChannel(_dataChannel!);

    debugPrint('WebRTCClient: Data channel created');
  }

  Future<void> connect() async {
    if (_pc == null) {
      throw StateError('initialize() must be called first');
    }

    // Disable trickle ICE by waiting until gathering is complete
    Completer<void> iceGatheringCompleter = Completer();
    _pc!.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !iceGatheringCompleter.isCompleted) {
        iceGatheringCompleter.complete();
      }
    };

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    // Wait until ICE gathering is done to send full SDP
    await iceGatheringCompleter.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );

    final localDesc = await _pc!.getLocalDescription();

    final uri = Uri.parse('$serverUrl/offer');
    final response = await http.post(
      uri,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({'sdp': localDesc!.sdp, 'type': localDesc.type}),
    );

    if (response.statusCode != 200) {
      throw HttpException('Failed to obtain answer: ${response.statusCode}');
    }

    final Map<String, dynamic> answerJson = jsonDecode(response.body);
    await _pc!.setRemoteDescription(
      RTCSessionDescription(answerJson['sdp'], answerJson['type']),
    );
  }

  // Handle incoming data channel from server
  void _handleDataChannel(RTCDataChannel channel) {
    debugPrint(
      'WebRTCClient: Received data channel from server: ${channel.label}',
    );

    if (channel.label == 'narration') {
      _dataChannel = channel;
      _setupDataChannel(channel);
    } else {
      debugPrint('WebRTCClient: Unknown data channel: ${channel.label}');
      _setupDataChannel(channel); // Still set up the channel even if unknown
    }
  }

  // Configure data channel event handlers
  void _setupDataChannel(RTCDataChannel channel) {
    channel.onMessage = (RTCDataChannelMessage message) {
      // Try to parse as JSON first
      try {
        final dynamic data = jsonDecode(message.text);
        debugPrint(
          'WebRTCClient: Received message: ${message.text.substring(0, min(30, message.text.length))}...',
        );
        if (onMessage != null) {
          onMessage!(data);
        }
      } catch (e) {
        debugPrint('WebRTCClient: Error parsing message: $e');
        // If not JSON, pass the raw text
        if (onMessage != null) {
          onMessage!(message.text);
        }
      }
    };

    channel.onDataChannelState = (RTCDataChannelState state) {
      debugPrint('WebRTCClient: Data channel state changed to: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        debugPrint('WebRTCClient: Data channel is now open!');
        if (!_dataChannelOpenCompleter.isCompleted) {
          _dataChannelOpenCompleter.complete();
        }
      }
      if (onDataChannelStateChange != null) {
        onDataChannelStateChange!(state);
      }
    };
  }

  // Send a message through the data channel
  Future<bool> sendMessage(dynamic message) async {
    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        // Convert to JSON string if it's not already a string
        final String messageStr =
            message is String ? message : jsonEncode(message);
        _dataChannel!.send(RTCDataChannelMessage(messageStr));
        return true;
      } catch (e) {
        debugPrint('WebRTCClient: Error sending message: $e');
        return false;
      }
    } else {
      debugPrint(
        'WebRTCClient: Cannot send message - data channel not open or null',
      );
      return false;
    }
  }

  Future<Uint8List?> captureFrameFromLocalStream() async {
    if (_localStream == null || _localStream!.getVideoTracks().isEmpty) {
      debugPrint(
        'WebRTCClient: No local video stream or video track available to capture frame.',
      );
      return null;
    }
    final videoTrack = _localStream!.getVideoTracks()[0];
    try {
      final ByteBuffer? frameBuffer = await videoTrack.captureFrame();
      if (frameBuffer != null) {
        final Uint8List frame = frameBuffer.asUint8List();
        final String frameHash = sha256.convert(frame).toString();
        if (_lastFrameHash != null && _lastFrameHash == frameHash) {
          _duplicateFrameCount++;
        } else {
          _lastFrameHash = frameHash;
          _frameCount++;
        }
        debugPrint(
          'WebRTCClient: Captured frame ${_frameCount} (duplicates: ${_duplicateFrameCount})',
        );
        if (_frameDebugTimer == null) {
          _frameDebugTimer = Timer.periodic(const Duration(seconds: 1), (
            timer,
          ) {
            debugPrint(
              'WebRTCClient: Frame capture stats: ${_frameCount} frames, ${_duplicateFrameCount} duplicates',
            );
          });
        }
        return frame;
      } else {
        debugPrint('WebRTCClient: Frame capture returned null buffer.');
        return null;
      }
    } catch (e) {
      debugPrint('WebRTCClient: Error capturing frame from local stream: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    // Close the data channel
    if (_dataChannel != null) {
      _dataChannel!.close();
      _dataChannel = null;
      debugPrint('WebRTCClient: Data channel closed');
    }

    // Stop all tracks
    if (_localStream != null) {
      final tracks = _localStream!.getTracks();
      debugPrint('WebRTCClient: Stopping ${tracks.length} tracks');
      for (var track in tracks) {
        await track.stop();
      }
    }

    // Close the peer connection
    if (_pc != null) {
      debugPrint('WebRTCClient: Closing peer connection');
      await _pc!.close();
      _pc = null;
    }

    // Release the renderer
    if (localRenderer.srcObject != null) {
      localRenderer.srcObject = null;
      await localRenderer.dispose();
      debugPrint('WebRTCClient: Disposed renderer');
    }

    _localStream = null;
    debugPrint('WebRTCClient: All resources released');
  }
}
