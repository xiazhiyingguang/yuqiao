part of 'main.dart';

class CameraWordPage extends StatefulWidget {
  const CameraWordPage({
    super.key,
    required this.qwenService,
    required this.locationController,
    required this.companionAgent,
    required this.personalizedLearningEnabled,
    required this.vocabularyEntries,
    required this.personalObjects,
    required this.expressionHabits,
    required this.personalObjectStore,
    required this.featureLauncher,
    required this.onPersonalObjectsChanged,
    required this.onHabitRecorded,
    required this.onVocabularyChanged,
    required this.onExpressionCompleted,
    required this.onFavoriteSaved,
  });

  final QwenService qwenService;
  final LocationRecommendationController locationController;
  final CompanionAgentController companionAgent;
  final bool personalizedLearningEnabled;
  final List<VocabularyEntry> vocabularyEntries;
  final List<PersonalObject> personalObjects;
  final List<ExpressionHabit> expressionHabits;
  final PersonalObjectStore personalObjectStore;
  final YuqiaoFeatureLauncher featureLauncher;
  final Future<void> Function() onPersonalObjectsChanged;
  final HabitRecordCallback onHabitRecorded;
  final VocabularyChangedCallback onVocabularyChanged;
  final ExpressionCallback onExpressionCompleted;
  final ExpressionCallback onFavoriteSaved;

  @override
  State<CameraWordPage> createState() => _CameraWordPageState();
}

class _CameraWordPageState extends State<CameraWordPage> {
  static const _galleryChannel =
      MethodChannel('com.example.yuqiao_app/gallery');
  static const double _cameraControlsClearance = 176;
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();
  final LocalObjectLocator _localObjectLocator = LocalObjectLocator();
  Future<ObjectRecognition>? _recognition;
  Uint8List? _imageBytes;
  Uint8List? _frozenPreviewBytes;
  Size? _capturedImageSize;
  ObjectCandidate? _selectedCandidate;
  late List<VocabularyEntry> _localVocabularyEntries;
  late List<PersonalObject> _personalObjects;
  bool _isTakingPhoto = false;
  SensorConfig? _sensorConfig;
  double _pinchBaseZoom = 0.0;
  double _minZoomRatio = 1.0;
  double _maxZoomRatio = 1.0;
  bool _zoomInitialized = false;
  final ValueNotifier<double> _zoomValue = ValueNotifier<double>(0);
  double? _pendingZoom;
  bool _zoomWriteInProgress = false;
  bool _isFrontCamera = false;
  bool _captureWasFrontCamera = false;
  bool _capturedImageMirrored = false;
  int _imageRequestId = 0;
  bool _photoUploadConsentAccepted = false;
  final GlobalKey _resultPanelKey = GlobalKey();
  double _resultPanelHeight = 160;

  // 闪光灯
  FlashMode _flashMode = FlashMode.none;
  bool _flashExpanded = false;

  // 亮度调节
  double _brightness = 0.5;
  bool _isAdjustingBrightness = false;
  final Set<int> _previewPointers = <int>{};
  int? _brightnessPointer;
  Offset _brightnessDrag = Offset.zero;

  void _setFlashMode(FlashMode mode) {
    setState(() {
      _flashMode = mode;
      _flashExpanded = false;
    });
    _sensorConfig?.setFlashMode(mode);
  }

  IconData _flashIcon() {
    switch (_flashMode) {
      case FlashMode.on:
        return Icons.flash_on_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
        return Icons.flashlight_on_rounded;
      case FlashMode.none:
        return Icons.flash_off_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    _localVocabularyEntries = List.of(widget.vocabularyEntries);
    _personalObjects = List.of(widget.personalObjects);
    widget.locationController.refreshLocationContext();
    _tts.setLanguage('zh-CN');
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
    unawaited(_loadPhotoUploadConsent());
  }

  @override
  void dispose() {
    _tts.stop();
    unawaited(_localObjectLocator.close());
    _zoomValue.dispose();
    super.dispose();
  }

  String get _locationTypeContext {
    if (!widget.locationController.enabled) return '未知地点';
    final place = widget.locationController.currentPlace;
    if (place != null) return place.typeLabel;
    final semantic = widget.locationController.currentSemantic;
    return semantic == null ? '未知地点' : PlaceTypeCatalog.labelOf(semantic.type);
  }

  String get _timeContext {
    final now = DateTime.now();
    final period = switch (now.hour) {
      >= 5 && < 11 => '早上',
      >= 11 && < 14 => '中午',
      >= 14 && < 18 => '下午',
      >= 18 && < 24 => '晚上',
      _ => '深夜',
    };
    return '$period ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  Future<ObjectRecognition> _recognizeImage(Uint8List bytes) async {
    final localBoxesFuture = _localObjectLocator.detect(bytes);
    final recognition = await widget.qwenService.recognizeObject(
      bytes,
      personalObjects: _personalObjects,
      locationType: _locationTypeContext,
      timeContext: _timeContext,
    );
    final localBoxes = await localBoxesFuture.catchError(
      (_) => <LocalObjectBox>[],
    );
    final merged = _mergeLocalObjectBoxes(recognition, localBoxes);
    if (merged.candidates.length < 2) return merged;
    try {
      final rankedNames = await widget.companionAgent.rankExpressions(
        merged.candidates.map((candidate) => candidate.objectName).toList(),
        feature: 'camera',
        category: 'camera',
        prompt: '$_locationTypeContext $_timeContext 识别物品',
        slot: RecommendationSlot.actionOrObject,
        includeContextWords: false,
        allowContextExpansion: false,
        limit: merged.candidates.length,
      );
      final rank = <String, int>{
        for (var index = 0; index < rankedNames.length; index++)
          LocationRecommendationController.normalizeText(rankedNames[index]):
              index,
      };
      final candidates = List<ObjectCandidate>.of(merged.candidates)
        ..sort((a, b) {
          final aRank = rank[LocationRecommendationController.normalizeText(
                  a.objectName)] ??
              merged.candidates.length;
          final bRank = rank[LocationRecommendationController.normalizeText(
                  b.objectName)] ??
              merged.candidates.length;
          return aRank.compareTo(bRank);
        });
      return ObjectRecognition(candidates: candidates);
    } catch (error) {
      yuqiaoDebugLog('[Camera] companion ranking skipped: $error');
      return merged;
    }
  }

  ObjectRecognition _mergeLocalObjectBoxes(
    ObjectRecognition recognition,
    List<LocalObjectBox> localBoxes,
  ) {
    if (recognition.candidates.isEmpty || localBoxes.isEmpty) {
      return recognition;
    }
    final merged = <ObjectCandidate>[];
    final usedLocalBoxIndexes = <int>{};
    for (var index = 0; index < recognition.candidates.length; index++) {
      final candidate = recognition.candidates[index];
      final localBoxIndex = _bestLocalBoxIndexForCandidate(
        candidate,
        recognition.candidates.length,
        localBoxes,
        usedLocalBoxIndexes,
      );
      if (localBoxIndex == null) {
        merged.add(candidate);
      } else {
        usedLocalBoxIndexes.add(localBoxIndex);
        final localBox = localBoxes[localBoxIndex];
        merged.add(candidate.copyWith(bbox: localBox.bbox));
      }
    }
    return ObjectRecognition(candidates: merged);
  }

  int? _bestLocalBoxIndexForCandidate(
    ObjectCandidate candidate,
    int candidateCount,
    List<LocalObjectBox> localBoxes,
    Set<int> usedLocalBoxIndexes,
  ) {
    final qwenBox = candidate.bbox;
    if (qwenBox == null || qwenBox.length != 4) {
      if (candidateCount == 1 && !usedLocalBoxIndexes.contains(0)) return 0;
      return null;
    }

    var bestIndex = -1;
    var bestScore = 0.0;
    for (var index = 0; index < localBoxes.length; index++) {
      if (usedLocalBoxIndexes.contains(index)) continue;
      final box = localBoxes[index];
      final overlap = _boxIou(qwenBox, box.bbox);
      final centerScore = _boxCenterScore(qwenBox, box.bbox);
      final sizePenalty = _boxAreaRatioPenalty(qwenBox, box.bbox);
      final score = overlap * 0.62 +
          centerScore * 0.28 +
          box.confidence * 0.10 -
          sizePenalty;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    if (bestIndex < 0 || bestScore < 0.20) return null;
    return bestIndex;
  }

  double _boxIou(List<double> a, List<double> b) {
    final left = math.max(a[0], b[0]);
    final top = math.max(a[1], b[1]);
    final right = math.min(a[2], b[2]);
    final bottom = math.min(a[3], b[3]);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final areaA = math.max(0.0, a[2] - a[0]) * math.max(0.0, a[3] - a[1]);
    final areaB = math.max(0.0, b[2] - b[0]) * math.max(0.0, b[3] - b[1]);
    final union = areaA + areaB - intersection;
    if (union <= 0) return 0;
    return intersection / union;
  }

  double _boxCenterScore(List<double> a, List<double> b) {
    final ax = (a[0] + a[2]) / 2;
    final ay = (a[1] + a[3]) / 2;
    final bx = (b[0] + b[2]) / 2;
    final by = (b[1] + b[3]) / 2;
    final distance = math.sqrt(math.pow(ax - bx, 2) + math.pow(ay - by, 2));
    return (1 - distance / 1414.0).clamp(0.0, 1.0).toDouble();
  }

  double _boxAreaRatioPenalty(List<double> a, List<double> b) {
    final areaA = math.max(1.0, (a[2] - a[0]) * (a[3] - a[1]));
    final areaB = math.max(1.0, (b[2] - b[0]) * (b[3] - b[1]));
    final ratio = areaA > areaB ? areaA / areaB : areaB / areaA;
    if (ratio <= 3.5) return 0;
    return math.min(0.18, (ratio - 3.5) / 20);
  }

  void _resetForRetake() {
    _imageRequestId++;
    setState(() {
      _imageBytes = null;
      _frozenPreviewBytes = null;
      _capturedImageSize = null;
      _capturedImageMirrored = false;
      _recognition = null;
      _selectedCandidate = null;
      _resultPanelHeight = 160;
    });
  }

  Future<void> _speakObject(ObjectCandidate candidate) async {
    unawaited(widget.companionAgent.recordInteraction(
      text: candidate.objectName,
      feature: 'camera',
      action: CompanionFeedbackAction.spoken,
      prompt: candidate.visualDescription,
      slot: RecommendationSlot.actionOrObject,
    ));
    await _speakText(candidate.objectName);
    if (candidate.personalObjectId.isNotEmpty) {
      unawaited(
          widget.personalObjectStore.markUsed(candidate.personalObjectId));
    }
  }

  Future<void> _speakText(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    unawaited(
      widget.onHabitRecorded(
        text,
        category: 'camera',
        source: 'camera_quick_speak',
      ),
    );
    unawaited(widget.onExpressionCompleted(text));
    try {
      await _tts.stop();
      await _tts.speak(text);
      if (mounted) {
        showYuqiaoLearningReceipt(
          context,
          personalizedLearningEnabled: widget.personalizedLearningEnabled,
          learnedMessage: '已播报，语桥会记住这个物品选择',
          disabledMessage: '已播报，个性化学习已关闭',
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('语音播报暂时不可用，请稍后重试。')),
      );
    }
  }

  void _requestZoom(double value) {
    if (!_zoomInitialized || _sensorConfig == null) return;
    final target = value.clamp(0.0, 1.0).toDouble();
    if ((_zoomValue.value - target).abs() > 0.0001) {
      _zoomValue.value = target;
    }
    _pendingZoom = target;
    _drainZoomQueue();
  }

  Future<void> _drainZoomQueue() async {
    if (_zoomWriteInProgress) return;
    _zoomWriteInProgress = true;
    try {
      while (mounted && _pendingZoom != null) {
        final target = _pendingZoom!;
        _pendingZoom = null;
        final sensorConfig = _sensorConfig;
        if (sensorConfig == null) break;
        try {
          await sensorConfig.setZoom(target);
        } catch (_) {
          // A sensor switch can invalidate an in-flight zoom request.
        }
      }
    } finally {
      _zoomWriteInProgress = false;
      if (mounted && _pendingZoom != null) _drainZoomQueue();
    }
  }

  void _onPreviewPointerDown(PointerDownEvent event) {
    _previewPointers.add(event.pointer);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isInsideCameraGestureArea = event.position.dy >= 96 &&
        event.position.dy <= screenHeight - 170 &&
        _imageBytes == null;
    if (!isInsideCameraGestureArea) return;
    if (_previewPointers.length == 1) {
      _brightnessPointer = event.pointer;
      _brightnessDrag = Offset.zero;
    } else {
      _cancelBrightnessGesture();
    }
  }

  void _onPreviewPointerMove(PointerMoveEvent event) {
    if (_previewPointers.length != 1 || event.pointer != _brightnessPointer) {
      return;
    }
    _brightnessDrag += event.delta;
    if (!_isAdjustingBrightness) {
      final isIntentionalVerticalDrag = _brightnessDrag.dy.abs() >= 24 &&
          _brightnessDrag.dy.abs() > _brightnessDrag.dx.abs() * 1.35;
      if (!isIntentionalVerticalDrag) return;
      setState(() => _isAdjustingBrightness = true);
    }

    final nextBrightness =
        (_brightness - event.delta.dy / 400).clamp(0.0, 1.0).toDouble();
    if ((nextBrightness - _brightness).abs() < 0.0001) return;
    setState(() => _brightness = nextBrightness);
    // 直接调用原生 API，绕过 SensorConfig 的 500ms 防抖
    try {
      CamerawesomePlugin.setBrightness(nextBrightness);
    } catch (_) {}
  }

  void _onPreviewPointerUp(PointerEvent event) {
    _previewPointers.remove(event.pointer);
    if (event.pointer == _brightnessPointer || _previewPointers.isEmpty) {
      _cancelBrightnessGesture();
    }
  }

  void _cancelBrightnessGesture() {
    _brightnessPointer = null;
    _brightnessDrag = Offset.zero;
    if (_isAdjustingBrightness && mounted) {
      setState(() => _isAdjustingBrightness = false);
    }
  }

  /// 初始化相机倍率到 1.0x，使用重试机制确保成功
  Future<void> _initZoomToOneX() async {
    if (_zoomInitialized || _sensorConfig == null || !mounted) return;

    // 尝试多次，因为相机管线可能尚未完全就绪
    for (int attempt = 0; attempt < 8; attempt++) {
      if (!mounted || _sensorConfig == null) return;
      try {
        // 直接查询设备的缩放范围
        final minR = await CamerawesomePlugin.getMinZoom();
        final maxR = await CamerawesomePlugin.getMaxZoom();
        if (minR != null && maxR != null && maxR > minR) {
          _minZoomRatio = minR;
          _maxZoomRatio = maxR;
          // 计算 1.0x 光学变焦在 normalized (0-1) 范围中的位置
          if (minR <= 1.0 && maxR >= 1.0) {
            final oneXNormalized =
                ((1.0 - minR) / (maxR - minR)).clamp(0.0, 1.0);
            await _sensorConfig!.setZoom(oneXNormalized);
            _zoomValue.value = oneXNormalized.toDouble();
            _zoomInitialized = true;
            return;
          }
        }
      } catch (_) {}
      // 等待后重试（相机管线可能还没就绪）
      await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }

    // 最终回退
    if (!_zoomInitialized && mounted && _sensorConfig != null) {
      try {
        await _sensorConfig!.setZoom(0.0);
        _zoomValue.value = 0;
        _zoomInitialized = true;
      } catch (_) {}
    }
  }

  Future<void> _captureWithCamerawesome(CameraState state) async {
    if (_isTakingPhoto) {
      return;
    }
    if (_imageBytes != null) {
      setState(() {
        _imageBytes = null;
        _frozenPreviewBytes = null;
        _capturedImageSize = null;
        _capturedImageMirrored = false;
        _recognition = null;
        _selectedCandidate = null;
        _resultPanelHeight = 160;
      });
      return;
    }

    try {
      if (state is PhotoCameraState) {
        await _freezeCurrentPreviewFrame();
        if (!mounted) {
          return;
        }
        setState(() {
          _isTakingPhoto = true;
          _captureWasFrontCamera = _isFrontCamera;
        });
        await state.takePhoto(
          onPhotoFailed: (exception) {
            if (!mounted) {
              return;
            }
            setState(() {
              _isTakingPhoto = false;
              _frozenPreviewBytes = null;
            });
          },
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isTakingPhoto = false;
        _frozenPreviewBytes = null;
      });
    }
  }

  Future<void> _freezeCurrentPreviewFrame() async {
    if (_imageBytes != null || _frozenPreviewBytes != null) return;
    try {
      final previewContext = previewWidgetKey.currentContext;
      final renderObject = previewContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return;
      if (renderObject.debugNeedsPaint) {
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted || _imageBytes != null) return;
      final image = await renderObject.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      if (!mounted || byteData == null || _imageBytes != null) return;
      setState(() {
        _frozenPreviewBytes = byteData.buffer.asUint8List();
      });
    } catch (error) {
      yuqiaoDebugLog('[Camera freeze] preview snapshot skipped: $error');
    }
  }

  Future<void> _handleMediaCapture(MediaCapture mediaCapture) async {
    if (!mediaCapture.isPicture) {
      return;
    }
    if (mediaCapture.status == MediaCaptureStatus.capturing) {
      if (mounted) {
        setState(() {
          _isTakingPhoto = true;
        });
      }
      return;
    }
    if (mediaCapture.status == MediaCaptureStatus.failure) {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _frozenPreviewBytes = null;
        });
      }
      return;
    }
    if (mediaCapture.status != MediaCaptureStatus.success) {
      return;
    }

    final path = mediaCapture.captureRequest.path;
    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _frozenPreviewBytes = null;
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }
    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _isTakingPhoto = false;
      });
      await _startRecognition(bytes, mirrored: _captureWasFrontCamera);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isTakingPhoto = false;
        _frozenPreviewBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('照片处理失败：$error')),
      );
    }
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 76,
      maxWidth: 1280,
    );
    if (picked == null) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (mounted) {
      setState(() => _frozenPreviewBytes = null);
    }
    await _startRecognition(bytes);
  }

  /// 打开系统默认相册（而非文件管理器）
  Future<void> _openDefaultGallery() async {
    try {
      final String? path = await _galleryChannel.invokeMethod('openGallery');
      if (path == null || path.isEmpty) return; // 用户取消
      final bytes = await File(path).readAsBytes();
      if (mounted) {
        setState(() => _frozenPreviewBytes = null);
      }
      await _startRecognition(bytes);
    } catch (e) {
      // 平台通道失败时回退到 image_picker
      await _pick(ImageSource.gallery);
    }
  }

  static const String _photoUploadConsentKey = 'photo_upload_consent_v1';

  Future<void> _loadPhotoUploadConsent() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _photoUploadConsentAccepted =
          prefs.getBool(_photoUploadConsentKey) ?? false;
    });
  }

  Future<bool> _ensurePhotoUploadConsent() async {
    if (_photoUploadConsentAccepted) return true;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('照片识别隐私提示'),
        content: const Text(
          '为了识别照片中的物品，语桥会把本次照片上传到模型服务。'
          '如果开启个人物品匹配，也可能上传相关参考图用于核验。'
          '照片只用于本次识别，不会写入公开内容。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不识别'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_photoUploadConsentKey, true);
    if (mounted) setState(() => _photoUploadConsentAccepted = true);
    return true;
  }

  Future<void> _startRecognition(
    Uint8List bytes, {
    bool mirrored = false,
  }) async {
    final consented = await _ensurePhotoUploadConsent();
    if (!consented) {
      if (mounted) {
        setState(() {
          _isTakingPhoto = false;
          _frozenPreviewBytes = null;
        });
      }
      return;
    }
    final requestId = ++_imageRequestId;
    Uint8List normalizedBytes;
    try {
      normalizedBytes = await compute(normalizeCameraImage, bytes);
    } catch (error) {
      yuqiaoDebugLog('[Camera image] normalization skipped: $error');
      normalizedBytes = bytes;
    }
    if (!mounted || requestId != _imageRequestId) return;
    setState(() {
      _imageBytes = normalizedBytes;
      _frozenPreviewBytes = null;
      _capturedImageSize = null;
      _capturedImageMirrored = mirrored;
      _selectedCandidate = null;
      _resultPanelHeight = 160;
      _recognition = _recognizeImage(normalizedBytes);
    });
    _readCapturedImageSize(normalizedBytes);
  }

  Future<void> _readCapturedImageSize(Uint8List bytes) async {
    try {
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      if (!mounted || !identical(bytes, _imageBytes)) return;
      setState(() => _capturedImageSize = size);
    } catch (_) {
      // Fall back to normalized screen coordinates if metadata cannot be read.
    }
  }

  void _useExpression(
    ObjectCandidate candidate,
    String expression, {
    String? expressionType,
  }) {
    unawaited(widget.companionAgent.recordInteraction(
      text: expression,
      feature: 'camera',
      action: CompanionFeedbackAction.accepted,
      prompt: candidate.objectName,
      slot: RecommendationSlot.sentence,
    ));
    widget.locationController.recordWordUsed(candidate.objectName, 'camera');
    widget.locationController.recordWordUsed(expression, 'camera');
    unawaited(
      widget.onHabitRecorded(
        candidate.objectName,
        category: 'camera',
        source: 'camera_object',
      ),
    );
    unawaited(
      widget.onHabitRecorded(
        expression,
        category: 'camera',
        source: 'camera_expression',
      ),
    );
    final draft = ExpressionDraft(
      source: '拍照找词',
      intent: expressionType == null ? '物品表达' : '物品表达 · $expressionType',
      keywords: [
        candidate.objectName,
        if (expressionType != null) expressionType,
        expression,
      ],
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiCandidatesPage(
          draft: draft,
          qwenService: widget.qwenService,
          personalizedLearningEnabled: widget.personalizedLearningEnabled,
          onCandidateSelected: (text) async {
            unawaited(widget.locationController.recordWordUsed(text, 'camera'));
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'camera',
              action: CompanionFeedbackAction.accepted,
              prompt: candidate.objectName,
              slot: RecommendationSlot.sentence,
            ));
            unawaited(
              widget.onHabitRecorded(
                text,
                category: 'camera',
                source: 'camera_sentence_candidate',
              ),
            );
          },
          onCandidateSaved: (text) async {
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'camera',
              action: CompanionFeedbackAction.saved,
              prompt: candidate.objectName,
              slot: RecommendationSlot.sentence,
            ));
          },
          onExpressionCompleted: widget.onExpressionCompleted,
          onFavoriteSaved: widget.onFavoriteSaved,
        ),
      ),
    );
  }

  Future<bool> _savePersonalObject(ObjectCandidate candidate) async {
    final imageBytes = _imageBytes;
    if (imageBytes == null) return false;
    final suggestedName = candidate.objectName.startsWith('我的')
        ? candidate.objectName
        : '我的${candidate.objectName}';
    final draft = await showModalBottomSheet<PersonalObjectDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PersonalObjectEditSheet(
        initialName: suggestedName,
        initialCategory: candidate.category.isEmpty ? '其他' : candidate.category,
        initialDescription: candidate.visualDescription,
        initialExpressions: candidate.expressions,
      ),
    );
    if (draft == null || draft.displayName.trim().isEmpty) return false;
    final clean = draft.displayName.trim();
    final existingObject = _personalObjects.any(
      (item) => item.displayName.toLowerCase() == clean.toLowerCase(),
    );
    if (existingObject) {
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“$clean”已经保存在我的物品中。')),
      );
      return true;
    }
    final created = await widget.personalObjectStore.create(
      draft: draft,
      referenceImageBytes: imageBytes,
    );
    final alreadyInVocabulary = _localVocabularyEntries.any(
      (entry) => entry.category == '物品' && entry.text == clean,
    );
    if (!alreadyInVocabulary) {
      final next = [
        VocabularyEntry(
          id: created.id,
          category: '物品',
          text: clean,
          note: '我的物品',
        ),
        ..._localVocabularyEntries,
      ];
      await widget.onVocabularyChanged(next);
      _localVocabularyEntries = next;
    }
    await widget.locationController.recordWordUsed(clean, 'vocabulary');
    await widget.onHabitRecorded(
      clean,
      category: 'vocabulary',
      source: 'personal_object_saved',
    );
    unawaited(widget.companionAgent.recordInteraction(
      text: clean,
      feature: 'camera',
      action: CompanionFeedbackAction.saved,
      prompt: candidate.objectName,
      slot: RecommendationSlot.actionOrObject,
    ));
    _personalObjects = await widget.personalObjectStore.loadAll();
    await widget.onPersonalObjectsChanged();
    if (!mounted) return true;
    setState(() {
      _selectedCandidate = candidate.copyWith(
        objectName: clean,
        personalObjectId: created.id,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已记住“$clean”')),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPreviewPointerDown,
            onPointerMove: _onPreviewPointerMove,
            onPointerUp: _onPreviewPointerUp,
            onPointerCancel: _onPreviewPointerUp,
            child: CameraAwesomeBuilder.custom(
              saveConfig: SaveConfig.photo(),
              sensorConfig: SensorConfig.single(
                sensor: Sensor.position(SensorPosition.back),
                // 16:9 更接近竖屏取景比例，减少 4:3 预览在全屏 cover 下
                // 被裁掉的大量左右区域。
                aspectRatio: CameraAspectRatios.ratio_16_9,
              ),
              // 预览与拍后结果都显示完整画面，避免用户取景时看不到的
              // JPEG 边缘在识别后突然出现。
              previewFit: CameraPreviewFit.contain,
              progressIndicator: const _CameraBootView(),
              onMediaCaptureEvent: _handleMediaCapture,
              onPreviewScaleBuilder: (cameraState) => OnPreviewScale(
                onScaleStart: () {
                  // 记录手势开始时的 normalized zoom
                  _pinchBaseZoom = _zoomValue.value;
                },
                onScale: (scale) {
                  if (_sensorConfig == null || !_zoomInitialized) return;
                  // scale 是相对于手势开始时的比例（1.0 = 无变化）
                  // 将 normalized zoom 转换为实际缩放比，应用手势缩放，再转回
                  final baseRatio = _minZoomRatio +
                      _pinchBaseZoom * (_maxZoomRatio - _minZoomRatio);
                  final newRatio =
                      (baseRatio * scale).clamp(_minZoomRatio, _maxZoomRatio);
                  final newZoom = ((newRatio - _minZoomRatio) /
                          (_maxZoomRatio - _minZoomRatio))
                      .clamp(0.0, 1.0);
                  _requestZoom(newZoom.toDouble());
                },
              ),
              builder: (cameraState, preview) {
                // Hold a reference to the sensor config for our pinch handler
                final newSensorConfig = cameraState.sensorConfig;
                if (_sensorConfig != newSensorConfig) {
                  _sensorConfig = newSensorConfig;
                  _zoomInitialized = false; // 传感器变化时重新初始化
                }

                // Initialize zoom to 1.0x after the camera pipeline is ready
                if (!_zoomInitialized) {
                  _initZoomToOneX();
                }

                return Stack(
                  children: [
                    // 亮度手势层：仅包裹相机预览区域
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Stack(
                          children: [
                            if (_imageBytes != null)
                              Positioned.fill(
                                child: Transform.flip(
                                  flipX: _capturedImageMirrored,
                                  child: Image.memory(
                                    _imageBytes!,
                                    // 识别结果必须展示完整 JPEG；否则 cover 裁掉的区域
                                    // 仍会拥有模型框，看起来就像框跑到了屏幕外。
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.medium,
                                  ),
                                ),
                              )
                            else if (_isTakingPhoto &&
                                _frozenPreviewBytes != null)
                              Positioned.fill(
                                child: Image.memory(
                                  _frozenPreviewBytes!,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  filterQuality: FilterQuality.low,
                                ),
                              ),
                            const Positioned.fill(
                                child: _CameraOverlayGradient()),
                            // 亮度视觉遮罩（曝光补偿效果不明显时的辅助反馈）
                            if (_brightness < 0.49)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    color: Colors.black.withValues(
                                      alpha: (0.5 - _brightness) * 1.4,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_recognition != null)
                      Positioned.fill(
                        child: _buildRecognitionOverlay(),
                      ),
                    // UI 层：在手势层之上，按钮和控件优先接收触摸
                    SafeArea(
                      child: Stack(
                        children: [
                          // 返回按钮（左上）
                          // 闪光灯按钮（顶部中间）
                          if (_imageBytes == null)
                            Positioned(
                              top: 18,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: _buildFlashButton(),
                              ),
                            ),
                          // 亮度调节指示器（右侧，滑动时显示）
                          if (_isAdjustingBrightness)
                            Positioned(
                              right: 24,
                              top: 0,
                              bottom: 200,
                              child: Center(
                                child: _buildBrightnessIndicator(),
                              ),
                            ),
                          // 对焦框已移除，避免拦截双指缩放手势
                          if (_imageBytes == null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: ValueListenableBuilder<double>(
                                valueListenable: _zoomValue,
                                builder: (context, zoomValue, _) =>
                                    _CameraBottomControl(
                                  imageBytes: _imageBytes,
                                  currentZoom: zoomValue,
                                  minZoomRatio: _minZoomRatio,
                                  maxZoomRatio: _maxZoomRatio,
                                  onZoomChanged: (newNormalizedZoom) {
                                    _requestZoom(newNormalizedZoom);
                                  },
                                  onGallery: () => _openDefaultGallery(),
                                  onShutter: () =>
                                      _captureWithCamerawesome(cameraState),
                                  onFlip: () async {
                                    _pendingZoom = null;
                                    _zoomValue.value = 0;
                                    setState(() {
                                      _imageBytes = null;
                                      _frozenPreviewBytes = null;
                                      _capturedImageSize = null;
                                      _capturedImageMirrored = false;
                                      _recognition = null;
                                      _selectedCandidate = null;
                                      _isFrontCamera = !_isFrontCamera;
                                      _resultPanelHeight = 160;
                                      _zoomInitialized = false;
                                    });
                                    await cameraState.switchCameraSensor(
                                      aspectRatio:
                                          cameraState.sensorConfig.aspectRatio,
                                    );
                                  },
                                  isLoading: _isTakingPhoto,
                                ),
                              ),
                            ),
                          // Keep navigation above recognition and result overlays.
                          Positioned(
                            top: 18,
                            left: 24,
                            child: SizedBox(
                              width: 60,
                              child: _GlassToolbar(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => Navigator.of(context).maybePop(),
                                  child: Center(
                                    child: Icon(
                                      Icons.arrow_back_ios_new,
                                      color:
                                          Colors.white.withValues(alpha: 0.92),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          YuqiaoFeatureAssistiveBall(
            currentFeature: YuqiaoFeature.camera,
            launcher: widget.featureLauncher,
            bottomClearance: _imageBytes == null
                ? _cameraControlsClearance + 18
                : _resultPanelHeight + 42,
          ),
        ],
      ),
    );
  }

  Widget _buildFlashButton() {
    return _GlassToolbar(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 闪光灯图标按钮
          if (!_flashExpanded)
            GestureDetector(
              onTap: () {
                if (_flashExpanded) {
                  setState(() => _flashExpanded = false);
                } else {
                  setState(() => _flashExpanded = true);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                  horizontal: _flashExpanded ? 10 : 0,
                ),
                child: Icon(
                  _flashIcon(),
                  color: Colors.white.withValues(alpha: 0.92),
                  size: 22,
                ),
              ),
            ),
          // 展开的模式选项
          if (_flashExpanded) ...[
            _flashModeChip(FlashMode.none, '关', Icons.flash_off_rounded),
            const SizedBox(width: 4),
            _flashModeChip(FlashMode.on, '开', Icons.flash_on_rounded),
            const SizedBox(width: 4),
            _flashModeChip(FlashMode.auto, '自动', Icons.flash_auto_rounded),
          ],
        ],
      ),
    );
  }

  Widget _flashModeChip(FlashMode mode, String label, IconData _) {
    final selected = _flashMode == mode;
    final displayLabel = switch (mode) {
      FlashMode.none => '关闭',
      FlashMode.on => '开启',
      FlashMode.auto => '自动',
      FlashMode.always => '常亮',
    };
    return GestureDetector(
      onTap: () => _setFlashMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          displayLabel,
          style: TextStyle(
            color: Colors.white.withValues(alpha: selected ? 1.0 : 0.68),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBrightnessIndicator() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.brightness_6_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 18,
              ),
              const SizedBox(height: 8),
              // 垂直进度条
              SizedBox(
                height: 100,
                child: Center(
                  child: Container(
                    width: 4,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 4,
                        height: 100 * _brightness,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(_brightness * 100).round()}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecognitionOverlay() {
    return FutureBuilder<ObjectRecognition>(
      future: _recognition,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation(
                            Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'AI 识别中...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _buildRecognitionFallback(
            title: '识别失败',
            message: snapshot.error.toString(),
          );
        }

        final recognition = snapshot.data!;
        return _buildResultPanel(recognition);
      },
    );
  }

  void _retryRecognition() {
    final bytes = _imageBytes;
    if (bytes == null) return;
    setState(() {
      _selectedCandidate = null;
      _recognition = _recognizeImage(bytes);
    });
  }

  Widget _buildRecognitionFallback({
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.image_search_rounded,
                    size: 42,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.76),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildRecoveryButton(
                        icon: Icons.refresh_rounded,
                        label: '重试',
                        onTap: _retryRecognition,
                      ),
                      _buildRecoveryButton(
                        icon: Icons.camera_alt_rounded,
                        label: '重新拍摄',
                        onTap: _resetForRetake,
                      ),
                      _buildRecoveryButton(
                        icon: Icons.photo_library_rounded,
                        label: '从相册选择',
                        onTap: _openDefaultGallery,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecoveryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultPanel(ObjectRecognition recognition) {
    final candidates = recognition.candidates;
    if (candidates.isEmpty) {
      return _buildRecognitionFallback(
        title: '没有识别到物品',
        message: '可以重新拍摄、重试识别，或从相册选择另一张照片。',
      );
    }
    return _InteractiveBoundingBoxes(
      candidates: candidates,
      imageSize: _capturedImageSize,
      mirrored: _capturedImageMirrored,
      colors: _labelColors,
      onSelected: _openObjectDetails,
    );
  }

  Future<void> _openObjectDetails(ObjectCandidate candidate) async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraObjectDetailPage(
          candidate: candidate,
          imageBytes: bytes,
          mirrored: _capturedImageMirrored,
          initiallySaved: candidate.personalObjectId.isNotEmpty ||
              _personalObjects.any(
                (item) => item.displayName == candidate.objectName,
              ),
          onSpeak: _speakText,
          onGenerateSentence: (option) => _useExpression(
            candidate,
            option.phrase,
            expressionType: option.type,
          ),
          onSave: () => _savePersonalObject(candidate),
        ),
      ),
    );
  }

  Widget _buildLegacyResultPanel(ObjectRecognition recognition) {
    final candidates = recognition.candidates;
    if (candidates.isEmpty) {
      return _buildRecognitionFallback(
        title: '没有识别到物品',
        message: '可以重新拍摄、重试识别，或从相册选择另一张照片。',
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject =
          _resultPanelKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderObject == null || !renderObject.hasSize) return;
      final nextHeight = renderObject.size.height;
      if ((nextHeight - _resultPanelHeight).abs() < 1) return;
      setState(() => _resultPanelHeight = nextHeight);
    });

    return Stack(
      children: [
        // 坐标标注层
        Positioned.fill(
          child: CustomPaint(
            painter: _BBoxPainter(
              candidates: candidates,
              excludedBottom: _cameraControlsClearance + _resultPanelHeight + 8,
            ),
          ),
        ),
        // 底部结果面板
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              12,
              0,
              12,
              _cameraControlsClearance,
            ),
            child: ConstrainedBox(
              key: _resultPanelKey,
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: (MediaQuery.sizeOf(context).height -
                        _cameraControlsClearance -
                        120)
                    .clamp(180.0, 440.0),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      color: const Color(0xFF98A5AD).withValues(alpha: 0.35),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 1,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 标题
                          Row(
                            children: [
                              Icon(Icons.auto_awesome_rounded,
                                  size: 18,
                                  color: Colors.white.withValues(alpha: 0.8)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '图中识别到 ${candidates.length} 个物品',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 每个物品及其表达
                          for (int i = 0; i < candidates.length; i++) ...[
                            if (i > 0)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Divider(
                                    height: 1,
                                    color:
                                        Colors.white.withValues(alpha: 0.10)),
                              ),
                            _buildObjectSection(candidates[i], i),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const _labelColors = [
    Color(0xFF6CB4FF),
    Color(0xFF81C784),
    Color(0xFFFFD54F),
    Color(0xFFFF8A65),
    Color(0xFFCE93D8),
  ];

  Widget _buildObjectSection(ObjectCandidate candidate, int index) {
    final color = _labelColors[index % _labelColors.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 物品名称
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              button: true,
              label: '播报${candidate.objectName}',
              child: Material(
                color: color.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => _speakObject(candidate),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.volume_up_rounded,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          candidate.objectName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (candidate.personalObjectId.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      '我的物品',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            else if (!_personalObjects.any(
              (item) => item.displayName == candidate.objectName,
            ))
              Material(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => _savePersonalObject(candidate),
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_add_rounded,
                          size: 17,
                          color: Colors.white,
                        ),
                        SizedBox(width: 5),
                        Text(
                          '记住它',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // 表达按钮
            ...candidate.expressions.take(3).map((expr) {
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: GestureDetector(
                  onTap: () => _useExpression(candidate, expr),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: color.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      expr,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}

class _InteractiveBoundingBoxes extends StatelessWidget {
  const _InteractiveBoundingBoxes({
    required this.candidates,
    required this.imageSize,
    required this.mirrored,
    required this.colors,
    required this.onSelected,
  });

  final List<ObjectCandidate> candidates;
  final Size? imageSize;
  final bool mirrored;
  final List<Color> colors;
  final ValueChanged<ObjectCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final markers = _buildMarkerLayouts(canvasSize);
        final labels = _layoutLabels(canvasSize, markers);
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ObjectBoxesPainter(markers: markers),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ObjectLeaderLinePainter(
                    markers: markers,
                    labels: labels,
                  ),
                ),
              ),
            ),
            for (final marker in markers) _buildTapTarget(marker),
            for (var index = 0; index < markers.length; index++)
              _buildFloatingLabel(markers[index], labels[index]),
          ],
        );
      },
    );
  }

  List<_ObjectMarkerLayout> _buildMarkerLayouts(Size canvasSize) {
    final markers = <_ObjectMarkerLayout>[];
    for (int index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      var rect = _displayRect(canvasSize, candidate, index);
      final duplicatesExistingBox = markers.any((previous) {
        return _rectIou(previous.rect, rect) > 0.82 &&
            (previous.rect.center - rect.center).distance < 16;
      });
      if (duplicatesExistingBox) {
        rect = _fallbackDisplayRect(canvasSize, index);
      }
      var overlapLevel = 0;
      for (final previous in markers) {
        if (_rectIou(previous.rect, rect) > 0.46 ||
            (previous.rect.center - rect.center).distance < 28) {
          overlapLevel++;
        }
      }
      final tapRect = Rect.fromCenter(
        center: rect.center,
        width: math.max(rect.width, 52),
        height: math.max(rect.height, 52),
      ).intersect(Offset.zero & canvasSize);
      markers.add(_ObjectMarkerLayout(
        candidate: candidate,
        rect: rect,
        tapRect: tapRect,
        color: colors[index % colors.length],
        overlapLevel: overlapLevel,
      ));
    }
    return markers;
  }

  List<Rect> _layoutLabels(
    Size canvasSize,
    List<_ObjectMarkerLayout> markers,
  ) {
    final order = [
      for (int index = 0; index < markers.length; index++) index,
    ]..sort((a, b) => markers[a].rect.top.compareTo(markers[b].rect.top));
    final labels = List<Rect>.filled(markers.length, Rect.zero);
    final placed = <Rect>[];
    final minTop = math.min(92.0, canvasSize.height * 0.12);
    final maxTop = math.max(minTop, canvasSize.height - 54);

    for (final index in order) {
      final marker = markers[index];
      final width = _labelWidth(canvasSize, marker.candidate.objectName);
      const height = 34.0;
      final left = marker.rect.left
          .clamp(8.0, math.max(8.0, canvasSize.width - width - 8))
          .toDouble();
      var top = (marker.rect.top - height - 6).clamp(minTop, maxTop).toDouble();
      var label = Rect.fromLTWH(left, top, width, height);
      var guard = 0;
      while (
          placed.any((item) => item.inflate(5).overlaps(label)) && guard < 8) {
        top = (top + height + 8).clamp(minTop, maxTop).toDouble();
        label = Rect.fromLTWH(left, top, width, height);
        guard++;
      }
      if (placed.any((item) => item.inflate(5).overlaps(label))) {
        top = (marker.rect.bottom + 8).clamp(minTop, maxTop).toDouble();
        label = Rect.fromLTWH(left, top, width, height);
      }
      labels[index] = label;
      placed.add(label);
    }
    return labels;
  }

  double _labelWidth(Size canvasSize, String text) {
    final estimated = text.runes.length * 15.0 + 42;
    return estimated
        .clamp(82.0, math.min(190.0, canvasSize.width * 0.58))
        .toDouble();
  }

  Widget _buildTapTarget(_ObjectMarkerLayout marker) {
    return Positioned.fromRect(
      rect: marker.tapRect,
      child: Semantics(
        button: true,
        label: '查看${marker.candidate.objectName}的表达',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected(marker.candidate),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildFloatingLabel(_ObjectMarkerLayout marker, Rect labelRect) {
    return Positioned(
      left: labelRect.left,
      top: labelRect.top,
      child: GestureDetector(
        onTap: () => onSelected(marker.candidate),
        child: Container(
          width: labelRect.width,
          height: labelRect.height,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: marker.color.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.72),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  marker.candidate.objectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _rectIou(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final union = a.width * a.height + b.width * b.height - intersection;
    if (union <= 0) return 0;
    return intersection / union;
  }

  List<Widget> buildMarkerLegacy(
    Size canvasSize,
    ObjectCandidate candidate,
    int index,
  ) {
    final color = colors[index % colors.length];
    final rect = _displayRect(canvasSize, candidate, index);
    final tapRect = Rect.fromCenter(
      center: rect.center,
      width: math.max(rect.width, 48),
      height: math.max(rect.height, 48),
    ).intersect(Offset.zero & canvasSize);
    final labelTop = math.max(6.0, rect.top - 34);

    return [
      Positioned.fromRect(
        rect: tapRect,
        child: Semantics(
          button: true,
          label: '查看${candidate.objectName}的表达',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(candidate),
            child: CustomPaint(
              painter: _ObjectBoxPainter(
                color: color,
                boxRect: Rect.fromLTWH(
                  rect.left - tapRect.left,
                  rect.top - tapRect.top,
                  rect.width,
                  rect.height,
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: rect.left.clamp(6.0, math.max(6.0, canvasSize.width - 80)),
        top: labelTop,
        child: GestureDetector(
          onTap: () => onSelected(candidate),
          child: Container(
            constraints: BoxConstraints(maxWidth: canvasSize.width * 0.55),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    candidate.objectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Rect _displayRect(
    Size canvasSize,
    ObjectCandidate candidate,
    int index,
  ) {
    final bbox = candidate.bbox;
    if (bbox == null || bbox.length != 4 || imageSize == null) {
      return _fallbackDisplayRect(canvasSize, index);
    }

    final source = imageSize!;
    final fitted = applyBoxFit(
      BoxFit.contain,
      source,
      canvasSize,
    );
    final sourceRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & source,
    );
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & canvasSize,
    );
    final rawLeft = mirrored ? 1000 - bbox[2] : bbox[0];
    final rawRight = mirrored ? 1000 - bbox[0] : bbox[2];
    final sourceLeft = rawLeft / 1000 * source.width;
    final sourceTop = bbox[1] / 1000 * source.height;
    final sourceRight = rawRight / 1000 * source.width;
    final sourceBottom = bbox[3] / 1000 * source.height;
    final rect = Rect.fromLTRB(
      destinationRect.left +
          (sourceLeft - sourceRect.left) /
              sourceRect.width *
              destinationRect.width,
      destinationRect.top +
          (sourceTop - sourceRect.top) /
              sourceRect.height *
              destinationRect.height,
      destinationRect.left +
          (sourceRight - sourceRect.left) /
              sourceRect.width *
              destinationRect.width,
      destinationRect.top +
          (sourceBottom - sourceRect.top) /
              sourceRect.height *
              destinationRect.height,
    );
    return rect.intersect(Offset.zero & canvasSize);
  }

  Rect _fallbackDisplayRect(Size canvasSize, int index) {
    final width = math.min(180.0, canvasSize.width * 0.45);
    final height = math.min(120.0, canvasSize.height * 0.18);
    final column = index % 2;
    final row = index ~/ 2;
    final left = (canvasSize.width - width) / 2 + column * 32 - 16;
    final top = canvasSize.height * 0.24 + row * (height + 18);
    return Rect.fromLTWH(left, top, width, height)
        .intersect(Offset.zero & canvasSize);
  }
}

class _ObjectBoxPainter extends CustomPainter {
  const _ObjectBoxPainter({required this.color, required this.boxRect});

  final Color color;
  final Rect boxRect;

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(boxRect, const Radius.circular(10));
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ObjectBoxPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.boxRect != boxRect;
  }
}

class _ObjectMarkerLayout {
  const _ObjectMarkerLayout({
    required this.candidate,
    required this.rect,
    required this.tapRect,
    required this.color,
    required this.overlapLevel,
  });

  final ObjectCandidate candidate;
  final Rect rect;
  final Rect tapRect;
  final Color color;
  final int overlapLevel;
}

class _ObjectBoxesPainter extends CustomPainter {
  const _ObjectBoxesPainter({required this.markers});

  final List<_ObjectMarkerLayout> markers;

  @override
  void paint(Canvas canvas, Size size) {
    for (final marker in markers) {
      final inset = math.min(marker.overlapLevel * 3.0, 9.0);
      final rect = marker.rect.deflate(
        math.min(inset, marker.rect.shortestSide / 6),
      );
      final rounded = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(11),
      );
      canvas.drawRRect(
        rounded,
        Paint()
          ..color = marker.color.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        rounded,
        Paint()
          ..color = marker.color.withValues(alpha: 0.98)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke,
      );
      if (marker.overlapLevel > 0) {
        canvas.drawCircle(
          rect.topLeft + const Offset(9, 9),
          4,
          Paint()..color = marker.color.withValues(alpha: 0.95),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ObjectBoxesPainter oldDelegate) {
    return oldDelegate.markers != markers;
  }
}

class _ObjectLeaderLinePainter extends CustomPainter {
  const _ObjectLeaderLinePainter({
    required this.markers,
    required this.labels,
  });

  final List<_ObjectMarkerLayout> markers;
  final List<Rect> labels;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0;
        index < markers.length && index < labels.length;
        index++) {
      final marker = markers[index];
      final label = labels[index];
      final boxAnchor = marker.rect.center;
      final labelAnchor = Offset(label.left + 18, label.center.dy);
      if ((boxAnchor - labelAnchor).distance < 34) continue;
      final path = Path()
        ..moveTo(labelAnchor.dx, labelAnchor.dy)
        ..quadraticBezierTo(
          (labelAnchor.dx + boxAnchor.dx) / 2,
          labelAnchor.dy,
          boxAnchor.dx,
          boxAnchor.dy,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = marker.color.withValues(alpha: 0.72)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        boxAnchor,
        3,
        Paint()..color = marker.color.withValues(alpha: 0.90),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ObjectLeaderLinePainter oldDelegate) {
    return oldDelegate.markers != markers || oldDelegate.labels != labels;
  }
}

class CameraObjectDetailPage extends StatefulWidget {
  const CameraObjectDetailPage({
    super.key,
    required this.candidate,
    required this.imageBytes,
    required this.mirrored,
    required this.initiallySaved,
    required this.onSpeak,
    required this.onGenerateSentence,
    required this.onSave,
  });

  final ObjectCandidate candidate;
  final Uint8List imageBytes;
  final bool mirrored;
  final bool initiallySaved;
  final Future<void> Function(String text) onSpeak;
  final ValueChanged<ObjectExpressionOption> onGenerateSentence;
  final Future<bool> Function() onSave;

  @override
  State<CameraObjectDetailPage> createState() => _CameraObjectDetailPageState();
}

class _CameraObjectDetailPageState extends State<CameraObjectDetailPage> {
  late bool _saved;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.initiallySaved;
  }

  Future<void> _save() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    final saved = await widget.onSave();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = saved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final expressionOptions = candidate.effectiveExpressionOptions;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 290,
            backgroundColor: const Color(0xFFF4F7FB),
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.all(7),
              child: _DetailGlassButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.flip(
                    flipX: widget.mirrored,
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.cover,
                      cacheWidth: 1080,
                      gaplessPlayback: true,
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x88000000)],
                        stops: [0.58, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom: 20,
                    child: Text(
                      candidate.objectName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            sliver: SliverList.list(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (candidate.category.isNotEmpty)
                      _DetailTag(text: candidate.category),
                    if (candidate.personalObjectId.isNotEmpty)
                      const _DetailTag(
                        text: '我的物品',
                        icon: Icons.verified_rounded,
                      ),
                  ],
                ),
                if (candidate.visualDescription.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    candidate.visualDescription,
                    style: const TextStyle(
                      color: Color(0xFF6E6E73),
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () => widget.onSpeak(candidate.objectName),
                    icon: const Icon(Icons.volume_up_rounded),
                    label: Text(
                      '播报“${candidate.objectName}”',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5974E8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                const Text(
                  '你可能想说',
                  style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '轻触句子直接播报，点击星光按钮可整理成完整表达。',
                  style: TextStyle(color: Color(0xFF7A7A80), fontSize: 13),
                ),
                const SizedBox(height: 14),
                for (int index = 0;
                    index < expressionOptions.length;
                    index++) ...[
                  _ExpressionSuggestionTile(
                    type: expressionOptions[index].type,
                    phrase: expressionOptions[index].phrase,
                    color: _CameraWordPageState._labelColors[
                        index % _CameraWordPageState._labelColors.length],
                    onSpeak: () =>
                        widget.onSpeak(expressionOptions[index].phrase),
                    onGenerate: () =>
                        widget.onGenerateSentence(expressionOptions[index]),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _saved || _saving ? null : _save,
                  icon: Icon(
                    _saved
                        ? Icons.bookmark_added_rounded
                        : Icons.bookmark_add_rounded,
                  ),
                  label: Text(
                    _saved
                        ? '已保存到我的物品'
                        : _saving
                            ? '正在保存…'
                            : '记住这个物品',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: const Color(0xFF4E61B8),
                    side: const BorderSide(color: Color(0xFFCAD2F6)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailGlassButton extends StatelessWidget {
  const _DetailGlassButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.white.withValues(alpha: 0.24),
          child: InkWell(
            onTap: onTap,
            child: Icon(icon, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }
}

class _DetailTag extends StatelessWidget {
  const _DetailTag({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: const Color(0xFF5974E8)),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF4A4A50),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpressionSuggestionTile extends StatelessWidget {
  const _ExpressionSuggestionTile({
    required this.type,
    required this.phrase,
    required this.color,
    required this.onSpeak,
    required this.onGenerate,
  });

  final String type;
  final String phrase;
  final Color color;
  final VoidCallback onSpeak;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onSpeak,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.34)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.volume_up_rounded, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.isEmpty ? '表达' : type,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      phrase,
                      style: const TextStyle(
                        color: Color(0xFF252529),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '生成完整句',
                onPressed: onGenerate,
                icon: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF6577D8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BBoxPainter extends CustomPainter {
  final List<ObjectCandidate> candidates;
  final double excludedBottom;

  _BBoxPainter({
    required this.candidates,
    required this.excludedBottom,
  });

  static const _colors = [
    Color(0xFF6CB4FF),
    Color(0xFF81C784),
    Color(0xFFFFD54F),
    Color(0xFFFF8A65),
    Color(0xFFCE93D8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final visibleHeight =
        (size.height - excludedBottom).clamp(0.0, size.height);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, visibleHeight));
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final bbox = candidate.bbox;
      if (bbox == null || bbox.length != 4) continue;

      final color = _colors[i % _colors.length];
      // 归一化坐标 (0-1000) → 像素坐标
      final x1 = bbox[0] / 1000 * size.width;
      final y1 = bbox[1] / 1000 * size.height;
      final x2 = bbox[2] / 1000 * size.width;
      final y2 = bbox[3] / 1000 * size.height;

      final rect = Rect.fromLTRB(x1, y1, x2, y2);

      // 半透明填充
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        fillPaint,
      );

      // 边框
      final strokePaint = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        strokePaint,
      );

      // 标签背景
      final labelText = candidate.objectName;
      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelW = textPainter.width + 16;
      final labelH = textPainter.height + 8;
      final labelRect = Rect.fromLTWH(x1, y1 - labelH - 2, labelW, labelH);

      final labelBgPaint = Paint()..color = color.withValues(alpha: 0.90);
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
        labelBgPaint,
      );

      textPainter.paint(canvas, Offset(x1 + 8, y1 - labelH + 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BBoxPainter oldDelegate) {
    return oldDelegate.candidates != candidates ||
        oldDelegate.excludedBottom != excludedBottom;
  }
}

// Camera overlay components adapted from photos_test.dart; preview is provided by CamerAwesome.

class _CameraBootView extends StatelessWidget {
  const _CameraBootView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '\u6B63\u5728\u542F\u52A8\u76F8\u673A',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraOverlayGradient extends StatelessWidget {
  const _CameraOverlayGradient();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.14),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.22),
            ],
            stops: const [0.0, 0.18, 0.58, 1.0],
          ),
        ),
      ),
    );
  }
}

class _GlassToolbar extends StatelessWidget {
  final Widget child;
  const _GlassToolbar({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF7E8790).withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ToolbarIcon({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 32,
        child: Center(
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.92),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class FocusFrame extends StatelessWidget {
  final double size;
  const FocusFrame({super.key, this.size = 140});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FocusFramePainter(),
    );
  }
}

class _FocusFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const corner = 24.0;
    final r = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawLine(r.topLeft, Offset(r.left + corner, r.top), paint);
    canvas.drawLine(r.topLeft, Offset(r.left, r.top + corner), paint);
    canvas.drawLine(
        Offset(r.right - corner, r.top), Offset(r.right, r.top), paint);
    canvas.drawLine(r.topRight, Offset(r.right, r.top + corner), paint);
    canvas.drawLine(
        Offset(r.left, r.bottom - corner), Offset(r.left, r.bottom), paint);
    canvas.drawLine(
        Offset(r.left, r.bottom), Offset(r.left + corner, r.bottom), paint);
    canvas.drawLine(
        Offset(r.right - corner, r.bottom), Offset(r.right, r.bottom), paint);
    canvas.drawLine(
        Offset(r.right, r.bottom - corner), Offset(r.right, r.bottom), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraBottomControl extends StatefulWidget {
  final Uint8List? imageBytes;
  final double currentZoom; // normalized 0.0 - 1.0
  final double minZoomRatio;
  final double maxZoomRatio;
  final ValueChanged<double>? onZoomChanged; // normalized 0.0 - 1.0
  final VoidCallback onGallery;
  final VoidCallback onShutter;
  final VoidCallback onFlip;
  final bool isLoading;

  const _CameraBottomControl({
    required this.imageBytes,
    this.currentZoom = 0.0,
    this.minZoomRatio = 1.0,
    this.maxZoomRatio = 10.0,
    this.onZoomChanged,
    required this.onGallery,
    required this.onShutter,
    required this.onFlip,
    required this.isLoading,
  });

  @override
  State<_CameraBottomControl> createState() => _CameraBottomControlState();
}

class _CameraBottomControlState extends State<_CameraBottomControl> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.04),
            Colors.black.withValues(alpha: 0.14),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: const Color(0xFF98A5AD).withValues(alpha: 0.32),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: widget.onGallery,
                          child: _buildSideButton(
                            icon: Icons.photo_library_rounded,
                            imageBytes: widget.imageBytes,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.onShutter,
                          child: _buildShutterButton(),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.onFlip,
                          child: _buildSideButton(
                            icon: Icons.flip_camera_ios_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildZoomRuler(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideButton({required IconData icon, Uint8List? imageBytes}) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 1,
            ),
          ),
          child: imageBytes != null
              ? ClipOval(child: Image.memory(imageBytes, fit: BoxFit.cover))
              : Icon(
                  icon,
                  color: Colors.white.withValues(alpha: 0.92),
                  size: 22,
                ),
        ),
      ),
    );
  }

  Widget _buildShutterButton() {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.26),
          width: 1,
        ),
      ),
      child: Center(
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.92),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: widget.isLoading
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF4A4A5A),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildZoomRuler() {
    return _ZoomRulerWidget(
      currentNormalizedZoom: widget.currentZoom,
      minZoomRatio: widget.minZoomRatio,
      maxZoomRatio: widget.maxZoomRatio,
      onZoomChanged: widget.onZoomChanged,
    );
  }
}

/// \u72EC\u7ACB\u7684\u7F29\u653E\u6807\u5C3A\u7EC4\u4EF6\uFF0C\u907F\u514D\u62D6\u62FD\u65F6\u91CD\u5EFA\u6574\u4E2A\u5E95\u90E8\u63A7\u5236\u680F
class _ZoomRulerWidget extends StatefulWidget {
  final double currentNormalizedZoom;
  final double minZoomRatio;
  final double maxZoomRatio;
  final ValueChanged<double>? onZoomChanged;

  const _ZoomRulerWidget({
    required this.currentNormalizedZoom,
    required this.minZoomRatio,
    required this.maxZoomRatio,
    this.onZoomChanged,
  });

  @override
  State<_ZoomRulerWidget> createState() => _ZoomRulerWidgetState();
}

class _ZoomRulerWidgetState extends State<_ZoomRulerWidget> {
  bool _isDragging = false;
  bool _showRatio = false;
  Timer? _hideRatioTimer;
  double _displayZoom = 0;
  double _lastSentZoom = -1;

  static const int _tickCount = 40;
  static const double _rulerHeight = 28;

  @override
  void initState() {
    super.initState();
    _displayZoom = widget.currentNormalizedZoom;
  }

  @override
  void didUpdateWidget(covariant _ZoomRulerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging &&
        (widget.currentNormalizedZoom - _displayZoom).abs() > 0.0005) {
      _displayZoom = widget.currentNormalizedZoom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRatioTemporarily();
      });
    }
  }

  @override
  void dispose() {
    _hideRatioTimer?.cancel();
    super.dispose();
  }

  double _normalizedToRatio(double normalized) {
    return widget.minZoomRatio +
        normalized * (widget.maxZoomRatio - widget.minZoomRatio);
  }

  String _formatRatio(double ratio) {
    if ((ratio - ratio.round()).abs() < 0.05) return '${ratio.round()}x';
    return '${ratio.toStringAsFixed(1)}x';
  }

  void _showRatioTemporarily() {
    _hideRatioTimer?.cancel();
    if (mounted && !_showRatio) setState(() => _showRatio = true);
    _hideRatioTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_isDragging) setState(() => _showRatio = false);
    });
  }

  void _setZoomFromPosition(double dx, double width) {
    if (width <= 0) return;
    const edgeInset = 8.0;
    final usableWidth = width - edgeInset * 2;
    final newZoom = ((dx - edgeInset) / usableWidth).clamp(0.0, 1.0).toDouble();
    setState(() => _displayZoom = newZoom);

    // Keep the preview smooth by avoiding redundant platform-channel calls.
    if (_lastSentZoom < 0 || (newZoom - _lastSentZoom).abs() >= 0.004) {
      _lastSentZoom = newZoom;
      widget.onZoomChanged?.call(newZoom);
    }
  }

  void _onDragStart(DragStartDetails details, double width) {
    _hideRatioTimer?.cancel();
    setState(() {
      _isDragging = true;
      _showRatio = true;
    });
    _setZoomFromPosition(details.localPosition.dx, width);
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    _setZoomFromPosition(details.localPosition.dx, width);
  }

  void _onDragEnd(DragEndDetails details) {
    final snappedZoom = (_displayZoom * _tickCount).round() / _tickCount;
    setState(() {
      _isDragging = false;
      _displayZoom = snappedZoom;
    });
    _lastSentZoom = snappedZoom;
    widget.onZoomChanged?.call(snappedZoom);
    _showRatioTemporarily();
  }

  void _onTapDown(TapDownDetails details, double width) {
    _setZoomFromPosition(details.localPosition.dx, width);
    _showRatioTemporarily();
  }

  @override
  Widget build(BuildContext context) {
    final displayRatio = _normalizedToRatio(_displayZoom);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _onTapDown(details, width),
          onHorizontalDragStart: (details) => _onDragStart(details, width),
          onHorizontalDragUpdate: (details) => _onDragUpdate(details, width),
          onHorizontalDragEnd: _onDragEnd,
          child: SizedBox(
            height: 58,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  top: _showRatio ? 0 : 6,
                  child: AnimatedOpacity(
                    opacity: _showRatio ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        _formatRatio(displayRatio),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: CustomPaint(
                    size: const Size(double.infinity, _rulerHeight),
                    painter: _ZoomRulerPainter(
                      normalizedZoom: _displayZoom,
                      isDragging: _isDragging,
                      tickCount: _tickCount,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ZoomRulerPainter extends CustomPainter {
  final double normalizedZoom;
  final bool isDragging;
  final int tickCount;

  _ZoomRulerPainter({
    required this.normalizedZoom,
    required this.isDragging,
    required this.tickCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const edgeInset = 8.0;
    final usableWidth = size.width - edgeInset * 2;
    final activeIndex = (normalizedZoom * tickCount).round();
    final activeX = edgeInset + usableWidth * activeIndex / tickCount;
    const centerY = 13.0;
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    canvas.drawLine(
      const Offset(edgeInset, centerY),
      Offset(size.width - edgeInset, centerY),
      trackPaint,
    );

    for (int i = 0; i <= tickCount; i++) {
      final x = edgeInset + usableWidth * i / tickCount;
      final isMajor = i % 5 == 0;
      final isActive = i == activeIndex;
      final height = isActive ? 22.0 : (isMajor ? 12.0 : 7.0);
      final paint = Paint()
        ..color = isActive
            ? const Color(0xFFFFD45A)
            : Colors.white.withValues(alpha: isMajor ? 0.58 : 0.30)
        ..strokeWidth = isActive ? 3 : (isMajor ? 1.5 : 1)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }

    final thumbPaint = Paint()..color = const Color(0xFFFFD45A);
    canvas.drawCircle(Offset(activeX, centerY), isDragging ? 5 : 4, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _ZoomRulerPainter oldDelegate) {
    return normalizedZoom != oldDelegate.normalizedZoom ||
        isDragging != oldDelegate.isDragging;
  }
}
