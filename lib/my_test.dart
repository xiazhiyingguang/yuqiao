import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_icons.dart';

const bool kProfileDemoDebugLogs = false;

void _profileDemoDebugLog(String message) {
  if (kProfileDemoDebugLogs) debugPrint(message);
}

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ProfileCenterDemoPage(),
  ));
}

class ProfileCenterDemoPage extends StatelessWidget {
  const ProfileCenterDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF2F6),
      body: Center(
        child: SizedBox(
          width: 390,
          height: 844,
          child: PersonalCenterScreen(
            name: '语桥用户',
            subtitle: '常去地点 · 12 个',
            avatarImage: null,
            backgroundImage: null,
            onEditProfile: () {
              _profileDemoDebugLog('点击编辑个人资料');
            },
          ),
        ),
      ),
    );
  }
}

class PersonalCenterScreen extends StatelessWidget {
  final String name;
  final String subtitle;
  final ImageProvider? avatarImage;
  final ImageProvider? backgroundImage;
  final VoidCallback? onEditProfile;

  const PersonalCenterScreen({
    super.key,
    required this.name,
    required this.subtitle,
    this.avatarImage,
    this.backgroundImage,
    this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAF7),
        borderRadius: BorderRadius.circular(38),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _SoftPageBackground()),
          Column(
            children: [
              const _MockStatusBar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Column(
                    children: [
                      ProfileHeroCard(
                        name: name,
                        subtitle: subtitle,
                        avatarImage: avatarImage,
                        backgroundImage: backgroundImage,
                        onEditProfile: onEditProfile,
                      ),
                      const SizedBox(height: 12),
                      const _NewDocsCard(),
                      const SizedBox(height: 16),
                      const _SettingsPanel(),
                      const Spacer(),
                      const _BottomNavBar(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class YuqiaoPersonalCenter extends StatefulWidget {
  const YuqiaoPersonalCenter({
    super.key,
    required this.name,
    required this.wordCount,
    required this.placeCount,
    required this.locationRecommendationEnabled,
    required this.personalizedLearningEnabled,
    required this.autoStuckDetectionEnabled,
    required this.expressionPreferenceSummary,
    required this.onLocationRecommendationChanged,
    required this.onPersonalizedLearningChanged,
    required this.onAutoStuckDetectionChanged,
    required this.onOpenExpressionPreferences,
    required this.onClearPersonalizedLearningData,
    required this.onOpenLocationMemory,
    required this.personalObjectCount,
    this.onOpenYuqiaoMemory,
    this.onOpenPersonalObjects,
    this.unconfirmedPlaceCount = 0,
    this.avatarImage,
    this.onNameChanged,
  });

  final String name;
  final int wordCount;
  final int placeCount;
  final bool locationRecommendationEnabled;
  final bool personalizedLearningEnabled;
  final bool autoStuckDetectionEnabled;
  final String expressionPreferenceSummary;
  final ValueChanged<bool> onLocationRecommendationChanged;
  final ValueChanged<bool> onPersonalizedLearningChanged;
  final ValueChanged<bool> onAutoStuckDetectionChanged;
  final VoidCallback onOpenExpressionPreferences;
  final VoidCallback onClearPersonalizedLearningData;
  final VoidCallback onOpenLocationMemory;
  final int personalObjectCount;
  final VoidCallback? onOpenYuqiaoMemory;
  final VoidCallback? onOpenPersonalObjects;
  final int unconfirmedPlaceCount;
  final ImageProvider? avatarImage;
  final ValueChanged<String>? onNameChanged;

  @override
  State<YuqiaoPersonalCenter> createState() => _YuqiaoPersonalCenterState();
}

class _YuqiaoPersonalCenterState extends State<YuqiaoPersonalCenter> {
  Uint8List? _backgroundBytes;
  Uint8List? _avatarBytes;
  late String _name;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _loadProfileImages();
  }

  Future<void> _loadProfileImages() async {
    final prefs = await SharedPreferences.getInstance();
    final bgStr = prefs.getString('profile_background_image');
    final avStr = prefs.getString('profile_avatar_image');
    final decoded = await Future.wait<Uint8List?>([
      bgStr != null && bgStr.isNotEmpty
          ? compute(base64Decode, bgStr)
          : Future<Uint8List?>.value(),
      avStr != null && avStr.isNotEmpty
          ? compute(base64Decode, avStr)
          : Future<Uint8List?>.value(),
    ]);
    if (!mounted) return;
    setState(() {
      _backgroundBytes = decoded[0];
      _avatarBytes = decoded[1];
    });
  }

  Future<void> _navigateToSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProfileSettingsPage(
          name: _name,
          avatarBytes: _avatarBytes,
          backgroundBytes: _backgroundBytes,
        ),
      ),
    );
    // 从设置页返回后重新加载
    final prefs = await SharedPreferences.getInstance();
    final newName = prefs.getString('profile_nickname') ?? widget.name;
    if (!mounted) return;
    setState(() => _name = newName);
    widget.onNameChanged?.call(newName);
    await _loadProfileImages();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundImage = _backgroundBytes != null
        ? ResizeImage.resizeIfNeeded(
            1080,
            null,
            MemoryImage(_backgroundBytes!),
          )
        : null;
    final avatarImage = _avatarBytes != null
        ? ResizeImage.resizeIfNeeded(
            512,
            512,
            MemoryImage(_avatarBytes!),
          )
        : widget.avatarImage;

    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final topPadding = MediaQuery.viewPaddingOf(context).top;

    return Stack(
      children: [
        const Positioned.fill(child: _SoftPageBackground()),
        ListView(
          padding:
              EdgeInsets.fromLTRB(20, topPadding + 8, 20, bottomPadding + 96),
          children: [
            RepaintBoundary(
              child: ProfileHeroCard(
                name: _name,
                subtitle: '常去地点 · ${widget.placeCount} 个',
                wordCount: widget.wordCount.toString(),
                placeCount: widget.placeCount.toString(),
                avatarImage: avatarImage,
                backgroundImage: backgroundImage,
                onEditProfile: _navigateToSettings,
              ),
            ),
            if (widget.locationRecommendationEnabled &&
                widget.unconfirmedPlaceCount > 0) ...[
              const SizedBox(height: 12),
              const _NewDocsCard(),
            ],
            const SizedBox(height: 16),
            _SettingsPanel(
              locationEnabled: widget.locationRecommendationEnabled,
              personalizedLearningEnabled: widget.personalizedLearningEnabled,
              autoStuckDetectionEnabled: widget.autoStuckDetectionEnabled,
              expressionPreferenceSummary: widget.expressionPreferenceSummary,
              onLocationChanged: widget.onLocationRecommendationChanged,
              onPersonalizedLearningChanged:
                  widget.onPersonalizedLearningChanged,
              onAutoStuckDetectionChanged: widget.onAutoStuckDetectionChanged,
              onOpenExpressionPreferences: widget.onOpenExpressionPreferences,
              onClearPersonalizedLearningData:
                  widget.onClearPersonalizedLearningData,
              onOpenYuqiaoMemory: widget.onOpenYuqiaoMemory,
              onOpenLocationMemory: widget.onOpenLocationMemory,
              personalObjectCount: widget.personalObjectCount,
              onOpenPersonalObjects: widget.onOpenPersonalObjects,
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileSettingsPage extends StatefulWidget {
  final String name;
  final Uint8List? avatarBytes;
  final Uint8List? backgroundBytes;

  const _ProfileSettingsPage({
    required this.name,
    this.avatarBytes,
    this.backgroundBytes,
  });

  @override
  State<_ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<_ProfileSettingsPage> {
  static const _galleryChannel = MethodChannel(
    'com.example.yuqiao_app/gallery',
  );

  late TextEditingController _nameController;
  Uint8List? _avatarBytes;
  Uint8List? _backgroundBytes;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _avatarBytes = widget.avatarBytes;
    _backgroundBytes = widget.backgroundBytes;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<String?> _pickGalleryImagePath() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        return await _galleryChannel.invokeMethod<String>('openGallery');
      } on PlatformException {
        // Older builds may not have the native gallery channel yet.
      } on MissingPluginException {
        // Keep development builds usable before a full native rebuild.
      }
    }

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    return picked?.path;
  }

  Future<Uint8List?> _pickAndCropImage({required bool isAvatar}) async {
    final sourcePath = await _pickGalleryImagePath();
    if (sourcePath == null) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      maxWidth: isAvatar ? 1024 : 1920,
      maxHeight: isAvatar ? 1024 : 1280,
      aspectRatio:
          isAvatar ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: isAvatar ? '调整头像' : '调整背景图片',
          toolbarColor: const Color(0xFFF7F5F0),
          statusBarLight: true,
          toolbarWidgetColor: const Color(0xFF1F2328),
          activeControlsWidgetColor: const Color(0xFF3478F6),
          backgroundColor: const Color(0xFF151515),
          cropFrameColor: Colors.white,
          cropGridColor: Colors.white70,
          initAspectRatio: isAvatar
              ? CropAspectRatioPreset.square
              : CropAspectRatioPreset.ratio16x9,
          lockAspectRatio: isAvatar,
          aspectRatioPresets: isAvatar
              ? const [CropAspectRatioPreset.square]
              : const [
                  CropAspectRatioPreset.original,
                  CropAspectRatioPreset.ratio16x9,
                  CropAspectRatioPreset.ratio3x2,
                  CropAspectRatioPreset.square,
                ],
        ),
        IOSUiSettings(
          title: isAvatar ? '调整头像' : '调整背景图片',
          aspectRatioLockEnabled: isAvatar,
          resetAspectRatioEnabled: !isAvatar,
          aspectRatioPresets: isAvatar
              ? const [CropAspectRatioPreset.square]
              : const [
                  CropAspectRatioPreset.original,
                  CropAspectRatioPreset.ratio16x9,
                  CropAspectRatioPreset.ratio3x2,
                  CropAspectRatioPreset.square,
                ],
        ),
      ],
    );
    if (cropped == null) return null;
    return cropped.readAsBytes();
  }

  Future<void> _pickAvatar() async {
    await _replaceProfileImage(isAvatar: true);
  }

  Future<void> _pickBackground() async {
    await _replaceProfileImage(isAvatar: false);
  }

  Future<void> _replaceProfileImage({required bool isAvatar}) async {
    try {
      final bytes = await _pickAndCropImage(isAvatar: isAvatar);
      if (bytes == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        isAvatar ? 'profile_avatar_image' : 'profile_background_image',
        base64Encode(bytes),
      );
      if (!mounted) return;
      setState(() {
        if (isAvatar) {
          _avatarBytes = bytes;
        } else {
          _backgroundBytes = bytes;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片处理失败：$error')),
      );
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_nickname', name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            // 顶部栏
            SizedBox(
              height: 46,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () async {
                        await _saveName();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.86),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 14,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Icon(
                          YuqiaoIcons.back,
                          color: Colors.black.withOpacity(0.70),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const Center(
                    child: Text(
                      '个人资料',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Color(0xFF1F2328),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 头像设置
            _buildSectionCard(
              child: Column(
                children: [
                  const Text(
                    '头像',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8E8A84),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.92),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.95),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: _avatarBytes != null
                                ? Image.memory(
                                    _avatarBytes!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 512,
                                    cacheHeight: 512,
                                    filterQuality: FilterQuality.medium,
                                  )
                                : const _DefaultAvatarPlaceholder(),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3478F6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              YuqiaoIcons.camera,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '点击更换头像',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 背景图片设置
            _buildSectionCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '背景图片',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2A2D34),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _pickBackground,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3478F6).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            '更换',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3478F6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // 预览
                  Container(
                    height: 160,
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: const Color(0xFFFFF3E4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _backgroundBytes != null
                        ? Image.memory(
                            _backgroundBytes!,
                            fit: BoxFit.cover,
                            cacheWidth: 1080,
                            filterQuality: FilterQuality.medium,
                          )
                        : Stack(
                            children: [
                              Positioned(
                                top: 30,
                                left: 40,
                                child: _softBlob(
                                    100, const Color(0xFFFFD6B0), 0.42),
                              ),
                              Positioned(
                                top: 60,
                                right: 30,
                                child: _softBlob(
                                    110, const Color(0xFFD9EAF6), 0.46),
                              ),
                              Center(
                                child: Text(
                                  '默认渐变背景',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black.withOpacity(0.3),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 昵称设置
            _buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '昵称',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2A2D34),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.9),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2A2D34),
                      ),
                      decoration: InputDecoration(
                        hintText: '输入你的昵称',
                        hintStyle: TextStyle(
                          color: Colors.black.withOpacity(0.3),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        suffixIcon: Icon(
                          YuqiaoIcons.edit,
                          size: 20,
                          color: Colors.black.withOpacity(0.3),
                        ),
                      ),
                      onChanged: (_) => _saveName(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.92),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  static Widget _softBlob(double size, Color color, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(alpha),
        boxShadow: [
          BoxShadow(color: color.withOpacity(alpha * 0.5), blurRadius: 30),
        ],
      ),
    );
  }
}

class _SoftPageBackground extends StatelessWidget {
  const _SoftPageBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 40,
          left: -60,
          child: _blurCircle(160, const Color(0xFFFFE6C8), 0.35),
        ),
        Positioned(
          top: 240,
          right: -90,
          child: _blurCircle(220, const Color(0xFFE7EEF9), 0.55),
        ),
        Positioned(
          bottom: 80,
          left: -70,
          child: _blurCircle(180, const Color(0xFFF6E6DB), 0.42),
        ),
      ],
    );
  }

  Widget _blurCircle(double size, Color color, double alpha) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: alpha),
        ),
      ),
    );
  }
}

class _MockStatusBar extends StatelessWidget {
  const _MockStatusBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 31,
            top: 18,
            child: Text(
              '13:13',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black.withValues(alpha: 0.86),
              ),
            ),
          ),
          Positioned(
            top: 11,
            child: Container(
              width: 102,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            right: 30,
            top: 18,
            child: Row(
              children: [
                Icon(
                  YuqiaoIcons.signal,
                  size: 15,
                  color: Colors.black.withValues(alpha: 0.82),
                ),
                const SizedBox(width: 4),
                Icon(
                  YuqiaoIcons.wifi,
                  size: 15,
                  color: Colors.black.withValues(alpha: 0.82),
                ),
                const SizedBox(width: 5),
                Container(
                  width: 21,
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.82),
                      width: 1.4,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 15,
                      margin: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(2),
                      ),
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

class ProfileHeroCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final ImageProvider? avatarImage;
  final ImageProvider? backgroundImage;
  final VoidCallback? onEditProfile;
  final String wordCount;
  final String placeCount;

  const ProfileHeroCard({
    super.key,
    required this.name,
    required this.subtitle,
    this.avatarImage,
    this.backgroundImage,
    this.onEditProfile,
    this.wordCount = '32',
    this.placeCount = '12',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 356,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.88),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: _ProfileBackground(
              image: backgroundImage,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.20),
                    Colors.white.withValues(alpha: 0.50),
                    Colors.white.withValues(alpha: 0.90),
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: 22,
            left: 18,
            child: _TopChip(
              icon: YuqiaoIcons.article,
              title: '我的词汇',
              count: wordCount,
              iconColor: const Color(0xFFD9A251),
            ),
          ),
          Positioned(
            top: 22,
            right: 18,
            child: _TopChip(
              icon: YuqiaoIcons.location,
              title: '常去地点',
              count: placeCount,
              iconColor: const Color(0xFFF4D84A),
            ),
          ),
          Positioned(
            top: 82,
            left: 0,
            right: 0,
            child: GestureDetector(
              onTap: onEditProfile,
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  EditableProfileAvatar(image: avatarImage),
                  const SizedBox(height: 28),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: const Color(0xFF3A3938).withValues(alpha: 0.96),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '点击编辑个人资料',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8E8A84).withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBackground extends StatelessWidget {
  final ImageProvider? image;

  const _ProfileBackground({
    required this.image,
  });

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF3E4),
              Color(0xFFF6EFEA),
              Color(0xFFEAF1F7),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 34,
              left: 42,
              child: _softBlob(
                130,
                const Color(0xFFFFD6B0),
                0.42,
              ),
            ),
            Positioned(
              top: 82,
              right: 38,
              child: _softBlob(
                150,
                const Color(0xFFD9EAF6),
                0.46,
              ),
            ),
            Positioned(
              bottom: 34,
              left: 80,
              child: _softBlob(
                140,
                const Color(0xFFF3D7E7),
                0.32,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: image!,
          fit: BoxFit.cover,
        ),
        Container(
          color: Colors.white.withValues(alpha: 0.10),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.02),
                Colors.white.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0.78),
              ],
              stops: const [0.0, 0.52, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _softBlob(double size, Color color, double alpha) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: alpha),
        ),
      ),
    );
  }
}

class EditableProfileAvatar extends StatelessWidget {
  final ImageProvider? image;

  const EditableProfileAvatar({
    super.key,
    this.image,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      height: 142,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 142,
            height: 142,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE7BFA0).withValues(alpha: 0.30),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.72),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Container(
            width: 124,
            height: 124,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.92),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.95),
                width: 5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: image == null
                  ? const _DefaultAvatarPlaceholder()
                  : Image(
                      image: image!,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultAvatarPlaceholder extends StatelessWidget {
  const _DefaultAvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.2, -0.35),
          radius: 0.9,
          colors: [
            Color(0xFFFFE0C6),
            Color(0xFFF1D5E6),
            Color(0xFFE8F1F9),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          YuqiaoIcons.person,
          size: 58,
          color: Colors.white.withValues(alpha: 0.88),
        ),
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String count;
  final Color iconColor;

  const _TopChip({
    required this.icon,
    required this.title,
    required this.count,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF605F5B),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '($count)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFAAA7A1).withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewDocsCard extends StatelessWidget {
  const _NewDocsCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFFEFCBA1).withValues(alpha: 0.88),
                        const Color(0xFFF7E5CC).withValues(alpha: 0.74),
                        const Color(0xFFECE8DE).withValues(alpha: 0.88),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.035),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 15,
            top: 13,
            child: Container(
              width: 47,
              height: 47,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFFFFD3AF),
                    Color(0xFFE8C7FF),
                    Color(0xFFFFE5A8),
                    Color(0xFFFFD3AF),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.55),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 76,
            top: 16,
            child: Text(
              '需要确认的地点',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF4B4037).withValues(alpha: 0.92),
              ),
            ),
          ),
          Positioned(
            left: 77,
            top: 42,
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE3A555),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '已记录地点',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9E8E7D).withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 19,
            top: 9,
            bottom: 9,
            child: SizedBox(
              width: 63,
              child: CustomPaint(
                painter: _PaperStackPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperStackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paper = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final line = Paint()
      ..color = const Color(0xFFBFC1C2).withValues(alpha: 0.75)
      ..strokeWidth = 1.2;

    void drawPaper(Offset offset, double rotate) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(rotate);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * 0.55, size.height * 0.72),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paper);
      for (int i = 0; i < 5; i++) {
        final y = 12.0 + i * 8;
        canvas.drawLine(Offset(8, y), Offset(size.width * 0.43, y), line);
      }
      canvas.restore();
    }

    drawPaper(Offset(size.width * 0.30, 4), 0.25);
    drawPaper(Offset(size.width * 0.12, 9), -0.12);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    this.locationEnabled = false,
    this.personalizedLearningEnabled = true,
    this.autoStuckDetectionEnabled = false,
    this.expressionPreferenceSummary = '少 · 图文一起',
    this.onLocationChanged,
    this.onPersonalizedLearningChanged,
    this.onAutoStuckDetectionChanged,
    this.onOpenExpressionPreferences,
    this.onClearPersonalizedLearningData,
    this.onOpenYuqiaoMemory,
    this.onOpenLocationMemory,
    this.personalObjectCount = 0,
    this.onOpenPersonalObjects,
  });

  final bool locationEnabled;
  final bool personalizedLearningEnabled;
  final bool autoStuckDetectionEnabled;
  final String expressionPreferenceSummary;
  final ValueChanged<bool>? onLocationChanged;
  final ValueChanged<bool>? onPersonalizedLearningChanged;
  final ValueChanged<bool>? onAutoStuckDetectionChanged;
  final VoidCallback? onOpenExpressionPreferences;
  final VoidCallback? onClearPersonalizedLearningData;
  final VoidCallback? onOpenYuqiaoMemory;
  final VoidCallback? onOpenLocationMemory;
  final int personalObjectCount;
  final VoidCallback? onOpenPersonalObjects;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _SettingRow(
            title: '语桥记忆',
            subtitle: '看看语桥学会了什么',
            onTap: onOpenYuqiaoMemory,
            trailing: const Icon(
              YuqiaoIcons.sparkle,
              color: Color(0xFF8E8A84),
            ),
          ),
          const _ThinDivider(),
          _SettingRow(
            title: '我的物品',
            subtitle: '已保存 $personalObjectCount 件个人物品',
            onTap: onOpenPersonalObjects,
            trailing: const Icon(
              YuqiaoIcons.forward,
              color: Color(0xFF8E8A84),
            ),
          ),
          const _ThinDivider(),
          _SettingRow(
            title: '表达偏好',
            subtitle: expressionPreferenceSummary,
            onTap: onOpenExpressionPreferences,
            trailing: const Icon(
              YuqiaoIcons.forward,
              color: Color(0xFF8E8A84),
            ),
          ),
          const _ThinDivider(),
          _SettingRow(
            title: '个性化学习推荐',
            subtitle: '本机学习常用表达，可随时关闭或清除',
            trailing: _PersonalizedLearningControl(
              enabled: personalizedLearningEnabled,
              onChanged: onPersonalizedLearningChanged,
              onClearData: onClearPersonalizedLearningData,
            ),
          ),
          const _ThinDivider(),
          _SettingRow(
            title: '自动卡顿检测',
            subtitle: '对话模式中疑似卡顿时轻震提示，默认关闭',
            trailing: _TwoOptionSwitch(
              left: '关闭',
              right: '开启',
              rightSelected: autoStuckDetectionEnabled,
              onChanged: onAutoStuckDetectionChanged,
            ),
          ),
          const _ThinDivider(),
          _SettingRow(
            title: '地点词汇推荐',
            subtitle: '根据位置推荐常用表达',
            trailing: _LocationControl(
              enabled: locationEnabled,
              onChanged: onLocationChanged,
              onOpenMemory: onOpenLocationMemory,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF54504C).withValues(alpha: 0.96),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: trailing,
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: const Color(0xFFEDEBE7).withValues(alpha: 0.8),
    );
  }
}

class _TwoOptionSwitch extends StatelessWidget {
  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool>? onChanged;

  const _TwoOptionSwitch({
    required this.left,
    required this.right,
    required this.rightSelected,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => onChanged!(!rightSelected),
      child: Container(
        width: 92,
        height: 34,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F1EF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment:
                  rightSelected ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 42,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(child: _switchText(left, !rightSelected)),
                Expanded(child: _switchText(right, rightSelected)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchText(String text, bool selected) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: selected
              ? const Color(0xFF5A5652)
              : const Color(0xFFB9B5AF).withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar();

  @override
  Widget build(BuildContext context) {
    const items = [
      YuqiaoIcons.text,
      YuqiaoIcons.dictionary,
      YuqiaoIcons.grid,
      YuqiaoIcons.collection,
      YuqiaoIcons.person,
    ];

    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final selected = index == 4;

          return SizedBox(
            width: 52,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 34 : 30,
                height: selected ? 34 : 30,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.88)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Icon(
                  items[index],
                  size: selected ? 20 : 22,
                  color: selected
                      ? Colors.black.withValues(alpha: 0.92)
                      : const Color(0xFF8E8A84).withValues(alpha: 0.78),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PersonalizedLearningControl extends StatelessWidget {
  const _PersonalizedLearningControl({
    required this.enabled,
    this.onChanged,
    this.onClearData,
  });

  final bool enabled;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onClearData;

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除学习记录？'),
        content: const Text(
          '这只会清除自动学习到的常用表达，不会删除收藏、词库和个人物品。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) onClearData?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TwoOptionSwitch(
          left: '关闭',
          right: '开启',
          rightSelected: enabled,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _LocationControl extends StatelessWidget {
  const _LocationControl({
    required this.enabled,
    this.onChanged,
    this.onOpenMemory,
  });

  final bool enabled;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onOpenMemory;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TwoOptionSwitch(
          left: '关闭',
          right: '开启',
          rightSelected: enabled,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _CompactActionIcon extends StatelessWidget {
  const _CompactActionIcon({
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Opacity(
          opacity: onPressed == null ? 0.38 : 1,
          child: SizedBox(
            width: 28,
            height: 34,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
