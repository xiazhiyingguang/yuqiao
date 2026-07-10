import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class XfyunTranscriptEvent {
  const XfyunTranscriptEvent({
    required this.segmentId,
    required this.text,
    required this.isFinal,
    required this.speakerId,
  });

  final String segmentId;
  final String text;
  final bool isFinal;
  final int speakerId;
}

typedef XfyunTranscriptCallback = void Function(XfyunTranscriptEvent event);
typedef XfyunStatusCallback = void Function(String status);
typedef XfyunErrorCallback = void Function(String message);

const bool kXfyunAsrDebugLogs = false;

void _xfyunDebugLog(String message) {
  if (kXfyunAsrDebugLogs) debugPrint(message);
}

class XfyunRealtimeAsrService {
  static const String _appId = String.fromEnvironment('XFYUN_APP_ID');
  static const String _apiKey = String.fromEnvironment('XFYUN_API_KEY');
  static const String _apiSecret = String.fromEnvironment('XFYUN_API_SECRET');
  static const String _proxyUrl = String.fromEnvironment(
    'YUQIAO_XFYUN_PROXY_WS_URL',
  );
  static const String _endpoint =
      'wss://office-api-ast-dx.iflyaisol.com/ast/communicate/v1';
  static const String _proxyToken = String.fromEnvironment(
    'YUQIAO_PROXY_TOKEN',
  );
  static const int _frameSize = 1280;

  final AudioRecorder _recorder = AudioRecorder();
  final List<int> _pendingAudio = [];
  final Set<String> _finalSegmentIds = {};

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _finished;
  XfyunTranscriptCallback? _onTranscript;
  XfyunStatusCallback? _onStatus;
  XfyunErrorCallback? _onError;
  String? _sessionId;
  String? _requestId;
  int _lastSpeakerId = 0;
  bool _active = false;
  bool _stopping = false;

  bool get isActive => _active;

  Future<void> start({
    required XfyunTranscriptCallback onTranscript,
    required XfyunStatusCallback onStatus,
    required XfyunErrorCallback onError,
  }) async {
    if (_active) return;
    final usesProxy = _proxyUrl.trim().isNotEmpty;
    if (!usesProxy &&
        (_appId.isEmpty || _apiKey.isEmpty || _apiSecret.isEmpty)) {
      throw const XfyunAsrException(
        '缺少 XFYUN_APP_ID、XFYUN_API_KEY、XFYUN_API_SECRET 或 YUQIAO_XFYUN_PROXY_WS_URL。',
      );
    }
    if (!await _recorder.hasPermission()) {
      throw const XfyunAsrException('麦克风权限未开启。');
    }

    _onTranscript = onTranscript;
    _onStatus = onStatus;
    _onError = onError;
    _requestId = _newUuid();
    _sessionId = null;
    _lastSpeakerId = 0;
    _pendingAudio.clear();
    _finalSegmentIds.clear();
    _finished = Completer<void>();
    _stopping = false;
    _onStatus?.call('正在连接讯飞实时转写');

    try {
      final socket = await WebSocket.connect(
        usesProxy ? _proxyUrl : _buildAuthenticatedUrl(_requestId!),
        headers: {
          if (usesProxy && _proxyToken.trim().isNotEmpty)
            'Authorization': 'Bearer $_proxyToken',
          'user-agent': 'yuqiao-flutter/0.1.0',
        },
      ).timeout(const Duration(seconds: 12));
      _socket = socket;
      _active = true;
      _socketSubscription = socket.listen(
        _handleServerMessage,
        onError: (Object error, StackTrace stackTrace) {
          _fail('讯飞 WebSocket 连接错误：$error');
        },
        onDone: () {
          if (_finished?.isCompleted == false) _finished!.complete();
          if (_active && !_stopping) {
            _fail('讯飞实时转写连接已断开，请重新开启对话模式。');
          }
        },
        cancelOnError: false,
      );

      // WebSocket.connect completing means the protocol handshake succeeded.
      // Some Xfyun sessions do not emit a separate `started` event until audio
      // arrives, so waiting for that event before recording creates a deadlock.
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          streamBufferSize: _frameSize,
        ),
      );
      _audioSubscription = audioStream.listen(
        _handleAudioChunk,
        onError: (Object error, StackTrace stackTrace) {
          _fail('麦克风音频流错误：$error');
        },
        cancelOnError: false,
      );
      _onStatus?.call('正在聆听并区分说话者');
      _xfyunDebugLog('[Xfyun ASR] streaming request=$_requestId');
    } catch (error) {
      await _cleanup();
      if (error is XfyunAsrException) rethrow;
      throw XfyunAsrException('启动讯飞实时转写失败：$error');
    }
  }

  Future<void> stop() async {
    if (!_active && _socket == null) return;
    _stopping = true;
    _onStatus?.call('正在结束讯飞实时转写');

    try {
      await _recorder.stop();
    } catch (error) {
      _xfyunDebugLog('[Xfyun ASR] recorder stop failed: $error');
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    final socket = _socket;
    if (socket != null) {
      if (_pendingAudio.isNotEmpty) {
        socket.add(Uint8List.fromList(_pendingAudio));
        _pendingAudio.clear();
      }
      socket.add(jsonEncode({
        'end': true,
        'sessionId': _sessionId ?? _requestId,
      }));
      try {
        await _finished?.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        // The socket still needs closing when the final frame is delayed.
      }
    }
    await _cleanup();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }

  void _handleAudioChunk(Uint8List chunk) {
    if (!_active || _stopping || chunk.isEmpty) return;
    _pendingAudio.addAll(chunk);
    while (_pendingAudio.length >= _frameSize) {
      final frame = Uint8List.fromList(_pendingAudio.sublist(0, _frameSize));
      _pendingAudio.removeRange(0, _frameSize);
      _socket?.add(frame);
    }
  }

  void _handleServerMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final event =
          decoded['action']?.toString() ?? decoded['msg_type']?.toString();
      final code = decoded['code']?.toString();
      _xfyunDebugLog('[Xfyun ASR] event=$event code=$code');

      if (event == 'error' || (code != null && code != '0')) {
        final message = decoded['desc']?.toString() ?? raw;
        _fail('讯飞实时转写失败：${code ?? 'unknown'} $message');
        return;
      }
      if (event == 'started') {
        _sessionId = decoded['sid']?.toString() ??
            decoded['sessionId']?.toString() ??
            _sessionIdFrom(decoded['data']);
        return;
      }
      if (event != 'result') return;

      final data = _asMap(decoded['data']);
      if (data == null) return;
      _sessionId ??= decoded['sid']?.toString() ??
          data['sessionId']?.toString() ??
          data['sid']?.toString();
      _handleRecognitionData(data);
      if (data['ls'] == true && _finished?.isCompleted == false) {
        _finished!.complete();
      }
    } catch (error) {
      _xfyunDebugLog('[Xfyun ASR] invalid message: $error');
    }
  }

  void _handleRecognitionData(Map<String, dynamic> data) {
    final cn = _asMap(data['cn']);
    final st = _asMap(cn?['st']);
    if (st == null) return;
    final isFinal = st['type']?.toString() == '0';
    final segmentId = data['seg_id']?.toString() ??
        st['bg']?.toString() ??
        '${st['bg'] ?? 'live'}-${st['ed'] ?? 'open'}';
    if (isFinal && !_finalSegmentIds.add(segmentId)) {
      return;
    }

    final grouped = <int, StringBuffer>{};
    final rtItems = st['rt'];
    if (rtItems is! List) return;
    for (final rtValue in rtItems) {
      final rt = _asMap(rtValue);
      final words = rt?['ws'];
      if (words is! List) continue;
      for (final wordValue in words) {
        final word = _asMap(wordValue);
        final candidates = word?['cw'];
        if (candidates is! List || candidates.isEmpty) continue;
        final candidate = _asMap(candidates.first);
        if (candidate == null) continue;
        final role = _asInt(candidate['rl']);
        if (role != null && role > 0) _lastSpeakerId = role;
        final speakerId = _lastSpeakerId > 0 ? _lastSpeakerId : 1;
        final text = candidate['w']?.toString() ?? '';
        if (text.isNotEmpty) {
          grouped.putIfAbsent(speakerId, StringBuffer.new).write(text);
        }
      }
    }

    for (final entry in grouped.entries) {
      final text = entry.value.toString().trim();
      if (text.isNotEmpty) {
        _onTranscript?.call(XfyunTranscriptEvent(
          segmentId: '$segmentId-${entry.key}',
          text: text,
          isFinal: isFinal,
          speakerId: entry.key,
        ));
      }
    }
  }

  String _buildAuthenticatedUrl(String requestId) {
    final params = <String, String>{
      'accessKeyId': _apiKey,
      'appId': _appId,
      'audio_encode': 'pcm_s16le',
      'eng_vad_mdn': '1',
      'lang': 'autodialect',
      'role_type': '2',
      'samplerate': '16000',
      'utc': _formattedLocalTime(DateTime.now()),
      'uuid': requestId,
    };
    final sortedKeys = params.keys.toList()..sort();
    final baseString = sortedKeys.map((key) {
      return '${Uri.encodeQueryComponent(key)}='
          '${Uri.encodeQueryComponent(params[key]!)}';
    }).join('&');
    final signature = base64Encode(
      Hmac(sha1, utf8.encode(_apiSecret))
          .convert(utf8.encode(baseString))
          .bytes,
    );
    final query = [
      baseString,
      'signature=${Uri.encodeQueryComponent(signature)}',
    ].join('&');
    return '$_endpoint?$query';
  }

  String _formattedLocalTime(DateTime value) {
    final offset = value.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${two(value.month)}-${two(value.day)}T'
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}'
        '$sign$hours$minutes';
  }

  String? _sessionIdFrom(dynamic value) {
    final data = _asMap(value);
    return data?['sessionId']?.toString() ?? data?['sid']?.toString();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  void _fail(String message) {
    if (!_active || _stopping) return;
    _xfyunDebugLog('[Xfyun ASR] $message');
    _onError?.call(message);
    unawaited(_cleanup());
  }

  Future<void> _cleanup() async {
    _active = false;
    _stopping = true;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      await _socket?.close(WebSocketStatus.normalClosure);
    } catch (_) {}
    _socket = null;
    _pendingAudio.clear();
    _requestId = null;
    _sessionId = null;
    _finished = null;
    _stopping = false;
  }

  String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}

class XfyunAsrException implements Exception {
  const XfyunAsrException(this.message);

  final String message;

  @override
  String toString() => message;
}
