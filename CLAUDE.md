# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

语桥 (Yuqiao) is a Flutter-based AAC (Augmentative and Alternative Communication) app for Chinese aphasia patients. It helps users express themselves through contextual word suggestions, photo-based object recognition, conversation-mode word completion, and AI-generated sentence assembly — all with a "confirm before speaking" design philosophy.

**Core principle:** AI suggests, patient confirms, system speaks. Never auto-express on behalf of the user.

## Commands

```bash
# Install dependencies
flutter pub get

# Run on connected Android device
flutter run --dart-define=QWEN_API_KEY=your_key

# Run tests
flutter test

# Static analysis
flutter analyze

# Build debug APK
flutter build apk --debug

# Clean build
flutter clean
```

## Environment Variables (via --dart-define)

| Variable | Default | Purpose |
| --- | --- | --- |
| `QWEN_API_KEY` | *(required)* | API key for Qwen (通义千问) via DashScope — also used for Paraformer ASR |
| `QWEN_BASE_URL` | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` | Chat API endpoint |
| `QWEN_TEXT_MODEL` | `qwen-plus` | Model for sentence generation |
| `QWEN_RECOMMEND_MODEL` | `qwen-turbo` | Model for candidate word recommendation |
| `QWEN_VISION_MODEL` | `qwen-vl-plus` | Model for image recognition |

Never hardcode API keys in source files. Pass them via `--dart-define` at runtime.

## Architecture

### File Structure

- **`lib/main.dart`** — The monolithic core (~14000 lines). Contains all pages, widgets, data models, services, design tokens, and local storage logic. This is the primary file to work in.
- **`lib/star_home.dart`** — The animated home screen with draggable glass bubbles for feature navigation, PageView with 3 pages (home, 补词, 我的), sliding tab indicator. Imported by `main.dart` as `star_ui`.
- **`lib/my_test.dart`** — Profile/settings page ("我的"). Contains `YuqiaoPersonalCenter`, `ProfileHeroCard`, `_ProfileSettingsPage` (avatar/background/nickname editor), `_CategoryDetailPage` (vocabulary detail with TTS), category style editor. Imported by `star_home.dart` as `profile_ui`.
- **`lib/voice_orb_test_page.dart`** — Exports `VoiceOrbPainter` and `VoiceDotsIndicator` (CustomPaint voice visualization). Imported by `main.dart`.
- **`lib/paraformer_asr_service.dart`** — DashScope Paraformer real-time ASR via WebSocket. Used by vocabulary search. Streams PCM audio, returns partial/final transcripts.
- **`lib/xfyun_realtime_asr_service.dart`** — iFlytek (讯飞) real-time ASR via WebSocket with speaker diarization support. Used by conversation mode.
- **`lib/location_recommendation.dart`** — `LocationRecommendationController` for location-based word recommendation. Tracks places, word usage per place, integrates with Amap semantic API.
- **`lib/location_memory_pages.dart`** — Place memory management UI (`PlaceMemoryManagementPage`, `CurrentPlaceStatusCard`).
- **`lib/personal_objects.dart`** / **`lib/personal_object_pages.dart`** — Personal object management (user's custom items).
- **`lib/personal_object_match_policy.dart`** — Matching logic for personal objects during camera recognition.
- **`lib/camera_image_processing.dart`** — Camera image processing utilities.
- **`lib/conversation_terms.dart`** — Special term extraction from conversation transcripts (names, places, institutions).
- **`lib/conversation_feedback.dart`** — Conversation feedback tracking for word preference learning.
- **`lib/expression_habits.dart`** — User expression habit tracking.
- **`lib/stuck_expression_flow.dart`** — Stuck flow expression logic.
- **`lib/local_object_locator.dart`** — Local object location matching.
- **`CamerAwesome-master/`** — Vendored camera plugin. Do not modify unless intentionally fixing the plugin.
- **`android/`** — Standard Flutter Android shell with Gradle KTS build scripts. Uses Aliyun mirrors.

### Key Classes in `lib/main.dart`

| Class | Role |
| --- | --- |
| `YuqiaoApp` | Root widget, manages global state (recent expressions, favorites, vocabulary) |
| `HomePage` | Delegates to `MainInterfaceScreen` from `star_home.dart` |
| `StuckFlowPage` | The "我卡住了" multi-step flow: intent → word selection → AI sentence candidates |
| `AiCandidatesPage` | Displays AI-generated sentence candidates with colorful gradient UI |
| `ConfirmSpeakPage` | Final confirmation + TTS playback |
| `CameraWordPage` | Photo-based object recognition with bounding box annotations |
| `ConversationModePage` | Real-time ASR (iFlytek) with voice orb, sliding tabs, word suggestions, speaker diarization |
| `VocabularyPage` | Personal dictionary with category grid, search (text + voice), TTS, frequency sorting |
| `QwenService` | All AI API calls: sentence generation, recommendation, conversation, object recognition |
| `LocalStore` | SharedPreferences wrapper for persistence |
| `ParaformerAsrService` | Real-time ASR via DashScope WebSocket (in `paraformer_asr_service.dart`) |
| `XfyunRealtimeAsrService` | Real-time ASR via iFlytek WebSocket with speaker diarization (in `xfyun_realtime_asr_service.dart`) |

### ASR Architecture

The app uses two ASR services for different purposes:

1. **iFlytek (讯飞)** — Used by conversation mode for real-time speech recognition with speaker diarization (`ptt=1`). Connects via WebSocket, streams PCM 16-bit 16kHz audio, returns transcripts with speaker labels.
2. **DashScope Paraformer** — Used by vocabulary search for short-voice input. Simpler WebSocket-based ASR without speaker separation.

Both services use the same `record` package for audio capture.

### Data Flow

1. **Expression flow (StuckFlowPage):** User picks intent → iterates through ChoiceSteps → each step calls `QwenService.recommendNextOptions()` → builds `ExpressionDraft` → `AiCandidatesPage` generates sentences → user picks → `ConfirmSpeakPage` speaks via FlutterTts
2. **Camera flow (CameraWordPage):** User takes photo → `QwenService.recognizeObject()` returns objects with bounding boxes and expressions → user taps expression → flows into AiCandidatesPage
3. **Conversation flow (ConversationModePage):** iFlytek ASR streams transcripts with speaker labels → on pause or "我卡住了" → `QwenService.recommendConversationOptions()` → user selects → flows into AiCandidatesPage
4. **Vocabulary flow:** Category grid → detail page with TTS playback → search (text + voice via ParaformerAsrService) → frequency-sorted results

### Design System

Design tokens are defined as static classes in `lib/main.dart`:

- `AppColors` — background (#F5F5F7), card (white), primary (#3478F6), textPrimary, textSecondary, divider, danger
- `AppTextStyles` — title (32sp), subtitle (18sp), sectionTitle (22sp), candidate (24sp), confirmSentence (30sp)
- `AppSpacing` — page (20), gap (14), section (28)
- `AppRadius` — card (24), button (18)

The profile page (`my_test.dart`) and vocabulary page use a warmer design: `Color(0xFFF7F5F0)` background, iOS-style rounded cards (28-34px radius), colorful gradients.

Popup dialogs (suggestions, new category, ASR transcript) use a consistent colorful gradient border design: 6-color gradient (pink → yellow → green → blue), `BackdropFilter` blur, inner glow via `_TranscriptGlowPainter`.

## Key Dependencies

- `flutter_tts` — Chinese TTS (zh-CN, rate 0.45)
- `camerawesome` — Camera plugin, vendored locally
- `image_picker` — Gallery photo selection
- `image_cropper` — Image cropping for avatar/background
- `record` — Audio recording for ASR (PCM 16kHz)
- `shared_preferences` — Local persistence
- `http` — Direct HTTP calls to DashScope API
- `path_provider` — Temp file paths for audio recording

## Coding Conventions

- UI follows iOS-style design: large buttons, big fonts (22-34sp), max 3-4 choices per screen, always include escape hatches
- AI responses are parsed as JSON with fallback handling; `QwenService` strips markdown code fences before parsing
- Vocabulary has 7 default categories: `['人物', '饮食', '地点', '活动', '物品', '感受', '常用句']` + user-created custom categories
- Navigation uses `MaterialPageRoute` push/pop (no named routes)
- `const` constructors are intentionally not enforced (`prefer_const_constructors: false`)
- `use_build_context_synchronously: true` is enforced — always check `mounted` before using context after async gaps
- `withValues(alpha:)` is preferred over the deprecated `withOpacity()`

## Android Build Configuration

- `compileSdk = 36` (required by dependencies)
- `minSdk = 24` (Android 7.0)
- Aliyun mirrors in `android/settings.gradle.kts` and `android/build.gradle.kts`
- `kotlin.incremental=false` in `gradle.properties` (cross-drive issue with D: project and C: Pub cache)
- Huawei HBN AL00 (Android 12, API 31) — primary test device

## Troubleshooting

### `flutter clean` fails to delete `build/`

Kill `adb.exe` and `java.exe` first, then delete manually.

### Gradle download timeout

Verify Aliyun mirrors are configured in `settings.gradle.kts` and `build.gradle.kts`.

### Gradle lock timeout

Run `android/gradlew.bat --stop` to kill stale Gradle daemons.

### `image_cropper` compileSdk error

Ensure `compileSdk = 36` in `android/app/build.gradle.kts`.

## Important Constraints

- Accessibility-focused app for aphasia patients — low-cognitive-load UI: large text, few choices, always confirmable
- AI must never add unconfirmed information to generated sentences
- Camera, microphone, and location must be explicitly triggered by the user
- Android permissions: `CAMERA`, `RECORD_AUDIO`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
