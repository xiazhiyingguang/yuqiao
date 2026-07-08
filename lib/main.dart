import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'companion_agent.dart';
import 'conversation_terms.dart';
import 'camera_image_processing.dart';
import 'conversation_feedback.dart';
import 'expression_habits.dart';
import 'local_object_locator.dart';
import 'location_recommendation.dart';
import 'memory_insights_page.dart';
import 'paraformer_asr_service.dart';
import 'personal_object_match_policy.dart';
import 'personal_object_pages.dart';
import 'personal_objects.dart';
import 'star_home.dart' as star_ui;
import 'stuck_expression_flow.dart';
import 'user_learning.dart';
import 'voice_orb_test_page.dart' show VoiceOrbPainter, VoiceDotsIndicator;
import 'xfyun_realtime_asr_service.dart';

part 'expression_setup_pages.dart';

typedef ExpressionCallback = Future<void> Function(String text);
typedef HabitRecordCallback = Future<void> Function(
  String text, {
  required String category,
  required String source,
  bool? favorite,
});
typedef VocabularyChangedCallback = Future<void> Function(
    List<VocabularyEntry> entries);

enum YuqiaoFeature {
  stuck,
  camera,
  conversation,
  vocabulary,
}

class YuqiaoFeatureLauncher {
  const YuqiaoFeatureLauncher({
    required this.openFeature,
  });

  final void Function(BuildContext context, YuqiaoFeature feature) openFeature;

  void open(BuildContext context, YuqiaoFeature feature) {
    openFeature(context, feature);
  }
}

const bool kYuqiaoDebugLogs = false;

const SystemUiOverlayStyle kYuqiaoSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Color(0xFFF7F2EA),
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarContrastEnforced: false,
  statusBarIconBrightness: Brightness.dark,
  systemNavigationBarIconBrightness: Brightness.dark,
);

void yuqiaoDebugLog(String message) {
  if (kYuqiaoDebugLogs) debugPrint(message);
}

void showYuqiaoLearningReceipt(
  BuildContext context, {
  required bool personalizedLearningEnabled,
  required String learnedMessage,
  required String disabledMessage,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          personalizedLearningEnabled ? learnedMessage : disabledMessage,
        ),
        duration: const Duration(milliseconds: 1300),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(kYuqiaoSystemUiStyle);
  runApp(const YuqiaoApp());
}

class YuqiaoApp extends StatefulWidget {
  const YuqiaoApp({super.key});

  @override
  State<YuqiaoApp> createState() => _YuqiaoAppState();
}

class _YuqiaoAppState extends State<YuqiaoApp> {
  final QwenService _qwenService = QwenService();
  final LocalStore _store = LocalStore();
  final ExpressionHabitStore _habitStore = ExpressionHabitStore();
  final UserLearningStore _userLearningStore = UserLearningStore();
  final PersonalObjectStore _personalObjectStore = PersonalObjectStore();
  late final LocationRecommendationController _locationController;
  late final CompanionAgentController _companionAgent;
  bool _locationInitialized = false;
  bool _localDataLoaded = false;
  bool _personalizedLearningEnabled = true;
  bool _autoStuckDetectionEnabled = false;
  ExpressionPreference _expressionPreference = const ExpressionPreference();
  SupportProfile _supportProfile = const SupportProfile();
  List<String> _recentExpressions = const [];
  List<String> _favoriteExpressions = const [];
  List<ExpressionHabit> _expressionHabits = const [];
  List<VocabularyEntry> _vocabularyEntries = const [];
  List<PersonalObject> _personalObjects = const [];
  List<ConversationTerm> _conversationTerms = const [];

  @override
  void initState() {
    super.initState();
    _locationController = LocationRecommendationController(store: _store)
      ..addListener(_handleLocationChanged);
    _companionAgent = CompanionAgentController(
      locationController: _locationController,
      userLearningStore: _userLearningStore,
    );
    _loadLocalData();
  }

  @override
  void dispose() {
    _locationController
      ..removeListener(_handleLocationChanged)
      ..dispose();
    super.dispose();
  }

  void _handleLocationChanged() {
    if (mounted) setState(() {});
  }

  void _syncCompanionMemory({
    List<String>? recentExpressions,
    List<String>? favoriteExpressions,
    List<ExpressionHabit>? expressionHabits,
    List<PersonalObject>? personalObjects,
    List<ConversationTerm>? conversationTerms,
    bool? learningEnabled,
  }) {
    _companionAgent.updateMemory(
      recentExpressions: recentExpressions ?? _recentExpressions,
      favoriteExpressions: favoriteExpressions ?? _favoriteExpressions,
      expressionHabits: expressionHabits ?? _expressionHabits,
      personalObjects: personalObjects ?? _personalObjects,
      conversationTerms: conversationTerms ?? _conversationTerms,
      learningEnabled: learningEnabled ?? _personalizedLearningEnabled,
    );
  }

  Future<void> _loadLocalData() async {
    final recent = await _store.loadRecentExpressions();
    final favorites = await _store.loadFavoriteExpressions();
    final expressionPreference = await _store.loadExpressionPreference();
    final supportProfile = await _store.loadSupportProfile();
    final autoStuckDetectionEnabled =
        await _store.loadAutoStuckDetectionEnabled();
    final personalizedLearningEnabled = await _habitStore.loadEnabled();
    final List<ExpressionHabit> habits = personalizedLearningEnabled
        ? await _habitStore.loadAll()
        : const <ExpressionHabit>[];
    final vocabulary = await _store.loadVocabularyEntries();
    final vocabularySeedVersion = await _store.loadVocabularySeedVersion();
    final personalObjects = await _personalObjectStore.loadAll();
    final conversationTerms = await ConversationTermStore().loadAll();
    final shouldMergeVocabularyDefaults = vocabulary.isEmpty ||
        vocabularySeedVersion < VocabularyDefaults.version;
    final baseVocabulary = shouldMergeVocabularyDefaults
        ? _mergeVocabularyDefaults(vocabulary)
        : vocabulary;
    final personalById = {
      for (final object in personalObjects) object.id: object,
    };
    final synchronizedVocabulary = <VocabularyEntry>[
      for (final entry in baseVocabulary)
        if (entry.note != '我的物品')
          entry
        else if (personalById[entry.id] case final object?)
          entry.copyWith(text: object.displayName),
      for (final object in personalObjects)
        if (!baseVocabulary.any((entry) => entry.id == object.id))
          VocabularyEntry(
            id: object.id,
            category: '物品',
            text: object.displayName,
            note: '我的物品',
          ),
    ];
    if (shouldMergeVocabularyDefaults ||
        jsonEncode(baseVocabulary.map((entry) => entry.toJson()).toList()) !=
            jsonEncode(synchronizedVocabulary
                .map((entry) => entry.toJson())
                .toList())) {
      await _store.saveVocabularyEntries(synchronizedVocabulary);
      await _store.saveVocabularySeedVersion(VocabularyDefaults.version);
    }
    final effectiveFavorites = favorites.isEmpty
        ? const ['我想问医生', '我不舒服', '请再说一遍', '我想联系家人']
        : favorites;
    if (!_locationInitialized) {
      await _locationController.initialize(favoriteWords: effectiveFavorites);
      _locationInitialized = true;
    } else {
      _locationController.updateFavoriteWords(effectiveFavorites);
    }
    _locationController.updateExpressionHabits(habits, notify: false);
    _syncCompanionMemory(
      recentExpressions: recent,
      favoriteExpressions: effectiveFavorites,
      expressionHabits: habits,
      personalObjects: personalObjects,
      conversationTerms: conversationTerms,
      learningEnabled: personalizedLearningEnabled,
    );
    if (!mounted) return;
    setState(() {
      _recentExpressions = recent;
      _favoriteExpressions = effectiveFavorites;
      _personalizedLearningEnabled = personalizedLearningEnabled;
      _autoStuckDetectionEnabled = autoStuckDetectionEnabled;
      _expressionPreference = expressionPreference;
      _supportProfile = supportProfile;
      _expressionHabits = habits;
      _vocabularyEntries = synchronizedVocabulary;
      _personalObjects = personalObjects;
      _conversationTerms = conversationTerms;
      _localDataLoaded = true;
    });
  }

  List<VocabularyEntry> _mergeVocabularyDefaults(
    List<VocabularyEntry> vocabulary,
  ) {
    if (vocabulary.isEmpty) return VocabularyDefaults.entries;
    final existingIds = vocabulary.map((entry) => entry.id).toSet();
    final existingCategoryTexts = vocabulary
        .map((entry) => '${entry.category.trim()}|${entry.text.trim()}')
        .toSet();
    return [
      ...vocabulary,
      for (final entry in VocabularyDefaults.entries)
        if (!existingIds.contains(entry.id) &&
            !existingCategoryTexts
                .contains('${entry.category.trim()}|${entry.text.trim()}'))
          entry,
    ];
  }

  Future<void> _recordExpression(String text) async {
    await _store.addRecentExpression(text);
    await _recordHabit(
      text,
      category: 'expression',
      source: 'confirm',
    );
    await _loadLocalData();
  }

  Future<void> _saveFavorite(String text) async {
    await _store.addFavoriteExpression(text);
    await _recordHabit(
      text,
      category: 'favorite',
      source: 'favorite',
      favorite: true,
    );
    await _loadLocalData();
  }

  Future<void> _recordHabit(
    String text, {
    required String category,
    required String source,
    bool? favorite,
  }) async {
    if (!_personalizedLearningEnabled) return;
    final placeType = _locationController.currentPlace?.normalizedType ??
        _locationController.currentSemantic?.type;
    await _habitStore.recordUsed(
      text,
      category: category,
      source: source,
      placeType: placeType,
      favorite: favorite ?? false,
    );
    final habits = await _habitStore.loadAll();
    _locationController.updateExpressionHabits(habits, notify: false);
    _syncCompanionMemory(expressionHabits: habits);
    if (!mounted) return;
    setState(() => _expressionHabits = habits);
  }

  Future<void> _setPersonalizedLearningEnabled(bool enabled) async {
    await _habitStore.setEnabled(enabled);
    final List<ExpressionHabit> habits =
        enabled ? await _habitStore.loadAll() : const <ExpressionHabit>[];
    _locationController.updateExpressionHabits(habits, notify: false);
    _syncCompanionMemory(
      expressionHabits: habits,
      learningEnabled: enabled,
    );
    if (!mounted) return;
    setState(() {
      _personalizedLearningEnabled = enabled;
      _expressionHabits = habits;
    });
  }

  Future<void> _setAutoStuckDetectionEnabled(bool enabled) async {
    await _store.saveAutoStuckDetectionEnabled(enabled);
    if (!mounted) return;
    setState(() => _autoStuckDetectionEnabled = enabled);
  }

  Future<void> _saveExpressionPreference(
    ExpressionPreference preference,
  ) async {
    await _store.saveExpressionPreference(preference);
    if (!mounted) return;
    setState(() => _expressionPreference = preference);
  }

  Future<List<String>> _seedSupportProfileFavorites(
    SupportProfile profile,
  ) async {
    final phrases = <String>{
      if (profile.scenes.contains('家里')) ...[
        '我想喝水',
        '我想休息',
        '请帮我拿一下',
      ],
      if (profile.scenes.contains('医院')) ...[
        '我想问医生',
        '我不舒服',
        '请帮我叫护士',
      ],
      if (profile.scenes.contains('康复训练')) ...[
        '我想慢一点',
        '我需要休息一下',
        '请再示范一次',
      ],
      if (profile.scenes.contains('超市')) ...[
        '我要买这个',
        '这个多少钱',
        '请帮我结账',
      ],
      if (profile.scenes.contains('电话')) ...[
        '请说慢一点',
        '我听不太清楚',
        '请再说一遍',
      ],
      if (profile.scenes.contains('社交')) ...[
        '谢谢你',
        '我想和你聊聊',
        '请等我一下',
      ],
      if (profile.scenes.contains('出门交通')) ...[
        '我要回家',
        '请带我去这里',
        '我需要帮助',
      ],
      if (profile.scenes.contains('紧急求助')) ...[
        '请帮帮我',
        '请联系我的家人',
        '我需要医生',
      ],
    };
    for (final phrase in phrases.take(8)) {
      await _store.addFavoriteExpression(phrase);
    }
    return _store.loadFavoriteExpressions();
  }

  Future<void> _completeSupportProfile(SupportProfile profile) async {
    final completedProfile = profile.copyWith(
      completed: true,
      createdAt: DateTime.now(),
    );
    final preference = completedProfile.toExpressionPreference();
    await _store.saveSupportProfile(completedProfile);
    await _store.saveExpressionPreference(preference);
    await _habitStore.setEnabled(completedProfile.rememberChoices);
    final updatedFavorites =
        await _seedSupportProfileFavorites(completedProfile);
    _locationController.updateFavoriteWords(updatedFavorites);
    _syncCompanionMemory(
      favoriteExpressions: updatedFavorites,
      learningEnabled: completedProfile.rememberChoices,
    );
    if (!mounted) return;
    setState(() {
      _supportProfile = completedProfile;
      _expressionPreference = preference;
      _personalizedLearningEnabled = completedProfile.rememberChoices;
      _favoriteExpressions = updatedFavorites;
    });
  }

  Future<void> _clearExpressionHabits() async {
    await _habitStore.clearAll();
    await _userLearningStore.clear();
    await CompanionFeedbackStore().clearAll();
    _locationController.updateExpressionHabits(const [], notify: false);
    _syncCompanionMemory(expressionHabits: const []);
    if (!mounted) return;
    setState(() {
      _expressionHabits = const [];
    });
  }

  Future<void> _saveVocabulary(List<VocabularyEntry> entries) async {
    await _store.saveVocabularyEntries(entries);
    await _loadLocalData();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kYuqiaoSystemUiStyle,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '语桥',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        builder: (context, child) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: kYuqiaoSystemUiStyle,
            child: ColoredBox(
              color: const Color(0xFFF7F2EA),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: !_localDataLoaded
            ? const _YuqiaoLoadingPage()
            : !_supportProfile.completed
                ? SupportProfileSetupPage(
                    initialProfile: _supportProfile,
                    onCompleted: _completeSupportProfile,
                  )
                : HomePage(
                    qwenService: _qwenService,
                    locationController: _locationController,
                    companionAgent: _companionAgent,
                    personalizedLearningEnabled: _personalizedLearningEnabled,
                    autoStuckDetectionEnabled: _autoStuckDetectionEnabled,
                    expressionPreference: _expressionPreference,
                    recentExpressions: _recentExpressions,
                    favoriteExpressions: _favoriteExpressions,
                    expressionHabits: _expressionHabits,
                    vocabularyEntries: _vocabularyEntries,
                    personalObjects: _personalObjects,
                    personalObjectStore: _personalObjectStore,
                    onExpressionCompleted: _recordExpression,
                    onFavoriteSaved: _saveFavorite,
                    onHabitRecorded: _recordHabit,
                    onPersonalizedLearningChanged:
                        _setPersonalizedLearningEnabled,
                    onAutoStuckDetectionChanged: _setAutoStuckDetectionEnabled,
                    onExpressionPreferenceChanged: _saveExpressionPreference,
                    onClearPersonalizedLearningData: _clearExpressionHabits,
                    onVocabularyChanged: _saveVocabulary,
                    onPersonalObjectsChanged: _loadLocalData,
                  ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.qwenService,
    required this.locationController,
    required this.companionAgent,
    required this.personalizedLearningEnabled,
    required this.autoStuckDetectionEnabled,
    required this.expressionPreference,
    required this.recentExpressions,
    required this.favoriteExpressions,
    required this.expressionHabits,
    required this.vocabularyEntries,
    required this.personalObjects,
    required this.personalObjectStore,
    required this.onExpressionCompleted,
    required this.onFavoriteSaved,
    required this.onHabitRecorded,
    required this.onPersonalizedLearningChanged,
    required this.onAutoStuckDetectionChanged,
    required this.onExpressionPreferenceChanged,
    required this.onClearPersonalizedLearningData,
    required this.onVocabularyChanged,
    required this.onPersonalObjectsChanged,
  });

  final QwenService qwenService;
  final LocationRecommendationController locationController;
  final CompanionAgentController companionAgent;
  final bool personalizedLearningEnabled;
  final bool autoStuckDetectionEnabled;
  final ExpressionPreference expressionPreference;
  final List<String> recentExpressions;
  final List<String> favoriteExpressions;
  final List<ExpressionHabit> expressionHabits;
  final List<VocabularyEntry> vocabularyEntries;
  final List<PersonalObject> personalObjects;
  final PersonalObjectStore personalObjectStore;
  final ExpressionCallback onExpressionCompleted;
  final ExpressionCallback onFavoriteSaved;
  final HabitRecordCallback onHabitRecorded;
  final ValueChanged<bool> onPersonalizedLearningChanged;
  final ValueChanged<bool> onAutoStuckDetectionChanged;
  final ValueChanged<ExpressionPreference> onExpressionPreferenceChanged;
  final VoidCallback onClearPersonalizedLearningData;
  final VocabularyChangedCallback onVocabularyChanged;
  final Future<void> Function() onPersonalObjectsChanged;

  YuqiaoFeatureLauncher get _featureLauncher => YuqiaoFeatureLauncher(
        openFeature: _openFeatureFromFloatingBall,
      );

  void _openFeatureFromFloatingBall(
    BuildContext context,
    YuqiaoFeature feature,
  ) {
    locationController.refreshLocationContext();
    Navigator.of(context).pushReplacement(_buildFeatureRoute(context, feature));
  }

  MaterialPageRoute<void> _buildFeatureRoute(
    BuildContext context,
    YuqiaoFeature feature,
  ) {
    return MaterialPageRoute<void>(
      builder: (_) {
        switch (feature) {
          case YuqiaoFeature.stuck:
            return StuckFlowPage(
              qwenService: qwenService,
              locationController: locationController,
              companionAgent: companionAgent,
              personalizedLearningEnabled: personalizedLearningEnabled,
              vocabularyEntries: vocabularyEntries,
              expressionHabits: expressionHabits,
              preferredCandidateCount:
                  expressionPreference.effectiveCandidateCount,
              candidateImageScale: expressionPreference.effectiveImageScale,
              featureLauncher: _featureLauncher,
              onHabitRecorded: onHabitRecorded,
              onExpressionCompleted: (text) async {
                await onExpressionCompleted(text);
                unawaited(locationController.recordWordUsed(text, 'stuck'));
              },
              onFavoriteSaved: (text) async {
                await onFavoriteSaved(text);
                unawaited(locationController.recordWordUsed(text, 'stuck'));
              },
            );
          case YuqiaoFeature.camera:
            return CameraWordPage(
              qwenService: qwenService,
              locationController: locationController,
              companionAgent: companionAgent,
              personalizedLearningEnabled: personalizedLearningEnabled,
              vocabularyEntries: vocabularyEntries,
              personalObjects: personalObjects,
              expressionHabits: expressionHabits,
              personalObjectStore: personalObjectStore,
              featureLauncher: _featureLauncher,
              onPersonalObjectsChanged: onPersonalObjectsChanged,
              onHabitRecorded: onHabitRecorded,
              onVocabularyChanged: onVocabularyChanged,
              onExpressionCompleted: (text) async {
                await onExpressionCompleted(text);
                unawaited(locationController.recordWordUsed(text, 'camera'));
              },
              onFavoriteSaved: (text) async {
                await onFavoriteSaved(text);
                unawaited(locationController.recordWordUsed(text, 'camera'));
              },
            );
          case YuqiaoFeature.conversation:
            return ConversationModePage(
              qwenService: qwenService,
              locationController: locationController,
              companionAgent: companionAgent,
              personalizedLearningEnabled: personalizedLearningEnabled,
              recentExpressions: recentExpressions,
              favoriteExpressions: favoriteExpressions,
              expressionHabits: expressionHabits,
              vocabularyEntries: vocabularyEntries,
              candidateImageScale: expressionPreference.effectiveImageScale,
              featureLauncher: _featureLauncher,
              onHabitRecorded: onHabitRecorded,
              onExpressionCompleted: (text) async {
                await onExpressionCompleted(text);
                unawaited(
                  locationController.recordWordUsed(text, 'conversation'),
                );
              },
              onFavoriteSaved: (text) async {
                await onFavoriteSaved(text);
                unawaited(
                  locationController.recordWordUsed(text, 'conversation'),
                );
              },
            );
          case YuqiaoFeature.vocabulary:
            return VocabularyPage(
              entries: vocabularyEntries,
              onChanged: onVocabularyChanged,
              locationController: locationController,
              companionAgent: companionAgent,
              personalizedLearningEnabled: personalizedLearningEnabled,
              qwenService: qwenService,
              personalObjects: personalObjects,
              expressionHabits: expressionHabits,
              personalObjectStore: personalObjectStore,
              featureLauncher: _featureLauncher,
              onAddPersonalObject: (objects) => _openCamera(
                context,
                personalObjectsOverride: objects,
              ),
              onOpenPersonalObjects: () => _openPersonalObjects(context),
              onExpressionCompleted: onExpressionCompleted,
              onFavoriteSaved: onFavoriteSaved,
              onHabitRecorded: onHabitRecorded,
            );
        }
      },
    );
  }

  Future<void> _openCamera(
    BuildContext context, {
    List<PersonalObject>? personalObjectsOverride,
  }) async {
    locationController.refreshLocationContext();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraWordPage(
          qwenService: qwenService,
          locationController: locationController,
          companionAgent: companionAgent,
          personalizedLearningEnabled: personalizedLearningEnabled,
          vocabularyEntries: vocabularyEntries,
          personalObjects: personalObjectsOverride ?? personalObjects,
          expressionHabits: expressionHabits,
          personalObjectStore: personalObjectStore,
          featureLauncher: _featureLauncher,
          onPersonalObjectsChanged: onPersonalObjectsChanged,
          onHabitRecorded: onHabitRecorded,
          onVocabularyChanged: onVocabularyChanged,
          onExpressionCompleted: (text) async {
            await onExpressionCompleted(text);
            unawaited(locationController.recordWordUsed(text, 'camera'));
          },
          onFavoriteSaved: (text) async {
            await onFavoriteSaved(text);
            unawaited(locationController.recordWordUsed(text, 'camera'));
          },
        ),
      ),
    );
    await onPersonalObjectsChanged();
  }

  Future<void> _openPersonalObjects(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (managerContext) => PersonalObjectManagementPage(
          store: personalObjectStore,
          companionAgent: companionAgent,
          personalizedLearningEnabled: personalizedLearningEnabled,
          onChanged: onPersonalObjectsChanged,
          onAdd: () => _openCamera(managerContext),
        ),
      ),
    );
    await onPersonalObjectsChanged();
  }

  Future<void> _openYuqiaoMemory(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => YuqiaoMemoryPage(
          recentExpressions: recentExpressions,
          favoriteExpressions: favoriteExpressions,
          expressionHabits: expressionHabits,
          personalObjects: personalObjects,
          locationController: locationController,
          personalizedLearningEnabled: personalizedLearningEnabled,
        ),
      ),
    );
  }

  Future<void> _openExpressionPreferences(BuildContext context) async {
    final updated = await Navigator.of(context).push<ExpressionPreference>(
      MaterialPageRoute<ExpressionPreference>(
        builder: (_) => ExpressionPreferencePage(
          initialPreference: expressionPreference,
        ),
      ),
    );
    if (updated != null) onExpressionPreferenceChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return star_ui.MainInterfaceScreen(
      locationRecommendationEnabled: locationController.enabled,
      personalizedLearningEnabled: personalizedLearningEnabled,
      autoStuckDetectionEnabled: autoStuckDetectionEnabled,
      expressionPreferenceSummary: expressionPreference.summary,
      savedWordCount: vocabularyEntries.length,
      savedPlaceCount: locationController.placeCount,
      savedPersonalObjectCount: personalObjects.length,
      onLocationRecommendationChanged: locationController.setEnabled,
      onPersonalizedLearningChanged: onPersonalizedLearningChanged,
      onLearningProfileChanged: () async {},
      onAutoStuckDetectionChanged: onAutoStuckDetectionChanged,
      onOpenExpressionPreferences: () => _openExpressionPreferences(context),
      onClearPersonalizedLearningData: onClearPersonalizedLearningData,
      onClearPlaceData: locationController.clearPlaceData,
      locationController: locationController, // TODO: 调试用，以后删除
      onFavoriteSaved: onFavoriteSaved,
      onStarPhraseSpoken: onExpressionCompleted,
      onOpenYuqiaoMemory: () => _openYuqiaoMemory(context),
      onOpenPersonalObjects: () => _openPersonalObjects(context),
      onStuck: () {
        locationController.refreshLocationContext();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StuckFlowPage(
              qwenService: qwenService,
              locationController: locationController,
              companionAgent: companionAgent,
              personalizedLearningEnabled: personalizedLearningEnabled,
              vocabularyEntries: vocabularyEntries,
              expressionHabits: expressionHabits,
              preferredCandidateCount:
                  expressionPreference.effectiveCandidateCount,
              candidateImageScale: expressionPreference.effectiveImageScale,
              featureLauncher: _featureLauncher,
              onHabitRecorded: onHabitRecorded,
              onExpressionCompleted: (text) async {
                await onExpressionCompleted(text);
                unawaited(locationController.recordWordUsed(text, 'stuck'));
              },
              onFavoriteSaved: (text) async {
                await onFavoriteSaved(text);
                unawaited(locationController.recordWordUsed(text, 'stuck'));
              },
            ),
          ),
        );
      },
      onCamera: () => _openCamera(context),
      onConversation: () {
        locationController.refreshLocationContext();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConversationModePage(
              qwenService: qwenService,
              locationController: locationController,
              companionAgent: companionAgent,
              personalizedLearningEnabled: personalizedLearningEnabled,
              recentExpressions: recentExpressions,
              favoriteExpressions: favoriteExpressions,
              expressionHabits: expressionHabits,
              vocabularyEntries: vocabularyEntries,
              candidateImageScale: expressionPreference.effectiveImageScale,
              featureLauncher: _featureLauncher,
              onHabitRecorded: onHabitRecorded,
              onExpressionCompleted: (text) async {
                await onExpressionCompleted(text);
                unawaited(
                  locationController.recordWordUsed(text, 'conversation'),
                );
              },
              onFavoriteSaved: (text) async {
                await onFavoriteSaved(text);
                unawaited(
                  locationController.recordWordUsed(text, 'conversation'),
                );
              },
            ),
          ),
        );
      },
      onVocabulary: () {
        locationController.refreshLocationContext();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VocabularyPage(
              entries: vocabularyEntries,
              onChanged: onVocabularyChanged,
              locationController: locationController,
              companionAgent: companionAgent,
              personalizedLearningEnabled: personalizedLearningEnabled,
              qwenService: qwenService,
              personalObjects: personalObjects,
              expressionHabits: expressionHabits,
              personalObjectStore: personalObjectStore,
              featureLauncher: _featureLauncher,
              onAddPersonalObject: (objects) => _openCamera(
                context,
                personalObjectsOverride: objects,
              ),
              onOpenPersonalObjects: () => _openPersonalObjects(context),
              onExpressionCompleted: onExpressionCompleted,
              onFavoriteSaved: onFavoriteSaved,
              onHabitRecorded: onHabitRecorded,
            ),
          ),
        );
      },
    );
  }
}

class YuqiaoFeatureAssistiveBall extends StatefulWidget {
  const YuqiaoFeatureAssistiveBall({
    super.key,
    required this.currentFeature,
    required this.launcher,
    this.bottomClearance = 24,
  });

  final YuqiaoFeature currentFeature;
  final YuqiaoFeatureLauncher launcher;
  final double bottomClearance;

  @override
  State<YuqiaoFeatureAssistiveBall> createState() =>
      _YuqiaoFeatureAssistiveBallState();
}

class _YuqiaoFeatureAssistiveBallState
    extends State<YuqiaoFeatureAssistiveBall> {
  static Offset? _lastOffset;
  static const double _ballSize = 58;
  static const double _margin = 14;

  Offset? _offset;
  bool _expanded = false;
  bool _dragged = false;
  bool _docked = false;
  Timer? _idleTimer;

  List<YuqiaoFeature> get _targets => YuqiaoFeature.values
      .where((feature) => feature != widget.currentFeature)
      .toList(growable: false);

  Offset _initialOffset(Size size, EdgeInsets safeArea) {
    return Offset(
      size.width - _ballSize - _margin,
      (size.height * 0.56).clamp(
        safeArea.top + 76,
        size.height - safeArea.bottom - widget.bottomClearance - _ballSize,
      ),
    );
  }

  Offset _clampOffset(Offset value, Size size, EdgeInsets safeArea) {
    final minY = safeArea.top + 72;
    final maxY = math.max(
      minY,
      size.height - safeArea.bottom - widget.bottomClearance - _ballSize,
    );
    return Offset(
      value.dx.clamp(_margin, size.width - _ballSize - _margin).toDouble(),
      value.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Offset _offsetForPointer(
    Offset globalPosition,
    BuildContext layoutContext,
    Size size,
    EdgeInsets safeArea,
  ) {
    final box = layoutContext.findRenderObject() as RenderBox?;
    if (box == null) {
      return _offset ?? _initialOffset(size, safeArea);
    }
    final localPosition = box.globalToLocal(globalPosition);
    return _clampOffset(
      localPosition - Offset(_ballSize / 2, _ballSize / 2),
      size,
      safeArea,
    );
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (_expanded || _dragged) return;
    _idleTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _expanded || _dragged) return;
      setState(() => _docked = true);
    });
  }

  void _wakeBall() {
    _idleTimer?.cancel();
    if (_docked) {
      setState(() => _docked = false);
    }
  }

  void _snapToEdge(Size size, EdgeInsets safeArea) {
    final current = _offset ?? _initialOffset(size, safeArea);
    final snapLeft = current.dx + _ballSize / 2 < size.width / 2;
    final snapped = _clampOffset(
      Offset(
        snapLeft ? _margin : size.width - _ballSize - _margin,
        current.dy,
      ),
      size,
      safeArea,
    );
    setState(() {
      _offset = snapped;
      _lastOffset = snapped;
    });
    _restartIdleTimer();
  }

  @override
  void initState() {
    super.initState();
    _restartIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  String _labelOf(YuqiaoFeature feature) {
    return switch (feature) {
      YuqiaoFeature.stuck => '卡住表达',
      YuqiaoFeature.camera => '拍照找词',
      YuqiaoFeature.conversation => '对话补词',
      YuqiaoFeature.vocabulary => '常用词库',
    };
  }

  String _hintOf(YuqiaoFeature feature) {
    return switch (feature) {
      YuqiaoFeature.stuck => '说不出来时',
      YuqiaoFeature.camera => '看见物品时',
      YuqiaoFeature.conversation => '听对话时',
      YuqiaoFeature.vocabulary => '找常用词时',
    };
  }

  IconData _iconOf(YuqiaoFeature feature) {
    return switch (feature) {
      YuqiaoFeature.stuck => Icons.psychology_alt_rounded,
      YuqiaoFeature.camera => Icons.photo_camera_rounded,
      YuqiaoFeature.conversation => Icons.graphic_eq_rounded,
      YuqiaoFeature.vocabulary => Icons.menu_book_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final currentOffset = _clampOffset(
              _offset ?? _lastOffset ?? _initialOffset(size, safeArea),
              size,
              safeArea);
          _offset = currentOffset;
          final isLeftSide = currentOffset.dx < size.width / 2;
          final menuWidth = math.min(190.0, size.width - _margin * 2);
          final menuLeft = isLeftSide
              ? currentOffset.dx + _ballSize + 10
              : currentOffset.dx - menuWidth - 10;
          final menuTop = _clampOffset(
            Offset(
              currentOffset.dx,
              currentOffset.dy - 42,
            ),
            size,
            safeArea,
          ).dy;
          final dockShift = _docked
              ? (isLeftSide ? -_ballSize * 0.46 : _ballSize * 0.46)
              : 0.0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (_expanded)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      setState(() => _expanded = false);
                      _restartIdleTimer();
                    },
                  ),
                ),
              if (_expanded)
                Positioned(
                  left:
                      menuLeft.clamp(_margin, size.width - menuWidth - _margin),
                  top: menuTop,
                  width: menuWidth,
                  child: _YuqiaoFeatureMenu(
                    targets: _targets,
                    labelOf: _labelOf,
                    hintOf: _hintOf,
                    iconOf: _iconOf,
                    onSelected: (feature) {
                      setState(() => _expanded = false);
                      _restartIdleTimer();
                      widget.launcher.open(context, feature);
                    },
                  ),
                ),
              AnimatedPositioned(
                duration: _dragged
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: currentOffset.dx,
                top: currentOffset.dy,
                child: AnimatedSlide(
                  offset: Offset(dockShift / _ballSize, 0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_dragged) return;
                      if (_docked) {
                        _wakeBall();
                        _restartIdleTimer();
                        return;
                      }
                      setState(() => _expanded = !_expanded);
                      _restartIdleTimer();
                    },
                    onPanStart: (details) {
                      _idleTimer?.cancel();
                      setState(() {
                        _dragged = true;
                        _docked = false;
                        _expanded = false;
                        _offset = _offsetForPointer(
                          details.globalPosition,
                          context,
                          size,
                          safeArea,
                        );
                        _lastOffset = _offset;
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _offset = _offsetForPointer(
                          details.globalPosition,
                          context,
                          size,
                          safeArea,
                        );
                        _lastOffset = _offset;
                      });
                    },
                    onPanEnd: (_) {
                      _dragged = false;
                      _snapToEdge(size, safeArea);
                    },
                    onPanCancel: () {
                      _dragged = false;
                      _snapToEdge(size, safeArea);
                    },
                    child: _YuqiaoFeatureBallButton(
                      expanded: _expanded,
                      docked: _docked,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _YuqiaoFeatureBallButton extends StatelessWidget {
  const _YuqiaoFeatureBallButton({
    required this.expanded,
    required this.docked,
  });

  final bool expanded;
  final bool docked;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: docked ? 0.48 : 1,
      duration: const Duration(milliseconds: 260),
      child: AnimatedScale(
        scale: expanded ? 1.04 : 1,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: _YuqiaoFeatureAssistiveBallState._ballSize,
          height: _YuqiaoFeatureAssistiveBallState._ballSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFF8D9),
                Color(0xFFFFC86A),
                Color(0xFFFF8E6E),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: docked ? 0.56 : 0.86),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7A4C13)
                    .withValues(alpha: docked ? 0.08 : 0.22),
                blurRadius: docked ? 12 : 22,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Icon(
            expanded ? Icons.close_rounded : Icons.auto_awesome_rounded,
            color: const Color(0xFF503615),
            size: expanded ? 27 : 29,
          ),
        ),
      ),
    );
  }
}

class _YuqiaoFeatureMenu extends StatelessWidget {
  const _YuqiaoFeatureMenu({
    required this.targets,
    required this.labelOf,
    required this.hintOf,
    required this.iconOf,
    required this.onSelected,
  });

  final List<YuqiaoFeature> targets;
  final String Function(YuqiaoFeature feature) labelOf;
  final String Function(YuqiaoFeature feature) hintOf;
  final IconData Function(YuqiaoFeature feature) iconOf;
  final ValueChanged<YuqiaoFeature> onSelected;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.74),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final feature in targets)
                _YuqiaoFeatureMenuItem(
                  icon: iconOf(feature),
                  label: labelOf(feature),
                  hint: hintOf(feature),
                  onTap: () => onSelected(feature),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YuqiaoFeatureMenuItem extends StatelessWidget {
  const _YuqiaoFeatureMenuItem({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0CE),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: const Color(0xFF7B4E15), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF24211C),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8C8172),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF9B8B77),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VocabularyPage extends StatefulWidget {
  const VocabularyPage({
    super.key,
    required this.entries,
    required this.onChanged,
    required this.locationController,
    required this.companionAgent,
    required this.personalizedLearningEnabled,
    required this.featureLauncher,
    required this.qwenService,
    required this.personalObjects,
    required this.expressionHabits,
    required this.personalObjectStore,
    required this.onAddPersonalObject,
    required this.onOpenPersonalObjects,
    required this.onExpressionCompleted,
    required this.onFavoriteSaved,
    required this.onHabitRecorded,
  });

  final List<VocabularyEntry> entries;
  final VocabularyChangedCallback onChanged;
  final LocationRecommendationController locationController;
  final CompanionAgentController companionAgent;
  final bool personalizedLearningEnabled;
  final YuqiaoFeatureLauncher featureLauncher;
  final QwenService qwenService;
  final List<PersonalObject> personalObjects;
  final List<ExpressionHabit> expressionHabits;
  final PersonalObjectStore personalObjectStore;
  final Future<void> Function(List<PersonalObject>) onAddPersonalObject;
  final Future<void> Function() onOpenPersonalObjects;
  final ExpressionCallback onExpressionCompleted;
  final ExpressionCallback onFavoriteSaved;
  final HabitRecordCallback onHabitRecorded;

  @override
  State<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<VocabularyPage> {
  late List<VocabularyEntry> _entries;
  late List<PersonalObject> _personalObjects;
  List<String> _customCategories = [];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ParaformerAsrService _asrService = ParaformerAsrService();
  final FlutterTts _tts = FlutterTts();
  bool _isRecording = false;
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _entries = List.of(widget.entries);
    _personalObjects = List.of(widget.personalObjects);
    _loadCustomCategories();
    _loadCustomStyles();
    widget.locationController.refreshLocationContext();
    _tts.setLanguage('zh-CN');
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text);
    });
  }

  @override
  void didUpdateWidget(covariant VocabularyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personalObjects != widget.personalObjects) {
      _personalObjects = List.of(widget.personalObjects);
    }
  }

  Future<void> _reloadPersonalObjects() async {
    final objects = await widget.personalObjectStore.loadAll();
    if (mounted) setState(() => _personalObjects = objects);
  }

  Future<void> _addPersonalObject() async {
    await widget.onAddPersonalObject(_personalObjects);
    await _reloadPersonalObjects();
  }

  Future<void> _openPersonalObjectManager() async {
    await widget.onOpenPersonalObjects();
    await _reloadPersonalObjects();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _tts.stop();
    unawaited(_asrService.dispose());
    super.dispose();
  }

  Future<void> _loadCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('custom_vocabulary_categories') ?? [];
    if (mounted) {
      setState(() => _customCategories = list);
    }
  }

  Future<void> _saveCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'custom_vocabulary_categories', _customCategories);
  }

  Map<String, Map<String, dynamic>> _customStyles = {};

  Future<void> _loadCustomStyles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('custom_category_styles') ?? '{}';
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, Map<String, dynamic>>{};
      for (final entry in decoded.entries) {
        result[entry.key] = Map<String, dynamic>.from(entry.value as Map);
      }
      if (mounted) setState(() => _customStyles = result);
    } catch (_) {}
  }

  Future<void> _saveCustomStyle(
      String name, IconData icon, Color iconColor, List<Color> colors) async {
    final iconCodePoint = icon.codePoint;
    final iconFontFamily = icon.fontFamily;
    final iconColorValue = iconColor.toARGB32();
    final colorValues = colors.map((c) => c.toARGB32()).toList();

    _customStyles[name] = {
      'iconCodePoint': iconCodePoint,
      'iconFontFamily': iconFontFamily,
      'iconColor': iconColorValue,
      'colors': colorValues,
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_category_styles', jsonEncode(_customStyles));
    if (mounted) setState(() {});
  }

  _VocabularyCategoryMeta _applyCustomStyle(_VocabularyCategoryMeta meta) {
    final style = _customStyles[meta.name];
    if (style == null) return meta;
    return _VocabularyCategoryMeta(
      name: meta.name,
      description: meta.description,
      icon: IconData(
        style['iconCodePoint'] as int? ?? meta.icon.codePoint,
        fontFamily: style['iconFontFamily'] as String? ?? meta.icon.fontFamily,
      ),
      iconColor: Color(style['iconColor'] as int? ?? meta.iconColor.toARGB32()),
      colors: (style['colors'] as List<dynamic>?)
              ?.map((v) => Color(v as int))
              .toList() ??
          meta.colors,
    );
  }

  Future<void> _recordWordUsage(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final freq = prefs.getStringList('vocabulary_word_freq') ?? [];
    final map = <String, int>{};
    for (final item in freq) {
      final parts = item.split(':');
      if (parts.length == 2) {
        map[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
    }
    map[text] = (map[text] ?? 0) + 1;
    await prefs.setStringList(
      'vocabulary_word_freq',
      map.entries.map((e) => '${e.key}:${e.value}').toList(),
    );
    await widget.onHabitRecorded(
      text,
      category: 'vocabulary',
      source: 'vocabulary_word',
    );
    unawaited(widget.companionAgent.recordInteraction(
      text: text,
      feature: 'vocabulary',
      action: CompanionFeedbackAction.spoken,
      prompt: _searchText,
      slot: RecommendationSlot.actionOrObject,
    ));
    if (mounted) {
      showYuqiaoLearningReceipt(
        context,
        personalizedLearningEnabled: widget.personalizedLearningEnabled,
        learnedMessage: '已播报，语桥会记住这个常用词',
        disabledMessage: '已播报，个性化学习已关闭',
      );
    }
  }

  Future<void> _toggleSearchAsr() async {
    if (_isRecording) {
      await _asrService.stop();
      if (mounted) setState(() => _isRecording = false);
      return;
    }
    setState(() => _isRecording = true);
    _searchFocus.unfocus();
    try {
      await _asrService.start(
        onTranscript: (text, isFinal) {
          if (!mounted) return;
          _searchController.text = text;
          _searchController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
          if (isFinal) {
            setState(() => _isRecording = false);
            unawaited(_asrService.stop());
          }
        },
        onStatus: (_) {},
        onError: (msg) {
          if (!mounted) return;
          setState(() => _isRecording = false);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('语音识别失败：$msg')));
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecording = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('无法启动阿里云语音搜索：$e')));
    }
  }

  List<VocabularyEntry> get _filteredEntries {
    if (_searchText.trim().isEmpty) return _entries;
    final query = _searchText.trim().toLowerCase();
    final personalObjectIds =
        _personalObjects.map((object) => object.id).toSet();
    return _entries
        .where((e) =>
            !personalObjectIds.contains(e.id) &&
            (e.text.toLowerCase().contains(query) ||
                e.category.toLowerCase().contains(query) ||
                e.note.toLowerCase().contains(query)))
        .toList();
  }

  List<PersonalObject> get _filteredPersonalObjects {
    final query = _searchText.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _personalObjects.where((object) {
      return object.displayName.toLowerCase().contains(query) ||
          object.category.toLowerCase().contains(query) ||
          object.visualDescription.toLowerCase().contains(query) ||
          object.note.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _persist(List<VocabularyEntry> next) async {
    setState(() => _entries = next);
    await widget.onChanged(next);
  }

  Future<void> _addEntry(String category) async {
    final result = await showModalBottomSheet<VocabularyEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddVocabularySheet(initialCategory: category),
    );
    if (result == null) return;
    final cleaned = result.text.trim();
    if (cleaned.isEmpty) return;
    final exists = _entries.any(
      (entry) => entry.category == result.category && entry.text == cleaned,
    );
    if (exists) return;
    await _persist([result.copyWith(text: cleaned), ..._entries]);
    await widget.locationController.recordWordUsed(cleaned, 'vocabulary');
    await widget.onHabitRecorded(
      cleaned,
      category: 'vocabulary',
      source: 'vocabulary_saved',
    );
    await widget.companionAgent.recordInteraction(
      text: cleaned,
      feature: 'vocabulary',
      action: CompanionFeedbackAction.saved,
      prompt: result.category,
      slot: RecommendationSlot.actionOrObject,
    );
    if (mounted) {
      showYuqiaoLearningReceipt(
        context,
        personalizedLearningEnabled: widget.personalizedLearningEnabled,
        learnedMessage: '已保存，语桥会记住这个常用词',
        disabledMessage: '已保存，个性化学习已关闭',
      );
    }
  }

  Future<void> _deleteEntry(VocabularyEntry entry) async {
    await _persist(_entries.where((item) => item.id != entry.id).toList());
    await widget.companionAgent.recordInteraction(
      text: entry.text,
      feature: 'vocabulary',
      action: CompanionFeedbackAction.deleted,
      prompt: entry.category,
      slot: RecommendationSlot.actionOrObject,
    );
    if (mounted) {
      showYuqiaoLearningReceipt(
        context,
        personalizedLearningEnabled: widget.personalizedLearningEnabled,
        learnedMessage: '已删除，语桥会降低这个词的优先级',
        disabledMessage: '已删除，个性化学习已关闭',
      );
    }
  }

  Future<void> _addCategory() async {
    final name = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (ctx) {
        final controller = TextEditingController();
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: SizedBox(
            width: 320,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 外层柔光
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFFF72A8).withValues(alpha: 0.10),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color:
                                const Color(0xFF8FD7F7).withValues(alpha: 0.08),
                            blurRadius: 28,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 渐变边框 + 内容
                Container(
                  padding: const EdgeInsets.all(1.6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFF78AF),
                        Color(0xFFFFC1BE),
                        Color(0xFFF4F1A1),
                        Color(0xFFAAEEA8),
                        Color(0xFFADE8F6),
                        Color(0xFFFFD9E5),
                      ],
                      stops: [0.00, 0.22, 0.40, 0.62, 0.82, 1.00],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.92),
                              const Color(0xFFFFFBFC).withValues(alpha: 0.86),
                              const Color(0xFFFDFDFE).withValues(alpha: 0.82),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            // 顶部高光
                            Positioned(
                              left: 18,
                              right: 18,
                              top: 10,
                              child: Container(
                                height: 26,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.58),
                                      Colors.white.withValues(alpha: 0.08),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // 内部彩色雾感
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _TranscriptGlowPainter(),
                                ),
                              ),
                            ),
                            // 内容
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 28, 24, 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 标题
                                  const Text(
                                    '新建词典',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                      color: Color(0xFF17181C),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '创建一个自定义词典分类',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF2A2D34)
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  // 输入框
                                  Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                      ),
                                    ),
                                    child: TextField(
                                      controller: controller,
                                      autofocus: true,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF2A2D34),
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '如"运动""工作"',
                                        hintStyle: TextStyle(
                                          color: Colors.black
                                              .withValues(alpha: 0.28),
                                          fontWeight: FontWeight.w600,
                                        ),
                                        border: InputBorder.none,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 18, vertical: 14),
                                        counterStyle: TextStyle(
                                          color: Colors.black
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      maxLength: 10,
                                      onSubmitted: (v) =>
                                          Navigator.of(ctx).pop(v.trim()),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  // 按钮行
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => Navigator.of(ctx).pop(),
                                          child: Container(
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.6),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '取消',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(0xFF425064)
                                                      .withValues(alpha: 0.7),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => Navigator.of(ctx)
                                              .pop(controller.text.trim()),
                                          child: Container(
                                            height: 48,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF3478F6),
                                                  Color(0xFF6CB4FF),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF3478F6)
                                                      .withValues(alpha: 0.25),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            child: const Center(
                                              child: Text(
                                                '创建',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (name == null || name.isEmpty) return;
    if (_customCategories.contains(name) ||
        VocabularyDefaults.categories.contains(name)) return;
    setState(() => _customCategories.add(name));
    await _saveCustomCategories();
  }

  List<VocabularyEntry> _entriesOf(String category) {
    return _entries.where((e) => e.category == category).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      body: Stack(
        children: [
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题栏
                        SizedBox(
                          height: 46,
                          child: Stack(
                            children: [
                              // 返回按钮
                              Positioned(
                                left: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
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
                                      Icons.arrow_back_ios_new_rounded,
                                      color: Colors.black.withOpacity(0.70),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              // 居中标题
                              const Center(
                                child: Text(
                                  '常用词库',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: Color(0xFF1F2328),
                                  ),
                                ),
                              ),
                              // 添加按钮
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: _addCategory,
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
                                    child: const Icon(
                                      Icons.add_rounded,
                                      color: Color(0xFF3C3A37),
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 副标题
                        Center(
                          child: Text(
                            '按场景快速找到想表达的内容',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8E8A84).withOpacity(0.8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        // 搜索栏
                        Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.82),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: _searchFocus.hasFocus
                                  ? const Color(0xFF3478F6).withOpacity(0.4)
                                  : Colors.white.withOpacity(0.9),
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
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 23,
                                color: Colors.black.withOpacity(0.42),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocus,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2A2D34),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '搜索词语、句子、场景',
                                    hintStyle: TextStyle(
                                      color: Colors.black.withOpacity(0.36),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              if (_searchText.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    _searchFocus.unfocus();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(Icons.close_rounded,
                                        size: 20,
                                        color: Colors.black.withOpacity(0.35)),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _toggleSearchAsr,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: _isRecording
                                        ? const Color(0xFFE8615B)
                                            .withOpacity(0.15)
                                        : const Color(0xFFF2F0EA),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    _isRecording
                                        ? Icons.stop_rounded
                                        : Icons.mic_rounded,
                                    size: 19,
                                    color: _isRecording
                                        ? const Color(0xFFE8615B)
                                        : Colors.black.withOpacity(0.45),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // 最近常用（搜索时不显示）
                        if (_searchText.isEmpty) ...[
                          _buildPersonalObjectDictionary(),
                          const SizedBox(height: 22),
                        ],
                        // 搜索结果或分类标题
                        if (_searchText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '找到 ${_filteredEntries.length + _filteredPersonalObjects.length} 条结果',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF8E8A84).withOpacity(0.7),
                              ),
                            ),
                          ),
                        if (_searchText.isEmpty)
                          const Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '词典分类',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: Color(0xFF242629),
                                ),
                              ),
                              SizedBox(width: 9),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '先选择场景，再找到常用词和句子',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFAAA59E),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                // 搜索结果或分类网格
                if (_searchText.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index < _filteredPersonalObjects.length) {
                            return _buildPersonalObjectSearchResult(
                              _filteredPersonalObjects[index],
                            );
                          }
                          final entry = _filteredEntries[
                              index - _filteredPersonalObjects.length];
                          final meta = _allCategoryMetas
                              .where((m) => m.name == entry.category)
                              .firstOrNull;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GestureDetector(
                              onTap: () async {
                                await _recordWordUsage(entry.text);
                                await _tts.speak(entry.text);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.86),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.92),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: (meta?.iconColor ??
                                                const Color(0xFF8E8A84))
                                            .withOpacity(0.14),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        meta?.icon ?? Icons.label_rounded,
                                        size: 22,
                                        color: meta?.iconColor ??
                                            const Color(0xFF8E8A84),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.text,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF2A2D34),
                                            ),
                                          ),
                                          if (entry.note.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              entry.note,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.black
                                                    .withOpacity(0.4),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (meta?.iconColor ??
                                                const Color(0xFF8E8A84))
                                            .withOpacity(0.10),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        entry.category,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: meta?.iconColor ??
                                              const Color(0xFF8E8A84),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: _filteredEntries.length +
                            _filteredPersonalObjects.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final meta = _allCategoryMetas[index];
                          final count = _entriesOf(meta.name).length;
                          return _VocabularyCategoryCard(
                            meta: meta,
                            entryCount: count,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _CategoryDetailPage(
                                    meta: meta,
                                    entries: _entriesOf(meta.name),
                                    onAdd: () => _addEntry(meta.name),
                                    onDelete: _deleteEntry,
                                    onWordUsed: _recordWordUsage,
                                    isCustom:
                                        _customCategories.contains(meta.name),
                                    onStyleChanged: _saveCustomStyle,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        childCount: _allCategoryMetas.length,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.93,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          YuqiaoFeatureAssistiveBall(
            currentFeature: YuqiaoFeature.vocabulary,
            launcher: widget.featureLauncher,
            bottomClearance: 34,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalObjectDictionary() {
    return Container(
      height: 112,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFE4CF).withOpacity(0.96),
            const Color(0xFFFFF7E8).withOpacity(0.94),
            const Color(0xFFEAF4FF).withOpacity(0.86),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_rounded,
                size: 18,
                color: Color(0xFF8B6E55),
              ),
              const SizedBox(width: 6),
              const Text(
                '个人物品词典',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF594A3F),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '${_personalObjects.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF594A3F).withValues(alpha: 0.45),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _openPersonalObjectManager,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    '查看全部',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF776354),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Expanded(
            child: _personalObjects.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: _addPersonalObject,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_rounded,
                                size: 17, color: Color(0xFF776354)),
                            SizedBox(width: 7),
                            Text(
                              '拍照添加第一个个人物品',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF594A3F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _personalObjects.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == _personalObjects.length) {
                        return InkWell(
                          onTap: _addPersonalObject,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.58),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                            child: const Icon(Icons.add_rounded,
                                size: 21, color: Color(0xFF776354)),
                          ),
                        );
                      }
                      final object = _personalObjects[index];
                      return InkWell(
                        onTap: () => _showPersonalObjectQuickView(object),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(5, 4, 13, 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildPersonalObjectThumbnail(object, 34),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 92),
                                child: Text(
                                  object.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4A4038),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalObjectThumbnail(PersonalObject object, double size) {
    final file = File(object.referenceImagePath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.34),
      child: SizedBox(
        width: size,
        height: size,
        child: object.referenceImagePath.isNotEmpty && file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, __, ___) => _personalObjectPlaceholder(),
              )
            : _personalObjectPlaceholder(),
      ),
    );
  }

  Widget _personalObjectPlaceholder() {
    return Container(
      color: const Color(0xFFF2E7DA),
      alignment: Alignment.center,
      child: const Icon(
        Icons.inventory_2_rounded,
        size: 18,
        color: Color(0xFFA58468),
      ),
    );
  }

  Widget _buildPersonalObjectSearchResult(PersonalObject object) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showPersonalObjectQuickView(object),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
          ),
          child: Row(
            children: [
              _buildPersonalObjectThumbnail(object, 48),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      object.displayName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2A2D34),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      object.note.isNotEmpty ? object.note : object.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFAAA59E)),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _expressionsFor(PersonalObject object) {
    if (object.commonExpressions.isNotEmpty) {
      return object.commonExpressions.take(4).toList();
    }
    return ['我想要${object.displayName}', '请帮我拿${object.displayName}'];
  }

  Future<void> _speakPersonalObject(
    PersonalObject object,
    String text,
  ) async {
    await widget.personalObjectStore.markUsed(object.id);
    await _recordWordUsage(text);
    await widget.locationController.recordWordUsed(text, 'vocabulary');
    unawaited(widget.companionAgent.recordInteraction(
      text: text,
      feature: 'personalObject',
      action: CompanionFeedbackAction.spoken,
      prompt: object.displayName,
      slot: RecommendationSlot.actionOrObject,
    ));
    await _tts.stop();
    await _tts.speak(text);
    await _reloadPersonalObjects();
  }

  Future<void> _openPersonalObjectExpression(
    PersonalObject object,
    String expression,
  ) async {
    await widget.personalObjectStore.markUsed(object.id);
    await _reloadPersonalObjects();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiCandidatesPage(
          draft: ExpressionDraft(
            source: '个人物品词典',
            intent: '围绕个人物品生成准确表达',
            keywords: [object.displayName, expression],
          ),
          qwenService: widget.qwenService,
          personalizedLearningEnabled: widget.personalizedLearningEnabled,
          onCandidateSelected: (text) async {
            unawaited(
              widget.locationController.recordWordUsed(text, 'vocabulary'),
            );
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'personalObject',
              action: CompanionFeedbackAction.accepted,
              prompt: object.displayName,
              slot: RecommendationSlot.sentence,
            ));
            unawaited(
              widget.onHabitRecorded(
                text,
                category: 'vocabulary',
                source: 'personal_object_sentence_candidate',
              ),
            );
          },
          onCandidateSaved: (text) async {
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'personalObject',
              action: CompanionFeedbackAction.saved,
              prompt: object.displayName,
              slot: RecommendationSlot.sentence,
            ));
          },
          onExpressionCompleted: widget.onExpressionCompleted,
          onFavoriteSaved: widget.onFavoriteSaved,
        ),
      ),
    );
  }

  Future<void> _showPersonalObjectQuickView(PersonalObject object) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final expressions = _expressionsFor(object);
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F7F3),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4D0C9),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildPersonalObjectThumbnail(object, 72),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              object.displayName,
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF242629),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              object.category,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8E8A84),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '播报名称',
                        onPressed: () =>
                            _speakPersonalObject(object, object.displayName),
                        icon: const Icon(Icons.volume_up_rounded),
                        color: const Color(0xFF6C8B78),
                      ),
                    ],
                  ),
                  if (object.visualDescription.isNotEmpty ||
                      object.note.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      object.note.isNotEmpty
                          ? object.note
                          : object.visualDescription,
                      style: const TextStyle(
                        height: 1.45,
                        fontSize: 14,
                        color: Color(0xFF696A6D),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    '常用表达',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2A2D34),
                    ),
                  ),
                  const SizedBox(height: 9),
                  for (final expression in expressions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          onTap: () => _speakPersonalObject(object, expression),
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(15, 10, 7, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    expression,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF34363A),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '生成完整表达',
                                  onPressed: () async {
                                    Navigator.of(sheetContext).pop();
                                    await _openPersonalObjectExpression(
                                      object,
                                      expression,
                                    );
                                  },
                                  icon: const Icon(Icons.auto_awesome_rounded,
                                      size: 20),
                                  color: const Color(0xFFE2A84A),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _openPersonalObjectManager();
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('编辑物品信息'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<_VocabularyCategoryMeta> get _allCategoryMetas {
    final customs = _customCategories.asMap().entries.map((e) {
      // 为自定义分类分配颜色和图标
      const icons = [
        Icons.folder_rounded,
        Icons.bookmark_rounded,
        Icons.label_rounded,
        Icons.star_rounded,
        Icons.local_offer_rounded,
        Icons.push_pin_rounded,
      ];
      const colorSets = [
        [Color(0xFFD4E4FF), Color(0xFFE4F0FF), Color(0xFFF0F6FF)],
        [Color(0xFFFFE0F0), Color(0xFFFFF0F6), Color(0xFFFFF6FA)],
        [Color(0xFFE0FFE8), Color(0xFFF0FFF4), Color(0xFFF6FFF8)],
        [Color(0xFFFFF0D0), Color(0xFFFFF6E0), Color(0xFFFFFAF0)],
        [Color(0xFFE8E0FF), Color(0xFFF0EAFF), Color(0xFFF6F4FF)],
        [Color(0xFFFFE8E0), Color(0xFFFFF0EA), Color(0xFFFFF6F4)],
      ];
      const iconColors = [
        Color(0xFF5B8DEF),
        Color(0xFFE86B8A),
        Color(0xFF4CAF80),
        Color(0xFFFFB84D),
        Color(0xFF9B6BDE),
        Color(0xFFE8785B),
      ];
      final i = e.key % icons.length;
      return _VocabularyCategoryMeta(
        name: e.value,
        description: '自定义词典',
        icon: icons[i],
        iconColor: iconColors[i],
        colors: colorSets[i],
      );
    }).toList();
    // 应用自定义样式
    final styled = customs.map(_applyCustomStyle).toList();
    return [..._categoryMetas, ...styled];
  }

  static const _categoryMetas = [
    _VocabularyCategoryMeta(
      name: '人物',
      description: '家人、医生、朋友',
      icon: Icons.groups_rounded,
      iconColor: Color(0xFF8A6B4A),
      colors: [Color(0xFFECD7C4), Color(0xFFF4E8DD), Color(0xFFFFF7EF)],
    ),
    _VocabularyCategoryMeta(
      name: '饮食',
      description: '吃饭、饮料、口味',
      icon: Icons.restaurant_rounded,
      iconColor: Color(0xFFE09B31),
      colors: [Color(0xFFFFE4B6), Color(0xFFFFF1C9), Color(0xFFFFF8E7)],
    ),
    _VocabularyCategoryMeta(
      name: '地点',
      description: '家、医院、厕所',
      icon: Icons.location_on_rounded,
      iconColor: Color(0xFF3E91D8),
      colors: [Color(0xFFD8EEFF), Color(0xFFE4F6FF), Color(0xFFE6F4EF)],
    ),
    _VocabularyCategoryMeta(
      name: '活动',
      description: '散步、休息、看电视',
      icon: Icons.directions_run_rounded,
      iconColor: Color(0xFF43A777),
      colors: [Color(0xFFD7F5DF), Color(0xFFBFEFD4), Color(0xFFFFF6DB)],
    ),
    _VocabularyCategoryMeta(
      name: '物品',
      description: '手机、钥匙、眼镜',
      icon: Icons.category_rounded,
      iconColor: Color(0xFFE2615B),
      colors: [Color(0xFFFFD6C9), Color(0xFFFFE7DC), Color(0xFFFDEFE8)],
    ),
    _VocabularyCategoryMeta(
      name: '感受',
      description: '开心、难过、害怕',
      icon: Icons.emoji_emotions_rounded,
      iconColor: Color(0xFF9C6ADE),
      colors: [Color(0xFFE9D8FF), Color(0xFFF2E8FF), Color(0xFFFFEAF5)],
    ),
    _VocabularyCategoryMeta(
      name: '常用句',
      description: '高频、紧急表达',
      icon: Icons.chat_bubble_rounded,
      iconColor: Color(0xFFE5A51F),
      colors: [Color(0xFFFFE6A7), Color(0xFFFFF2C7), Color(0xFFFFF8E8)],
    ),
  ];
}

class _VocabularyCategoryMeta {
  final String name;
  final String description;
  final IconData icon;
  final Color iconColor;
  final List<Color> colors;

  const _VocabularyCategoryMeta({
    required this.name,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.colors,
  });
}

class _VocabularyCategoryCard extends StatelessWidget {
  final _VocabularyCategoryMeta meta;
  final int entryCount;
  final VoidCallback? onTap;

  const _VocabularyCategoryCard({
    required this.meta,
    required this.entryCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: meta.colors,
          ),
          boxShadow: [
            BoxShadow(
              color: meta.colors.first.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -32,
              top: -28,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.20),
                ),
              ),
            ),
            Positioned(
              left: -26,
              bottom: -32,
              child: Container(
                width: 115,
                height: 115,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.13),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(meta.icon, size: 26, color: meta.iconColor),
                  ),
                  const Spacer(),
                  Text(
                    meta.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.7,
                      color: Color(0xFF303033),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    meta.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3D3B39).withOpacity(0.52),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.56),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$entryCount 个词',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.black.withOpacity(0.52),
                      ),
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
}

class _CategoryDetailPage extends StatefulWidget {
  final _VocabularyCategoryMeta meta;
  final List<VocabularyEntry> entries;
  final VoidCallback onAdd;
  final Future<void> Function(VocabularyEntry) onDelete;
  final Future<void> Function(String) onWordUsed;
  final bool isCustom;
  final Future<void> Function(
          String name, IconData icon, Color iconColor, List<Color> colors)?
      onStyleChanged;

  const _CategoryDetailPage({
    required this.meta,
    required this.entries,
    required this.onAdd,
    required this.onDelete,
    required this.onWordUsed,
    this.isCustom = false,
    this.onStyleChanged,
  });

  @override
  State<_CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<_CategoryDetailPage> {
  final FlutterTts _tts = FlutterTts();
  Map<String, int> _freq = {};
  bool _sorted = false;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('zh-CN');
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
    _loadFreq();
  }

  Future<void> _loadFreq() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('vocabulary_word_freq') ?? [];
    final map = <String, int>{};
    for (final item in raw) {
      final parts = item.split(':');
      if (parts.length == 2) {
        map[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
    }
    if (mounted) setState(() => _freq = map);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    await widget.onWordUsed(text);
    await _tts.speak(text);
    // 刷新频率
    await _loadFreq();
  }

  List<VocabularyEntry> get _sortedEntries {
    final list = List<VocabularyEntry>.of(widget.entries);
    if (_sorted) {
      list.sort((a, b) => (_freq[b.text] ?? 0).compareTo(_freq[a.text] ?? 0));
    }
    return list;
  }

  static const _iconOptions = [
    Icons.folder_rounded,
    Icons.bookmark_rounded,
    Icons.label_rounded,
    Icons.star_rounded,
    Icons.local_offer_rounded,
    Icons.push_pin_rounded,
    Icons.sports_esports_rounded,
    Icons.fitness_center_rounded,
    Icons.music_note_rounded,
    Icons.brush_rounded,
    Icons.pets_rounded,
    Icons.flight_rounded,
    Icons.work_rounded,
    Icons.school_rounded,
    Icons.restaurant_rounded,
    Icons.shopping_bag_rounded,
  ];

  static const _colorOptions = [
    [
      Color(0xFF5B8DEF),
      [Color(0xFFD4E4FF), Color(0xFFE4F0FF), Color(0xFFF0F6FF)]
    ],
    [
      Color(0xFFE86B8A),
      [Color(0xFFFFE0F0), Color(0xFFFFF0F6), Color(0xFFFFF6FA)]
    ],
    [
      Color(0xFF4CAF80),
      [Color(0xFFE0FFE8), Color(0xFFF0FFF4), Color(0xFFF6FFF8)]
    ],
    [
      Color(0xFFFFB84D),
      [Color(0xFFFFF0D0), Color(0xFFFFF6E0), Color(0xFFFFFAF0)]
    ],
    [
      Color(0xFF9B6BDE),
      [Color(0xFFE8E0FF), Color(0xFFF0EAFF), Color(0xFFF6F4FF)]
    ],
    [
      Color(0xFFE8785B),
      [Color(0xFFFFE8E0), Color(0xFFFFF0EA), Color(0xFFFFF6F4)]
    ],
    [
      Color(0xFF3E91D8),
      [Color(0xFFD8EEFF), Color(0xFFE4F6FF), Color(0xFFE6F4EF)]
    ],
    [
      Color(0xFFD4A574),
      [Color(0xFFECD7C4), Color(0xFFF4E8DD), Color(0xFFFFF7EF)]
    ],
  ];

  void _showStyleDialog(BuildContext context) {
    IconData selectedIcon = widget.meta.icon;
    Color selectedIconColor = widget.meta.iconColor;
    List<Color> selectedColors = widget.meta.colors;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F5F0),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      const Center(
                        child: Text(
                          '自定义外观',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: Color(0xFF1F2328),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // 预览
                      Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: selectedColors,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    selectedIconColor.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(selectedIcon,
                                size: 44, color: selectedIconColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // 图标选择
                      const Text(
                        '图标',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2A2D34),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _iconOptions.map((icon) {
                          final isSelected = icon == selectedIcon;
                          return GestureDetector(
                            onTap: () =>
                                setDialogState(() => selectedIcon = icon),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? selectedIconColor.withValues(alpha: 0.18)
                                    : Colors.white.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? selectedIconColor.withValues(alpha: 0.5)
                                      : Colors.white.withValues(alpha: 0.9),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                icon,
                                size: 24,
                                color: isSelected
                                    ? selectedIconColor
                                    : const Color(0xFF8E8A84),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      // 颜色选择
                      const Text(
                        '配色',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2A2D34),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _colorOptions.map((opt) {
                          final iconColor = opt[0] as Color;
                          final bgColors = opt[1] as List<Color>;
                          final isSelected = iconColor == selectedIconColor;
                          return GestureDetector(
                            onTap: () => setDialogState(() {
                              selectedIconColor = iconColor;
                              selectedColors = bgColors;
                            }),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: bgColors,
                                ),
                                border: Border.all(
                                  color: isSelected
                                      ? iconColor.withValues(alpha: 0.6)
                                      : Colors.white.withValues(alpha: 0.9),
                                  width: isSelected ? 2.5 : 1,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: iconColor.withValues(alpha: 0.25),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.circle,
                                      size: 12, color: iconColor),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 28),
                      // 按钮行
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.of(ctx).pop(),
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Center(
                                  child: Text(
                                    '取消',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF425064)
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(ctx).pop();
                                widget.onStyleChanged?.call(
                                  widget.meta.name,
                                  selectedIcon,
                                  selectedIconColor,
                                  selectedColors,
                                );
                              },
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF3478F6),
                                      Color(0xFF6CB4FF)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF3478F6)
                                          .withValues(alpha: 0.25),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    '应用',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      body: SafeArea(
        child: Column(
          children: [
            // 彩色头部
            Container(
              height: 200,
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.meta.colors,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.meta.colors.first.withOpacity(0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 11),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -26,
                    top: -26,
                    child: Container(
                      width: 146,
                      height: 146,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.18),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: Icon(
                      widget.meta.icon,
                      size: 98,
                      color: Colors.white.withOpacity(0.42),
                    ),
                  ),
                  // 返回按钮
                  Positioned(
                    top: 16,
                    left: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.62),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: Colors.black.withOpacity(0.70),
                        ),
                      ),
                    ),
                  ),
                  // 设置按钮（仅自定义分类显示）
                  if (widget.isCustom)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: () => _showStyleDialog(context),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.62),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: Colors.black.withOpacity(0.70),
                          ),
                        ),
                      ),
                    ),
                  // 标题
                  Positioned(
                    left: 20,
                    bottom: 24,
                    right: 130,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.meta.name,
                          style: const TextStyle(
                            fontSize: 34,
                            height: 1.02,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.2,
                            color: Color(0xFF26272A),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.meta.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF333333).withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 排序按钮
            if (widget.entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _sorted = !_sorted),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _sorted
                              ? const Color(0xFF3478F6).withOpacity(0.12)
                              : Colors.white.withOpacity(0.72),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _sorted
                                ? const Color(0xFF3478F6).withOpacity(0.3)
                                : Colors.white.withOpacity(0.9),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _sorted
                                  ? Icons.sort_rounded
                                  : Icons.swap_vert_rounded,
                              size: 16,
                              color: _sorted
                                  ? const Color(0xFF3478F6)
                                  : const Color(0xFF8E8A84),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sorted ? '按频率排序' : '默认排序',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _sorted
                                    ? const Color(0xFF3478F6)
                                    : const Color(0xFF8E8A84),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.entries.length} 个词',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8E8A84).withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // 词汇列表
            Expanded(
              child: _sortedEntries.isEmpty
                  ? Center(
                      child: Text(
                        '还没有${widget.meta.name}类的词汇\n点击下方按钮添加',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: const Color(0xFF2A2D34).withOpacity(0.56),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _sortedEntries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final entry = _sortedEntries[index];
                        return GestureDetector(
                          onTap: () => _speak(entry.text),
                          onLongPress: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('删除词汇？'),
                                content: Text('确定删除"${entry.text}"吗？'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await widget.onDelete(entry);
                            }
                          },
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 88),
                            padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.88),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.96),
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
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color:
                                        widget.meta.iconColor.withOpacity(0.17),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(
                                    widget.meta.icon,
                                    size: 27,
                                    color:
                                        widget.meta.iconColor.withOpacity(0.92),
                                  ),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.text,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          height: 1.22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.4,
                                          color: Color(0xFF2D2E31),
                                        ),
                                      ),
                                      if (entry.note.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          entry.note,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                Colors.black.withOpacity(0.35),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF4F2EE),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 24,
                                    color: Colors.black.withOpacity(0.56),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: widget.onAdd,
        backgroundColor: widget.meta.colors.first,
        child: const Icon(Icons.add, color: Color(0xFF303033)),
      ),
    );
  }
}

class AddVocabularySheet extends StatefulWidget {
  const AddVocabularySheet({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  State<AddVocabularySheet> createState() => _AddVocabularySheetState();
}

class _AddVocabularySheetState extends State<AddVocabularySheet> {
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  late String _category;

  @override
  void initState() {
    super.initState();
    _category = (widget.initialCategory != null &&
            VocabularyDefaults.categories.contains(widget.initialCategory))
        ? widget.initialCategory!
        : VocabularyDefaults.categories.first;
  }

  @override
  void dispose() {
    _textController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      VocabularyEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        category: _category,
        text: text,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('添加日常词', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: VocabularyDefaults.categories
                    .map((category) => DropdownMenuItem(
                        value: category, child: Text(category)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
                decoration: InputDecoration(
                  labelText: '分类',
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '词语或短语',
                  hintText: '例如：咖啡、散步、楼下、公园',
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: '备注（可选）',
                  hintText: '例如：早上常说、出门时常用',
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              PrimaryActionButton(
                text: '保存',
                icon: Icons.check,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VocabularyCategoryPanel extends StatelessWidget {
  const VocabularyCategoryPanel({
    super.key,
    required this.entries,
    required this.onDelete,
  });

  final List<VocabularyEntry> entries;
  final ValueChanged<VocabularyEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyPanel(text: '还没有添加。');
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: entries.map((entry) {
          return InputChip(
            label: Text(
              entry.note.isEmpty ? entry.text : '${entry.text} · ${entry.note}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            backgroundColor: AppColors.primaryLight,
            side: BorderSide.none,
            onDeleted: () => onDelete(entry),
          );
        }).toList(),
      ),
    );
  }
}

class ObjectCandidatePanel extends StatelessWidget {
  const ObjectCandidatePanel({
    super.key,
    required this.candidates,
    required this.selected,
    required this.onSelected,
  });

  final List<ObjectCandidate> candidates;
  final ObjectCandidate? selected;
  final ValueChanged<ObjectCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: candidates.map((candidate) {
        final isSelected = selected?.objectName == candidate.objectName;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: () => onSelected(candidate),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryLight : AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.button),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.divider,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.objectName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (candidate.confidence.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '置信度：${candidate.confidence}',
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class SavePersonalObjectSheet extends StatefulWidget {
  const SavePersonalObjectSheet({
    super.key,
    required this.initialName,
  });

  final String initialName;

  @override
  State<SavePersonalObjectSheet> createState() =>
      _SavePersonalObjectSheetState();
}

class _SavePersonalObjectSheetState extends State<SavePersonalObjectSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('记住这个物品', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 10),
              const Text(
                '以后拍照识物时，语桥会把这个名称作为个人物品参考。',
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: '物品名称',
                  hintText: '例如：我的水杯、我的钥匙',
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              PrimaryActionButton(
                text: '保存为我的物品',
                icon: Icons.check,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConversationModePage extends StatefulWidget {
  const ConversationModePage({
    super.key,
    required this.qwenService,
    required this.locationController,
    required this.companionAgent,
    required this.personalizedLearningEnabled,
    required this.featureLauncher,
    required this.recentExpressions,
    required this.favoriteExpressions,
    required this.expressionHabits,
    required this.vocabularyEntries,
    this.candidateImageScale = 1.0,
    required this.onHabitRecorded,
    required this.onExpressionCompleted,
    required this.onFavoriteSaved,
  });

  final QwenService qwenService;
  final LocationRecommendationController locationController;
  final CompanionAgentController companionAgent;
  final bool personalizedLearningEnabled;
  final YuqiaoFeatureLauncher featureLauncher;
  final List<String> recentExpressions;
  final List<String> favoriteExpressions;
  final List<ExpressionHabit> expressionHabits;
  final List<VocabularyEntry> vocabularyEntries;
  final double candidateImageScale;
  final HabitRecordCallback onHabitRecorded;
  final ExpressionCallback onExpressionCompleted;
  final ExpressionCallback onFavoriteSaved;

  @override
  State<ConversationModePage> createState() => _ConversationModePageState();
}

class _ConversationTranscriptSegment {
  const _ConversationTranscriptSegment({
    required this.id,
    required this.speakerId,
    required this.text,
    required this.isFinal,
  });

  final String id;
  final int speakerId;
  final String text;
  final bool isFinal;

  String get displayText => '说话者$speakerId：$text';
}

class _SpeechRepairSuggestion {
  const _SpeechRepairSuggestion({
    required this.original,
    required this.candidates,
    required this.reason,
  });

  final String original;
  final List<String> candidates;
  final String reason;
}

class _PendingSpeechRepair {
  const _PendingSpeechRepair({
    required this.segmentId,
    required this.suggestion,
  });

  final String segmentId;
  final _SpeechRepairSuggestion suggestion;
}

class _UnderstandingPart {
  const _UnderstandingPart({
    required this.label,
    required this.text,
    required this.evidence,
  });

  final String label;
  final String text;
  final String evidence;
}

class _ConversationUnderstanding {
  const _ConversationUnderstanding({
    required this.original,
    required this.parts,
    required this.simpleMeaning,
    required this.importantNote,
    required this.uncertainties,
  });

  final String original;
  final List<_UnderstandingPart> parts;
  final String simpleMeaning;
  final String importantNote;
  final List<String> uncertainties;
}

class _ConversationModePageState extends State<ConversationModePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final XfyunRealtimeAsrService _asrService = XfyunRealtimeAsrService();
  final FlutterTts _conversationTts = FlutterTts();
  final ScrollController _transcriptScrollController = ScrollController();
  final ConversationTermStore _conversationTermStore = ConversationTermStore();
  final ConversationFeedbackStore _conversationFeedbackStore =
      ConversationFeedbackStore();
  final ValueNotifier<int> _transcriptRevision = ValueNotifier<int>(0);
  final LinkedHashMap<String, _ConversationTranscriptSegment>
      _transcriptSegments = LinkedHashMap();
  final Map<String, ConversationTermCandidate> _sessionTerms = {};
  final Set<String> _extractedFinalLines = {};
  final Set<int> _knownSpeakerIds = {};
  final List<String> _pendingTermLines = [];
  Timer? _pauseTimer;
  Timer? _speechRepairTimer;
  Timer? _termExtractionTimer;
  Timer? _asrReconnectTimer;
  QwenCancellationToken? _conversationSuggestionToken;
  QwenCancellationToken? _stuckAssistToken;
  QwenCancellationToken? _speechRepairToken;
  QwenCancellationToken? _understandingToken;
  QwenCancellationToken? _termExtractionToken;
  List<ConversationTerm> _savedConversationTerms = const [];
  bool _isExtractingConversationTerms = false;
  bool _conversationActive = false;
  bool _isListening = false;
  bool _isStartingSpeech = false;
  bool _isSuggesting = false;
  bool _isGeneratingStuckAssist = false;
  bool _isSpeakingStuckAssist = false;
  bool _isAnalyzingSpeechRepair = false;
  bool _isUnderstanding = false;
  bool _isReadingUnderstanding = false;
  bool _asrNeedsManualReconnect = false;
  bool _manualConversationStop = false;
  bool _conversationPausedByLifecycle = false;
  int _asrReconnectAttempts = 0;
  int? _userSpeakerId;
  int _conversationEventRevision = 0;
  DateTime? _stuckAssistCooldownUntil;
  DateTime? _speechRepairCooldownUntil;
  String? _lastStuckTriggerText;
  String? _lastSpeechRepairText;
  _PendingSpeechRepair? _pendingSpeechRepair;
  String _conversationSummary = '';
  String _currentTranscript = '';
  String _status = '对话模式未开启';
  String? _error;

  late final AnimationController _orbController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.locationController.refreshLocationContext();
    unawaited(_loadSavedConversationTerms());
    unawaited(_configureConversationTts());
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orbController.dispose();
    _pauseTimer?.cancel();
    _speechRepairTimer?.cancel();
    _understandingToken?.cancel();
    _termExtractionTimer?.cancel();
    _asrReconnectTimer?.cancel();
    _manualConversationStop = true;
    _cancelConversationQwenRequests();
    _transcriptScrollController.dispose();
    _transcriptRevision.dispose();
    unawaited(_conversationTts.stop());
    unawaited(_asrService.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_conversationPausedByLifecycle && mounted) {
        setState(() {
          _conversationPausedByLifecycle = false;
          _asrNeedsManualReconnect = _conversationActive;
          _status = _conversationActive ? '对话已暂停，点击重新连接继续' : _status;
        });
        if (_conversationActive && !_orbController.isAnimating) {
          _orbController.repeat();
        }
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _pauseConversationForLifecycle();
    }
  }

  void _pauseConversationForLifecycle() {
    if (_conversationPausedByLifecycle) return;
    _conversationPausedByLifecycle = true;
    _pauseTimer?.cancel();
    _speechRepairTimer?.cancel();
    _asrReconnectTimer?.cancel();
    _cancelConversationQwenRequests();
    if (_orbController.isAnimating) {
      _orbController.stop();
    }
    if (_conversationActive) {
      unawaited(_asrService.stop());
    }
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _isStartingSpeech = false;
      _isSuggesting = false;
      _isGeneratingStuckAssist = false;
      _isAnalyzingSpeechRepair = false;
      _asrNeedsManualReconnect = _conversationActive;
      _status = _conversationActive ? '对话已暂停，回到前台后可继续' : _status;
    });
  }

  Future<void> _configureConversationTts() async {
    await _conversationTts.setLanguage('zh-CN');
    await _conversationTts.setSpeechRate(0.45);
    await _conversationTts.setPitch(1.0);
    await _conversationTts.awaitSpeakCompletion(true);
  }

  Future<void> _loadSavedConversationTerms() async {
    final terms = await _conversationTermStore.loadAll();
    if (!mounted) return;
    setState(() => _savedConversationTerms = terms);
    _syncCompanionConversationContext();
    _transcriptRevision.value++;
  }

  void _queueConversationTermExtraction(String text) {
    final normalizedLine = text.trim();
    if (normalizedLine.isEmpty || !_extractedFinalLines.add(normalizedLine)) {
      return;
    }

    var foundSavedTerm = false;
    for (final term in _savedConversationTerms) {
      if (!normalizedLine.contains(term.text)) continue;
      _sessionTerms[term.normalizedText] = ConversationTermCandidate(
        text: term.text,
        type: term.type,
        confidence: 1,
      );
      foundSavedTerm = true;
    }
    if (foundSavedTerm) _transcriptRevision.value++;

    _pendingTermLines.add(normalizedLine);
    _termExtractionTimer?.cancel();
    _termExtractionTimer = Timer(
      const Duration(milliseconds: 800),
      () => unawaited(_extractPendingConversationTerms()),
    );
  }

  Future<void> _extractPendingConversationTerms() async {
    if (_pendingTermLines.isEmpty) return;
    if (_isExtractingConversationTerms) {
      _termExtractionTimer = Timer(
        const Duration(milliseconds: 500),
        () => unawaited(_extractPendingConversationTerms()),
      );
      return;
    }
    final transcript = _pendingTermLines.join('\n');
    _pendingTermLines.clear();
    _isExtractingConversationTerms = true;
    final token = QwenCancellationToken();
    _termExtractionToken = token;
    try {
      final terms = await widget.qwenService
          .extractConversationTerms(
            transcript,
            cancellationToken: token,
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted || terms.isEmpty) return;
      for (final term in terms) {
        _sessionTerms[term.normalizedText] = term;
      }
      _transcriptRevision.value++;
    } catch (error) {
      yuqiaoDebugLog('[Conversation terms] extraction skipped: $error');
    } finally {
      token.cancel();
      if (identical(_termExtractionToken, token)) {
        _termExtractionToken = null;
      }
      _isExtractingConversationTerms = false;
      if (_pendingTermLines.isNotEmpty && mounted) {
        _termExtractionTimer = Timer(
          const Duration(milliseconds: 500),
          () => unawaited(_extractPendingConversationTerms()),
        );
      }
    }
  }

  Future<void> _startConversation() async {
    if (_isStartingSpeech || _conversationActive) return;
    setState(() {
      _conversationActive = true;
      _manualConversationStop = false;
      _asrNeedsManualReconnect = false;
      _asrReconnectAttempts = 0;
      _isStartingSpeech = true;
      _isListening = false;
      _error = null;
      _status = '正在连接讯飞实时转写';
    });
    _orbController
      ..duration = const Duration(milliseconds: 1600)
      ..repeat();

    try {
      await _asrService.start(
        onTranscript: _handleXfyunTranscript,
        onStatus: _handleAsrStatus,
        onError: _handleAsrError,
      );
      if (!mounted || !_conversationActive) return;
      setState(() {
        _isStartingSpeech = false;
        _isListening = true;
        _status = '正在聆听并区分说话者';
      });
    } catch (error) {
      _handleAsrError(error.toString());
    }
  }

  Future<void> _stopConversation() async {
    _pauseTimer?.cancel();
    _speechRepairTimer?.cancel();
    _asrReconnectTimer?.cancel();
    _manualConversationStop = true;
    _cancelConversationQwenRequests();
    setState(() {
      _conversationActive = false;
      _isListening = false;
      _isStartingSpeech = false;
      _lastStuckTriggerText = null;
      _pendingSpeechRepair = null;
      _isAnalyzingSpeechRepair = false;
      _asrNeedsManualReconnect = false;
      _status = '正在关闭对话模式';
    });
    await _asrService.stop();
    if (!mounted) return;
    setState(() => _status = '对话模式已关闭');
    _orbController
      ..duration = const Duration(milliseconds: 2800)
      ..stop();
  }

  void _handleAsrStatus(String status) {
    if (!mounted || !_conversationActive || _manualConversationStop) return;
    final listening = status.startsWith('正在聆听');
    setState(() {
      _status = status;
      _isListening = listening;
      if (listening) {
        _isStartingSpeech = false;
        _asrReconnectAttempts = 0;
        _asrNeedsManualReconnect = false;
        _error = null;
      }
    });
  }

  void _handleAsrError(String message) {
    if (!mounted || !_conversationActive || _manualConversationStop) return;
    setState(() {
      _isListening = false;
      _isStartingSpeech = false;
      _status = '讯飞实时转写连接中断';
      _error = message;
    });
    _scheduleAsrReconnect();
  }

  void _scheduleAsrReconnect() {
    if (_manualConversationStop || !_conversationActive) return;
    if (_asrReconnectTimer?.isActive == true) return;
    if (_asrReconnectAttempts >= 3) {
      if (!mounted) return;
      setState(() {
        _asrNeedsManualReconnect = true;
        _status = '实时转写已断开';
      });
      return;
    }
    final delaySeconds = 1 << _asrReconnectAttempts;
    _asrReconnectAttempts++;
    if (mounted) {
      setState(() => _status = '$delaySeconds 秒后尝试重新连接');
    }
    _asrReconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_manualConversationStop || !_conversationActive) return;
      await _asrService.stop();
      if (!mounted || _manualConversationStop || !_conversationActive) return;
      await _resumeConversationAfterSpeech();
    });
  }

  Future<void> _retryAsrConnection() async {
    if (!_conversationActive || _isStartingSpeech) return;
    _asrReconnectTimer?.cancel();
    _asrReconnectAttempts = 0;
    setState(() {
      _asrNeedsManualReconnect = false;
      _error = null;
    });
    await _asrService.stop();
    if (!mounted || !_conversationActive) return;
    await _resumeConversationAfterSpeech();
  }

  void _handleXfyunTranscript(XfyunTranscriptEvent event) {
    if (!mounted || !_conversationActive || event.text.trim().isEmpty) return;
    final words = event.text.trim();
    final isFinal = event.isFinal;
    final speakerId = event.speakerId;
    _conversationEventRevision++;
    _conversationSuggestionToken?.cancel();
    _stuckAssistToken?.cancel();
    _speechRepairTimer?.cancel();
    _speechRepairToken?.cancel();
    _knownSpeakerIds.add(speakerId);
    _userSpeakerId ??= speakerId;
    _pauseTimer?.cancel();
    setState(() {
      _status = '正在聆听并区分说话者';
      _isAnalyzingSpeechRepair = false;
      _pendingSpeechRepair = null;
      final existing = _transcriptSegments[event.segmentId];
      if (existing?.isFinal != true) {
        _transcriptSegments[event.segmentId] = _ConversationTranscriptSegment(
          id: event.segmentId,
          speakerId: speakerId,
          text: words,
          isFinal: isFinal,
        );
      }
      if (isFinal) {
        _currentTranscript = '';
        _compactConversationTranscript();
      } else {
        _currentTranscript = '说话者$speakerId：$words';
      }
    });
    _transcriptRevision.value++;
    _syncCompanionConversationContext();
    _scrollTranscriptToLatest();
    if (isFinal) {
      _queueConversationTermExtraction(words);
    }
    if (speakerId == _userSpeakerId && !_isSpeakingStuckAssist) {
      _scheduleStuckDetection(words, isFinal: isFinal);
      if (isFinal) {
        _scheduleSpeechRepairAnalysis(event.segmentId, words);
      }
    }
  }

  void _scheduleSpeechRepairAnalysis(String segmentId, String text) {
    final trimmed = text.trim();
    if (trimmed.length < 3 ||
        trimmed.length > 60 ||
        _looksLikeIncompleteExpression(trimmed) ||
        _lastSpeechRepairText == trimmed ||
        _isSpeakingStuckAssist ||
        _isGeneratingStuckAssist) {
      return;
    }
    final cooldown = _speechRepairCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) return;
    final finalizedCount =
        _transcriptSegments.values.where((segment) => segment.isFinal).length;
    // 没有前文时无法可靠地推断用户意图，不发起模型请求。
    if (finalizedCount < 2 && _conversationSummary.isEmpty) return;

    final revision = _conversationEventRevision;
    _speechRepairTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted ||
          !_conversationActive ||
          revision != _conversationEventRevision) {
        return;
      }
      unawaited(_analyzeSpeechRepair(segmentId, trimmed, revision));
    });
  }

  Future<void> _analyzeSpeechRepair(
    String segmentId,
    String original,
    int revision,
  ) async {
    if (_isAnalyzingSpeechRepair || !_conversationActive) return;
    _lastSpeechRepairText = original;
    _speechRepairToken?.cancel();
    final token = QwenCancellationToken();
    _speechRepairToken = token;
    setState(() => _isAnalyzingSpeechRepair = true);

    _SpeechRepairSuggestion? suggestion;
    try {
      suggestion = await widget.qwenService
          ._analyzeSpeechRepair(
            ConversationContextRequest(
              transcript: _conversationContextForModel,
              currentPartial: original,
              userSpeakerLabel:
                  _userSpeakerId == null ? '未确认' : '说话者$_userSpeakerId',
              timeText: _timeContext,
              locationText: !widget.locationController.enabled
                  ? '未启用定位'
                  : widget.locationController.currentPlace?.typeLabel ??
                      PlaceTypeCatalog.labelOf(
                        widget.locationController.currentSemantic?.type,
                      ),
              recentExpressions: widget.recentExpressions.take(6).toList(),
              personalWords: [
                ...ExpressionHabitStore.rank(
                  widget.expressionHabits,
                  category: 'conversation',
                  limit: 8,
                ).map((habit) => '常用${habit.count}次：${habit.text}'),
                ..._savedConversationTerms.take(8).map((term) => term.text),
                ...widget.favoriteExpressions,
                ...widget.vocabularyEntries.map((entry) => entry.text),
              ].take(20).toList(),
            ),
            cancellationToken: token,
          )
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      if (error is! QwenCancelledException) {
        yuqiaoDebugLog('[Conversation speech repair] analysis skipped: $error');
      }
    }
    if (identical(_speechRepairToken, token)) _speechRepairToken = null;
    if (!mounted) return;
    setState(() => _isAnalyzingSpeechRepair = false);
    if (!_conversationActive || revision != _conversationEventRevision) return;
    if (suggestion == null || suggestion.candidates.length < 2) return;

    setState(() {
      _pendingSpeechRepair = _PendingSpeechRepair(
        segmentId: segmentId,
        suggestion: suggestion!,
      );
    });
    _speechRepairCooldownUntil =
        DateTime.now().add(const Duration(seconds: 18));
    await HapticFeedback.lightImpact();
  }

  bool _looksLikeIncompleteExpression(String text) {
    final normalized = text.replaceAll(RegExp(r'[，。！？、,.!?：:；;\s]'), '').trim();
    if (normalized.isEmpty) return false;
    const fillers = [
      '嗯',
      '呃',
      '那个',
      '这个',
      '就是',
      '怎么说',
      '我想想',
      '等一下',
    ];
    const incompleteEndings = [
      '我想',
      '我要',
      '我那个',
      '能不能',
      '可以帮我',
      '帮我',
      '给我',
      '我要去',
      '我需要',
      '因为',
      '但是',
      '然后',
      '还有',
    ];
    final hasFiller = fillers.any(normalized.contains);
    final incompleteEnding = incompleteEndings.any(normalized.endsWith);
    final repeatedCharacter = RegExp(r'(.)\1{2,}').hasMatch(normalized);
    final repeatedFiller =
        RegExp(r'(那个|这个|就是).*(那个|这个|就是)').hasMatch(normalized);
    const repeatablePhrases = ['我想', '我要', '帮我', '给我', '然后'];
    final repeatedPhrase = repeatablePhrases.any((phrase) {
      final first = normalized.indexOf(phrase);
      return first >= 0 &&
          normalized.indexOf(phrase, first + phrase.length) >= 0;
    });
    return hasFiller ||
        incompleteEnding ||
        repeatedCharacter ||
        repeatedFiller ||
        repeatedPhrase;
  }

  void _selectUserSpeaker(int speakerId) {
    _pauseTimer?.cancel();
    setState(() {
      _userSpeakerId = speakerId;
      _lastStuckTriggerText = null;
    });
    _transcriptRevision.value++;
  }

  void _scheduleStuckDetection(String text, {required bool isFinal}) {
    final cooldown = _stuckAssistCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) return;
    if (_isGeneratingStuckAssist || _isSpeakingStuckAssist) return;

    // 停在未完成的实时片段本身就是强信号；完整终句只在含有
    // 填充词、重复或明显未完成结构时触发，避免把正常轮次停顿当成卡顿。
    if (isFinal && !_looksLikeIncompleteExpression(text)) return;
    final delay = isFinal
        ? const Duration(milliseconds: 2400)
        : const Duration(milliseconds: 3200);
    _pauseTimer = Timer(delay, () {
      if (!mounted || !_conversationActive || _isSpeakingStuckAssist) return;
      unawaited(_triggerStuckAssistance(text));
    });
  }

  Future<void> _triggerStuckAssistance(String triggerText) async {
    final trimmed = triggerText.trim();
    if (trimmed.isEmpty ||
        _isGeneratingStuckAssist ||
        _isSpeakingStuckAssist ||
        _lastStuckTriggerText == trimmed) {
      return;
    }
    final cooldown = _stuckAssistCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) return;
    _lastStuckTriggerText = trimmed;
    final triggerRevision = _conversationEventRevision;
    _stuckAssistToken?.cancel();
    final token = QwenCancellationToken();
    _stuckAssistToken = token;
    setState(() {
      _isGeneratingStuckAssist = true;
      _status = '检测到可能卡顿，正在整理表达';
    });

    String? suggestion;
    try {
      suggestion = await widget.qwenService
          .suggestStuckAssistSentence(
            ConversationContextRequest(
              transcript: _conversationContextForModel,
              currentPartial: trimmed,
              userSpeakerLabel:
                  _userSpeakerId == null ? '未确认' : '说话者$_userSpeakerId',
              timeText: _timeContext,
              locationText: !widget.locationController.enabled
                  ? '未启用定位'
                  : widget.locationController.currentPlace?.typeLabel ??
                      PlaceTypeCatalog.labelOf(
                        widget.locationController.currentSemantic?.type,
                      ),
              recentExpressions: widget.recentExpressions.take(6).toList(),
              personalWords: [
                ...ExpressionHabitStore.rank(
                  widget.expressionHabits,
                  category: 'conversation',
                  limit: 8,
                ).map((habit) => '甯哥敤${habit.count}娆★細${habit.text}'),
                ..._savedConversationTerms.take(8).map((term) => term.text),
                ...widget.favoriteExpressions,
                ...widget.vocabularyEntries.map((entry) => entry.text),
              ].take(20).toList(),
            ),
            cancellationToken: token,
          )
          .timeout(const Duration(seconds: 6));
    } catch (error) {
      token.cancel();
      if (error is! QwenCancelledException) {
        yuqiaoDebugLog(
            '[Conversation stuck assist] generation skipped: $error');
      }
    }
    if (identical(_stuckAssistToken, token)) _stuckAssistToken = null;
    if (!mounted) return;
    if (!_conversationActive) {
      setState(() {
        _isGeneratingStuckAssist = false;
        _lastStuckTriggerText = null;
      });
      return;
    }
    if (triggerRevision != _conversationEventRevision) {
      setState(() {
        _isGeneratingStuckAssist = false;
        _lastStuckTriggerText = null;
        _status = '正在聆听并区分说话者';
      });
      return;
    }
    setState(() {
      _isGeneratingStuckAssist = false;
      _status = _isListening ? '正在聆听并区分说话者' : _status;
    });
    if (suggestion == null || suggestion.trim().isEmpty) {
      _lastStuckTriggerText = null;
      return;
    }

    await HapticFeedback.lightImpact();
    if (!mounted) return;
    final confirmed = await _showStuckAssistConfirmation(suggestion.trim());
    if (!mounted) return;
    if (confirmed) {
      await _speakStuckAssist(suggestion.trim());
    } else {
      setState(() {
        _lastStuckTriggerText = null;
      });
    }
  }

  Future<bool> _showStuckAssistConfirmation(String suggestion) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE25C7F).withValues(alpha: 0.13),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D9DE),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '你可能想说',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE25C7F),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                suggestion,
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1D1D1F),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '确认后才会播报',
                style: TextStyle(fontSize: 13, color: Color(0xFF7A7C84)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: const Color(0xFF565860),
                        side: const BorderSide(color: Color(0xFFE1E2E7)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('不是'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      icon: const Icon(Icons.volume_up_rounded, size: 20),
                      label: const Text('确认播报'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: const Color(0xFFE25C7F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _speakStuckAssist(String text) async {
    _pauseTimer?.cancel();
    setState(() {
      _isSpeakingStuckAssist = true;
      _isListening = false;
      _status = '正在播报';
    });
    try {
      // 暂停 ASR，避免把手机自己的 TTS 再次识别成对话内容。
      await _asrService.stop();
      await _configureConversationTts();
      await _conversationTts.stop();
      await _conversationTts.speak(text);
      await widget.onExpressionCompleted(text);
      unawaited(
        widget.locationController.recordWordUsed(text, 'conversation'),
      );
      unawaited(
        widget.onHabitRecorded(
          text,
          category: 'conversation',
          source: 'conversation_auto_assist',
        ),
      );
    } catch (error) {
      yuqiaoDebugLog('[Conversation stuck assist] speak failed: $error');
      if (mounted) {
        setState(() => _error = '播报失败，请稍后重试');
      }
    } finally {
      _stuckAssistCooldownUntil =
          DateTime.now().add(const Duration(seconds: 15));
      _lastStuckTriggerText = null;
      if (mounted) {
        setState(() => _isSpeakingStuckAssist = false);
      }
    }
    if (mounted && _conversationActive) {
      await _resumeConversationAfterSpeech();
    }
  }

  Future<void> _resumeConversationAfterSpeech() async {
    if (!_conversationActive || _isStartingSpeech || _manualConversationStop) {
      return;
    }
    setState(() {
      _isStartingSpeech = true;
      _status = '正在恢复实时转写';
    });
    try {
      await _asrService.start(
        onTranscript: _handleXfyunTranscript,
        onStatus: _handleAsrStatus,
        onError: _handleAsrError,
      );
      if (!mounted || !_conversationActive) return;
      setState(() {
        _isStartingSpeech = false;
        _isListening = true;
        _status = '正在聆听并区分说话者';
      });
    } catch (error) {
      _handleAsrError(error.toString());
    }
  }

  Future<void> _toggleConversation() async {
    if (_conversationActive) {
      await _stopConversation();
      return;
    }
    await _startConversation();
  }

  String get _feedbackContextKey {
    final slot = RecommendationContext.inferSlot(_latestUserFragment);
    final normalized = LocationRecommendationController.normalizeText(
      _latestUserFragment,
    );
    final fragment = normalized.length <= 12
        ? normalized
        : normalized.substring(normalized.length - 12);
    return 'conversation:${slot.name}:$fragment';
  }

  Future<void> _suggestFromContext({
    List<String> excludedCandidates = const [],
  }) async {
    if (_isGeneratingStuckAssist || _isSpeakingStuckAssist) return;
    await _waitForTranscriptSnapshot();
    if (!mounted) return;
    final contextText = _conversationContextForModel;
    if (contextText.trim().isEmpty) {
      setState(() {
        _error = '还没有记录到对话内容。请先开启对话模式并说几句话。';
      });
      return;
    }
    setState(() {
      _isSuggesting = true;
      _error = null;
      _status = '正在让 Qwen 根据上下文补词';
    });

    // 记录加载弹窗是否仍在，避免用户主动关闭后误把当前页面 pop 掉。
    var loadingDialogOpen = true;
    final loadingDialogFuture = _showSuggestionDialog(context, null);
    unawaited(
      loadingDialogFuture.whenComplete(() {
        loadingDialogOpen = false;
      }),
    );

    List<String> suggestions;
    final feedbackProfile =
        await _conversationFeedbackStore.profileFor(_feedbackContextKey);
    if (!mounted) return;
    final rejectedCandidates = <String>{
      ...feedbackProfile.rejectedCandidates,
      ...excludedCandidates,
    }.toList();
    _conversationSuggestionToken?.cancel();
    final token = QwenCancellationToken();
    _conversationSuggestionToken = token;
    var cancelled = false;
    try {
      final raw = await widget.qwenService
          .recommendConversationOptions(
            ConversationContextRequest(
              transcript: contextText,
              currentPartial: _latestUserFragment,
              userSpeakerLabel:
                  _userSpeakerId == null ? '未确认' : '说话者$_userSpeakerId',
              timeText: _timeContext,
              locationText: !widget.locationController.enabled
                  ? '未启用定位'
                  : widget.locationController.currentPlace?.typeLabel ??
                      (widget.locationController.currentSemantic == null
                          ? '位置不可用'
                          : PlaceTypeCatalog.labelOf(
                              widget.locationController.currentSemantic?.type,
                            )),
              recentExpressions: widget.recentExpressions.take(6).toList(),
              personalWords: [
                ...ExpressionHabitStore.rank(
                  widget.expressionHabits,
                  category: 'conversation',
                  limit: 8,
                ).map((habit) => '常用${habit.count}次：${habit.text}'),
                ..._savedConversationTerms.take(8).map((term) =>
                    '${conversationTermTypeLabel(term.type)}：${term.text}'),
                ...widget.favoriteExpressions,
                ...widget.vocabularyEntries
                    .map((entry) => '${entry.category}：${entry.text}'),
              ].take(20).toList(),
              preferredTypes: feedbackProfile.preferredTypes,
              rejectedCandidates: rejectedCandidates,
            ),
            cancellationToken: token,
          )
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      _syncCompanionConversationContext();
      final ranked = await widget.companionAgent.rankExpressions(
        raw,
        feature: 'conversation',
        category: 'conversation',
        prompt: _latestUserFragment,
        slot: RecommendationContext.inferSlot(_latestUserFragment),
        selectedWords: [_latestUserFragment],
        allowContextExpansion:
            RecommendationContext.inferSlot(_latestUserFragment) !=
                RecommendationSlot.topic,
        limit: 8,
      );
      final rawByNormalized = <String, String>{
        for (final item in raw)
          LocationRecommendationController.normalizeText(item): item,
      };
      suggestions = [
        ...ranked.where((item) => rawByNormalized.containsKey(
              LocationRecommendationController.normalizeText(item),
            )),
        ...raw,
      ];
      final seenSuggestions = <String>{};
      suggestions = suggestions
          .where((item) {
            return seenSuggestions.add(
              LocationRecommendationController.normalizeText(item),
            );
          })
          .take(4)
          .toList();
      setState(() {
        _isSuggesting = false;
        _status = raw.isEmpty ? '未生成可用补词' : 'Qwen 已推荐下一个词或短语';
      });
    } catch (error) {
      final requestWasCancelled =
          error is QwenCancelledException || token.isCancelled;
      token.cancel();
      if (!mounted) return;
      if (requestWasCancelled) {
        cancelled = true;
        suggestions = const [];
        setState(() {
          _isSuggesting = false;
          _status = _conversationActive ? '正在聆听并区分说话者' : '对话模式已关闭';
        });
      } else {
        suggestions = const [];
        setState(() {
          _isSuggesting = false;
          _error = '暂时没有理解当前上下文，请再说几个字后重试。';
          _status = '上下文补词失败';
        });
        yuqiaoDebugLog('[Qwen conversation] failed: $error');
      }
    }
    if (identical(_conversationSuggestionToken, token)) {
      _conversationSuggestionToken = null;
    }

    // 关闭加载弹窗，弹出结果弹窗
    if (!mounted) return;
    if (loadingDialogOpen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await loadingDialogFuture;
    if (!mounted) return;
    if (cancelled) return;
    unawaited(_showSuggestionDialog(context, suggestions));
  }

  void _cancelConversationQwenRequests() {
    _conversationSuggestionToken?.cancel();
    _conversationSuggestionToken = null;
    _stuckAssistToken?.cancel();
    _stuckAssistToken = null;
    _speechRepairTimer?.cancel();
    _speechRepairToken?.cancel();
    _speechRepairToken = null;
    _understandingToken?.cancel();
    _understandingToken = null;
    _termExtractionToken?.cancel();
    _termExtractionToken = null;
  }

  Future<void> _openSpeechRepairConfirmation() async {
    final pending = _pendingSpeechRepair;
    if (pending == null || !mounted) return;
    final suggestion = pending.suggestion;
    var selected = suggestion.original;
    final decision = await showModalBottomSheet<({String text, bool speak})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE25C7F).withValues(alpha: 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9D9DE),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '要核对刚才这句话吗？',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  suggestion.reason.isEmpty
                      ? '这句话可能与前文不一致，请你来确认。'
                      : suggestion.reason,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Color(0xFF747780),
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.42,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: suggestion.candidates.map((candidate) {
                        final isSelected = candidate == selected;
                        final isOriginal = candidate == suggestion.original;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(17),
                            onTap: () =>
                                setSheetState(() => selected = candidate),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFFEDF3)
                                    : const Color(0xFFF6F6F8),
                                borderRadius: BorderRadius.circular(17),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFE25C7F)
                                      : const Color(0xFFE5E5EA),
                                  width: isSelected ? 1.4 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      candidate,
                                      style: TextStyle(
                                        fontSize: 18,
                                        height: 1.35,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: const Color(0xFF24252A),
                                      ),
                                    ),
                                  ),
                                  if (isOriginal)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: Text(
                                        '原话',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF8A8D95),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: isSelected
                                        ? const Color(0xFFE25C7F)
                                        : const Color(0xFFB8BAC1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(
                          (text: selected, speak: false),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: const Color(0xFF555861),
                          side: const BorderSide(color: Color(0xFFDADCE2)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          selected == suggestion.original ? '保留原话' : '只修正',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop(
                          (text: selected, speak: true),
                        ),
                        icon: const Icon(Icons.volume_up_rounded, size: 19),
                        label: const Text('确认并播报'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: const Color(0xFFE25C7F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted ||
        decision == null ||
        !identical(_pendingSpeechRepair, pending)) {
      return;
    }
    _applySpeechRepair(pending, decision.text);
    if (decision.speak) {
      await _speakStuckAssist(decision.text);
    }
  }

  void _applySpeechRepair(_PendingSpeechRepair pending, String selectedText) {
    final segment = _transcriptSegments[pending.segmentId];
    if (segment != null && selectedText != pending.suggestion.original) {
      _transcriptSegments[pending.segmentId] = _ConversationTranscriptSegment(
        id: segment.id,
        speakerId: segment.speakerId,
        text: selectedText,
        isFinal: true,
      );
      _conversationEventRevision++;
      _transcriptRevision.value++;
      _scrollTranscriptToLatest();
    }
    setState(() => _pendingSpeechRepair = null);
  }

  void _dismissSpeechRepair() {
    if (_pendingSpeechRepair == null) return;
    setState(() => _pendingSpeechRepair = null);
    _speechRepairCooldownUntil =
        DateTime.now().add(const Duration(seconds: 30));
  }

  void _chooseSuggestion(String suggestion) {
    unawaited(_conversationFeedbackStore.recordAccepted(
      contextKey: _feedbackContextKey,
      candidate: suggestion,
    ));
    unawaited(widget.companionAgent.recordInteraction(
      text: suggestion,
      feature: 'conversation',
      action: CompanionFeedbackAction.accepted,
      prompt: _latestUserFragment,
      slot: RecommendationContext.inferSlot(_latestUserFragment),
    ));
    final separator = suggestion.indexOf(RegExp(r'[：:]'));
    final suggestionType =
        separator > 0 ? suggestion.substring(0, separator).trim() : '继续表达';
    final suggestionText = separator > 0
        ? suggestion.substring(separator + 1).trim()
        : suggestion.trim();
    widget.locationController.recordWordUsed(suggestionText, 'conversation');
    unawaited(
      widget.onHabitRecorded(
        suggestionText,
        category: 'conversation',
        source: 'conversation_candidate',
      ),
    );
    final draft = ExpressionDraft(
      source: '对话模式',
      intent: '表达中断补词',
      keywords: [
        '最近对话：$_conversationContextForModel',
        '用户最后表达：$_latestUserFragment',
        '用户选择的补充类型：$suggestionType',
        '用户确认的补充内容：$suggestionText',
      ],
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiCandidatesPage(
          draft: draft,
          qwenService: widget.qwenService,
          personalizedLearningEnabled: widget.personalizedLearningEnabled,
          onCandidateSelected: (text) async {
            unawaited(
              widget.locationController.recordWordUsed(text, 'conversation'),
            );
            unawaited(
              widget.onHabitRecorded(
                text,
                category: 'conversation',
                source: 'conversation_sentence_candidate',
              ),
            );
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'conversation',
              action: CompanionFeedbackAction.accepted,
              prompt: _latestUserFragment,
              slot: RecommendationContext.inferSlot(_latestUserFragment),
            ));
          },
          onCandidateSaved: (text) async {
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'conversation',
              action: CompanionFeedbackAction.saved,
              prompt: _latestUserFragment,
              slot: RecommendationContext.inferSlot(_latestUserFragment),
            ));
          },
          onCandidatesRejected: (sentences) async {
            await widget.companionAgent.recordRejectedBatch(
              texts: sentences,
              feature: 'conversation',
              action: CompanionFeedbackAction.rejected,
              prompt: _latestUserFragment,
              slot: RecommendationContext.inferSlot(_latestUserFragment),
            );
          },
          onExpressionCompleted: widget.onExpressionCompleted,
          onFavoriteSaved: widget.onFavoriteSaved,
        ),
      ),
    );
  }

  Future<void> _showSuggestionDialog(
    BuildContext context,
    List<String>? suggestions,
  ) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 外层柔光
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFFF72A8).withValues(alpha: 0.10),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color:
                                const Color(0xFF8FD7F7).withValues(alpha: 0.08),
                            blurRadius: 28,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 渐变边框 + 内容
                Container(
                  padding: const EdgeInsets.all(1.6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFF78AF),
                        Color(0xFFFFC1BE),
                        Color(0xFFF4F1A1),
                        Color(0xFFAAEEA8),
                        Color(0xFFADE8F6),
                        Color(0xFFFFD9E5),
                      ],
                      stops: [0.00, 0.22, 0.40, 0.62, 0.82, 1.00],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.92),
                              const Color(0xFFFFFBFC).withValues(alpha: 0.86),
                              const Color(0xFFFDFDFE).withValues(alpha: 0.82),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            // 顶部高光
                            Positioned(
                              left: 18,
                              right: 18,
                              top: 10,
                              child: Container(
                                height: 26,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.58),
                                      Colors.white.withValues(alpha: 0.08),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // 内部彩色雾感
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _TranscriptGlowPainter(),
                                ),
                              ),
                            ),
                            // 内容
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(22, 22, 22, 18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 标题行
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          '可能想说',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF17181C),
                                            letterSpacing: -0.4,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () =>
                                            Navigator.of(dialogContext).pop(),
                                        child: Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.58),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.65),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: Color(0xFF4B4F58),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  // 候选卡片或加载中
                                  if (suggestions == null)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 32),
                                      child: Center(
                                        child: Text(
                                          '正在补词…',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ),
                                    )
                                  else if (suggestions.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 32),
                                      child: Center(
                                        child: Text(
                                          '暂无补词建议',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: const Color(0xFF2A2D34)
                                                .withValues(alpha: 0.56),
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: suggestions.take(4).length,
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 2,
                                            crossAxisSpacing: 14,
                                            mainAxisSpacing: 14,
                                            childAspectRatio:
                                                widget.candidateImageScale >=
                                                        1.25
                                                    ? 0.9
                                                    : 1.1,
                                          ),
                                          itemBuilder: (context, index) {
                                            return CandidateCard(
                                              text: suggestions[index],
                                              icon: _candidateIconForText(
                                                suggestions[index],
                                              ),
                                              imageScale:
                                                  widget.candidateImageScale,
                                              styleIndex: index,
                                              onTap: () {
                                                Navigator.of(dialogContext)
                                                    .pop();
                                                _chooseSuggestion(
                                                    suggestions[index]);
                                              },
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        TextButton.icon(
                                          onPressed: () {
                                            final rejected =
                                                suggestions.take(4).toList();
                                            unawaited(_conversationFeedbackStore
                                                .recordRejectedBatch(
                                              contextKey: _feedbackContextKey,
                                              candidates: rejected,
                                            ));
                                            unawaited(widget.companionAgent
                                                .recordRejectedBatch(
                                              texts: rejected,
                                              feature: 'conversation',
                                              action: CompanionFeedbackAction
                                                  .refreshed,
                                              prompt: _latestUserFragment,
                                              slot: RecommendationContext
                                                  .inferSlot(
                                                _latestUserFragment,
                                              ),
                                            ));
                                            Navigator.of(dialogContext).pop();
                                            unawaited(_suggestFromContext(
                                              excludedCandidates: rejected,
                                            ));
                                          },
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('都不是，换一组'),
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFF596171),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

  String get _conversationText {
    return [
      ..._contextLines,
      if (_currentTranscript.trim().isNotEmpty) _currentTranscript.trim(),
    ].join('\n');
  }

  List<String> get _contextLines => _transcriptSegments.values
      .where((segment) => segment.isFinal)
      .map((segment) => segment.displayText)
      .toList(growable: false);

  void _compactConversationTranscript() {
    final finalized = _transcriptSegments.entries
        .where((entry) => entry.value.isFinal)
        .toList(growable: false);
    if (finalized.length <= 12) return;
    final removeCount = finalized.length - 8;
    final removed = finalized.take(removeCount).toList(growable: false);
    final summaryParts = <String>[
      if (_conversationSummary.isNotEmpty)
        ..._conversationSummary
            .replaceFirst('较早对话：', '')
            .split('；')
            .where((item) => item.trim().isNotEmpty),
      ...removed.map((entry) {
        final text = entry.value.displayText;
        return text.length <= 54 ? text : '${text.substring(0, 54)}…';
      }),
    ];
    final unique = <String>[];
    final seen = <String>{};
    for (final part in summaryParts.reversed) {
      final normalized = LocationRecommendationController.normalizeText(part);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      unique.add(part.trim());
      if (unique.length == 6) break;
    }
    _conversationSummary = '较早对话：${unique.reversed.join('；')}';
    for (final entry in removed) {
      _transcriptSegments.remove(entry.key);
    }
  }

  String get _conversationContextForModel {
    final lines = <String>[
      if (_conversationSummary.isNotEmpty) _conversationSummary,
      ..._contextLines.skip(math.max(0, _contextLines.length - 8)),
      if (_currentTranscript.trim().isNotEmpty) _currentTranscript.trim(),
    ];
    final text = lines.join('\n');
    return text.length <= 1400 ? text : text.substring(text.length - 1400);
  }

  String get _latestUserFragment {
    final prefix = _userSpeakerId == null ? null : '说话者$_userSpeakerId：';
    if (_currentTranscript.trim().isNotEmpty &&
        (prefix == null || _currentTranscript.startsWith(prefix))) {
      return prefix == null
          ? _currentTranscript.trim()
          : _currentTranscript.substring(prefix.length).trim();
    }
    if (prefix != null) {
      for (final line in _contextLines.reversed) {
        if (line.startsWith(prefix)) {
          return line.substring(prefix.length).trim();
        }
      }
    }
    return _contextLines.isEmpty ? '' : _contextLines.last.trim();
  }

  void _syncCompanionConversationContext() {
    widget.companionAgent.updateConversationContext(
      transcript: _conversationContextForModel,
      latestUserFragment: _latestUserFragment,
      userSpeakerLabel: _userSpeakerId == null ? '未确认' : '说话者$_userSpeakerId',
      conversationTerms: _savedConversationTerms,
    );
  }

  Future<void> _waitForTranscriptSnapshot() async {
    final deadline = DateTime.now().add(const Duration(milliseconds: 850));
    var observedRevision = _conversationEventRevision;
    var stableSince = DateTime.now();
    while (mounted && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_conversationEventRevision != observedRevision) {
        observedRevision = _conversationEventRevision;
        stableSince = DateTime.now();
        continue;
      }
      if (DateTime.now().difference(stableSince) >=
          const Duration(milliseconds: 300)) {
        return;
      }
    }
  }

  void _scrollTranscriptToLatest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_transcriptScrollController.hasClients) return;
      final target = _transcriptScrollController.position.maxScrollExtent;
      if (animate) {
        _transcriptScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _transcriptScrollController.jumpTo(target);
      }
    });
  }

  void _openStuckSuggestionFromTranscript(BuildContext dialogContext) {
    Navigator.of(dialogContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_suggestFromContext());
    });
  }

  List<ConversationTermCandidate> get _conversationTermCandidates {
    final terms = <String, ConversationTermCandidate>{};
    terms.addAll(_sessionTerms);
    for (final term in _savedConversationTerms) {
      terms[term.normalizedText] = ConversationTermCandidate(
        text: term.text,
        type: term.type,
        confidence: 1,
      );
    }
    return terms.values.toList()
      ..sort((a, b) => b.text.length.compareTo(a.text.length));
  }

  ConversationTerm? _savedConversationTermFor(
    ConversationTermCandidate candidate,
  ) {
    for (final term in _savedConversationTerms) {
      if (term.normalizedText == candidate.normalizedText) return term;
    }
    return null;
  }

  Color _conversationTermColor(String type) {
    switch (normalizeConversationTermType(type)) {
      case 'person':
        return const Color(0xFFE25C7F);
      case 'place':
        return const Color(0xFF30A879);
      case 'organization':
        return const Color(0xFF3478F6);
      default:
        return const Color(0xFFD68A1F);
    }
  }

  List<_ConversationTranscriptSegment> get _finalizedTranscriptSegments =>
      _transcriptSegments.values
          .where((segment) => segment.isFinal)
          .toList(growable: false);

  Future<void> _openConversationUnderstanding(
    _ConversationTranscriptSegment segment,
  ) async {
    if (_isUnderstanding || segment.text.trim().isEmpty) return;
    final finalized = _finalizedTranscriptSegments;
    final selectedIndex = finalized.indexWhere((item) => item.id == segment.id);
    final start = math.max(0, selectedIndex - 2);
    final end = math.min(finalized.length, selectedIndex + 3);
    final surrounding = selectedIndex < 0
        ? const <String>[]
        : finalized
            .sublist(start, end)
            .map((item) => item.displayText)
            .toList(growable: false);

    _understandingToken?.cancel();
    final token = QwenCancellationToken();
    _understandingToken = token;
    setState(() => _isUnderstanding = true);
    final future = widget.qwenService._explainConversationUtterance(
      original: segment.text,
      speakerLabel: '说话者${segment.speakerId}',
      surroundingContext: surrounding,
      personalWords: _savedConversationTerms
          .take(10)
          .map((term) => '${conversationTermTypeLabel(term.type)}：${term.text}')
          .toList(growable: false),
      cancellationToken: token,
    );

    try {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.22),
        builder: (sheetContext) => _ConversationUnderstandingSheet(
          original: segment.text,
          result: future,
          onReadSlowly: _readUnderstandingText,
          onAskForSimplerSpeech: () => _readUnderstandingText(
            '不好意思，我没有听明白，可以说简单一点吗？',
          ),
        ),
      );
    } finally {
      token.cancel();
      if (identical(_understandingToken, token)) {
        _understandingToken = null;
      }
      if (mounted) setState(() => _isUnderstanding = false);
    }
  }

  Future<void> _readUnderstandingText(String text) async {
    if (_isReadingUnderstanding || text.trim().isEmpty) return;
    setState(() {
      _isReadingUnderstanding = true;
      _status = '正在慢速朗读文字';
    });
    try {
      if (_conversationActive) await _asrService.stop();
      await _conversationTts.stop();
      await _conversationTts.setLanguage('zh-CN');
      await _conversationTts.setSpeechRate(0.30);
      await _conversationTts.setPitch(1.0);
      await _conversationTts.awaitSpeakCompletion(true);
      await _conversationTts.speak(text.trim());
    } catch (error) {
      yuqiaoDebugLog('[Conversation understanding] TTS failed: $error');
      if (mounted) setState(() => _error = '慢速朗读失败，请稍后重试');
    } finally {
      await _configureConversationTts();
      if (mounted) setState(() => _isReadingUnderstanding = false);
    }
    if (mounted && _conversationActive) {
      await _resumeConversationAfterSpeech();
    }
  }

  Widget _buildTranscriptEntry(
    _ConversationTranscriptSegment segment,
  ) {
    final canUnderstand = _userSpeakerId != null &&
        segment.speakerId != _userSpeakerId &&
        segment.text.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 7),
      decoration: BoxDecoration(
        color: segment.speakerId == _userSpeakerId
            ? const Color(0xFFFFF4F7).withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHighlightedTranscriptLine(segment.displayText, false),
          if (canUnderstand)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isUnderstanding
                    ? null
                    : () => _openConversationUnderstanding(segment),
                icon: const Icon(Icons.menu_book_rounded, size: 17),
                label: const Text('帮我理解'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: const Color(0xFF3478F6),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHighlightedTranscriptLine(String text, bool isCurrent) {
    final candidates = _conversationTermCandidates
        .where((candidate) => text.contains(candidate.text))
        .toList();
    final baseStyle = TextStyle(
      fontSize: 15.5,
      height: 1.55,
      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
      color: isCurrent
          ? const Color(0xFF3478F6)
          : const Color(0xFF2A2D34).withValues(alpha: 0.76),
    );
    if (candidates.isEmpty) return Text(text, style: baseStyle);

    final spans = <InlineSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      ConversationTermCandidate? match;
      var matchIndex = text.length;
      for (final candidate in candidates) {
        final index = text.indexOf(candidate.text, cursor);
        if (index < 0) continue;
        if (index < matchIndex ||
            (index == matchIndex &&
                (match == null || candidate.text.length > match.text.length))) {
          match = candidate;
          matchIndex = index;
        }
      }
      if (match == null) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (matchIndex > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, matchIndex)));
      }
      final color = _conversationTermColor(match.type);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => _showConversationTermAction(match!),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: color.withValues(alpha: 0.34)),
              ),
              child: Text(
                match.text,
                style: baseStyle.copyWith(
                  height: 1.25,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
      cursor = matchIndex + match.text.length;
    }
    return RichText(text: TextSpan(style: baseStyle, children: spans));
  }

  Future<void> _showConversationTermAction(
    ConversationTermCandidate candidate,
  ) async {
    final saved = _savedConversationTermFor(candidate);
    var selectedType = normalizeConversationTermType(candidate.type);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          const types = ['person', 'place', 'organization', 'custom'];
          return SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
              decoration: const BoxDecoration(
                color: Color(0xFFFDFDFE),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D9DE),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    candidate.text,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF17181C),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    saved == null
                        ? '确认后会加入个人特殊词汇，并用于后续对话推荐。'
                        : '已保存到个人特殊词汇 · 使用 ${saved.count} 次',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Color(0xFF70727A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: types.map((type) {
                      final selected = selectedType == type;
                      final color = _conversationTermColor(type);
                      return ChoiceChip(
                        label: Text(conversationTermTypeLabel(type)),
                        selected: selected,
                        onSelected: saved == null
                            ? (_) => setSheetState(() => selectedType = type)
                            : null,
                        selectedColor: color.withValues(alpha: 0.16),
                        side: BorderSide(
                          color: selected
                              ? color.withValues(alpha: 0.48)
                              : const Color(0xFFE5E5EA),
                        ),
                        labelStyle: TextStyle(
                          color: selected ? color : const Color(0xFF565860),
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: saved != null
                          ? null
                          : () async {
                              final confirmed = ConversationTermCandidate(
                                text: candidate.text,
                                type: selectedType,
                                confidence: candidate.confidence,
                              );
                              await _conversationTermStore.confirm(confirmed);
                              if (!mounted) return;
                              _sessionTerms[confirmed.normalizedText] =
                                  confirmed;
                              await _loadSavedConversationTerms();
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                              if (mounted) {
                                unawaited(
                                  widget.companionAgent.recordInteraction(
                                    text: confirmed.text,
                                    feature: 'conversation',
                                    action: CompanionFeedbackAction.saved,
                                    prompt:
                                        '确认${conversationTermTypeLabel(confirmed.type)}',
                                    slot: RecommendationSlot.topic,
                                  ),
                                );
                                showYuqiaoLearningReceipt(
                                  this.context,
                                  personalizedLearningEnabled:
                                      widget.personalizedLearningEnabled,
                                  learnedMessage:
                                      '已记住“${candidate.text}”，语桥会用于理解后续对话',
                                  disabledMessage:
                                      '已记住“${candidate.text}”，个性化学习已关闭',
                                );
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE25C7F),
                        disabledBackgroundColor: const Color(0xFFE5E5EA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(saved == null ? '记住这个词' : '已保存'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showTranscriptBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      builder: (context) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        return ValueListenableBuilder<int>(
          valueListenable: _transcriptRevision,
          builder: (context, _, __) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    constraints: BoxConstraints(
                      maxHeight: screenHeight * 0.78,
                      minHeight: math.min(420.0, screenHeight * 0.52),
                    ),
                    padding: const EdgeInsets.all(1.6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF78AF),
                          Color(0xFFFFC1BE),
                          Color(0xFFF4F1A1),
                          Color(0xFFAAEEA8),
                          Color(0xFFADE8F6),
                          Color(0xFFFFD9E5),
                        ],
                        stops: [0.00, 0.22, 0.40, 0.62, 0.82, 1.00],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.11),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.94),
                                const Color(0xFFFFFBFC).withValues(alpha: 0.88),
                                const Color(0xFFFDFDFE).withValues(alpha: 0.84),
                              ],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: 18,
                                right: 18,
                                top: 10,
                                child: Center(
                                  child: Container(
                                    width: 54,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDADCE2),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _TranscriptGlowPainter(),
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(22, 24, 22, 18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '实时转录',
                                            style: TextStyle(
                                              fontSize: 23,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF17181C),
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () =>
                                              Navigator.of(context).pop(),
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.64),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              size: 19,
                                              color: Color(0xFF4B4F58),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_knownSpeakerIds.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Wrap(
                                          spacing: 7,
                                          runSpacing: 7,
                                          children: [
                                            const Text(
                                              '我的声音',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Color(0xFF7A7C84),
                                              ),
                                            ),
                                            ...(_knownSpeakerIds.toList()
                                                  ..sort())
                                                .map((speakerId) {
                                              final selected =
                                                  _userSpeakerId == speakerId;
                                              return ChoiceChip(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                label: Text('说话者$speakerId'),
                                                selected: selected,
                                                onSelected: (_) =>
                                                    _selectUserSpeaker(
                                                        speakerId),
                                                selectedColor:
                                                    const Color(0xFFE25C7F)
                                                        .withValues(
                                                            alpha: 0.14),
                                                side: BorderSide(
                                                  color: selected
                                                      ? const Color(0xFFE25C7F)
                                                      : const Color(0xFFE1E2E7),
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    if (_conversationTermCandidates.isNotEmpty)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                          '点击高亮词，可确认保存为个人特殊词汇',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: Color(0xFF7A7C84),
                                          ),
                                        ),
                                      ),
                                    if (_conversationSummary.isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(top: 10),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3478F6)
                                              .withValues(alpha: 0.07),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _conversationSummary,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: Color(0xFF60636C),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 14),
                                    Expanded(
                                      child: _conversationText.trim().isEmpty
                                          ? Center(
                                              child: Text(
                                                '还没有转录内容\n开启对话后开始收录',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  height: 1.5,
                                                  color: const Color(0xFF2A2D34)
                                                      .withValues(alpha: 0.56),
                                                ),
                                              ),
                                            )
                                          : ListView.builder(
                                              controller:
                                                  _transcriptScrollController,
                                              itemCount:
                                                  _finalizedTranscriptSegments
                                                          .length +
                                                      (_currentTranscript
                                                              .trim()
                                                              .isNotEmpty
                                                          ? 1
                                                          : 0),
                                              itemBuilder: (context, index) {
                                                final finalized =
                                                    _finalizedTranscriptSegments;
                                                final isCurrent =
                                                    index == finalized.length;
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    bottom: 12,
                                                  ),
                                                  child: isCurrent
                                                      ? _buildHighlightedTranscriptLine(
                                                          _currentTranscript
                                                              .trim(),
                                                          true,
                                                        )
                                                      : _buildTranscriptEntry(
                                                          finalized[index],
                                                        ),
                                                );
                                              },
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: FilledButton.icon(
                                        onPressed: _isSuggesting ||
                                                _isGeneratingStuckAssist
                                            ? null
                                            : () =>
                                                _openStuckSuggestionFromTranscript(
                                                  context,
                                                ),
                                        icon: const Icon(
                                          Icons.auto_awesome_rounded,
                                          size: 19,
                                        ),
                                        label: Text(
                                          _isSuggesting ||
                                                  _isGeneratingStuckAssist
                                              ? '正在理解上下文'
                                              : '我卡住了',
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFE25C7F),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _scrollTranscriptToLatest(animate: false);
  }

  void _showTranscriptDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (context) {
        return ValueListenableBuilder<int>(
          valueListenable: _transcriptRevision,
          builder: (context, _, __) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: SizedBox(
              width: 320,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 外层柔光
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(34),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF72A8)
                                  .withValues(alpha: 0.10),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: const Color(0xFF8FD7F7)
                                  .withValues(alpha: 0.08),
                              blurRadius: 28,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 渐变边框 + 内容
                  Container(
                    padding: const EdgeInsets.all(1.6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF78AF),
                          Color(0xFFFFC1BE),
                          Color(0xFFF4F1A1),
                          Color(0xFFAAEEA8),
                          Color(0xFFADE8F6),
                          Color(0xFFFFD9E5),
                        ],
                        stops: [0.00, 0.22, 0.40, 0.62, 0.82, 1.00],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 24,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 420),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.92),
                                const Color(0xFFFFFBFC).withValues(alpha: 0.86),
                                const Color(0xFFFDFDFE).withValues(alpha: 0.82),
                              ],
                            ),
                          ),
                          child: Stack(
                            children: [
                              // 顶部高光
                              Positioned(
                                left: 18,
                                right: 18,
                                top: 10,
                                child: Container(
                                  height: 26,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0.58),
                                        Colors.white.withValues(alpha: 0.08),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // 内部彩色雾感
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _TranscriptGlowPainter(),
                                  ),
                                ),
                              ),
                              // 内容
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(22, 22, 22, 18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 标题行
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '实时转录',
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF17181C),
                                              letterSpacing: -0.4,
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () =>
                                              Navigator.of(context).pop(),
                                          child: Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.58),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.65),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: Color(0xFF4B4F58),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_knownSpeakerIds.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Wrap(
                                          spacing: 7,
                                          runSpacing: 7,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            const Text(
                                              '我的声音',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Color(0xFF7A7C84),
                                              ),
                                            ),
                                            ...(_knownSpeakerIds.toList()
                                                  ..sort())
                                                .map((speakerId) {
                                              final selected =
                                                  _userSpeakerId == speakerId;
                                              return ChoiceChip(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                label: Text('说话者$speakerId'),
                                                selected: selected,
                                                onSelected: (_) =>
                                                    _selectUserSpeaker(
                                                        speakerId),
                                                selectedColor:
                                                    const Color(0xFFE25C7F)
                                                        .withValues(
                                                            alpha: 0.14),
                                                side: BorderSide(
                                                  color: selected
                                                      ? const Color(0xFFE25C7F)
                                                      : const Color(0xFFE1E2E7),
                                                ),
                                                labelStyle: TextStyle(
                                                  fontSize: 12,
                                                  color: selected
                                                      ? const Color(0xFFE25C7F)
                                                      : const Color(0xFF666870),
                                                  fontWeight: selected
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    if (_conversationTermCandidates.isNotEmpty)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                          '点击高亮词，可确认保存为个人特殊词汇',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: Color(0xFF7A7C84),
                                          ),
                                        ),
                                      ),
                                    if (_conversationSummary.isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(top: 10),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3478F6)
                                              .withValues(alpha: 0.07),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          _conversationSummary,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: Color(0xFF60636C),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    // 转录内容
                                    Flexible(
                                      child: _conversationText.trim().isEmpty
                                          ? Center(
                                              child: Text(
                                                '还没有转录内容\n开启对话后开始收录',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: const Color(0xFF2A2D34)
                                                      .withValues(alpha: 0.56),
                                                ),
                                              ),
                                            )
                                          : ListView.builder(
                                              controller:
                                                  _transcriptScrollController,
                                              shrinkWrap: true,
                                              itemCount:
                                                  _finalizedTranscriptSegments
                                                          .length +
                                                      (_currentTranscript
                                                              .trim()
                                                              .isNotEmpty
                                                          ? 1
                                                          : 0),
                                              itemBuilder: (context, index) {
                                                final finalized =
                                                    _finalizedTranscriptSegments;
                                                final isCurrent =
                                                    index == finalized.length;
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 12),
                                                  child: isCurrent
                                                      ? _buildHighlightedTranscriptLine(
                                                          _currentTranscript
                                                              .trim(),
                                                          true,
                                                        )
                                                      : _buildTranscriptEntry(
                                                          finalized[index],
                                                        ),
                                                );
                                              },
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: FilledButton.icon(
                                        onPressed: _isSuggesting ||
                                                _isGeneratingStuckAssist
                                            ? null
                                            : () =>
                                                _openStuckSuggestionFromTranscript(
                                                  context,
                                                ),
                                        icon: const Icon(
                                          Icons.auto_awesome_rounded,
                                          size: 19,
                                        ),
                                        label: Text(
                                          _isSuggesting ||
                                                  _isGeneratingStuckAssist
                                              ? '正在理解上下文…'
                                              : '我卡住了',
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFE25C7F),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _scrollTranscriptToLatest(animate: false);
  }

  String get _timeContext {
    final now = DateTime.now();
    final hour = now.hour;
    if (hour >= 5 && hour < 11) {
      return '早晨 ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    }
    if (hour >= 11 && hour < 14) {
      return '中午 ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    }
    if (hour >= 14 && hour < 18) {
      return '下午 ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    }
    return '晚上 ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSpeechRepairPrompt() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openSpeechRepairConfirmation,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFE25C7F).withValues(alpha: 0.32),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE25C7F).withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE8F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.fact_check_rounded,
                    size: 19,
                    color: Color(0xFFE25C7F),
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '要核对刚才这句话吗？',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF30323A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '点击查看可能表达',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF7A7C84),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '暂不核对',
                  onPressed: _dismissSpeechRepair,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: const Color(0xFF777A82),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final orbSize = screenWidth * 0.58;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Stack(
        children: [
          const Positioned.fill(child: _ConversationBackdrop()),
          SafeArea(
            child: Column(
              children: [
                // 顶部返回 + 标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: Color(0xFF243043),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          '对话模式',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1D1D1F),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _pendingSpeechRepair == null
                      ? const SizedBox.shrink()
                      : KeyedSubtree(
                          key: ValueKey(
                            _pendingSpeechRepair!.suggestion.original,
                          ),
                          child: _buildSpeechRepairPrompt(),
                        ),
                ),
                // 上方留白
                const Spacer(flex: 2),
                // 状态文字
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _isListening
                        ? const Color(0xFFE25C7F)
                        : const Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(height: 16),
                // Orb（点击弹出 ASR 转录内容）
                GestureDetector(
                  onTap: () => _showTranscriptBottomSheet(context),
                  child: SizedBox(
                    width: orbSize,
                    height: orbSize,
                    child: AnimatedBuilder(
                      animation: _orbController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: VoiceOrbPainter(
                            progress: _orbController.value,
                            isRecording: _isListening,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // 省略号（仅录音中显示）
                if (_isListening) ...[
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: _orbController,
                    builder: (context, child) {
                      return VoiceDotsIndicator(
                        progress: _orbController.value,
                        isRecording: _isListening,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 24),
                // 开启/关闭对话按钮（orb 下方）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: GestureDetector(
                    onTap: () => _toggleConversation(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _conversationActive
                              ? [
                                  const Color(0xFFE25C7F),
                                  const Color(0xFFF28B9E),
                                ]
                              : [
                                  const Color(0xFFF8A4B8),
                                  const Color(0xFFF28B9E),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(29),
                        boxShadow: [
                          BoxShadow(
                            color: (_conversationActive
                                    ? const Color(0xFFE25C7F)
                                    : const Color(0xFFF8A4B8))
                                .withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _conversationActive ? '关闭对话' : '开启对话',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 下方留白
                const Spacer(flex: 3),
                // 错误提示
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F0),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFD4D4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                          if (_asrNeedsManualReconnect) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _retryAsrConnection,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('重新连接'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFD32F2F),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                // 我卡住了
                if (_conversationActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: GestureDetector(
                      onTap: _isSuggesting || _isGeneratingStuckAssist
                          ? null
                          : () => _suggestFromContext(),
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: Center(
                          child: Text(
                            _isSuggesting || _isGeneratingStuckAssist
                                ? '正在补词…'
                                : '我卡住了',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF425064),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          YuqiaoFeatureAssistiveBall(
            currentFeature: YuqiaoFeature.conversation,
            launcher: widget.featureLauncher,
            bottomClearance: _conversationActive ? 96 : 32,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String? trailing) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1D1D1F),
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8E8E93),
            ),
          ),
      ],
    );
  }
}

class _ConversationUnderstandingSheet extends StatefulWidget {
  const _ConversationUnderstandingSheet({
    required this.original,
    required this.result,
    required this.onReadSlowly,
    required this.onAskForSimplerSpeech,
  });

  final String original;
  final Future<_ConversationUnderstanding> result;
  final Future<void> Function(String text) onReadSlowly;
  final Future<void> Function() onAskForSimplerSpeech;

  @override
  State<_ConversationUnderstandingSheet> createState() =>
      _ConversationUnderstandingSheetState();
}

class _ConversationUnderstandingSheetState
    extends State<_ConversationUnderstandingSheet> {
  bool _speaking = false;

  Future<void> _runSpeech(Future<void> Function() action) async {
    if (_speaking) return;
    setState(() => _speaking = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  IconData _iconForLabel(String label) {
    if (label.contains('时间')) return Icons.schedule_rounded;
    if (label.contains('地点')) return Icons.place_rounded;
    if (label.contains('人物')) return Icons.person_rounded;
    if (label.contains('然后')) return Icons.arrow_forward_rounded;
    if (label.contains('对象')) return Icons.category_rounded;
    if (label.contains('要求')) return Icons.record_voice_over_rounded;
    return Icons.check_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8F8FA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD2D3D8),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '帮我理解',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1D1D1F),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _UnderstandingSection(
                          title: '原话',
                          color: const Color(0xFF3478F6),
                          child: Text(
                            '“${widget.original}”',
                            style: const TextStyle(
                              fontSize: 19,
                              height: 1.55,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF272930),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FutureBuilder<_ConversationUnderstanding>(
                          future: widget.result,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const _UnderstandingLoading();
                            }
                            if (snapshot.hasError || !snapshot.hasData) {
                              return const _UnderstandingUnavailable();
                            }
                            return _buildUnderstanding(snapshot.data!);
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _speaking
                                    ? null
                                    : () => _runSpeech(
                                          () => widget.onReadSlowly(
                                            widget.original,
                                          ),
                                        ),
                                icon: const Icon(
                                  Icons.slow_motion_video_rounded,
                                  size: 19,
                                ),
                                label: Text(
                                  _speaking ? '正在朗读…' : '慢速朗读文字',
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  foregroundColor: const Color(0xFF3478F6),
                                  side: const BorderSide(
                                    color: Color(0xFFB9D0FA),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _speaking
                                ? null
                                : () => _runSpeech(
                                      widget.onAskForSimplerSpeech,
                                    ),
                            icon: const Icon(
                              Icons.record_voice_over_rounded,
                              size: 20,
                            ),
                            label: const Text('请对方说简单一点'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              backgroundColor: const Color(0xFFE25C7F),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFF555861),
                            ),
                            child: const Text('我明白了'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnderstanding(_ConversationUnderstanding result) {
    const colors = [
      Color(0xFFFFB56B),
      Color(0xFF8F86F7),
      Color(0xFF50B99A),
      Color(0xFFEA718F),
      Color(0xFF4D91E8),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UnderstandingSection(
          title: '分开来看',
          color: const Color(0xFF8F86F7),
          child: Column(
            children: List.generate(result.parts.length, (index) {
              final part = result.parts[index];
              final color = colors[index % colors.length];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == result.parts.length - 1 ? 0 : 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        _iconForLabel(part.label),
                        size: 18,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            part.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            part.text,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF292B31),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 14),
        _UnderstandingSection(
          title: '简单来说',
          color: const Color(0xFF50A482),
          child: Text(
            result.simpleMeaning,
            style: const TextStyle(
              fontSize: 19,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF25272D),
            ),
          ),
        ),
        if (result.importantNote.isNotEmpty) ...[
          const SizedBox(height: 14),
          _UnderstandingSection(
            title: '需要注意',
            color: const Color(0xFFE25C7F),
            child: Text(
              result.importantNote,
              style: const TextStyle(
                fontSize: 17,
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3A3034),
              ),
            ),
          ),
        ],
        if (result.uncertainties.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '暂时不确定：${result.uncertainties.join('；')}',
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF8A6B32),
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          '这是 AI 对原话的辅助解释，原话仍以上方转录为准。',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: Color(0xFF8A8D95),
          ),
        ),
      ],
    );
  }
}

class _UnderstandingSection extends StatelessWidget {
  const _UnderstandingSection({
    required this.title,
    required this.color,
    required this.child,
  });

  final String title;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

class _UnderstandingLoading extends StatelessWidget {
  const _UnderstandingLoading();

  @override
  Widget build(BuildContext context) {
    return const _UnderstandingSection(
      title: '正在整理',
      color: Color(0xFF8F86F7),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '正在拆分这句话的时间、人物和动作…',
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Color(0xFF666973),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnderstandingUnavailable extends StatelessWidget {
  const _UnderstandingUnavailable();

  @override
  Widget build(BuildContext context) {
    return const _UnderstandingSection(
      title: '暂时无法可靠解释',
      color: Color(0xFFE25C7F),
      child: Text(
        '语桥没有足够把握解释这句话。你可以慢速朗读转录文字，或请对方说得更简单。',
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: Color(0xFF5D5559),
        ),
      ),
    );
  }
}

class _ConversationBackdrop extends StatelessWidget {
  const _ConversationBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF9FCFF),
            Color(0xFFF4F0FF),
            Color(0xFFFFF0F3),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _ConversationBackdropPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ConversationBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFFB8D4FF).withValues(alpha: 0.28),
      const Color(0xFFFFC8D8).withValues(alpha: 0.24),
      const Color(0xFFE0C8FF).withValues(alpha: 0.20),
    ];
    final centers = [
      Offset(size.width * 0.22, size.height * 0.18),
      Offset(size.width * 0.78, size.height * 0.32),
      Offset(size.width * 0.45, size.height * 0.82),
    ];

    for (int i = 0; i < colors.length; i++) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [colors[i], colors[i].withValues(alpha: 0)],
        ).createShader(
          Rect.fromCircle(center: centers[i], radius: size.width * 0.46),
        );
      canvas.drawCircle(centers[i], size.width * 0.46, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TranscriptGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void drawGlow({
      required Offset center,
      required double radius,
      required List<Color> colors,
    }) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: colors,
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
          Rect.fromCircle(center: center, radius: radius),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(center, radius, paint);
    }

    drawGlow(
      center: Offset(size.width * 0.28, size.height * 0.28),
      radius: size.width * 0.24,
      colors: [
        const Color(0xFFFF8AAE).withValues(alpha: 0.16),
        const Color(0xFFFFC0C8).withValues(alpha: 0.08),
        Colors.transparent,
      ],
    );
    drawGlow(
      center: Offset(size.width * 0.62, size.height * 0.38),
      radius: size.width * 0.22,
      colors: [
        const Color(0xFFB5EEAB).withValues(alpha: 0.12),
        const Color(0xFFDCF6D4).withValues(alpha: 0.06),
        Colors.transparent,
      ],
    );
    drawGlow(
      center: Offset(size.width * 0.76, size.height * 0.30),
      radius: size.width * 0.20,
      colors: [
        const Color(0xFFACE3F6).withValues(alpha: 0.12),
        const Color(0xFFD8F1FA).withValues(alpha: 0.05),
        Colors.transparent,
      ],
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StuckFlowPage extends StatefulWidget {
  const StuckFlowPage({
    super.key,
    required this.qwenService,
    required this.locationController,
    required this.companionAgent,
    required this.personalizedLearningEnabled,
    required this.vocabularyEntries,
    required this.expressionHabits,
    this.preferredCandidateCount = 4,
    this.candidateImageScale = 1.0,
    required this.featureLauncher,
    required this.onHabitRecorded,
    required this.onExpressionCompleted,
    required this.onFavoriteSaved,
  });

  final QwenService qwenService;
  final LocationRecommendationController locationController;
  final CompanionAgentController companionAgent;
  final bool personalizedLearningEnabled;
  final List<VocabularyEntry> vocabularyEntries;
  final List<ExpressionHabit> expressionHabits;
  final int preferredCandidateCount;
  final double candidateImageScale;
  final YuqiaoFeatureLauncher featureLauncher;
  final HabitRecordCallback onHabitRecorded;
  final ExpressionCallback onExpressionCompleted;
  final ExpressionCallback onFavoriteSaved;

  @override
  State<StuckFlowPage> createState() => _GuidedStuckFlowPageState();
}

class _GuidedStuckFlowPageState extends State<StuckFlowPage> {
  final ParaformerAsrService _fragmentAsrService = ParaformerAsrService();
  StuckExpressionSession? _session;
  List<StuckCandidate> _visibleCandidates = const [];
  final Set<String> _seenCandidates = {};
  QwenCancellationToken? _recommendationToken;
  String _seedFragment = '';
  bool _isRecommending = false;
  bool _isRefreshing = false;
  bool _isHandlingBack = false;
  bool _isExitingCompletedFlow = false;
  int _recommendationRequestId = 0;
  int _refreshAttempts = 0;

  @override
  void initState() {
    super.initState();
    widget.locationController.refreshLocationContext();
  }

  @override
  void dispose() {
    _recommendationToken?.cancel();
    unawaited(_fragmentAsrService.dispose());
    super.dispose();
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

  String get _locationContext {
    if (!widget.locationController.enabled) return '未开启地点推荐';
    final place = widget.locationController.currentPlace;
    if (place != null) return place.typeLabel;
    final semantic = widget.locationController.currentSemantic;
    return semantic == null ? '未知地点' : PlaceTypeCatalog.labelOf(semantic.type);
  }

  void _chooseIntent(StuckExpressionIntent intent) {
    setState(() {
      _session = StuckExpressionSession(
        intent: intent,
        seedFragment: _seedFragment,
      );
      _resetStepState();
    });
    unawaited(_recommendCurrentStep());
  }

  void _resetStepState() {
    _recommendationRequestId++;
    _recommendationToken?.cancel();
    _visibleCandidates = const [];
    _seenCandidates.clear();
    _refreshAttempts = 0;
    _isRecommending = false;
    _isRefreshing = false;
  }

  Future<void> _chooseCandidate(StuckCandidate candidate) async {
    final session = _session;
    if (session == null) return;
    unawaited(
      widget.locationController.recordWordUsed(candidate.text, 'stuck'),
    );
    unawaited(
      widget.onHabitRecorded(
        candidate.text,
        category: 'stuck',
        source: 'stuck_candidate',
      ),
    );
    unawaited(widget.companionAgent.recordInteraction(
      text: candidate.text,
      feature: 'stuck',
      action: CompanionFeedbackAction.accepted,
      prompt: session.currentStep?.title ?? session.intent.sentenceIntent,
      slot: _locationSlotFor(candidate.slot),
    ));
    setState(() {
      session.select(candidate);
      _resetStepState();
    });
    if (session.currentStep != null) {
      await _recommendCurrentStep();
    }
  }

  Future<void> _skipCurrentStep() async {
    final session = _session;
    final step = session?.currentStep;
    if (session == null || step?.optional != true) return;
    _recordVisibleCandidateFeedback(
      session: session,
      step: step!,
      action: CompanionFeedbackAction.skipped,
    );
    setState(() {
      session.skipCurrent();
      _resetStepState();
    });
    if (session.currentStep != null) {
      await _recommendCurrentStep();
    }
  }

  Future<void> _editFrom(StuckExpressionSlot slot) async {
    final session = _session;
    if (session == null) return;
    setState(() {
      session.clearFrom(slot);
      _resetStepState();
    });
    await _recommendCurrentStep();
  }

  Future<void> _goBackWithinFlow() async {
    if (!mounted || _isHandlingBack) return;
    _isHandlingBack = true;
    try {
      final session = _session;
      if (session == null) {
        _recommendationToken?.cancel();
        await _fragmentAsrService.stop();
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
      final selections = session.selections;
      if (selections.isNotEmpty) {
        await _editFrom(selections.last.slot);
        return;
      }
      _recommendationToken?.cancel();
      setState(() {
        _session = null;
        _resetStepState();
      });
    } finally {
      _isHandlingBack = false;
    }
  }

  Future<void> _finishExpression() async {
    final session = _session;
    if (session == null || !session.canFinish) return;
    final keywords = <String>[
      if (session.seedFragment.trim().isNotEmpty)
        '用户记得的片段：${session.seedFragment.trim()}',
      ...session.selections.map(
        (selection) => '已确认${selection.slot.label}：${selection.candidate.text}',
      ),
    ];
    final draft = ExpressionDraft(
      source: '独立补词',
      intent: session.intent.sentenceIntent,
      keywords: keywords,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiCandidatesPage(
          draft: draft,
          qwenService: widget.qwenService,
          personalizedLearningEnabled: widget.personalizedLearningEnabled,
          onExitFlow: _exitCompletedFlow,
          onCandidateSelected: (text) async {
            unawaited(widget.locationController.recordWordUsed(text, 'stuck'));
            unawaited(
              widget.onHabitRecorded(
                text,
                category: 'stuck',
                source: 'stuck_sentence_candidate',
              ),
            );
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'stuck',
              action: CompanionFeedbackAction.accepted,
              prompt: session.intent.sentenceIntent,
              slot: RecommendationSlot.sentence,
            ));
          },
          onCandidateSaved: (text) async {
            unawaited(widget.companionAgent.recordInteraction(
              text: text,
              feature: 'stuck',
              action: CompanionFeedbackAction.saved,
              prompt: session.intent.sentenceIntent,
              slot: RecommendationSlot.sentence,
            ));
          },
          onCandidatesRejected: (sentences) async {
            await widget.companionAgent.recordRejectedBatch(
              texts: sentences,
              feature: 'stuck',
              action: CompanionFeedbackAction.rejected,
              prompt: session.intent.sentenceIntent,
              slot: RecommendationSlot.sentence,
            );
          },
          onExpressionCompleted: widget.onExpressionCompleted,
          onFavoriteSaved: widget.onFavoriteSaved,
        ),
      ),
    );
  }

  void _exitCompletedFlow() {
    if (!mounted || _isExitingCompletedFlow) return;
    _isExitingCompletedFlow = true;
    final flowRoute = ModalRoute.of(context);
    if (flowRoute == null) {
      Navigator.of(context).pop();
      return;
    }
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => identical(route, flowRoute));
    navigator.pop();
  }

  Future<void> _recommendCurrentStep({
    bool forceRefresh = false,
    int diversificationLevel = 0,
  }) async {
    final session = _session;
    final step = session?.currentStep;
    if (session == null || step == null) return;
    final requestId = ++_recommendationRequestId;
    _recommendationToken?.cancel();
    final token = QwenCancellationToken();
    _recommendationToken = token;
    final startedAt = DateTime.now();
    setState(() {
      _isRecommending = true;
      if (!forceRefresh) _visibleCandidates = const [];
    });

    final localCandidates = _localCandidates(step);
    List<StuckCandidate> modelCandidates = const [];
    try {
      modelCandidates = await widget.qwenService
          .recommendGuidedOptions(
            CandidateRecommendationRequest(
              intent: session.intent.sentenceIntent,
              stepTitle: step.title,
              slotKey: step.slot.key,
              slotLabel: step.slot.label,
              timeText: _timeContext,
              locationText: _locationContext,
              selectedKeywords: [
                if (session.seedFragment.isNotEmpty)
                  '记得的片段：${session.seedFragment}',
                ...session.selections.map(
                  (selection) =>
                      '${selection.slot.label}：${selection.candidate.text}',
                ),
              ],
              fallbackOptions:
                  localCandidates.map((candidate) => candidate.text).toList(),
              personalWords: _personalWordsForStep(step),
              excludeOptions: _seenCandidates.toList(),
              displayCount: widget.preferredCandidateCount.clamp(2, 6).toInt(),
              diversificationLevel: diversificationLevel,
            ),
            cancellationToken: token,
          )
          .timeout(const Duration(seconds: 6));
    } catch (error) {
      final cancelled = token.isCancelled || error is QwenCancelledException;
      token.cancel();
      if (!cancelled) {
        yuqiaoDebugLog('[StuckFlow] Qwen candidate fallback: $error');
      }
    }
    if (!mounted || requestId != _recommendationRequestId) return;

    // 首次 TLS 连接和模型冷启动可能超过 5 秒，不能过早伪装成模型推荐。
    if (modelCandidates.isEmpty && !forceRefresh) {
      final elapsed = DateTime.now().difference(startedAt);
      const fallbackDelay = Duration(seconds: 5);
      if (elapsed < fallbackDelay) {
        await Future<void>.delayed(fallbackDelay - elapsed);
      }
    }
    if (!mounted || requestId != _recommendationRequestId) return;

    final merged = await _mergeCandidatePool(
      modelCandidates: modelCandidates,
      localCandidates: localCandidates,
      step: step,
    );
    if (!mounted || requestId != _recommendationRequestId) return;
    final next = _takeDiverseCandidates(merged, step);
    yuqiaoDebugLog(
      '[StuckFlow] source=${modelCandidates.isEmpty ? 'local-fallback' : 'qwen'} '
      'elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds} '
      'context=${session.selections.map((item) => item.candidate.text).join('/')} '
      'seed=${session.seedFragment}',
    );
    setState(() {
      _visibleCandidates = next;
      _isRecommending = false;
      _isRefreshing = false;
    });
    if (next.isEmpty) {
      await _showClarificationSheet();
    }
  }

  List<StuckCandidate> _localCandidates(StuckStepDefinition step) {
    final result = <StuckCandidate>[];
    final seen = <String>{};
    for (final entry in widget.vocabularyEntries) {
      if (!step.vocabularyCategories.contains(entry.category)) continue;
      final normalized =
          LocationRecommendationController.normalizeText(entry.text);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(StuckCandidate(
        text: entry.text,
        semanticGroup: entry.category,
        slot: step.slot,
      ));
    }
    for (final candidate in step.options) {
      final normalized =
          LocationRecommendationController.normalizeText(candidate.text);
      if (seen.add(normalized)) result.add(candidate);
    }
    return result;
  }

  List<String> _personalWordsForStep(StuckStepDefinition step) {
    final habitWords = ExpressionHabitStore.rank(
      widget.expressionHabits,
      category: 'stuck',
      limit: 12,
    ).map((habit) => '常用${habit.count}次：${habit.text}');
    return [
      ...habitWords,
      ...widget.vocabularyEntries
          .where((entry) => step.vocabularyCategories.contains(entry.category))
          .map((entry) => '${entry.category}：${entry.text}'),
    ].take(24).toList();
  }

  Future<List<StuckCandidate>> _mergeCandidatePool({
    required List<StuckCandidate> modelCandidates,
    required List<StuckCandidate> localCandidates,
    required StuckStepDefinition step,
  }) async {
    final valid = <StuckCandidate>[];
    final seen = <String>{};
    for (final candidate in [...modelCandidates, ...localCandidates]) {
      if (candidate.slot != step.slot ||
          !StuckFlowCatalog.isPlausibleCandidate(
            candidate.slot,
            candidate.text,
          )) {
        continue;
      }
      final normalized =
          LocationRecommendationController.normalizeText(candidate.text);
      if (normalized.isEmpty ||
          _seenCandidates.contains(normalized) ||
          !seen.add(normalized)) {
        continue;
      }
      valid.add(candidate);
    }

    final rankedWords = widget.locationController.recommendWords(
      valid.map((candidate) => candidate.text).toList(),
      category: 'stuck',
      includeContextWords: true,
      context: _recommendationContext(step),
    );
    final locationRank = <String, int>{
      for (var index = 0; index < rankedWords.length; index++)
        LocationRecommendationController.normalizeText(rankedWords[index]):
            index,
    };
    final recommendationContext = _recommendationContext(step);
    final selectedWords = recommendationContext.selectedWords;
    List<String> companionRankedWords = const [];
    try {
      companionRankedWords = await widget.companionAgent.rankExpressions(
        valid.map((candidate) => candidate.text).toList(),
        feature: recommendationContext.feature,
        category: 'stuck',
        prompt: recommendationContext.prompt,
        slot: recommendationContext.slot,
        selectedWords: selectedWords,
        allowContextExpansion: recommendationContext.allowContextExpansion,
        limit: valid.length,
      );
    } catch (error) {
      yuqiaoDebugLog('[StuckFlow] companion ranking skipped: $error');
    }
    final companionRank = <String, int>{
      for (var index = 0; index < companionRankedWords.length; index++)
        LocationRecommendationController.normalizeText(
          companionRankedWords[index],
        ): index,
    };
    final baseIndex = <String, int>{
      for (var index = 0; index < valid.length; index++)
        LocationRecommendationController.normalizeText(valid[index].text):
            index,
    };
    valid.sort((a, b) {
      double scoreOf(StuckCandidate candidate) {
        final normalized =
            LocationRecommendationController.normalizeText(candidate.text);
        final sourceScore = candidate.isModelGenerated ? 1000.0 : 600.0;
        final orderScore = 120.0 - (baseIndex[normalized] ?? 12) * 8;
        final contextScore =
            math.max(0, 20 - (locationRank[normalized] ?? 20)).toDouble();
        final companionScore =
            math.max(0, 24 - (companionRank[normalized] ?? 24)).toDouble();
        return sourceScore + orderScore + contextScore + companionScore;
      }

      return scoreOf(b).compareTo(scoreOf(a));
    });

    final contextualSupplements = <StuckCandidate>[];
    final validNormalized = valid
        .map((candidate) =>
            LocationRecommendationController.normalizeText(candidate.text))
        .toSet();
    for (final word in rankedWords) {
      final normalized = LocationRecommendationController.normalizeText(word);
      if (validNormalized.contains(normalized)) continue;
      final contextual = _contextCandidate(word, step);
      if (contextual != null &&
          !_seenCandidates.contains(normalized) &&
          !contextualSupplements.any((item) =>
              LocationRecommendationController.normalizeText(item.text) ==
              normalized)) {
        // 地点和历史词只做补位，不插到模型及当前步骤候选之前。
        contextualSupplements.add(contextual);
      }
    }
    return [...valid, ...contextualSupplements.take(2)].take(16).toList();
  }

  RecommendationContext _recommendationContext(StuckStepDefinition step) {
    final session = _session!;
    return RecommendationContext(
      feature: 'stuck',
      intent: session.intent.sentenceIntent,
      prompt: step.title,
      slot: _locationSlotFor(step.slot),
      selectedWords: session.selections
          .map((selection) => selection.candidate.text)
          .toList(),
      allowContextExpansion: true,
    );
  }

  RecommendationSlot _locationSlotFor(StuckExpressionSlot slot) {
    return switch (slot) {
      StuckExpressionSlot.helper => RecommendationSlot.person,
      StuckExpressionSlot.communication => RecommendationSlot.sentence,
      StuckExpressionSlot.place => RecommendationSlot.place,
      StuckExpressionSlot.time => RecommendationSlot.time,
      StuckExpressionSlot.bodyPart => RecommendationSlot.bodyPart,
      StuckExpressionSlot.feeling ||
      StuckExpressionSlot.degree =>
        RecommendationSlot.feeling,
      StuckExpressionSlot.action => RecommendationSlot.actionOrObject,
      StuckExpressionSlot.target ||
      StuckExpressionSlot.object ||
      StuckExpressionSlot.subject =>
        RecommendationSlot.actionOrObject,
      StuckExpressionSlot.detail => RecommendationSlot.actionOrObject,
    };
  }

  StuckCandidate? _contextCandidate(
    String text,
    StuckStepDefinition step,
  ) {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > 18) return null;
    final fits = switch (step.slot) {
      StuckExpressionSlot.place =>
        RegExp(r'家|医院|超市|学校|公园|药店|餐厅|公司|小区|楼|房间|厕所|车站|地铁|这里|外面')
            .hasMatch(clean),
      StuckExpressionSlot.time =>
        RegExp(r'现在|刚才|今天|明天|昨天|早上|晚上|一会|最近|一直').hasMatch(clean),
      StuckExpressionSlot.bodyPart =>
        RegExp(r'头|肩|手|胸|肚|腰|腿|脚|背|喉咙').hasMatch(clean),
      StuckExpressionSlot.feeling =>
        RegExp(r'累|疼|痛|冷|热|怕|难过|高兴|着急|晕|麻|恶心').hasMatch(clean),
      StuckExpressionSlot.degree =>
        RegExp(r'一点|比较|很|严重|明显|越来越').hasMatch(clean),
      StuckExpressionSlot.action =>
        RegExp(r'找|拿|打开|关|去|回|吃|喝|休息|陪|说|看|买|用').hasMatch(clean),
      StuckExpressionSlot.helper =>
        RegExp(r'妈妈|爸爸|家人|朋友|老师|医生|护士|工作人员|同事').hasMatch(clean),
      StuckExpressionSlot.communication =>
        RegExp(r'帮我|请|你|哪里|怎么|自己|不用').hasMatch(clean),
      StuckExpressionSlot.detail => clean.length <= 8,
      // 泛化的历史名词容易污染对象槽位，只允许已按词库分类加入的对象。
      StuckExpressionSlot.target ||
      StuckExpressionSlot.object ||
      StuckExpressionSlot.subject =>
        false,
    };
    if (!fits) return null;
    return StuckCandidate(
      text: clean,
      semanticGroup: '个人常用',
      slot: step.slot,
    );
  }

  String _candidateMeaningKey(StuckCandidate candidate) {
    var normalized = LocationRecommendationController.normalizeText(
      candidate.text,
    );
    normalized = normalized
        .replaceAll(RegExp(r'^(我想|我要|请|麻烦|能不能|可以|帮我|给我|把)'), '')
        .replaceAll(RegExp(r'(一下|一点|可以吗|好吗|吗)$'), '')
        .trim();
    if (normalized.isEmpty) normalized = candidate.text.trim();

    final synonymGroups = <String, List<String>>{
      'get_object': ['拿', '取', '递', '给我', '带来', '找给我'],
      'find_object': ['找', '寻找', '找不到', '在哪里', '哪儿', '哪'],
      'drink_water': ['喝水', '水杯', '水瓶', '口渴', '倒水'],
      'eat_food': ['吃饭', '吃东西', '饭', '饿', '点餐'],
      'rest': ['休息', '坐一会', '躺', '睡觉', '太累'],
      'toilet': ['厕所', '卫生间', '上厕所'],
      'pain': ['疼', '痛', '不舒服', '难受'],
      'repeat': ['再说', '重复', '没听清', '慢一点'],
      'family': ['妈妈', '爸爸', '家人', '朋友'],
      'medical_staff': ['医生', '护士', '治疗师'],
      'pay': ['付款', '缴费', '结账', '买单', '多少钱'],
      'go_home': ['回家', '回去', '到家'],
    };
    for (final entry in synonymGroups.entries) {
      if (entry.value.any(normalized.contains)) {
        return '${candidate.slot.name}:${entry.key}';
      }
    }

    final compact =
        normalized.length <= 4 ? normalized : normalized.substring(0, 4);
    return '${candidate.slot.name}:$compact';
  }

  List<StuckCandidate> _takeDiverseCandidates(
    List<StuckCandidate> pool,
    StuckStepDefinition step,
  ) {
    final result = <StuckCandidate>[];
    final targetCount = widget.preferredCandidateCount.clamp(2, 6).toInt();
    final groups = <String>{};
    final selectedTexts = <String>{};
    final selectedMeanings = <String>{};
    final normalizedSeen = _seenCandidates
        .map(LocationRecommendationController.normalizeText)
        .toSet();

    bool addCandidate(
      StuckCandidate candidate, {
      required bool requireNewGroup,
      required bool requireNewMeaning,
    }) {
      final normalized =
          LocationRecommendationController.normalizeText(candidate.text);
      final meaningKey = _candidateMeaningKey(candidate);
      if (candidate.slot != step.slot ||
          normalizedSeen.contains(normalized) ||
          selectedTexts.contains(normalized) ||
          (requireNewMeaning && selectedMeanings.contains(meaningKey)) ||
          (requireNewGroup && groups.contains(candidate.semanticGroup))) {
        return false;
      }
      groups.add(candidate.semanticGroup);
      selectedTexts.add(normalized);
      selectedMeanings.add(meaningKey);
      result.add(candidate);
      return result.length == targetCount;
    }

    // 第一轮优先使用真正的模型结果；本地词只在模型不足时补位。
    for (final candidate in pool.where((item) => item.isModelGenerated)) {
      if (addCandidate(
        candidate,
        requireNewGroup: true,
        requireNewMeaning: true,
      )) {
        return result;
      }
    }
    // 模型偶尔会复用 semanticGroup。此时优先保留其上下文候选，
    // 不要为了凑齐四种标签而立即回填无关的本地模板。
    for (final candidate in pool.where((item) => item.isModelGenerated)) {
      if (addCandidate(
        candidate,
        requireNewGroup: false,
        requireNewMeaning: true,
      )) {
        return result;
      }
    }
    for (final candidate in pool) {
      if (addCandidate(
        candidate,
        requireNewGroup: true,
        requireNewMeaning: true,
      )) {
        return result;
      }
    }
    for (final candidate in pool) {
      if (addCandidate(
        candidate,
        requireNewGroup: false,
        requireNewMeaning: false,
      )) {
        return result;
      }
    }
    return result;
  }

  Future<void> _refreshOptions() async {
    final session = _session;
    final step = session?.currentStep;
    if (session == null || step == null || _isRecommending || _isRefreshing) {
      return;
    }
    _recordVisibleCandidateFeedback(
      session: session,
      step: step,
      action: CompanionFeedbackAction.refreshed,
    );
    _seenCandidates.addAll(
      _visibleCandidates.map(
        (candidate) =>
            LocationRecommendationController.normalizeText(candidate.text),
      ),
    );
    _refreshAttempts++;
    setState(() => _isRefreshing = true);
    await _recommendCurrentStep(
      forceRefresh: true,
      diversificationLevel: _refreshAttempts,
    );
  }

  void _recordVisibleCandidateFeedback({
    required StuckExpressionSession session,
    required StuckStepDefinition step,
    required CompanionFeedbackAction action,
  }) {
    final texts = _visibleCandidates
        .map((candidate) => candidate.text.trim())
        .where((text) => text.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (texts.isEmpty) return;
    unawaited(widget.companionAgent.recordRejectedBatch(
      texts: texts,
      feature: 'stuck',
      action: action,
      prompt: step.title.isEmpty ? session.intent.sentenceIntent : step.title,
      slot: _locationSlotFor(step.slot),
    ));
  }

  Future<void> _showClarificationSheet() async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFFFDFDFE),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('换个方式找一找', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 6),
              const Text(
                '连续换组仍不合适时，补充一个字或修改前面的选择会更准确。',
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 16),
              _ClarificationAction(
                icon: Icons.keyboard_alt_outlined,
                label: '输入一个字或词',
                onTap: () => Navigator.of(sheetContext).pop('type'),
              ),
              _ClarificationAction(
                icon: Icons.mic_rounded,
                label: '语音说出一部分',
                onTap: () => Navigator.of(sheetContext).pop('voice'),
              ),
              _ClarificationAction(
                icon: Icons.undo_rounded,
                label: '返回上一步修改',
                onTap: () => Navigator.of(sheetContext).pop('back'),
              ),
              _ClarificationAction(
                icon: Icons.category_outlined,
                label: '重新选择表达类型',
                onTap: () => Navigator.of(sheetContext).pop('restart'),
              ),
              _ClarificationAction(
                icon: Icons.refresh_rounded,
                label: '继续生成不同方向',
                onTap: () => Navigator.of(sheetContext).pop('more'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'type':
        await _openFragmentInput();
        return;
      case 'voice':
        await _openFragmentInput(autoStartVoice: true);
        return;
      case 'back':
        final selections = _session?.selections ?? const [];
        if (selections.isNotEmpty) await _editFrom(selections.last.slot);
        return;
      case 'restart':
        setState(() {
          _session = null;
          _resetStepState();
        });
        return;
      case 'more':
        setState(() => _refreshAttempts = 0);
        await _recommendCurrentStep(
          forceRefresh: true,
          diversificationLevel: 3,
        );
        return;
    }
  }

  Future<void> _openFragmentInput({
    bool autoStartVoice = false,
    bool asSeed = false,
  }) async {
    final step = asSeed ? null : _session?.currentStep;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FragmentInputSheet(
        service: _fragmentAsrService,
        title: step == null ? '你还记得哪些字？' : '补充“${step.slot.label}”',
        autoStartVoice: autoStartVoice,
      ),
    );
    await _fragmentAsrService.stop();
    if (!mounted || value == null || value.trim().isEmpty) return;
    if (asSeed || _session == null) {
      setState(() {
        _seedFragment = value.trim();
        _session?.seedFragment = _seedFragment;
        if (_session != null) _resetStepState();
      });
      if (_session?.currentStep != null) {
        await _recommendCurrentStep();
      }
      return;
    }
    await _chooseCandidate(StuckCandidate(
      text: value.trim(),
      semanticGroup: '用户输入',
      slot: step!.slot,
    ));
  }

  Widget _buildIntentPicker() {
    Widget card({
      required String title,
      required Color backgroundColor,
      required Color iconBackground,
      required IconData icon,
      required StuckExpressionIntent intent,
    }) {
      return Expanded(
        child: _IntentCard(
          title: title,
          backgroundColor: backgroundColor,
          iconBackground: iconBackground,
          icon: icon,
          onTap: () => _chooseIntent(intent),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            card(
              title: '要人帮忙',
              backgroundColor: const Color(0xFFFFE2C8),
              iconBackground: const Color(0xFFFFF1DC),
              icon: Icons.volunteer_activism_rounded,
              intent: StuckExpressionIntent.help,
            ),
            const SizedBox(width: 18),
            card(
              title: '表达不舒服',
              backgroundColor: const Color(0xFFC9F1E8),
              iconBackground: const Color(0xFFB7E6EE),
              icon: Icons.healing_rounded,
              intent: StuckExpressionIntent.discomfort,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            card(
              title: '要东西',
              backgroundColor: const Color(0xFFDCD9FF),
              iconBackground: const Color(0xFFEDD8F7),
              icon: Icons.local_mall_rounded,
              intent: StuckExpressionIntent.object,
            ),
            const SizedBox(width: 18),
            card(
              title: '问问题',
              backgroundColor: const Color(0xFFFFC9CC),
              iconBackground: const Color(0xFFFFE5E6),
              icon: Icons.help_outline_rounded,
              intent: StuckExpressionIntent.question,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _WideIntentCard(
          title: '说明情况',
          subtitle: '描述刚才发生的事，或补充一句背景',
          backgroundColor: const Color(0xFFEAF0FF),
          iconBackground: const Color(0xFFF2F5FF),
          icon: Icons.chat_bubble_outline_rounded,
          onTap: () => _chooseIntent(StuckExpressionIntent.situation),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => _openFragmentInput(asSeed: true),
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(
            _seedFragment.isEmpty ? '我只记得几个字' : '已记住：$_seedFragment（点击修改）',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpressionTrail(StuckExpressionSession session) {
    final selectedCount = session.selections.length;
    final stepCount = session.activeSteps.length;
    final lastSelection =
        session.selections.isEmpty ? null : session.selections.last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.route_rounded,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              selectedCount == 0
                  ? session.intent.label
                  : '${session.intent.label} · 已补充 $selectedCount/$stepCount 项',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (session.seedFragment.isNotEmpty)
            TextButton(
              onPressed: () => _openFragmentInput(asSeed: true),
              child: const Text('改提示'),
            ),
          if (lastSelection != null)
            TextButton(
              onPressed: () => _editFrom(lastSelection.slot),
              child: const Text('改上一步'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final step = session?.currentStep;
    final pickingIntent = session == null;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.page),
              children: [
                PageHeader(
                  title: pickingIntent ? '你想表达什么？' : step?.title ?? '表达已经足够清楚',
                  subtitle: pickingIntent
                      ? '先选择最接近的任务，也可以输入记得的几个字'
                      : step?.subtitle ?? '可以整理成完整句子，也可以返回修改',
                  onBack: _goBackWithinFlow,
                ),
                const SizedBox(height: 18),
                if (session != null) ...[
                  _buildExpressionTrail(session),
                  const SizedBox(height: AppSpacing.section),
                ],
                if (pickingIntent)
                  _buildIntentPicker()
                else ...[
                  if (step != null)
                    _isRecommending
                        ? _CandidateLoadingGrid(
                            count: widget.preferredCandidateCount,
                          )
                        : _StuckCandidateGrid(
                            candidates: _visibleCandidates,
                            imageScale: widget.candidateImageScale,
                            onSelected: _chooseCandidate,
                          ),
                  if (step != null && !_isRecommending) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: _isRefreshing ? null : _refreshOptions,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_isRefreshing ? '正在换一组' : '换一组'),
                        ),
                        if (step.optional) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _skipCurrentStep,
                            child: const Text('跳过这一步'),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (session.canFinish) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _finishExpression,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: Text(step == null ? '整理成完整句子' : '现在整理成句'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    if (step != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Center(
                          child: Text(
                            '也可以继续选择，让表达更准确',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
          YuqiaoFeatureAssistiveBall(
            currentFeature: YuqiaoFeature.stuck,
            launcher: widget.featureLauncher,
            bottomClearance: 28,
          ),
        ],
      ),
    );
  }
}

class _FragmentInputSheet extends StatefulWidget {
  const _FragmentInputSheet({
    required this.service,
    required this.title,
    required this.autoStartVoice,
  });

  final ParaformerAsrService service;
  final String title;
  final bool autoStartVoice;

  @override
  State<_FragmentInputSheet> createState() => _FragmentInputSheetState();
}

class _FragmentInputSheetState extends State<_FragmentInputSheet> {
  late final TextEditingController _controller;
  bool _recording = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    if (widget.autoStartVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_toggleVoice());
      });
    }
  }

  @override
  void dispose() {
    unawaited(widget.service.stop());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      await widget.service.stop();
      if (mounted) setState(() => _recording = false);
      return;
    }
    setState(() {
      _recording = true;
      _errorText = null;
    });
    try {
      await widget.service.start(
        onTranscript: (text, isFinal) {
          if (!mounted) return;
          _controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
          if (isFinal) {
            setState(() => _recording = false);
            unawaited(widget.service.stop());
          }
        },
        onStatus: (_) {},
        onError: (message) {
          if (!mounted) return;
          setState(() {
            _recording = false;
            _errorText = message;
          });
        },
      );
      if (!mounted) await widget.service.stop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _errorText = error.toString();
      });
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    unawaited(widget.service.stop());
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFFFDFDFE),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: AppTextStyles.sectionTitle),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: !widget.autoStartVoice,
              maxLength: 20,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '输入一个字、词或短语',
                filled: true,
                fillColor: const Color(0xFFF3F4F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  tooltip: _recording ? '停止录音' : '语音输入',
                  onPressed: _toggleVoice,
                  icon: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: _recording ? AppColors.danger : AppColors.primary,
                  ),
                ),
              ),
            ),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _errorText!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('使用这段内容'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StuckCandidateGrid extends StatelessWidget {
  const _StuckCandidateGrid({
    super.key,
    required this.candidates,
    required this.imageScale,
    required this.onSelected,
  });

  final List<StuckCandidate> candidates;
  final double imageScale;
  final ValueChanged<StuckCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    final effectiveScale = imageScale.clamp(0.85, 1.55).toDouble();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: candidates.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.gap,
        mainAxisSpacing: AppSpacing.gap,
        childAspectRatio: effectiveScale >= 1.25 ? 0.95 : 1.2,
      ),
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final style = _candidateCardStyles[index % _candidateCardStyles.length];
        final iconDiameter = (44 * effectiveScale).clamp(38.0, 70.0);
        final iconSize = (26 * effectiveScale).clamp(22.0, 42.0);
        final cardPadding = effectiveScale >= 1.3
            ? 12.0
            : effectiveScale >= 1.15
                ? 14.0
                : 16.0;
        return InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => onSelected(candidate),
          child: Container(
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: style.shadow.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconDiameter,
                  height: iconDiameter,
                  decoration: BoxDecoration(
                    color: style.iconBackground.withValues(alpha: 0.88),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _candidateIconForText(
                      candidate.text,
                      semanticGroup: candidate.semanticGroup,
                    ),
                    size: iconSize,
                    color: const Color(0xFF151515),
                  ),
                ),
                SizedBox(height: 10 + (effectiveScale - 1) * 4),
                Flexible(
                  child: Text(
                    candidate.text,
                    textAlign: TextAlign.center,
                    maxLines: effectiveScale >= 1.3 ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
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

class _ClarificationAction extends StatelessWidget {
  const _ClarificationAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _CandidateLoadingGrid extends StatefulWidget {
  const _CandidateLoadingGrid({
    super.key,
    required this.count,
  });

  final int count;

  @override
  State<_CandidateLoadingGrid> createState() => _CandidateLoadingGridState();
}

class _CandidateLoadingGridState extends State<_CandidateLoadingGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.count.clamp(2, 6).toInt();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.gap,
        mainAxisSpacing: AppSpacing.gap,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final style = _candidateCardStyles[index % _candidateCardStyles.length];
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final phase = (_controller.value - index * 0.14) % 1.0;
            final pulse =
                (1 - (phase * 2 - 1).abs()).clamp(0.0, 1.0).toDouble();
            return Transform.scale(
              scale: 0.985 + pulse * 0.015,
              child: Container(
                decoration: BoxDecoration(
                  color: Color.lerp(
                    style.background.withValues(alpha: 0.68),
                    style.background,
                    pulse,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.72),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: style.shadow.withValues(
                        alpha: 0.08 + pulse * 0.15,
                      ),
                      blurRadius: 12 + pulse * 10,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (dotIndex) {
                      final dotPhase =
                          (_controller.value * 1.5 - dotIndex * 0.16) % 1.0;
                      final dotPulse = (1 - (dotPhase * 2 - 1).abs())
                          .clamp(0.0, 1.0)
                          .toDouble();
                      return Container(
                        width: 7 + dotPulse * 2,
                        height: 7 + dotPulse * 2,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: style.shadow.withValues(
                            alpha: 0.30 + dotPulse * 0.50,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _IntentCard extends StatelessWidget {
  final String title;
  final Color backgroundColor;
  final Color iconBackground;
  final IconData icon;
  final VoidCallback onTap;

  const _IntentCard({
    required this.title,
    required this.backgroundColor,
    required this.iconBackground,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.98,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: backgroundColor.withValues(alpha: 0.26),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: iconBackground.withValues(alpha: 0.86),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 23, color: const Color(0xFF111111)),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF151515),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideIntentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final Color iconBackground;
  final IconData icon;
  final VoidCallback onTap;

  const _WideIntentCard({
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    required this.iconBackground,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBackground.withValues(alpha: 0.92),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: const Color(0xFF111111)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF151515),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF151515).withValues(alpha: 0.56),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: const Color(0xFF151515).withValues(alpha: 0.46),
            ),
          ],
        ),
      ),
    );
  }
}

class AiCandidatesPage extends StatefulWidget {
  const AiCandidatesPage({
    super.key,
    required this.draft,
    required this.qwenService,
    required this.personalizedLearningEnabled,
    this.onExitFlow,
    this.onCandidateSelected,
    this.onCandidateSaved,
    this.onCandidatesRejected,
    required this.onExpressionCompleted,
    required this.onFavoriteSaved,
  });

  final ExpressionDraft draft;
  final QwenService qwenService;
  final bool personalizedLearningEnabled;
  final VoidCallback? onExitFlow;
  final ExpressionCallback? onCandidateSelected;
  final ExpressionCallback? onCandidateSaved;
  final Future<void> Function(List<String> sentences)? onCandidatesRejected;
  final ExpressionCallback onExpressionCompleted;
  final ExpressionCallback onFavoriteSaved;

  @override
  State<AiCandidatesPage> createState() => _AiCandidatesPageState();
}

class _AiCandidatesPageState extends State<AiCandidatesPage> {
  late Future<List<String>> _future;
  QwenCancellationToken? _cancellationToken;
  bool _exitingFlow = false;
  bool _returningToSelection = false;

  @override
  void initState() {
    super.initState();
    _future = _loadCandidates();
  }

  Future<List<String>> _loadCandidates() {
    _cancellationToken?.cancel();
    final token = QwenCancellationToken();
    _cancellationToken = token;
    return widget.qwenService.generateSentences(
      widget.draft,
      cancellationToken: token,
    );
  }

  void _retry() {
    setState(() {
      _future = _loadCandidates();
    });
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    super.dispose();
  }

  void _handleBack() {
    if (_exitingFlow) return;
    final onExitFlow = widget.onExitFlow;
    if (onExitFlow == null) {
      Navigator.of(context).pop();
      return;
    }
    _exitingFlow = true;
    onExitFlow();
  }

  void _returnToSelection([List<String> rejectedSentences = const []]) {
    if (_returningToSelection || _exitingFlow) return;
    setState(() => _returningToSelection = true);
    _cancellationToken?.cancel();
    if (rejectedSentences.isNotEmpty) {
      final onCandidatesRejected = widget.onCandidatesRejected;
      if (onCandidatesRejected != null) {
        unawaited(onCandidatesRejected(rejectedSentences));
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: widget.onExitFlow == null || _returningToSelection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.onExitFlow != null && !_returningToSelection) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F5F0),
        body: SafeArea(
          child: FutureBuilder<List<String>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return _buildLoadingState();
              }
              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error.toString());
              }
              final sentences = snapshot.data ?? const [];
              return _buildResultState(sentences);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF3478F6).withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF3478F6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '正在整理表达',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2A2D34),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '语桥正在生成候选句…',
            style: TextStyle(
              fontSize: 14,
              color: const Color(0xFF2A2D34).withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final message = _friendlyGenerationError(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: Color(0xFFE8615B)),
            const SizedBox(height: 20),
            const Text(
              '生成失败',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2A2D34),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF2A2D34).withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _retry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF3478F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '重试',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyGenerationError(String error) {
    if (error.contains('FormatException') ||
        error.contains('Unexpected character') ||
        error.contains('Invalid model JSON')) {
      return '模型返回格式不稳定，语桥已经尝试自动修复。请重试一次。';
    }
    return error;
  }

  Widget _buildResultState(List<String> sentences) {
    return ListView(
      physics: const BouncingScrollPhysics(),
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
                  onTap: _handleBack,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.86),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 14,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.black.withValues(alpha: 0.70),
                      size: 20,
                    ),
                  ),
                ),
              ),
              const Center(
                child: Text(
                  '选择表达',
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
        // 标题区域
        const Center(
          child: Text(
            '请选择最接近的一句',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: Color(0xFF1F2328),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '轻触即可播报给对方',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8E8A84).withValues(alpha: 0.8),
            ),
          ),
        ),
        const SizedBox(height: 32),
        // 句子卡片
        for (int i = 0; i < sentences.take(3).length; i++) ...[
          _SentenceCardNew(
            text: sentences[i],
            index: i,
            onTap: () {
              final onCandidateSelected = widget.onCandidateSelected;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConfirmSpeakPage(
                    sentence: sentences[i],
                    personalizedLearningEnabled:
                        widget.personalizedLearningEnabled,
                    onExitFlow: widget.onExitFlow,
                    onExpressionCompleted: (sentence) async {
                      await widget.onExpressionCompleted(sentence);
                      await onCandidateSelected?.call(sentence);
                    },
                    onFavoriteSaved: widget.onFavoriteSaved,
                    onCandidateSaved: widget.onCandidateSaved,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 12),
        // 底部按钮
        Center(
          child: GestureDetector(
            onTap: () => _returnToSelection(sentences.take(3).toList()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFFE0E0E0).withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded,
                      size: 20,
                      color: const Color(0xFF425064).withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text(
                    '都不对，重新选择',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF425064).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SentenceCardNew extends StatelessWidget {
  final String text;
  final int index;
  final VoidCallback onTap;

  const _SentenceCardNew({
    required this.text,
    required this.index,
    required this.onTap,
  });

  static const _accentColors = [
    [Color(0xFF3478F6), Color(0xFF6CB4FF)],
    [Color(0xFF43A777), Color(0xFF81C784)],
    [Color(0xFFE5A51F), Color(0xFFFFD54F)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _accentColors[index % _accentColors.length];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.96),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // 左侧渐变色条
            Container(
              width: 5,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // 句子文字
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                  letterSpacing: -0.3,
                  color: Color(0xFF2A2D34),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 播放图标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.first.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.volume_up_rounded,
                size: 22,
                color: colors.first.withValues(alpha: 0.80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    return _mergeLocalObjectBoxes(recognition, localBoxes);
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

  Future<void> _startRecognition(
    Uint8List bytes, {
    bool mirrored = false,
  }) async {
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

class ConfirmSpeakPage extends StatefulWidget {
  const ConfirmSpeakPage({
    super.key,
    required this.sentence,
    required this.personalizedLearningEnabled,
    this.onExitFlow,
    required this.onExpressionCompleted,
    required this.onFavoriteSaved,
    this.onCandidateSaved,
  });

  final String sentence;
  final bool personalizedLearningEnabled;
  final VoidCallback? onExitFlow;
  final ExpressionCallback onExpressionCompleted;
  final ExpressionCallback onFavoriteSaved;
  final ExpressionCallback? onCandidateSaved;

  @override
  State<ConfirmSpeakPage> createState() => _ConfirmSpeakPageState();
}

class _ConfirmSpeakPageState extends State<ConfirmSpeakPage> {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _saved = false;
  bool _exitingFlow = false;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('zh-CN');
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak() async {
    setState(() => _isSpeaking = true);
    await widget.onExpressionCompleted(widget.sentence);
    await _tts.speak(widget.sentence);
    if (mounted) {
      setState(() => _isSpeaking = false);
      _showLearningFeedback(
        widget.personalizedLearningEnabled ? '已播报，语桥会记住你的选择' : '已播报，个性化学习已关闭',
      );
    }
  }

  Future<void> _saveFavorite() async {
    await widget.onFavoriteSaved(widget.sentence);
    await widget.onCandidateSaved?.call(widget.sentence);
    setState(() => _saved = true);
    _showLearningFeedback(
      widget.personalizedLearningEnabled ? '已收藏，下次会更容易找到' : '已收藏，可在收藏中找到',
    );
  }

  void _showLearningFeedback(String message) {
    if (!mounted) return;
    showYuqiaoLearningReceipt(
      context,
      personalizedLearningEnabled: true,
      learnedMessage: message,
      disabledMessage: message,
    );
  }

  void _handleBack() {
    if (_exitingFlow) return;
    final onExitFlow = widget.onExitFlow;
    if (onExitFlow == null) {
      Navigator.of(context).pop();
      return;
    }
    _exitingFlow = true;
    onExitFlow();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: widget.onExitFlow == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.onExitFlow != null) _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F5F0),
        body: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: SizedBox(
                  height: 46,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: _handleBack,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.86),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 14,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.black.withValues(alpha: 0.70),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const Center(
                        child: Text(
                          '确认播报',
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
              ),
              const SizedBox(height: 20),
              // 提示文字
              Text(
                '我想说',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8E8A84).withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 20),
              // 句子展示区
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.96),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF3478F6).withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 顶部装饰线
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3478F6), Color(0xFF6CB4FF)],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // 句子文字
                        Text(
                          widget.sentence,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1.4,
                            letterSpacing: -0.5,
                            color: Color(0xFF1F2328),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // 底部装饰线
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6CB4FF), Color(0xFF3478F6)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // 播报按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GestureDetector(
                  onTap: _isSpeaking ? null : _speak,
                  child: Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: _isSpeaking
                          ? const LinearGradient(
                              colors: [Color(0xFFB0B0B0), Color(0xFFCCCCCC)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF3478F6), Color(0xFF6CB4FF)],
                            ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: _isSpeaking
                          ? []
                          : [
                              BoxShadow(
                                color: const Color(0xFF3478F6)
                                    .withValues(alpha: 0.30),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isSpeaking
                                ? Icons.volume_up_rounded
                                : Icons.volume_up_outlined,
                            size: 24,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isSpeaking ? '正在播报…' : '播报给对方',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 底部操作按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: const Color(0xFFE0E0E0)
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.swap_horiz_rounded,
                                    size: 20,
                                    color: const Color(0xFF425064)
                                        .withValues(alpha: 0.7)),
                                const SizedBox(width: 6),
                                Text(
                                  '换一种说法',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF425064)
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: GestureDetector(
                        onTap: _saved ? null : _saveFavorite,
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            color: _saved
                                ? const Color(0xFF43A777)
                                    .withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: _saved
                                  ? const Color(0xFF43A777)
                                      .withValues(alpha: 0.3)
                                  : const Color(0xFFE0E0E0)
                                      .withValues(alpha: 0.6),
                            ),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _saved
                                      ? Icons.check_rounded
                                      : Icons.bookmark_border_rounded,
                                  size: 20,
                                  color: _saved
                                      ? const Color(0xFF43A777)
                                      : const Color(0xFF425064)
                                          .withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _saved ? '已保存' : '保存',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _saved
                                        ? const Color(0xFF43A777)
                                        : const Color(0xFF425064)
                                            .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QwenCancellationToken {
  final Completer<void> _abortCompleter = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _abortCompleter.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _abortCompleter.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const QwenCancelledException();
  }
}

class _StructuredSentenceCandidate {
  const _StructuredSentenceCandidate({
    required this.sentence,
    required this.evidence,
    required this.assumptions,
    required this.complete,
  });

  final String sentence;
  final List<String> evidence;
  final List<String> assumptions;
  final bool complete;

  static _StructuredSentenceCandidate? fromJson(Map<String, dynamic> json) {
    final sentence = json['sentence'];
    if (sentence is! String || sentence.trim().isEmpty) return null;
    List<String> stringsOf(Object? value) => value is List
        ? value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList()
        : const [];
    return _StructuredSentenceCandidate(
      sentence: sentence.trim(),
      evidence: stringsOf(json['evidence']),
      assumptions: stringsOf(json['assumptions']),
      complete: json['complete'] == true,
    );
  }
}

class _SentenceValidation {
  const _SentenceValidation.valid(this.sentence) : reason = '';

  const _SentenceValidation.invalid(this.reason) : sentence = null;

  final String? sentence;
  final String reason;
}

class QwenService {
  final http.Client _client = http.Client();

  static const String _apiKey = String.fromEnvironment('QWEN_API_KEY');
  static const String _baseUrl = String.fromEnvironment(
    'QWEN_BASE_URL',
    defaultValue:
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
  );
  static const String _textModel = String.fromEnvironment(
    'QWEN_TEXT_MODEL',
    defaultValue: 'qwen-plus',
  );
  static const String _recommendModel = String.fromEnvironment(
    'QWEN_RECOMMEND_MODEL',
    defaultValue: 'qwen-turbo',
  );
  static const String _visionModel = String.fromEnvironment(
    'QWEN_VISION_MODEL',
    defaultValue: 'qwen-vl-plus',
  );

  Future<List<String>> generateSentences(
    ExpressionDraft draft, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final accepted = <String>[];
    final rejectionReasons = <String>[];
    Object? lastError;
    for (var attempt = 0; attempt < 2 && accepted.length < 2; attempt++) {
      cancellationToken?.throwIfCancelled();
      try {
        final response = await _requestStructuredSentences(
          draft,
          rejectionReasons: attempt == 0 ? const [] : rejectionReasons,
          cancellationToken: cancellationToken,
        );
        final candidates = _parseStructuredSentenceCandidates(
          _messageContent(response),
        );
        for (final candidate in candidates) {
          final validation = _validateStructuredSentence(candidate, draft);
          if (validation.sentence == null) {
            rejectionReasons.add(validation.reason);
            continue;
          }
          accepted.add(validation.sentence!);
        }
      } on QwenCancelledException {
        rethrow;
      } catch (error) {
        lastError = error;
        rejectionReasons.add('上次返回格式不稳定或候选句未通过校验，请严格返回 JSON');
        yuqiaoDebugLog('[Qwen generateSentences] retryable failure: $error');
      }
    }
    if (lastError != null) {
      yuqiaoDebugLog(
          '[Qwen generateSentences] recovered after retry: $lastError');
    }
    final seen = <String>{};
    final sentences = <String>[];
    for (final sentence in accepted) {
      final normalized = sentence.replaceAll(RegExp(r'[，。！？、,.!?\s]'), '');
      if (!seen.add(normalized)) continue;
      sentences.add(sentence);
      if (sentences.length == 3) break;
    }
    if (sentences.isEmpty) {
      throw const FormatException('模型没有返回逻辑完整的候选句');
    }
    return sentences;
  }

  Future<Map<String, dynamic>> _requestStructuredSentences(
    ExpressionDraft draft, {
    required List<String> rejectionReasons,
    QwenCancellationToken? cancellationToken,
  }) {
    return _post({
      'model': _textModel,
      'temperature': 0.15,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的句子整理与语义校验模块。'
              '每条候选必须是可独立播报、语法完整、逻辑通顺的中文句子。'
              '区分两类信息：evidence 是输入中原文可找到的证据；assumptions 是为了补全表达而提出的新信息。'
              '新人名、地点、数字、症状并非一律禁止，可以作为合理假设出现；'
              '但有 assumptions 时，句子必须明确写成询问、请求、建议或可能性，不能把假设说成已经确认的事实。'
              '例如“王医生在吗？”和“请帮我去三楼”可以保留；'
              '没有依据时，“我已经吃了三片药”或“我得了某种病”不能保留。'
              'evidence 必须填写输入里的简短原文片段，不能把推测伪装成证据。'
              '不要机械拼接不同说话者的话，不要以“因为、但是、然后、我想”等未完成结构结束。'
              '只返回 JSON 对象：'
              '{"candidates":[{"sentence":"完整句子","intent":"询问或请求等","evidence":["输入原文"],"assumptions":["新增信息"],"complete":true}]}。',
        },
        {
          'role': 'user',
          'content': '来源：${draft.source}\n'
              '表达方向：${draft.intent}\n'
              '输入信息：${draft.keywords.join(' / ')}\n'
              '${rejectionReasons.isEmpty ? '' : '上次未通过原因：${rejectionReasons.take(6).join('；')}\n'}'
              '请生成 3 到 4 条简短、自然且彼此有区别的候选句。',
        },
      ],
    }, cancellationToken: cancellationToken);
  }

  List<_StructuredSentenceCandidate> _parseStructuredSentenceCandidates(
    String content,
  ) {
    Object decoded;
    try {
      decoded = jsonDecode(_stripCodeFence(content));
    } catch (_) {
      final recovered = _recoverStructuredSentenceCandidates(content);
      if (recovered.isNotEmpty) return recovered;
      rethrow;
    }
    if (decoded is! Map<String, dynamic> || decoded['candidates'] is! List) {
      throw const QwenException('候选句返回格式错误，应为 JSON 对象。');
    }
    return (decoded['candidates'] as List)
        .whereType<Map>()
        .map((item) => _StructuredSentenceCandidate.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .whereType<_StructuredSentenceCandidate>()
        .take(6)
        .toList();
  }

  List<_StructuredSentenceCandidate> _recoverStructuredSentenceCandidates(
    String content,
  ) {
    final cleaned = _stripCodeFence(content);
    final results = <_StructuredSentenceCandidate>[];
    final seen = <String>{};
    final patterns = [
      RegExp(r'"sentence"\s*:\s*"((?:\\.|[^"\\])*)"', dotAll: true),
      RegExp(r'“sentence”\s*[:：]\s*“([^”]+)”', dotAll: true),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(cleaned)) {
        final raw = match.group(1);
        if (raw == null || raw.trim().isEmpty) continue;
        final sentence = _decodeJsonStringFragment(raw);
        final normalized =
            LocationRecommendationController.normalizeText(sentence);
        if (normalized.isEmpty || !seen.add(normalized)) continue;
        results.add(_StructuredSentenceCandidate(
          sentence: sentence,
          evidence: const [],
          assumptions: const [],
          complete: true,
        ));
        if (results.length == 6) return results;
      }
    }
    return results;
  }

  String _decodeJsonStringFragment(String value) {
    try {
      final decoded = jsonDecode('"$value"');
      if (decoded is String) return decoded.trim();
    } catch (_) {}
    return value
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  _SentenceValidation _validateStructuredSentence(
    _StructuredSentenceCandidate candidate,
    ExpressionDraft draft,
  ) {
    if (!candidate.complete) {
      return const _SentenceValidation.invalid('模型标记句子尚不完整');
    }
    final sentence = _validatedCompleteSentence(candidate.sentence);
    if (sentence == null) {
      return const _SentenceValidation.invalid('句子缺少必要成分或结尾不完整');
    }
    final source = LocationRecommendationController.normalizeText(
      '${draft.source}${draft.intent}${draft.keywords.join()}',
    );
    for (final evidence in candidate.evidence) {
      final normalizedEvidence =
          LocationRecommendationController.normalizeText(evidence);
      if (normalizedEvidence.isNotEmpty &&
          !source.contains(normalizedEvidence)) {
        return _SentenceValidation.invalid('证据“$evidence”在输入中不存在');
      }
    }
    if (candidate.assumptions.isNotEmpty &&
        !_isExplicitlyFramedAssumption(sentence)) {
      return const _SentenceValidation.invalid(
        '新增信息被写成了确定事实，应改为询问、请求、建议或可能性',
      );
    }
    return _SentenceValidation.valid(sentence);
  }

  bool _isExplicitlyFramedAssumption(String sentence) {
    const markers = [
      '吗',
      '是不是',
      '是否',
      '可能',
      '也许',
      '大概',
      '要不要',
      '可以',
      '能不能',
      '请',
      '帮我',
      '麻烦',
      '我想',
      '我要',
      '我需要',
    ];
    return markers.any(sentence.contains) || sentence.endsWith('？');
  }

  String? _validatedCompleteSentence(String value) {
    var sentence = value
        .trim()
        .replaceFirst(RegExp(r'^\s*\d+[.、）)]\s*'), '')
        .replaceAll(RegExp(r'^["“”]+|["“”]+$'), '')
        .trim();
    if (sentence.length < 4 || sentence.length > 48) return null;
    if (sentence.contains('对话上下文：') || sentence.contains('用户已确认关键词：')) {
      return null;
    }
    final withoutPunctuation =
        sentence.replaceAll(RegExp(r'[，。！？、,.!?：:；;\s]+$'), '');
    const incompleteEndings = [
      '因为',
      '但是',
      '然后',
      '还有',
      '所以',
      '如果',
      '我想',
      '我要',
      '我需要',
      '能不能',
      '帮我',
      '给我',
    ];
    if (incompleteEndings.any(withoutPunctuation.endsWith)) return null;
    if (!RegExp(r'[。！？!?]$').hasMatch(sentence)) {
      sentence = '$sentence。';
    }
    return sentence;
  }

  Future<List<String>> recommendNextOptions(
      CandidateRecommendationRequest request) async {
    _ensureConfigured();
    yuqiaoDebugLog(
      '[Qwen recommendNextOptions] intent=${request.intent}, '
      'step=${request.stepTitle}, selected=${request.selectedKeywords.join('/')}, '
      'excluded=${request.excludeOptions.length}',
    );
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.35,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的候选词推荐模块。'
              '你的任务不是生成完整句子，而是预测用户下一步最可能想点的短候选词。'
              '必须紧扣“已确认内容”和“当前页面问题”，候选之间要有明显上下文关联。'
              '每个候选不超过 6 个汉字，适合按钮展示。'
              '除非本地兜底候选非常合适，否则不要简单照抄本地兜底候选。'
              '一次提供 8 到 12 个不重复候选，供界面分组展示。'
              '输出必须是 JSON 字符串数组，例如 ["医生","护士","家人","朋友","护工","老师","同事","康复师"]。',
        },
        {
          'role': 'user',
          'content': '表达方向：${request.intent}\n'
              '当前页面问题：${request.stepTitle}\n'
              '已确认内容：${request.selectedKeywords.join(' / ')}\n'
              '本地兜底候选：${request.fallbackOptions.join(' / ')}\n'
              '个人日常词库：${request.personalWords.join(' / ')}\n'
              '${request.excludeOptions.isEmpty ? '' : '不要推荐以下已出现过的词：${request.excludeOptions.join(' / ')}\n'}'
              '推荐要求：优先贴近日常生活表达，必要时使用个人词库中的人物、饮食、地点、活动、物品或常用句；'
              '不要过度偏向药品或重度照护场景，除非上下文明确提到身体不适或医疗问题。'
              '请尽量返回 8 到 12 个彼此不同的候选。\n'
              '请只返回下一步候选词 JSON 数组。',
        },
      ],
    });
    final options = _parseStringList(_messageContent(response))
        .map(_normalizeOption)
        .where((item) => item.isNotEmpty)
        .take(12)
        .toList();
    yuqiaoDebugLog(
      '[Qwen recommendNextOptions] returned=${options.length} '
      'options=${options.join('/')}',
    );
    return options;
  }

  Future<List<StuckCandidate>> recommendGuidedOptions(
    CandidateRecommendationRequest request, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    yuqiaoDebugLog(
      '[Qwen guided stuck] slot=${request.slotKey} '
      'diversify=${request.diversificationLevel} '
      'excluded=${request.excludeOptions.length}',
    );
    final expectedSlot = StuckExpressionSlot.values.firstWhere(
      (slot) => slot.key == request.slotKey,
      orElse: () => StuckExpressionSlot.detail,
    );
    final confirmedContext = request.selectedKeywords
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(' / ');
    final hasUserContext = confirmedContext.isNotEmpty;
    final response = await _post({
      'model': _recommendModel,
      'temperature': request.diversificationLevel > 0 ? 0.48 : 0.28,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的独立补词模块。'
              '这里没有实时对话上下文，只能使用用户当前选择的表达任务、已确认槽位和记得的文字片段。'
              '用户明确提供的信息是最高优先级：只要已有片段或已确认槽位，每个候选都必须能自然接在这些信息之后，不能重新猜一个无关话题。'
              '你只负责生成指定 slot 的候选，不能返回其他类型。'
              '候选可以是词、短语或很短的句子，每项不超过 18 个汉字。'
              'semanticGroup 表示候选代表的不同语义方向；前 ${request.displayCount} 项必须尽量属于不同方向，不能只是同义改写。'
              '地点、时间、历史词和个人词只能在符合当前 slot 且与用户已选内容连贯时使用。'
              '只返回 JSON 对象：'
              '{"candidates":[{"text":"候选","slot":"指定slot","semanticGroup":"语义方向"}]}。',
        },
        {
          'role': 'user',
          'content': '表达任务：${request.intent}\n'
              '当前时间：${request.timeText.isEmpty ? '未知' : request.timeText}\n'
              '当前地点：${request.locationText.isEmpty ? '未知' : request.locationText}\n'
              '当前问题：${request.stepTitle}\n'
              '当前槽位：${request.slotKey}（${request.slotLabel}）\n'
              '用户明确提供的信息（最高优先级）：${hasUserContext ? confirmedContext : '暂无，只有表达任务'}\n'
              '${hasUserContext ? '强约束：逐项检查候选是否与上述全部信息连贯；不连贯的候选不要输出。\n' : '当前信息不足，可以覆盖几个常见但不同的日常方向。\n'}'
              '${hasUserContext ? '' : '无上下文时的本地参考：${request.fallbackOptions.join(' / ')}\n'}'
              '个人词仅在与用户信息直接相关时使用：${request.personalWords.join(' / ')}\n'
              '${request.excludeOptions.isEmpty ? '' : '禁止重复：${request.excludeOptions.join(' / ')}\n'}'
              '${request.diversificationLevel > 0 ? '这是用户点击“换一组”后的第 ${request.diversificationLevel + 1} 组，必须重新基于已选内容生成，不要复用上一组语义方向，也不要只换同义词。\n' : ''}'
              '返回 ${math.max(8, request.displayCount + 4)} 到 12 个候选，严格保持 slot 为 ${request.slotKey}。',
        },
      ],
    }, cancellationToken: cancellationToken);
    final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
    if (decoded is! Map<String, dynamic> || decoded['candidates'] is! List) {
      throw const QwenException('补词候选格式错误，应为 JSON 对象。');
    }
    final excluded = request.excludeOptions
        .map(LocationRecommendationController.normalizeText)
        .toSet();
    final seen = <String>{};
    final candidates = <StuckCandidate>[];
    final rawCandidates = decoded['candidates'] as List;
    var rejected = 0;
    for (final raw in rawCandidates) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final text = (item['text']?.toString() ?? '')
          .trim()
          .replaceAll(RegExp(r'[。！？!?]+$'), '')
          .trim();
      final slot = item['slot']?.toString().trim() ?? '';
      final semanticGroup = item['semanticGroup']?.toString().trim() ?? '';
      final normalized = LocationRecommendationController.normalizeText(text);
      final slotMatches = slot.isEmpty ||
          slot == request.slotKey ||
          slot == request.slotLabel ||
          slot == expectedSlot.label;
      if (!slotMatches ||
          text.isEmpty ||
          text.length > 18 ||
          semanticGroup.isEmpty ||
          excluded.contains(normalized) ||
          !seen.add(normalized)) {
        rejected++;
        continue;
      }
      candidates.add(StuckCandidate(
        text: text,
        semanticGroup: semanticGroup,
        slot: expectedSlot,
        isModelGenerated: true,
      ));
      if (candidates.length == 12) break;
    }
    yuqiaoDebugLog(
      '[Qwen guided stuck] raw=${rawCandidates.length} '
      'accepted=${candidates.length} rejected=$rejected '
      'options=${candidates.map((item) => '${item.semanticGroup}:${item.text}').join('/')}',
    );
    return candidates;
  }

  Future<List<String>> recommendConversationOptions(
    ConversationContextRequest request, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    yuqiaoDebugLog(
        '[Qwen conversation] transcript=${request.transcript.length} chars');
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.3,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的对话补词模块。'
              '必须优先衔接指定用户最近尚未完成或刚完成的表达，而不是根据地点猜测通用需求。'
              '返回 4 个沟通功能不同的候选，可以是词、短语或完整短句，正文每项 2 到 14 个汉字。'
              '四项必须分别使用“继续、补充、询问、等待”作为类型前缀，格式为“类型：正文”；'
              '不能出现两个同义改写。可以提出上下文之外的新人物、地点、数字或症状，'
              '但只能写成询问、可能性或建议，不能当作用户已经确认的事实。'
              '上下文不足时宁可返回“请等我一下”等修复性表达，也不要猜测“我不舒服”。'
              '只返回 JSON 字符串数组，例如["继续：我想喝水","补充：要温水","询问：有温水吗","等待：请等我一下"]。',
        },
        {
          'role': 'user',
          'content': '当前时间：${request.timeText}\n'
              '当前位置：${request.locationText}\n'
              '用户对应说话者：${request.userSpeakerLabel}\n'
              '当前转写片段：${request.currentPartial}\n'
              '当前对话上下文：\n${request.transcript}\n\n'
              '近期表达：${request.recentExpressions.join(' / ')}\n'
              '个人常用语：${request.personalWords.join(' / ')}\n'
              '${request.preferredTypes.isEmpty ? '' : '用户过去更常选择的表达类型：${request.preferredTypes.join(' / ')}\n'}'
              '${request.rejectedCandidates.isEmpty ? '' : '本轮及相似语境中不合适的候选：${request.rejectedCandidates.join(' / ')}\n'}'
              '请紧扣该用户最后一句，返回四个意图不同的候选，只返回 JSON 数组。',
        },
      ],
    }, cancellationToken: cancellationToken);
    const allowedTypes = {'继续', '补充', '询问', '等待'};
    final seenTypes = <String>{};
    final seenContent = <String>{};
    final rejected = request.rejectedCandidates
        .map(LocationRecommendationController.normalizeText)
        .toSet();
    final options = <String>[];
    for (final value in _parseStringList(_messageContent(response))) {
      final option = _normalizeOption(value);
      final separator = option.indexOf(RegExp(r'[：:]'));
      if (separator <= 0) continue;
      final type = option.substring(0, separator).trim();
      final content = option.substring(separator + 1).trim();
      final normalizedContent =
          LocationRecommendationController.normalizeText(content);
      if (!allowedTypes.contains(type) ||
          content.isEmpty ||
          content.length > 14 ||
          rejected.contains(
            LocationRecommendationController.normalizeText(option),
          ) ||
          rejected.contains(normalizedContent) ||
          !seenTypes.add(type) ||
          !seenContent.add(normalizedContent)) {
        continue;
      }
      options.add('$type：$content');
    }
    yuqiaoDebugLog('[Qwen conversation] returned=${options.join('/')}');
    return options;
  }

  Future<String?> suggestStuckAssistSentence(
    ConversationContextRequest request, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.1,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的卡顿辅助模块。'
              '用户可能在表达中途卡住，请根据已经明确说出的内容整理一条可直接播报的简短句子。'
              '不能添加对话中没有出现的对象、意图、地点、症状或事实，不能替用户做决定。'
              '如果上下文不足以恢复具体意图，使用安全的沟通句，例如“请等一下，我还在想”。'
              '句子不超过 24 个汉字，只返回包含一个字符串的 JSON 数组。',
        },
        {
          'role': 'user',
          'content': '当前时间：${request.timeText}\n'
              '当前地点类型：${request.locationText}\n'
              '疑似卡顿片段：${request.currentPartial}\n'
              '最近对话：\n${request.transcript}\n\n'
              '近期表达：${request.recentExpressions.join(' / ')}\n'
              '个人词汇：${request.personalWords.join(' / ')}\n'
              '请整理一条需要用户确认后才能播报的候选句。',
        },
      ],
    }, cancellationToken: cancellationToken);
    final options = _parseStringList(_messageContent(response))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item.length <= 30)
        .toList();
    return options.isEmpty ? null : options.first;
  }

  Future<_ConversationUnderstanding> _explainConversationUtterance({
    required String original,
    required String speakerLabel,
    required List<String> surroundingContext,
    required List<String> personalWords,
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final source = original.trim();
    if (source.isEmpty) throw const QwenException('转录内容为空。');
    final response = await _post({
      'model': _textModel,
      'temperature': 0.0,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症用户的语句理解辅助模块。'
              '任务是把用户主动选中的一句话拆成少量、清楚的信息，再用更简单的中文解释。'
              '必须保留原句中的人物、动作、对象、时间、地点、数字、否定和先后顺序。'
              '不得补充原句没有的事实，不得把相邻对话中的内容写进原句解释。'
              '相邻对话只能用来理解代词；无法确定代词时写入 uncertainties，不要猜。'
              '每个 parts 项必须给出 evidence，而evidence 必须是原句中连续出现的原文。'
              'label 优先使用“人物、时间、地点、先做、然后、动作、对象、要求、重点”。'
              '只返回 JSON 对象：'
              '{"original":"逐字原句","parts":[{"label":"时间","text":"简短解释","evidence":"原句片段"}],'
              '"simpleMeaning":"一句简单解释","importantNote":"最需注意的一点","uncertainties":[]}。',
        },
        {
          'role': 'user',
          'content': '选中说话者：$speakerLabel\n'
              '待解释原句：$source\n'
              '相邻对话（仅用于代词理解）：\n${surroundingContext.join('\n')}\n'
              '已确认个人词汇（仅用于识别名称）：${personalWords.join(' / ')}\n'
              '请将原句拆成 1 到 5 个信息点。',
        },
      ],
    }, cancellationToken: cancellationToken);
    final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
    if (decoded is! Map<String, dynamic> ||
        decoded['original']?.toString().trim() != source ||
        decoded['parts'] is! List) {
      throw const QwenException('理解结果格式不正确。');
    }

    final parts = <_UnderstandingPart>[];
    for (final value in decoded['parts'] as List) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final label = item['label']?.toString().trim() ?? '';
      final text = item['text']?.toString().trim() ?? '';
      final evidence = item['evidence']?.toString().trim() ?? '';
      if (label.isEmpty ||
          label.length > 8 ||
          text.isEmpty ||
          text.length > 40 ||
          evidence.isEmpty ||
          !source.contains(evidence)) {
        continue;
      }
      parts.add(
        _UnderstandingPart(label: label, text: text, evidence: evidence),
      );
      if (parts.length == 5) break;
    }
    final simpleMeaning = decoded['simpleMeaning']?.toString().trim() ?? '';
    final importantNote = decoded['importantNote']?.toString().trim() ?? '';
    final uncertainties = decoded['uncertainties'] is List
        ? (decoded['uncertainties'] as List)
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .take(3)
            .toList(growable: false)
        : const <String>[];
    if (parts.isEmpty ||
        simpleMeaning.isEmpty ||
        simpleMeaning.length > 100 ||
        importantNote.length > 60 ||
        !_understandingPreservesCriticalMeaning(source, simpleMeaning)) {
      throw const QwenException('模型未能给出可靠的简化解释。');
    }
    return _ConversationUnderstanding(
      original: source,
      parts: parts,
      simpleMeaning: simpleMeaning,
      importantNote: importantNote,
      uncertainties: uncertainties,
    );
  }

  bool _understandingPreservesCriticalMeaning(
    String original,
    String simpleMeaning,
  ) {
    final sourceDigits = RegExp(r'\d+(?:[.:]\d+)?')
        .allMatches(original)
        .map((match) => match.group(0))
        .whereType<String>()
        .toSet();
    final resultDigits = RegExp(r'\d+(?:[.:]\d+)?')
        .allMatches(simpleMeaning)
        .map((match) => match.group(0))
        .whereType<String>()
        .toSet();
    if (!sourceDigits.containsAll(resultDigits)) return false;
    final hasSourceNegation = RegExp(r'不|没|别|禁止|无需|未').hasMatch(original);
    final hasResultNegation = RegExp(r'不|没|别|禁止|无需|未').hasMatch(simpleMeaning);
    return hasSourceNegation == hasResultNegation;
  }

  Future<_SpeechRepairSuggestion?> _analyzeSpeechRepair(
    ConversationContextRequest request, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.0,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文失语症辅助沟通 App 的表达核对模块。'
              '你不是自动纠错器，只有在用户最后一句与已有对话存在强烈、可解释的语义冲突时才建议核对。'
              '不得因为句子稀有、不符合常识、包含新人名、地点、数字或症状就判定有错。'
              '地点、时间、个人词只是弱参考，不能作为唯一依据。'
              '不确定时必须返回 needsConfirmation=false。'
              '需要核对时，original 必须逐字保留用户原话；'
              'candidates 必须包含原话，再给出 1 到 3 个语义不同的可能表达，不能只换同义词。'
              '不能替用户确定意图。'
              '只返回 JSON：'
              '{"needsConfirmation":true,"original":"用户原话","reason":"简短中性原因","candidates":["用户原话","可能表达"]}。',
        },
        {
          'role': 'user',
          'content': '当前时间：${request.timeText}\n'
              '当前地点类型：${request.locationText}\n'
              '用户对应说话者：${request.userSpeakerLabel}\n'
              '待核对原话：${request.currentPartial}\n'
              '最近对话：\n${request.transcript}\n\n'
              '近期表达：${request.recentExpressions.join(' / ')}\n'
              '个人词汇：${request.personalWords.join(' / ')}\n'
              '请优先避免打扰；只有证据充分时才请用户核对。',
        },
      ],
    }, cancellationToken: cancellationToken);
    final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
    if (decoded is! Map<String, dynamic> ||
        decoded['needsConfirmation'] != true) {
      return null;
    }
    final original = request.currentPartial.trim();
    final returnedOriginal = decoded['original']?.toString().trim() ?? '';
    if (original.isEmpty || returnedOriginal != original) return null;
    final values = decoded['candidates'];
    if (values is! List) return null;
    final candidates = <String>[original];
    final seen = <String>{
      LocationRecommendationController.normalizeText(original),
    };
    for (final value in values) {
      final candidate = value?.toString().trim() ?? '';
      final normalized =
          LocationRecommendationController.normalizeText(candidate);
      if (candidate.isEmpty ||
          candidate.length > 48 ||
          normalized.isEmpty ||
          !seen.add(normalized)) {
        continue;
      }
      candidates.add(candidate);
      if (candidates.length == 4) break;
    }
    if (candidates.length < 2) return null;
    final reason = decoded['reason']?.toString().trim() ?? '';
    return _SpeechRepairSuggestion(
      original: original,
      candidates: candidates,
      reason: reason.length <= 40 ? reason : '这句话可能与前文不一致，请你来确认。',
    );
  }

  Future<List<ConversationTermCandidate>> extractConversationTerms(
    String transcript, {
    QwenCancellationToken? cancellationToken,
  }) async {
    _ensureConfigured();
    final text = transcript.trim();
    if (text.isEmpty) return const [];
    final response = await _post({
      'model': _recommendModel,
      'temperature': 0.0,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文对话中的专有词汇提取模块。'
              '只提取明确出现的人名、具体地名、机构名或高度个性化的专有称呼。'
              '不要提取“妈妈、朋友、医院、公园、今天、吃饭”等普通词。'
              'text 必须逐字来自原句，不能纠错、补全或猜测。'
              'type 只能是 person、place、organization、custom。'
              'confidence 是 0 到 1。没有明确专有词时返回空数组。'
              '只返回 JSON：{"terms":[{"text":"王阿姨","type":"person","confidence":0.95}]}。',
        },
        {
          'role': 'user',
          'content': '原句：$text',
        },
      ],
    }, cancellationToken: cancellationToken);
    final cleaned = _stripCodeFence(_messageContent(response));
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map<String, dynamic> || decoded['terms'] is! List) {
      return const [];
    }
    final seen = <String>{};
    final terms = <ConversationTermCandidate>[];
    for (final value in (decoded['terms'] as List)) {
      if (value is! Map) continue;
      final item = Map<String, dynamic>.from(value);
      final termText = item['text']?.toString().trim() ?? '';
      final normalized = normalizeConversationTerm(termText);
      final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.0;
      if (termText.length < 2 ||
          termText.length > 20 ||
          !text.contains(termText) ||
          confidence < 0.65 ||
          !seen.add(normalized)) {
        continue;
      }
      terms.add(ConversationTermCandidate(
        text: termText,
        type: normalizeConversationTermType(item['type']?.toString()),
        confidence: confidence,
      ));
      if (terms.length == 6) break;
    }
    return terms;
  }

  Future<ObjectRecognition> recognizeObject(
    Uint8List imageBytes, {
    List<PersonalObject> personalObjects = const [],
    String locationType = '未知地点',
    String timeContext = '未知时间',
  }) async {
    _ensureConfigured();
    final encoded = base64Encode(imageBytes);
    final imageContent = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': '请识别第一张图片中的所有物品并给出位置坐标。'
            '当前地点类型：$locationType。当前本地时间：$timeContext。'
            '请优先给出在这个场景和时间下自然、可立即使用的表达。',
      },
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$encoded'},
      },
    ];
    final response = await _post({
      'model': _visionModel,
      'temperature': 0.1,
      'messages': [
        {
          'role': 'system',
          'content': '你是中文 AAC 辅助沟通 App 的拍照识别模块。'
              '直接识别图片中所有可见的物品，不要求用户确认，直接告诉用户图片中有什么。'
              '每个物品给出 3 个意图明显不同的表达选项（适合失语症患者使用）。'
              '每个选项必须包含 type 和 phrase：type 是 2 到 4 个汉字的表达类型，'
              '例如“购买、饮用、使用、寻找、询问、求助”；phrase 是可以直接播报的简短表达。'
              '同一物品的三个 type 不能重复或语义近似，不能只是对同一句话换一种说法。'
              '表达选项需要结合用户当前的地点类型和时间，但不能据此虚构用户意图。'
              'category 只能从“饮食、生活用品、衣物、电子设备、钥匙证件、康复用品、其他”中选择。'
              '同时给出每个物品在图片中的大致位置（归一化坐标，范围 0-1000）。'
              'bbox 必须紧贴物品可见轮廓，不要把大片背景、桌面或相邻物品包含进去；'
              '坐标必须相对于上传图片完整画面，而不是模型自行裁剪或缩放后的局部画面。'
              '这是客观识别阶段，不提供个人物品参考，personalObjectId 必须始终返回空字符串。'
              '输出必须是 JSON 对象，格式：'
              '{"candidates":[{"objectName":"水杯","category":"饮食","visualDescription":"蓝色杯身","personalObjectId":"","bbox":[100,200,500,600],"expressionOptions":[{"type":"购买","phrase":"我想买一个水杯"},{"type":"饮用","phrase":"我想喝水"},{"type":"使用","phrase":"帮我打开杯盖"}]}]}。'
              'bbox 为 [x1, y1, x2, y2]，分别表示左上角和右下角的归一化坐标（0-1000）。',
        },
        {
          'role': 'user',
          'content': imageContent,
        },
      ],
    });
    final parsedRecognition = _parseRecognition(_messageContent(response));
    final genericRecognition = ObjectRecognition(
      candidates: parsedRecognition.candidates
          .map((candidate) => candidate.copyWith(personalObjectId: ''))
          .toList(growable: false),
    );
    if (personalObjects.isEmpty || genericRecognition.candidates.isEmpty) {
      return genericRecognition;
    }
    return _verifyPersonalObjectMatches(
      imageBytes,
      genericRecognition,
      personalObjects,
    );
  }

  Future<ObjectRecognition> refineObjectBoundingBoxes(
    Uint8List imageBytes,
    ObjectRecognition recognition,
  ) async {
    if (recognition.candidates.isEmpty) return recognition;
    final targets = [
      for (var index = 0; index < recognition.candidates.length; index++)
        {
          'candidateIndex': index,
          'objectName': recognition.candidates[index].objectName,
          'roughBbox': recognition.candidates[index].bbox,
        },
    ];
    try {
      final response = await _post({
        'model': _visionModel,
        'temperature': 0.0,
        'messages': [
          {
            'role': 'system',
            'content': '你是视觉定位模块，只精修已识别物品的位置，不重新命名物品，不生成表达。'
                '对每个目标寻找其在图片中实际可见的完整轮廓，bbox 必须紧贴物品，不包含桌面、墙面或相邻物品。'
                '坐标统一使用相对于整张上传图片的 0-1000 归一化坐标，不能使用裁剪图、百分比或像素坐标。'
                '如果目标在图片中不可见或无法可靠定位，就省略该目标，不能猜测。'
                '只返回 JSON：{"boxes":[{"candidateIndex":0,"bbox":[x1,y1,x2,y2],"confidence":0.95}]}。',
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '需要精修的目标：${jsonEncode(targets)}',
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
                },
              },
            ],
          },
        ],
      });
      final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
      if (decoded is! Map<String, dynamic> || decoded['boxes'] is! List) {
        return recognition;
      }
      final refined = <int, List<double>>{};
      for (final raw in decoded['boxes'] as List) {
        if (raw is! Map) continue;
        final box = Map<String, dynamic>.from(raw);
        final index = (box['candidateIndex'] as num?)?.toInt() ?? -1;
        final confidence = (box['confidence'] as num?)?.toDouble() ?? 0;
        final bbox = normalizeModelBoundingBox(box['bbox']);
        if (index < 0 ||
            index >= recognition.candidates.length ||
            confidence < 0.72 ||
            bbox == null) {
          continue;
        }
        final area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]);
        if (area < 400 || area > 950000) continue;
        refined[index] = bbox;
        yuqiaoDebugLog(
          '[Camera bbox refine] index=$index confidence=$confidence bbox=$bbox',
        );
      }
      if (refined.isEmpty) return recognition;
      return ObjectRecognition(
        candidates: [
          for (var index = 0; index < recognition.candidates.length; index++)
            refined[index] == null
                ? recognition.candidates[index]
                : recognition.candidates[index].copyWith(
                    bbox: refined[index],
                  ),
        ],
      );
    } catch (error) {
      yuqiaoDebugLog('[Camera bbox refine] skipped: $error');
      return recognition;
    }
  }

  Future<ObjectRecognition> _verifyPersonalObjectMatches(
    Uint8List imageBytes,
    ObjectRecognition recognition,
    List<PersonalObject> personalObjects,
  ) async {
    final references = <PersonalObject>[];
    for (final object in personalObjects) {
      if (references.length >= 3) break;
      if (object.referenceImagePath.isEmpty ||
          !recognition.candidates.any(
            (candidate) => PersonalObjectMatchPolicy.kindsCompatible(
              candidate.objectName,
              object.displayName,
            ),
          )) {
        continue;
      }
      if (await File(object.referenceImagePath).exists()) {
        references.add(object);
      }
    }
    if (references.isEmpty) return recognition;

    final candidateSummary = [
      for (var index = 0; index < recognition.candidates.length; index++)
        {
          'candidateIndex': index,
          'objectName': recognition.candidates[index].objectName,
          'category': recognition.candidates[index].category,
          'visualDescription': recognition.candidates[index].visualDescription,
          'bbox': recognition.candidates[index].bbox,
        },
    ];
    final content = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': '第一张图片是本次拍摄图。第一阶段客观识别结果：'
            '${jsonEncode(candidateSummary)}。接下来是可能相关的个人物品参考图。',
      },
      {
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
        },
      },
    ];
    for (final object in references) {
      final bytes = await File(object.referenceImagePath).readAsBytes();
      content
        ..add({
          'type': 'text',
          'text': '参考物品：ID=${object.id}；名称=${object.displayName}；'
              '类型=${object.category}；用户记录的独特外观=${object.visualDescription}。',
        })
        ..add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/jpeg;base64,${base64Encode(bytes)}',
          },
        });
    }

    try {
      final response = await _post({
        'model': _visionModel,
        'temperature': 0.0,
        'messages': [
          {
            'role': 'system',
            'content': '你是个人物品同一实体核验器，不负责重新识别物品。'
                '只有能确认本次拍摄物体与参考图是同一件物理实体时才能匹配；同品类、同款、同颜色、同品牌都不足以证明是同一件。'
                '至少需要两条相互独立的外观证据，其中至少一条必须是贴纸、独特图案、划痕、磨损、缺口、挂件、标签、污渍、凹痕或用户记录的独特组合特征。'
                '角度、光照、背景不同不能当作匹配证据。有任何明显冲突或物体在本次图片中看不清时必须拒绝。'
                '不要因为系统提供了参考图就倾向匹配。宁可漏认，也不能误认。'
                '只返回 JSON：{"matches":[{"candidateIndex":0,"personalObjectId":"ID","samePhysicalObject":true,"confidence":0.98,"matchingEvidence":["证据1","证据2"],"conflictingEvidence":[]}]}。'
                '没有达到标准时返回 {"matches":[]}。',
          },
          {'role': 'user', 'content': content},
        ],
      });
      final decoded = jsonDecode(_stripCodeFence(_messageContent(response)));
      if (decoded is! Map<String, dynamic> || decoded['matches'] is! List) {
        return recognition;
      }
      final referenceById = {for (final item in references) item.id: item};
      final accepted = <int, PersonalObject>{};
      for (final raw in decoded['matches'] as List) {
        if (raw is! Map) continue;
        final match = Map<String, dynamic>.from(raw);
        final index = (match['candidateIndex'] as num?)?.toInt() ?? -1;
        final id = match['personalObjectId']?.toString() ?? '';
        final confidence = (match['confidence'] as num?)?.toDouble() ?? 0;
        final evidence = (match['matchingEvidence'] as List? ?? const [])
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final conflicts = (match['conflictingEvidence'] as List? ?? const [])
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        final object = referenceById[id];
        final validIndex = index >= 0 && index < recognition.candidates.length;
        final acceptedMatch = object != null &&
            validIndex &&
            PersonalObjectMatchPolicy.kindsCompatible(
              recognition.candidates[index].objectName,
              object.displayName,
            ) &&
            PersonalObjectMatchPolicy.acceptsMatch(
              samePhysicalObject: match['samePhysicalObject'] == true,
              confidence: confidence,
              matchingEvidence: evidence,
              conflictingEvidence: conflicts,
            );
        yuqiaoDebugLog(
          '[Personal object match] candidate=$index id=$id '
          'confidence=$confidence evidence=${evidence.length} '
          'conflicts=${conflicts.length} accepted=$acceptedMatch',
        );
        if (acceptedMatch) accepted[index] = object;
      }
      return ObjectRecognition(
        candidates: [
          for (var index = 0; index < recognition.candidates.length; index++)
            _applyPersonalObjectMatch(
              recognition.candidates[index],
              accepted[index],
            ),
        ],
      );
    } catch (error) {
      yuqiaoDebugLog('[Personal object match] verification skipped: $error');
      return recognition;
    }
  }

  ObjectCandidate _applyPersonalObjectMatch(
    ObjectCandidate candidate,
    PersonalObject? object,
  ) {
    if (object == null) return candidate.copyWith(personalObjectId: '');
    final options = <ObjectExpressionOption>[];
    final seen = <String>{};
    for (final phrase in [
      ...object.commonExpressions,
      ...candidate.expressions,
    ]) {
      final clean = phrase.trim();
      final normalized = LocationRecommendationController.normalizeText(clean);
      if (clean.isEmpty || !seen.add(normalized)) continue;
      options.add(ObjectExpressionOption(
        type: _inferExpressionType(clean),
        phrase: clean,
      ));
      if (options.length == 3) break;
    }
    return candidate.copyWith(
      objectName: object.displayName,
      personalObjectId: object.id,
      expressions: options.map((item) => item.phrase).toList(),
      expressionOptions: options,
    );
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body, {
    QwenCancellationToken? cancellationToken,
  }) async {
    final uri = Uri.parse(_baseUrl);
    yuqiaoDebugLog('[Qwen API] POST $uri model=${body['model']}');
    const retryableStatusCodes = {429, 500, 502, 503, 504};
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      cancellationToken?.throwIfCancelled();
      try {
        final request = http.AbortableRequest(
          'POST',
          uri,
          abortTrigger: cancellationToken?.whenCancelled,
        )
          ..headers.addAll({
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode(body);
        final streamed =
            await _client.send(request).timeout(const Duration(seconds: 35));
        final result = await http.Response.fromStream(streamed);
        cancellationToken?.throwIfCancelled();
        if (result.statusCode >= 200 && result.statusCode < 300) {
          yuqiaoDebugLog('[Qwen API] success ${result.statusCode}');
          final decoded = jsonDecode(utf8.decode(result.bodyBytes));
          if (decoded is! Map<String, dynamic>) {
            throw const QwenException('Qwen API 返回格式不是 JSON 对象。');
          }
          return decoded;
        }
        yuqiaoDebugLog('[Qwen API] error ${result.statusCode}: ${result.body}');
        if (!retryableStatusCodes.contains(result.statusCode) || attempt == 2) {
          throw QwenException(
            'Qwen API 请求失败：${result.statusCode} ${result.body}',
          );
        }
        lastError = QwenException('Qwen API 暂时不可用：${result.statusCode}');
      } on QwenCancelledException {
        rethrow;
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt == 2) rethrow;
      } on SocketException catch (error) {
        lastError = error;
        if (attempt == 2) rethrow;
      } on http.ClientException catch (error) {
        if (cancellationToken?.isCancelled == true) {
          throw const QwenCancelledException();
        }
        lastError = error;
        if (attempt == 2) rethrow;
      }
      cancellationToken?.throwIfCancelled();
      await Future<void>.delayed(Duration(milliseconds: 650 * attempt));
    }
    throw QwenException('Qwen API 请求失败：$lastError');
  }

  String _messageContent(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const QwenException('Qwen API 未返回候选结果。');
    }
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) {
      throw const QwenException('Qwen API 候选格式异常。');
    }
    final message = choice['message'];
    if (message is! Map<String, dynamic>) {
      throw const QwenException('Qwen API 消息格式异常。');
    }
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    throw const QwenException('Qwen API 返回内容为空。');
  }

  List<String> _parseStringList(String content) {
    final cleaned = _stripCodeFence(content);
    final decoded = jsonDecode(cleaned);
    if (decoded is! List) {
      throw const QwenException('候选句返回格式错误，应为 JSON 数组。');
    }
    final sentences = decoded
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (sentences.isEmpty) {
      throw const QwenException('未生成可用候选句。');
    }
    return sentences;
  }

  ObjectRecognition _parseRecognition(String content) {
    final cleaned = _stripCodeFence(content);
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map<String, dynamic>) {
      throw const QwenException('识别结果返回格式错误，应为 JSON 对象。');
    }
    final candidates = decoded['candidates'];
    if (candidates is List) {
      final parsedCandidates = candidates
          .whereType<Map<String, dynamic>>()
          .map(_parseObjectCandidate)
          .where((candidate) => candidate.objectName.isNotEmpty)
          .take(4)
          .toList();
      if (parsedCandidates.isNotEmpty) {
        return ObjectRecognition(candidates: parsedCandidates);
      }
    }

    // Backward compatible fallback for occasional single-result model output.
    final objectName = decoded['objectName'];
    final expressions = decoded['expressions'];
    if (objectName is! String ||
        objectName.trim().isEmpty ||
        expressions is! List) {
      throw const QwenException('识别结果缺少物品名称或表达候选。');
    }
    final expressionList = expressions
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(4)
        .toList();
    if (expressionList.isEmpty) {
      throw const QwenException('识别结果没有可用表达候选。');
    }
    return ObjectRecognition(
      candidates: [
        ObjectCandidate(
          objectName: objectName.trim(),
          confidence: '高',
          expressions: expressionList,
          expressionOptions: expressionList
              .map(
                (phrase) => ObjectExpressionOption(
                  type: _inferExpressionType(phrase),
                  phrase: phrase,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  ObjectCandidate _parseObjectCandidate(Map<String, dynamic> json) {
    final objectName = json['objectName'];
    final rawExpressionOptions = json['expressionOptions'];
    final expressionOptions = _parseExpressionOptions(rawExpressionOptions);
    final expressions = json['expressions'];
    final legacyExpressionList = expressions is List
        ? expressions
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .take(3)
            .toList()
        : <String>[];
    final effectiveOptions = expressionOptions.isNotEmpty
        ? expressionOptions
        : legacyExpressionList
            .map(
              (phrase) => ObjectExpressionOption(
                type: _inferExpressionType(phrase),
                phrase: phrase,
              ),
            )
            .toList();
    final expressionList = effectiveOptions
        .map((item) => item.phrase)
        .where((item) => item.isNotEmpty)
        .toList();
    final rawBbox = json['bbox'];
    final bbox = normalizeModelBoundingBox(rawBbox);
    yuqiaoDebugLog(
        '[Camera bbox] object=${objectName is String ? objectName : ''} '
        'raw=$rawBbox normalized=$bbox');
    return ObjectCandidate(
      objectName: objectName is String ? objectName.trim() : '',
      confidence:
          json['confidence'] is String ? json['confidence'] as String : '',
      category: json['category'] is String ? json['category'] as String : '',
      visualDescription: json['visualDescription'] is String
          ? json['visualDescription'] as String
          : '',
      personalObjectId: json['personalObjectId'] is String
          ? json['personalObjectId'] as String
          : '',
      expressionOptions: effectiveOptions,
      expressions:
          expressionList.isEmpty ? const ['我想要这个', '请帮我拿一下'] : expressionList,
      bbox: bbox,
    );
  }

  String _inferExpressionType(String phrase) {
    if (phrase.contains('买') || phrase.contains('多少钱')) return '购买';
    if (phrase.contains('喝') || phrase.contains('吃')) return '饮用';
    if (phrase.contains('找') || phrase.contains('哪里')) return '寻找';
    if (phrase.contains('拿') || phrase.contains('打开') || phrase.contains('用')) {
      return '使用';
    }
    if (phrase.contains('帮') || phrase.contains('请')) return '求助';
    return '表达';
  }

  List<ObjectExpressionOption> _parseExpressionOptions(dynamic raw) {
    if (raw is! List) return const [];
    final options = <ObjectExpressionOption>[];
    final seenTypes = <String>{};
    for (final value in raw.whereType<Map<String, dynamic>>()) {
      final parsed = ObjectExpressionOption.fromJson(value);
      if (parsed.phrase.isEmpty) continue;
      final type = parsed.type.isEmpty
          ? _inferExpressionType(parsed.phrase)
          : parsed.type;
      final normalizedType = type.replaceAll(RegExp(r'\s+'), '');
      if (!seenTypes.add(normalizedType)) continue;
      options.add(ObjectExpressionOption(type: type, phrase: parsed.phrase));
      if (options.length == 3) break;
    }
    return options;
  }

  String _stripCodeFence(String value) {
    return value
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();
  }

  String _normalizeOption(String value) {
    return value
        .replaceAll(RegExp(r'^[\s\d.、\-]+'), '')
        .replaceAll(RegExp(r'[。！？,.，；;：:]+$'), '')
        .trim();
  }

  void _ensureConfigured() {
    if (_apiKey.isEmpty) {
      throw const QwenException(
        '缺少 QWEN_API_KEY。请使用 --dart-define=QWEN_API_KEY=你的APIKey 启动应用。',
      );
    }
  }
}

class LocalStore implements LocationDataStore {
  static const String _recentKey = 'recent_expressions';
  static const String _favoriteKey = 'favorite_expressions';
  static const String _vocabularyKey = 'vocabulary_entries';
  static const String _vocabularySeedVersionKey = 'vocabulary_seed_version';
  static const String _expressionPreferenceKey = 'expression_preference_v2';
  static const String _supportProfileKey = 'support_profile_v1';
  static const String _autoStuckDetectionKey = 'auto_stuck_detection_enabled';
  static const String _locationEnabledKey = 'location_recommendation_enabled';
  static const String _locationDataKey = 'location_recommendation_data';

  Future<List<String>> loadRecentExpressions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentKey) ?? const [];
  }

  Future<List<String>> loadFavoriteExpressions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoriteKey) ?? const [];
  }

  Future<List<VocabularyEntry>> loadVocabularyEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_vocabularyKey) ?? const [];
    return raw
        .map((item) {
          try {
            final decoded = jsonDecode(item);
            if (decoded is Map<String, dynamic>) {
              return VocabularyEntry.fromJson(decoded);
            }
          } catch (_) {
            return null;
          }
          return null;
        })
        .whereType<VocabularyEntry>()
        .toList();
  }

  Future<int> loadVocabularySeedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_vocabularySeedVersionKey) ?? 0;
  }

  Future<void> addRecentExpression(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_recentKey) ?? const [];
    final updated =
        [text, ...existing.where((item) => item != text)].take(12).toList();
    await prefs.setStringList(_recentKey, updated);
  }

  Future<void> addFavoriteExpression(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_favoriteKey) ?? const [];
    final updated =
        [text, ...existing.where((item) => item != text)].take(20).toList();
    await prefs.setStringList(_favoriteKey, updated);
  }

  Future<void> saveVocabularyEntries(List<VocabularyEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = entries.map((entry) => jsonEncode(entry.toJson())).toList();
    await prefs.setStringList(_vocabularyKey, encoded);
  }

  Future<void> saveVocabularySeedVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_vocabularySeedVersionKey, version);
  }

  Future<ExpressionPreference> loadExpressionPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_expressionPreferenceKey);
    if (raw == null || raw.isEmpty) return const ExpressionPreference();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ExpressionPreference.fromJson(decoded);
      }
    } catch (_) {
      return const ExpressionPreference();
    }
    return const ExpressionPreference();
  }

  Future<void> saveExpressionPreference(ExpressionPreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _expressionPreferenceKey,
      jsonEncode(preference.toJson()),
    );
  }

  Future<SupportProfile> loadSupportProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_supportProfileKey);
    if (raw == null || raw.isEmpty) return const SupportProfile();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SupportProfile.fromJson(decoded);
      }
    } catch (_) {
      return const SupportProfile();
    }
    return const SupportProfile();
  }

  Future<void> saveSupportProfile(SupportProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_supportProfileKey, jsonEncode(profile.toJson()));
  }

  Future<bool> loadAutoStuckDetectionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoStuckDetectionKey) ?? false;
  }

  Future<void> saveAutoStuckDetectionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStuckDetectionKey, enabled);
  }

  @override
  Future<bool> loadLocationRecommendationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_locationEnabledKey) ?? false;
  }

  @override
  Future<void> saveLocationRecommendationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationEnabledKey, enabled);
  }

  @override
  Future<String?> loadLocationRecommendationData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_locationDataKey);
  }

  @override
  Future<void> saveLocationRecommendationData(String data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationDataKey, data);
  }

  @override
  Future<void> clearLocationRecommendationData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_locationDataKey);
  }
}

class VocabularyEntry {
  const VocabularyEntry({
    required this.id,
    required this.category,
    required this.text,
    this.note = '',
  });

  final String id;
  final String category;
  final String text;
  final String note;

  VocabularyEntry copyWith({
    String? id,
    String? category,
    String? text,
    String? note,
  }) {
    return VocabularyEntry(
      id: id ?? this.id,
      category: category ?? this.category,
      text: text ?? this.text,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'text': text,
      'note': note,
    };
  }

  factory VocabularyEntry.fromJson(Map<String, dynamic> json) {
    final text = json['text'];
    final category = json['category'];
    if (text is! String || category is! String) {
      throw const FormatException('Invalid vocabulary entry');
    }
    return VocabularyEntry(
      id: json['id'] is String ? json['id'] as String : text,
      category: category,
      text: text,
      note: json['note'] is String ? json['note'] as String : '',
    );
  }
}

class VocabularyDefaults {
  static const version = 3;

  static const categories = ['人物', '饮食', '地点', '活动', '物品', '感受', '常用句'];

  static const entries = [
    VocabularyEntry(id: 'person_mom', category: '人物', text: '妈妈'),
    VocabularyEntry(id: 'person_daughter', category: '人物', text: '女儿'),
    VocabularyEntry(id: 'person_friend', category: '人物', text: '朋友'),
    VocabularyEntry(id: 'person_dad', category: '人物', text: '爸爸'),
    VocabularyEntry(id: 'person_son', category: '人物', text: '儿子'),
    VocabularyEntry(id: 'person_spouse', category: '人物', text: '爱人'),
    VocabularyEntry(id: 'person_husband', category: '人物', text: '丈夫'),
    VocabularyEntry(id: 'person_wife', category: '人物', text: '妻子'),
    VocabularyEntry(id: 'person_grandpa', category: '人物', text: '爷爷'),
    VocabularyEntry(id: 'person_grandma', category: '人物', text: '奶奶'),
    VocabularyEntry(id: 'person_maternal_grandpa', category: '人物', text: '外公'),
    VocabularyEntry(id: 'person_maternal_grandma', category: '人物', text: '外婆'),
    VocabularyEntry(id: 'person_elder_brother', category: '人物', text: '哥哥'),
    VocabularyEntry(id: 'person_younger_brother', category: '人物', text: '弟弟'),
    VocabularyEntry(id: 'person_elder_sister', category: '人物', text: '姐姐'),
    VocabularyEntry(id: 'person_younger_sister', category: '人物', text: '妹妹'),
    VocabularyEntry(id: 'person_doctor', category: '人物', text: '医生'),
    VocabularyEntry(id: 'person_nurse', category: '人物', text: '护士'),
    VocabularyEntry(id: 'food_water', category: '饮食', text: '水'),
    VocabularyEntry(id: 'food_tea', category: '饮食', text: '茶'),
    VocabularyEntry(id: 'food_coffee', category: '饮食', text: '咖啡'),
    VocabularyEntry(id: 'food_fruit', category: '饮食', text: '水果'),
    VocabularyEntry(id: 'food_rice', category: '饮食', text: '米饭'),
    VocabularyEntry(id: 'food_porridge', category: '饮食', text: '粥'),
    VocabularyEntry(id: 'food_noodles', category: '饮食', text: '面条'),
    VocabularyEntry(id: 'food_steamed_bun', category: '饮食', text: '馒头'),
    VocabularyEntry(id: 'food_bread', category: '饮食', text: '面包'),
    VocabularyEntry(id: 'food_egg', category: '饮食', text: '鸡蛋'),
    VocabularyEntry(id: 'food_milk', category: '饮食', text: '牛奶'),
    VocabularyEntry(id: 'food_yogurt', category: '饮食', text: '酸奶'),
    VocabularyEntry(id: 'food_apple', category: '饮食', text: '苹果'),
    VocabularyEntry(id: 'food_banana', category: '饮食', text: '香蕉'),
    VocabularyEntry(id: 'food_vegetables', category: '饮食', text: '青菜'),
    VocabularyEntry(id: 'food_soup', category: '饮食', text: '汤'),
    VocabularyEntry(id: 'food_chicken', category: '饮食', text: '鸡肉'),
    VocabularyEntry(id: 'food_fish', category: '饮食', text: '鱼'),
    VocabularyEntry(id: 'food_beef', category: '饮食', text: '牛肉'),
    VocabularyEntry(id: 'food_warm_water', category: '饮食', text: '温水'),
    VocabularyEntry(id: 'food_juice', category: '饮食', text: '果汁'),
    VocabularyEntry(id: 'food_soy_milk', category: '饮食', text: '豆浆'),
    VocabularyEntry(id: 'food_dumplings', category: '饮食', text: '饺子'),
    VocabularyEntry(id: 'food_snack', category: '饮食', text: '点心'),
    VocabularyEntry(id: 'place_home', category: '地点', text: '家里'),
    VocabularyEntry(id: 'place_park', category: '地点', text: '公园'),
    VocabularyEntry(id: 'place_downstairs', category: '地点', text: '楼下'),
    VocabularyEntry(id: 'place_hospital', category: '地点', text: '医院'),
    VocabularyEntry(id: 'place_ward', category: '地点', text: '病房'),
    VocabularyEntry(id: 'place_clinic', category: '地点', text: '门诊'),
    VocabularyEntry(id: 'place_restroom', category: '地点', text: '卫生间'),
    VocabularyEntry(id: 'place_bedroom', category: '地点', text: '卧室'),
    VocabularyEntry(id: 'place_living_room', category: '地点', text: '客厅'),
    VocabularyEntry(id: 'place_kitchen', category: '地点', text: '厨房'),
    VocabularyEntry(id: 'place_balcony', category: '地点', text: '阳台'),
    VocabularyEntry(id: 'place_elevator', category: '地点', text: '电梯'),
    VocabularyEntry(id: 'place_pharmacy', category: '地点', text: '药房'),
    VocabularyEntry(id: 'place_supermarket', category: '地点', text: '超市'),
    VocabularyEntry(id: 'place_bus_stop', category: '地点', text: '公交站'),
    VocabularyEntry(id: 'place_subway_station', category: '地点', text: '地铁站'),
    VocabularyEntry(id: 'place_dining_room', category: '地点', text: '餐厅'),
    VocabularyEntry(id: 'place_rehab_room', category: '地点', text: '康复室'),
    VocabularyEntry(id: 'activity_walk', category: '活动', text: '散步'),
    VocabularyEntry(id: 'activity_rest', category: '活动', text: '休息'),
    VocabularyEntry(id: 'activity_tv', category: '活动', text: '看电视'),
    VocabularyEntry(id: 'activity_eat', category: '活动', text: '吃饭'),
    VocabularyEntry(id: 'activity_drink', category: '活动', text: '喝水'),
    VocabularyEntry(id: 'activity_take_medicine', category: '活动', text: '吃药'),
    VocabularyEntry(id: 'activity_go_toilet', category: '活动', text: '上厕所'),
    VocabularyEntry(id: 'activity_sleep', category: '活动', text: '睡觉'),
    VocabularyEntry(id: 'activity_sit_up', category: '活动', text: '坐起来'),
    VocabularyEntry(id: 'activity_lie_down', category: '活动', text: '躺下'),
    VocabularyEntry(id: 'activity_stand_up', category: '活动', text: '站起来'),
    VocabularyEntry(id: 'activity_wash_face', category: '活动', text: '洗脸'),
    VocabularyEntry(id: 'activity_brush_teeth', category: '活动', text: '刷牙'),
    VocabularyEntry(id: 'activity_shower', category: '活动', text: '洗澡'),
    VocabularyEntry(id: 'activity_change_clothes', category: '活动', text: '换衣服'),
    VocabularyEntry(id: 'activity_call_phone', category: '活动', text: '打电话'),
    VocabularyEntry(id: 'activity_listen_music', category: '活动', text: '听音乐'),
    VocabularyEntry(id: 'activity_exercise', category: '活动', text: '训练'),
    VocabularyEntry(id: 'item_phone', category: '物品', text: '手机'),
    VocabularyEntry(id: 'item_keys', category: '物品', text: '钥匙'),
    VocabularyEntry(id: 'item_glasses', category: '物品', text: '眼镜'),
    VocabularyEntry(id: 'item_cup', category: '物品', text: '杯子'),
    VocabularyEntry(id: 'item_bottle', category: '物品', text: '水杯'),
    VocabularyEntry(id: 'item_bowl', category: '物品', text: '碗'),
    VocabularyEntry(id: 'item_chopsticks', category: '物品', text: '筷子'),
    VocabularyEntry(id: 'item_spoon', category: '物品', text: '勺子'),
    VocabularyEntry(id: 'item_towel', category: '物品', text: '毛巾'),
    VocabularyEntry(id: 'item_tissue', category: '物品', text: '纸巾'),
    VocabularyEntry(id: 'item_mask', category: '物品', text: '口罩'),
    VocabularyEntry(id: 'item_charger', category: '物品', text: '充电器'),
    VocabularyEntry(id: 'item_remote', category: '物品', text: '遥控器'),
    VocabularyEntry(id: 'item_wheelchair', category: '物品', text: '轮椅'),
    VocabularyEntry(id: 'item_cane', category: '物品', text: '拐杖'),
    VocabularyEntry(id: 'item_blanket', category: '物品', text: '毯子'),
    VocabularyEntry(id: 'item_pillow', category: '物品', text: '枕头'),
    VocabularyEntry(id: 'item_medication', category: '物品', text: '药'),
    VocabularyEntry(id: 'feeling_tired', category: '感受', text: '有点累'),
    VocabularyEntry(id: 'feeling_happy', category: '感受', text: '挺好的'),
    VocabularyEntry(id: 'feeling_pain', category: '感受', text: '疼'),
    VocabularyEntry(id: 'feeling_dizzy', category: '感受', text: '头晕'),
    VocabularyEntry(id: 'feeling_thirsty', category: '感受', text: '口渴'),
    VocabularyEntry(id: 'feeling_hungry', category: '感受', text: '饿了'),
    VocabularyEntry(id: 'feeling_cold', category: '感受', text: '冷'),
    VocabularyEntry(id: 'feeling_hot', category: '感受', text: '热'),
    VocabularyEntry(id: 'feeling_anxious', category: '感受', text: '有点着急'),
    VocabularyEntry(id: 'feeling_scared', category: '感受', text: '有点害怕'),
    VocabularyEntry(id: 'feeling_uncomfortable', category: '感受', text: '不舒服'),
    VocabularyEntry(id: 'feeling_better', category: '感受', text: '好多了'),
    VocabularyEntry(id: 'phrase_again', category: '常用句', text: '请再说一遍'),
    VocabularyEntry(id: 'phrase_slow', category: '常用句', text: '你慢一点说'),
    VocabularyEntry(id: 'phrase_wait', category: '常用句', text: '等我一下'),
    VocabularyEntry(id: 'phrase_need_help', category: '常用句', text: '我需要帮忙'),
    VocabularyEntry(id: 'phrase_call_family', category: '常用句', text: '帮我联系家人'),
    VocabularyEntry(id: 'phrase_call_doctor', category: '常用句', text: '我想叫医生'),
    VocabularyEntry(id: 'phrase_call_nurse', category: '常用句', text: '我想叫护士'),
    VocabularyEntry(id: 'phrase_go_restroom', category: '常用句', text: '我想去卫生间'),
    VocabularyEntry(id: 'phrase_drink_water', category: '常用句', text: '我想喝水'),
    VocabularyEntry(id: 'phrase_pain_here', category: '常用句', text: '这里疼'),
    VocabularyEntry(
        id: 'phrase_explain_again', category: '常用句', text: '请你再解释一下'),
    VocabularyEntry(id: 'phrase_write_down', category: '常用句', text: '请帮我写下来'),
    VocabularyEntry(id: 'phrase_thank_you', category: '常用句', text: '谢谢你'),
    VocabularyEntry(id: 'person_rehab_therapist', category: '人物', text: '康复师'),
    VocabularyEntry(id: 'person_caregiver', category: '人物', text: '护工'),
    VocabularyEntry(id: 'person_teacher', category: '人物', text: '老师'),
    VocabularyEntry(id: 'person_classmate', category: '人物', text: '同学'),
    VocabularyEntry(id: 'person_neighbor', category: '人物', text: '邻居'),
    VocabularyEntry(id: 'person_driver', category: '人物', text: '司机'),
    VocabularyEntry(id: 'person_pharmacist', category: '人物', text: '药师'),
    VocabularyEntry(id: 'person_security_guard', category: '人物', text: '保安'),
    VocabularyEntry(id: 'person_volunteer', category: '人物', text: '志愿者'),
    VocabularyEntry(id: 'person_receptionist', category: '人物', text: '前台'),
    VocabularyEntry(id: 'person_grandson', category: '人物', text: '孙子'),
    VocabularyEntry(id: 'person_granddaughter', category: '人物', text: '孙女'),
    VocabularyEntry(id: 'person_uncle', category: '人物', text: '叔叔'),
    VocabularyEntry(id: 'person_aunt', category: '人物', text: '阿姨'),
    VocabularyEntry(id: 'person_colleague', category: '人物', text: '同事'),
    VocabularyEntry(id: 'food_sweet_potato', category: '饮食', text: '红薯'),
    VocabularyEntry(id: 'food_potato', category: '饮食', text: '土豆'),
    VocabularyEntry(id: 'food_pumpkin', category: '饮食', text: '南瓜'),
    VocabularyEntry(id: 'food_tofu', category: '饮食', text: '豆腐'),
    VocabularyEntry(id: 'food_tomato', category: '饮食', text: '西红柿'),
    VocabularyEntry(id: 'food_cucumber', category: '饮食', text: '黄瓜'),
    VocabularyEntry(id: 'food_carrot', category: '饮食', text: '胡萝卜'),
    VocabularyEntry(id: 'food_corn', category: '饮食', text: '玉米'),
    VocabularyEntry(id: 'food_wonton', category: '饮食', text: '馄饨'),
    VocabularyEntry(id: 'food_baozi', category: '饮食', text: '包子'),
    VocabularyEntry(id: 'food_flower_roll', category: '饮食', text: '花卷'),
    VocabularyEntry(id: 'food_cake', category: '饮食', text: '蛋糕'),
    VocabularyEntry(id: 'food_biscuit', category: '饮食', text: '饼干'),
    VocabularyEntry(id: 'food_salt', category: '饮食', text: '盐'),
    VocabularyEntry(id: 'food_sugar', category: '饮食', text: '糖'),
    VocabularyEntry(id: 'place_consulting_room', category: '地点', text: '诊室'),
    VocabularyEntry(id: 'place_exam_room', category: '地点', text: '检查室'),
    VocabularyEntry(id: 'place_infusion_room', category: '地点', text: '输液室'),
    VocabularyEntry(id: 'place_nurse_station', category: '地点', text: '护士站'),
    VocabularyEntry(id: 'place_waiting_area', category: '地点', text: '候诊区'),
    VocabularyEntry(id: 'place_garden', category: '地点', text: '花园'),
    VocabularyEntry(id: 'place_community', category: '地点', text: '小区'),
    VocabularyEntry(id: 'place_bank', category: '地点', text: '银行'),
    VocabularyEntry(id: 'place_station', category: '地点', text: '车站'),
    VocabularyEntry(id: 'place_school', category: '地点', text: '学校'),
    VocabularyEntry(id: 'place_study_room', category: '地点', text: '书房'),
    VocabularyEntry(id: 'place_corridor', category: '地点', text: '走廊'),
    VocabularyEntry(id: 'place_upstairs', category: '地点', text: '楼上'),
    VocabularyEntry(id: 'place_entrance', category: '地点', text: '门口'),
    VocabularyEntry(id: 'place_parking_lot', category: '地点', text: '停车场'),
    VocabularyEntry(id: 'activity_get_up', category: '活动', text: '起床'),
    VocabularyEntry(id: 'activity_measure_bp', category: '活动', text: '量血压'),
    VocabularyEntry(
        id: 'activity_take_temperature', category: '活动', text: '测体温'),
    VocabularyEntry(id: 'activity_follow_up', category: '活动', text: '复查'),
    VocabularyEntry(id: 'activity_queue', category: '活动', text: '排队'),
    VocabularyEntry(id: 'activity_pay', category: '活动', text: '付款'),
    VocabularyEntry(id: 'activity_buy_medicine', category: '活动', text: '买药'),
    VocabularyEntry(id: 'activity_medical_exam', category: '活动', text: '做检查'),
    VocabularyEntry(
        id: 'activity_rehab_training', category: '活动', text: '康复训练'),
    VocabularyEntry(id: 'activity_write', category: '活动', text: '写字'),
    VocabularyEntry(id: 'activity_read', category: '活动', text: '读书'),
    VocabularyEntry(id: 'activity_take_photo', category: '活动', text: '拍照'),
    VocabularyEntry(id: 'activity_send_message', category: '活动', text: '发消息'),
    VocabularyEntry(id: 'activity_turn_on_light', category: '活动', text: '开灯'),
    VocabularyEntry(id: 'activity_turn_off_light', category: '活动', text: '关灯'),
    VocabularyEntry(id: 'item_bed', category: '物品', text: '床'),
    VocabularyEntry(id: 'item_chair', category: '物品', text: '椅子'),
    VocabularyEntry(id: 'item_table', category: '物品', text: '桌子'),
    VocabularyEntry(id: 'item_door', category: '物品', text: '门'),
    VocabularyEntry(id: 'item_light', category: '物品', text: '灯'),
    VocabularyEntry(id: 'item_air_conditioner', category: '物品', text: '空调'),
    VocabularyEntry(id: 'item_tv', category: '物品', text: '电视'),
    VocabularyEntry(id: 'item_rice_cooker', category: '物品', text: '电饭煲'),
    VocabularyEntry(id: 'item_thermometer', category: '物品', text: '体温计'),
    VocabularyEntry(
        id: 'item_blood_pressure_meter', category: '物品', text: '血压计'),
    VocabularyEntry(id: 'item_medical_record', category: '物品', text: '病历'),
    VocabularyEntry(
        id: 'item_medical_insurance_card', category: '物品', text: '医保卡'),
    VocabularyEntry(id: 'item_id_card', category: '物品', text: '身份证'),
    VocabularyEntry(id: 'item_wallet', category: '物品', text: '钱包'),
    VocabularyEntry(id: 'item_umbrella', category: '物品', text: '雨伞'),
    VocabularyEntry(id: 'feeling_nauseous', category: '感受', text: '想吐'),
    VocabularyEntry(id: 'feeling_sick', category: '感受', text: '恶心'),
    VocabularyEntry(id: 'feeling_chest_tight', category: '感受', text: '胸闷'),
    VocabularyEntry(id: 'feeling_short_breath', category: '感受', text: '气短'),
    VocabularyEntry(id: 'feeling_cough', category: '感受', text: '咳嗽'),
    VocabularyEntry(id: 'feeling_fever', category: '感受', text: '发烧'),
    VocabularyEntry(id: 'feeling_chills', category: '感受', text: '发冷'),
    VocabularyEntry(id: 'feeling_sweating', category: '感受', text: '出汗'),
    VocabularyEntry(id: 'feeling_insomnia', category: '感受', text: '睡不着'),
    VocabularyEntry(id: 'feeling_weak', category: '感受', text: '没力气'),
    VocabularyEntry(id: 'feeling_hand_numb', category: '感受', text: '手麻'),
    VocabularyEntry(id: 'feeling_leg_numb', category: '感受', text: '腿麻'),
    VocabularyEntry(id: 'feeling_palpitations', category: '感受', text: '心慌'),
    VocabularyEntry(id: 'feeling_blurred_vision', category: '感受', text: '眼花'),
    VocabularyEntry(id: 'feeling_stomach_unwell', category: '感受', text: '胃不舒服'),
    VocabularyEntry(id: 'phrase_cannot_hear', category: '常用句', text: '我听不清'),
    VocabularyEntry(id: 'phrase_support_me', category: '常用句', text: '请扶我一下'),
    VocabularyEntry(id: 'phrase_turn_on_light', category: '常用句', text: '请把灯打开'),
    VocabularyEntry(
        id: 'phrase_turn_off_light', category: '常用句', text: '请把灯关掉'),
    VocabularyEntry(id: 'phrase_volume_up', category: '常用句', text: '请帮我调高一点'),
    VocabularyEntry(id: 'phrase_volume_down', category: '常用句', text: '请帮我调低一点'),
    VocabularyEntry(id: 'phrase_rest_awhile', category: '常用句', text: '我想休息一会儿'),
    VocabularyEntry(id: 'phrase_sit_up', category: '常用句', text: '我想坐起来'),
    VocabularyEntry(id: 'phrase_lie_down', category: '常用句', text: '我想躺下'),
    VocabularyEntry(id: 'phrase_better_now', category: '常用句', text: '我现在好多了'),
  ];
}

class ExpressionDraft {
  const ExpressionDraft({
    required this.source,
    required this.intent,
    required this.keywords,
  });

  final String source;
  final String intent;
  final List<String> keywords;
}

class CandidateRecommendationRequest {
  const CandidateRecommendationRequest({
    required this.intent,
    required this.stepTitle,
    required this.selectedKeywords,
    required this.fallbackOptions,
    required this.personalWords,
    this.excludeOptions = const [],
    this.slotKey = 'topic',
    this.slotLabel = '内容',
    this.timeText = '',
    this.locationText = '',
    this.displayCount = 4,
    this.diversificationLevel = 0,
  });

  final String intent;
  final String stepTitle;
  final List<String> selectedKeywords;
  final List<String> fallbackOptions;
  final List<String> personalWords;
  final List<String> excludeOptions;
  final String slotKey;
  final String slotLabel;
  final String timeText;
  final String locationText;
  final int displayCount;
  final int diversificationLevel;
}

class ConversationContextRequest {
  const ConversationContextRequest({
    required this.transcript,
    required this.currentPartial,
    required this.userSpeakerLabel,
    required this.timeText,
    required this.locationText,
    required this.recentExpressions,
    required this.personalWords,
    this.preferredTypes = const [],
    this.rejectedCandidates = const [],
  });

  final String transcript;
  final String currentPartial;
  final String userSpeakerLabel;
  final String timeText;
  final String locationText;
  final List<String> recentExpressions;
  final List<String> personalWords;
  final List<String> preferredTypes;
  final List<String> rejectedCandidates;
}

class ObjectRecognition {
  const ObjectRecognition({
    required this.candidates,
  });

  final List<ObjectCandidate> candidates;
}

class ObjectExpressionOption {
  const ObjectExpressionOption({required this.type, required this.phrase});

  final String type;
  final String phrase;

  factory ObjectExpressionOption.fromJson(Map<String, dynamic> json) {
    return ObjectExpressionOption(
      type: json['type'] is String ? (json['type'] as String).trim() : '',
      phrase: json['phrase'] is String ? (json['phrase'] as String).trim() : '',
    );
  }
}

class ObjectCandidate {
  const ObjectCandidate({
    required this.objectName,
    required this.confidence,
    required this.expressions,
    this.expressionOptions = const [],
    this.category = '',
    this.visualDescription = '',
    this.personalObjectId = '',
    this.bbox,
  });

  final String objectName;
  final String confidence;
  final List<String> expressions;
  final List<ObjectExpressionOption> expressionOptions;
  final String category;
  final String visualDescription;
  final String personalObjectId;

  List<ObjectExpressionOption> get effectiveExpressionOptions {
    if (expressionOptions.isNotEmpty) return expressionOptions;
    return expressions
        .map(
          (phrase) => ObjectExpressionOption(
            type: '表达',
            phrase: phrase,
          ),
        )
        .toList();
  }

  /// 归一化坐标 [x1, y1, x2, y2]，范围 0-1000
  final List<double>? bbox;

  ObjectCandidate copyWith({
    String? objectName,
    String? confidence,
    List<String>? expressions,
    List<ObjectExpressionOption>? expressionOptions,
    String? category,
    String? visualDescription,
    String? personalObjectId,
    List<double>? bbox,
  }) {
    return ObjectCandidate(
      objectName: objectName ?? this.objectName,
      confidence: confidence ?? this.confidence,
      expressions: expressions ?? this.expressions,
      expressionOptions: expressionOptions ?? this.expressionOptions,
      category: category ?? this.category,
      visualDescription: visualDescription ?? this.visualDescription,
      personalObjectId: personalObjectId ?? this.personalObjectId,
      bbox: bbox ?? this.bbox,
    );
  }
}

class QwenException implements Exception {
  const QwenException(this.message);

  final String message;

  @override
  String toString() => message;
}

class QwenCancelledException implements Exception {
  const QwenCancelledException();

  @override
  String toString() => 'Qwen 请求已取消';
}

class AppColors {
  static const background = Color(0xFFF5F5F7);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFF3478F6);
  static const primaryLight = Color(0xFFEAF2FF);
  static const textPrimary = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF6E6E73);
  static const divider = Color(0xFFE5E5EA);
  static const danger = Color(0xFFFF3B30);
}

class AppTextStyles {
  static const title = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.15,
    color: AppColors.textPrimary,
  );
  static const subtitle = TextStyle(
    fontSize: 18,
    height: 1.35,
    color: AppColors.textSecondary,
  );
  static const sectionTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const candidate = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const confirmSentence = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.35,
    color: AppColors.textPrimary,
  );
}

class AppSpacing {
  static const double page = 20;
  static const double gap = 14;
  static const double section = 28;
}

class AppRadius {
  static const double card = 24;
  static const double button = 18;
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPop) ...[
          LiquidBackButton(
            onTap: onBack ?? () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 18),
        ],
        Text(title, style: AppTextStyles.title),
        const SizedBox(height: 8),
        Text(subtitle, style: AppTextStyles.subtitle),
      ],
    );
  }
}

class LiquidBackButton extends StatelessWidget {
  const LiquidBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '返回',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.78),
                      Colors.white.withValues(alpha: 0.44),
                      AppColors.primaryLight.withValues(alpha: 0.28),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.82),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8BA7C9).withValues(alpha: 0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 22,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppTextStyles.sectionTitle)),
        if (trailing != null)
          Text(
            trailing!,
            style:
                const TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

class BigActionCard extends StatelessWidget {
  const BigActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            IconBadge(icon: icon),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.candidate),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 16, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class CandidateGrid extends StatelessWidget {
  const CandidateGrid({
    super.key,
    required this.options,
    required this.onSelected,
    this.icons,
  });

  final List<String> options;
  final List<IconData>? icons;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: options.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.gap,
        mainAxisSpacing: AppSpacing.gap,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        return CandidateCard(
          text: options[index],
          icon: icons == null ? null : icons![index],
          imageScale: 1.0,
          styleIndex: index,
          onTap: () => onSelected(options[index]),
        );
      },
    );
  }
}

class _CandidateCardStyle {
  const _CandidateCardStyle({
    required this.background,
    required this.iconBackground,
    required this.shadow,
  });

  final Color background;
  final Color iconBackground;
  final Color shadow;
}

const List<_CandidateCardStyle> _candidateCardStyles = [
  _CandidateCardStyle(
    background: Color(0xFFFFE2C8),
    iconBackground: Color(0xFFFFF1DC),
    shadow: Color(0xFFFFB36C),
  ),
  _CandidateCardStyle(
    background: Color(0xFFDCD9FF),
    iconBackground: Color(0xFFEDD8F7),
    shadow: Color(0xFF9B91FF),
  ),
  _CandidateCardStyle(
    background: Color(0xFFC9F1E8),
    iconBackground: Color(0xFFB7E6EE),
    shadow: Color(0xFF5BCDBB),
  ),
  _CandidateCardStyle(
    background: Color(0xFFFFC9CC),
    iconBackground: Color(0xFFFFE5E6),
    shadow: Color(0xFFFF7B82),
  ),
  _CandidateCardStyle(
    background: Color(0xFFD8E5DF),
    iconBackground: Color(0xFFEAF1ED),
    shadow: Color(0xFF8FA99D),
  ),
  _CandidateCardStyle(
    background: Color(0xFFE8D8CA),
    iconBackground: Color(0xFFF4E9DE),
    shadow: Color(0xFFC2A084),
  ),
];

IconData _candidateIconForText(String text, {String? semanticGroup}) {
  final normalized = '${semanticGroup ?? ''} $text'.toLowerCase();
  bool hasAny(List<String> tokens) =>
      tokens.any((token) => normalized.contains(token));

  if (hasAny(['疼', '痛', '不舒服', '医院', '医生', '药', '发烧', '咳'])) {
    return Icons.health_and_safety_rounded;
  }
  if (hasAny(['吃', '喝', '水', '饭', '饿', '渴', '餐', '菜'])) {
    return Icons.restaurant_rounded;
  }
  if (hasAny(['厕所', '洗手间', '卫生间', '上厕所'])) {
    return Icons.wc_rounded;
  }
  if (hasAny(['回家', '出去', '路', '车', '公交', '地铁', '位置', '带我'])) {
    return Icons.place_rounded;
  }
  if (hasAny(['帮', '拿', '开', '关', '递', '扶', '需要'])) {
    return Icons.volunteer_activism_rounded;
  }
  if (hasAny(['冷', '热', '衣', '空调', '被子', '灯'])) {
    return Icons.thermostat_rounded;
  }
  if (hasAny(['谢谢', '你好', '再见', '对不起', '请', '可以吗'])) {
    return Icons.chat_bubble_rounded;
  }
  if (hasAny(['时间', '几点', '今天', '明天', '等一下'])) {
    return Icons.schedule_rounded;
  }
  if (hasAny(['难过', '开心', '害怕', '生气', '想', '喜欢', '不喜欢'])) {
    return Icons.favorite_rounded;
  }
  if (hasAny(['钱', '买', '付款', '价格', '多少'])) {
    return Icons.payments_rounded;
  }
  return Icons.touch_app_rounded;
}

class CandidateCard extends StatelessWidget {
  const CandidateCard({
    super.key,
    required this.text,
    required this.onTap,
    this.icon,
    this.imageScale = 1.0,
    this.styleIndex = 0,
  });

  final String text;
  final VoidCallback onTap;
  final IconData? icon;
  final double imageScale;
  final int styleIndex;

  @override
  Widget build(BuildContext context) {
    final style =
        _candidateCardStyles[styleIndex % _candidateCardStyles.length];
    final effectiveScale = imageScale.clamp(0.85, 1.55).toDouble();
    final iconDiameter = (42 * effectiveScale).clamp(36.0, 68.0);
    final iconSize = (25 * effectiveScale).clamp(21.0, 41.0);
    final cardPadding = effectiveScale >= 1.3
        ? 12.0
        : effectiveScale >= 1.15
            ? 14.0
            : 18.0;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.72),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: style.shadow.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Container(
                width: iconDiameter,
                height: iconDiameter,
                decoration: BoxDecoration(
                  color: style.iconBackground.withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: const Color(0xFF111111),
                ),
              ),
              SizedBox(height: 10 + (effectiveScale - 1) * 4),
            ],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                maxLines: effectiveScale >= 1.3 ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.candidate.copyWith(
                  color: const Color(0xFF151515),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SentenceCard extends StatelessWidget {
  const SentenceCard({
    super.key,
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 24),
        label: Text(
          text,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primaryLight,
          disabledForegroundColor: AppColors.textSecondary,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
    );
  }
}

class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.divider),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(29)),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SecondaryActionButton(text: text, icon: icon, onTap: onTap);
  }
}

class QuickPhraseButton extends StatelessWidget {
  const QuickPhraseButton({
    super.key,
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      avatar: const Icon(Icons.volume_up_outlined, size: 20),
      backgroundColor: AppColors.card,
      side: const BorderSide(color: AppColors.divider),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      onPressed: onTap,
    );
  }
}

class RecentExpressionTile extends StatelessWidget {
  const RecentExpressionTile({
    super.key,
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.button),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.history, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Icon(icon, color: AppColors.primary, size: 30),
    );
  }
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(title, style: AppTextStyles.sectionTitle),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center, style: AppTextStyles.subtitle),
          ],
        ),
      ),
    );
  }
}

class ConversationStatusPanel extends StatelessWidget {
  const ConversationStatusPanel({
    super.key,
    required this.status,
    required this.isListening,
    required this.possibleStuck,
    required this.error,
  });

  final String status;
  final bool isListening;
  final bool possibleStuck;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final color = error != null
        ? AppColors.danger
        : isListening
            ? const Color(0xFF34C759)
            : AppColors.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isListening ? Icons.hearing_outlined : Icons.mic_off_outlined,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (possibleStuck) ...[
            const SizedBox(height: 8),
            const Text(
              '可能出现表达停顿',
              style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: const TextStyle(fontSize: 15, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class RecommendationHint extends StatelessWidget {
  const RecommendationHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            '正在推荐更合适的候选',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class RecommendationWaitingPanel extends StatelessWidget {
  const RecommendationWaitingPanel({
    super.key,
    this.message = '如果接口较慢，可以先用本地候选继续。',
    this.onUseLocal,
  });

  final String message;
  final VoidCallback? onUseLocal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          const Text(
            '正在让 Qwen 推荐候选',
            textAlign: TextAlign.center,
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
          if (onUseLocal != null) ...[
            const SizedBox(height: 18),
            SecondaryActionButton(
              text: '先用本地候选',
              icon: Icons.flash_on_outlined,
              onTap: onUseLocal,
            ),
          ],
        ],
      ),
    );
  }
}

class RecommendationDebugPanel extends StatelessWidget {
  const RecommendationDebugPanel({
    super.key,
    required this.status,
    required this.recommendations,
  });

  final String status;
  final List<String> recommendations;

  @override
  Widget build(BuildContext context) {
    final isSuccess = status.startsWith('Qwen 推荐成功');
    final isFailure = status.startsWith('Qwen 推荐失败');
    final color = isSuccess
        ? const Color(0xFF34C759)
        : isFailure
            ? AppColors.danger
            : AppColors.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSuccess
                    ? Icons.check_circle_outline
                    : isFailure
                        ? Icons.error_outline
                        : Icons.info_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '模型返回：${recommendations.join(' / ')}',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: AppTextStyles.sectionTitle
                    .copyWith(color: AppColors.danger)),
            const SizedBox(height: 10),
            Text(message, style: AppTextStyles.subtitle),
            const SizedBox(height: 20),
            PrimaryActionButton(
              text: '重试',
              icon: Icons.refresh,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(text, style: AppTextStyles.subtitle),
    );
  }
}
