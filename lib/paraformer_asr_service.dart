import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

typedef AsrTranscriptCallback = void Function(String text, bool isFinal);
typedef AsrStatusCallback = void Function(String status);
typedef AsrErrorCallback = void Function(String message);

const bool kParaformerAsrDebugLogs = false;

void _paraformerDebugLog(String message) {
  if (kParaformerAsrDebugLogs) debugPrint(message);
}

class ParaformerAsrService {
  static const String _dashScopeApiKey = String.fromEnvironment(
    'DASHSCOPE_API_KEY',
    defaultValue: String.fromEnvironment('QWEN_API_KEY'),
  );
  static const String _endpoint =
      'wss://dashscope.aliyuncs.com/api-ws/v1/inference';

  final AudioRecorder _recorder = AudioRecorder();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _taskStarted;
  Completer<void>? _taskFinished;
  AsrTranscriptCallback? _onTranscript;
  AsrStatusCallback? _onStatus;
  AsrErrorCallback? _onError;
  String? _taskId;
  bool _active = false;
  bool _stopping = false;

  bool get isActive => _active;

  Future<void> start({
    required AsrTranscriptCallback onTranscript,
    required AsrStatusCallback onStatus,
    required AsrErrorCallback onError,
  }) async {
    if (_active) return;
    if (_dashScopeApiKey.isEmpty) {
      throw const ParaformerAsrException(
        '缺少 DASHSCOPE_API_KEY 或 QWEN_API_KEY，无法启动云端语音识别。',
      );
    }
    if (!await _recorder.hasPermission()) {
      throw const ParaformerAsrException('麦克风权限未开启。');
    }

    _onTranscript = onTranscript;
    _onStatus = onStatus;
    _onError = onError;
    _taskId = _newUuid();
    _taskStarted = Completer<void>();
    _taskFinished = Completer<void>();
    _stopping = false;
    _onStatus?.call('正在连接阿里云语音识别');

    try {
      final socket = await WebSocket.connect(
        _endpoint,
        headers: {
          'Authorization': 'Bearer $_dashScopeApiKey',
          'user-agent': 'yuqiao-flutter/0.1.0',
        },
      ).timeout(const Duration(seconds: 12));
      _socket = socket;
      _active = true;
      _socketSubscription = socket.listen(
        _handleServerMessage,
        onError: (Object error, StackTrace stackTrace) {
          _fail('WebSocket 连接错误：$error');
        },
        onDone: () {
          if (_active && !_stopping) {
            _fail('云端语音连接已断开，请重新开启对话模式。');
          }
        },
        cancelOnError: false,
      );

      socket.add(jsonEncode(_runTaskMessage(_taskId!)));
      await _taskStarted!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const ParaformerAsrException(
          '等待 Paraformer 启动任务超时。',
        ),
      );

      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          streamBufferSize: 3200,
        ),
      );
      _audioSubscription = audioStream.listen(
        (chunk) {
          if (_active && !_stopping && chunk.isNotEmpty) {
            _socket?.add(chunk);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _fail('麦克风音频流错误：$error');
        },
        cancelOnError: false,
      );
      _onStatus?.call('正在聆听');
      _paraformerDebugLog('[Paraformer ASR] streaming task=$_taskId');
    } catch (error) {
      await _cleanup();
      if (error is ParaformerAsrException) rethrow;
      throw ParaformerAsrException('启动云端语音识别失败：$error');
    }
  }

  Future<void> stop() async {
    if (!_active && _socket == null) return;
    _stopping = true;
    _onStatus?.call('正在结束语音识别');

    try {
      await _recorder.stop();
    } catch (error) {
      _paraformerDebugLog('[Paraformer ASR] recorder stop failed: $error');
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    final socket = _socket;
    final taskId = _taskId;
    if (socket != null && taskId != null && _taskStarted?.isCompleted == true) {
      socket.add(jsonEncode(_finishTaskMessage(taskId)));
      try {
        await _taskFinished?.future.timeout(const Duration(seconds: 4));
      } catch (_) {
        // Closing the socket is still required when the final event is delayed.
      }
    }
    await _cleanup();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }

  void _handleServerMessage(dynamic data) {
    if (data is! String) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      final header = decoded['header'];
      if (header is! Map<String, dynamic>) return;
      final event = header['event']?.toString();
      _paraformerDebugLog('[Paraformer ASR] event=$event');

      switch (event) {
        case 'task-started':
          if (_taskStarted?.isCompleted == false) {
            _taskStarted!.complete();
          }
          break;
        case 'result-generated':
          final payload = decoded['payload'];
          final output =
              payload is Map<String, dynamic> ? payload['output'] : null;
          final sentence =
              output is Map<String, dynamic> ? output['sentence'] : null;
          if (sentence is Map<String, dynamic> &&
              sentence['heartbeat'] != true) {
            final text = sentence['text']?.toString().trim() ?? '';
            final isFinal = sentence['sentence_end'] == true;
            if (text.isNotEmpty) {
              _paraformerDebugLog(
                '[Paraformer ASR] result final=$isFinal chars=${text.length}',
              );
              _onTranscript?.call(text, isFinal);
            }
          }
          break;
        case 'task-finished':
          if (_taskFinished?.isCompleted == false) {
            _taskFinished!.complete();
          }
          break;
        case 'task-failed':
          final code = header['error_code']?.toString() ?? 'unknown';
          final message = header['error_message']?.toString() ?? data;
          final error = 'Paraformer 任务失败：$code $message';
          if (_taskStarted?.isCompleted == false) {
            _taskStarted!.completeError(ParaformerAsrException(error));
          }
          _fail(error);
          break;
      }
    } catch (error) {
      _paraformerDebugLog('[Paraformer ASR] invalid event: $error data=$data');
    }
  }

  void _fail(String message) {
    if (!_active || _stopping) return;
    _paraformerDebugLog('[Paraformer ASR] $message');
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
    _taskId = null;
    _taskStarted = null;
    _taskFinished = null;
    _stopping = false;
  }

  Map<String, dynamic> _runTaskMessage(String taskId) => {
        'header': {
          'action': 'run-task',
          'task_id': taskId,
          'streaming': 'duplex',
        },
        'payload': {
          'task_group': 'audio',
          'task': 'asr',
          'function': 'recognition',
          'model': 'paraformer-realtime-v2',
          'parameters': {
            'format': 'pcm',
            'sample_rate': 16000,
            'language_hints': ['zh'],
            'semantic_punctuation_enabled': false,
            // 较短阈值可及时提交句尾。即使失语用户的长停顿造成分段，
            // 后续仍会作为连续上下文交给 Qwen，不会丢失表达内容。
            'max_sentence_silence': 1500,
            'punctuation_prediction_enabled': true,
            'heartbeat': true,
          },
          'input': <String, dynamic>{},
        },
      };

  Map<String, dynamic> _finishTaskMessage(String taskId) => {
        'header': {
          'action': 'finish-task',
          'task_id': taskId,
          'streaming': 'duplex',
        },
        'payload': {
          'input': <String, dynamic>{},
        },
      };

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

class ParaformerAsrException implements Exception {
  const ParaformerAsrException(this.message);

  final String message;

  @override
  String toString() => message;
}
