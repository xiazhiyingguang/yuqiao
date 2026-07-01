# 语桥 Yuqiao

语桥是一款面向轻中度失语症人群的日常表达辅助 App。项目目标不是替用户说话，而是在用户找词、组句、理解对话或表达不准确时，提供低负担、可确认、可播报的辅助闭环。

当前工程使用 Flutter 实现，优先在 Android 真机调试，后续可迁移到 iOS。核心原则是：用户主动触发为主，AI 只做候选建议，最终表达必须由用户确认。

## 一句话闭环

```text
用户卡住 / 对话中需要帮助 / 拍照识物 / 词语训练
-> 结合上下文、地点、个人物品、历史习惯生成候选
-> 用户选择或确认
-> 生成更清晰表达
-> 用户二次确认
-> TTS 播报或保存到本机记忆
```

## 当前核心功能

### 1. 首页与主导航

- 首页使用小星星和四个功能球作为入口：补词、拍照、对话、词库。
- App 底部为三页结构：左侧词语花园，中间首页，右侧我的。
- 视觉风格以浅色、莫兰迪色、半透明卡片、柔和高光为主，不再依赖第三方 `liquid_glass_renderer`。
- 已处理 Android 系统导航栏颜色，尽量让底部系统栏与 App 背景融合。

### 2. 补词与成句

- 补词流程按用户当前任务逐步缩小表达范围。
- 候选词优先来自 Qwen 真实 API，模型失败或超时才使用本地兜底。
- 支持 2 / 4 / 6 个候选数量偏好，UI 只展示有效数量，但底层可请求更多候选用于过滤。
- “换一组”会避免重复语义，并在候选耗尽后继续请求模型。
- 完整句子生成后进入确认页，确认后才播报。
- 保存完整表达会写入本机常用表达、个性化学习和智能体轻量反馈。

### 3. 对话模式

- 对话模式使用讯飞实时转写，支持说话者区分，用于建立对话上下文。
- 阿里 Paraformer ASR 代码保留，用于词库搜索等普通语音输入场景。
- 粉色语音球可打开实时转录面板，转录内容支持人物、地点、特殊词汇高亮。
- 支持“帮我理解”：把对方长句拆成重点、动作、地点、顺序等，降低理解负担。
- 支持半自动卡顿辅助：检测疑似停顿后轻震提示，显示候选句，用户确认后才播报。
- 自动卡顿检测默认为关闭，用户可在“我的”中自行开启。
- App 进入后台时会暂停会话相关任务，避免后台持续占用麦克风、动画和网络资源。

### 4. 拍照识物与个人物品

- 相机基于 `camerawesome`，拍照或相册选择后调用 Qwen 视觉识别。
- 本地 ML Kit / 图像处理逻辑用于辅助物体框定位，Qwen 负责识别“图里有什么”。
- 识别结果以照片标注为主，点击物品后进入表达建议页。
- 支持一键播报物品名，也保留生成完整表达的能力。
- 表达建议会结合地点类型和时间生成更贴近场景的短句。
- 支持保存个人物品：用户可基于拍照结果自定义名称、类别、外观、备注和常用表达。
- 个人物品匹配采用保守策略，避免看到普通物体就误判为“我的物品”。

### 5. 地点词汇推荐

- 用户主动开启后才请求使用期间定位权限，不做后台定位。
- 地点数据默认只保存在本机，不上传精确经纬度给 AI 或服务器。
- 使用本地地点簇记录常去地点，结合高德 Web 服务做地点类型建议。
- 用户可以确认或修改地点名称与类型；用户确认后，自动识别不能覆盖。
- 补词、对话、拍照、词库等候选会结合地点历史高频词和地点类型通用词重新排序。

### 6. 个性化学习与语桥记忆

- 本机记录用户选择、播报、保存、换一组、跳过等行为。
- `CompanionAgentController` 统一处理上下文、候选排序和轻量反馈。
- `语桥记忆` 页面用于展示“越用越懂我”的证据：常用表达、地点习惯、个人物品关联表达、对话特殊词。
- 个性化学习可在“我的”中关闭；关闭后不再写入新的学习记录。

### 7. 词库与图文匹配

- 使用 Mulberry Symbols 作为第一版图文符号体系。
- `lib/mulberry_symbol_data.dart` 管理词语到图标的匹配。
- 词库界面已统一到 App 主题色和 iOS 风格图标方向。
- 已人工修复一批错误图标映射，例如蛋糕、鸡蛋、水果、身体部位、交通、医院等。

### 8. 词语花园

- 左侧页面为“词语花园”，用于康复训练和词汇强化。
- 当前支持看图、听音、选四选一。
- 支持普通练习、常错复习、个人物品训练。
- 已加入掌握度、今日练习、常错词、下次复习等本地记录。
- 复习计划按类似艾宾浩斯遗忘曲线的思路设计：答对越多，复习间隔越长；答错会提高近期出现概率。
- 长期掌握的词会降低出现频率，常错词多次答对后应从常错复习中淡出。

## 关键文件导览

```text
lib/main.dart
  App 入口、主要页面、Qwen 服务、补词与成句流程、对话/拍照页面主体。

lib/star_home.dart
  三页主界面、小星星、功能球、底部导航、首页交互。

lib/my_test.dart
  “我的”页面、个人资料、表达偏好、开关入口、个人中心 UI。

lib/companion_agent.dart
  伴身智能体雏形：上下文、反馈、候选排序、长期偏好信号。

lib/expression_habits.dart
  个性化学习记录和表达习惯存储。

lib/location_recommendation.dart
lib/location_memory_pages.dart
  地点词汇推荐、地点记忆管理、地点词汇详情。

lib/personal_objects.dart
lib/personal_object_pages.dart
  个人物品模型、存储、管理和编辑页面。

lib/memory_insights.dart
lib/memory_insights_page.dart
  “语桥记忆”本地聚合与可视化页面。

lib/mulberry_symbol_data.dart
lib/mulberry_symbols.dart
EN-symbols/
  Mulberry Symbols 图文匹配数据和资源。

lib/rehab_training.dart
  词语花园训练、掌握度、复习计划、训练结束反馈。

lib/paraformer_asr_service.dart
lib/xfyun_realtime_asr_service.dart
  阿里 Paraformer 与讯飞实时转写服务。

test/
  补词、智能体、记忆、词语花园等单元测试。
```

## 运行命令

不要把真实 API Key 写入代码或 README。运行时使用 `--dart-define` 注入。

### 仅运行本地 UI

```powershell
flutter run -d 2NP0224507003453
```

### 完整真机调试

```powershell
flutter run -d 2NP0224507003453 `
  --dart-define=QWEN_API_KEY=你的通义Key `
  --dart-define=DASHSCOPE_API_KEY=你的DashScopeKey `
  --dart-define=XFYUN_APP_ID=你的讯飞AppID `
  --dart-define=XFYUN_API_KEY=你的讯飞APIKey `
  --dart-define=XFYUN_API_SECRET=你的讯飞APISecret `
  --dart-define=AMAP_WEB_KEY=你的高德Web服务Key
```

### 构建 APK

如果要先构建再安装，所有 Key 必须在构建阶段传入，`flutter install` 不能再补 Key。

```powershell
flutter build apk --debug `
  --dart-define=QWEN_API_KEY=你的通义Key `
  --dart-define=DASHSCOPE_API_KEY=你的DashScopeKey `
  --dart-define=XFYUN_APP_ID=你的讯飞AppID `
  --dart-define=XFYUN_API_KEY=你的讯飞APIKey `
  --dart-define=XFYUN_API_SECRET=你的讯飞APISecret `
  --dart-define=AMAP_WEB_KEY=你的高德Web服务Key

flutter install --debug -d 2NP0224507003453
```

> 注意：当前协作中，Codex 不再主动执行 `flutter build apk`，因为本机经常耗时很久或卡住。构建和安装由用户本地执行。

## 重要设计决策

- AI 不直接替用户表达，所有播报必须经过用户确认。
- 对话模式是核心亮点：上下文、说话者区分、理解辅助、卡顿辅助，比单纯补词更能体现产品价值。
- 拍照识物不要强调“精准检测框”，因为大模型返回框和本地检测框都可能偏差；优先使用标签、区域和点击确认降低误导。
- 地点、个人物品、人名、表达习惯默认只保存在本机。
- 调试入口和日志不应暴露给普通用户；可保留代码，但前端入口需要隐藏。
- 首页不要频繁动态重排，避免给失语症用户增加认知负担。

## 已知风险和坑

- API Key 放在客户端仍有泄露风险，正式发布前应改为后端代理或短期 token。
- 讯飞、Qwen、高德等服务失败时必须有本地兜底，不能阻塞基础使用。
- 华为机型上 Android 系统 ASR 曾返回 `error_busy`，因此对话模式改用独立云端 ASR。
- `liquid_glass_renderer` 在当前华为真机上会降级为 FakeGlass，真实 shader 折射效果不可用，因此已放弃作为主界面方案。
- 相机物体框仍可能不完全准确，尤其是遮挡、重叠、近距离拍摄场景。
- `flutter build apk` 在当前机器上经常很慢；新对话不要默认跑构建。

## 新对话优先检查

新 Codex 对话建议先做这几件事：

1. 运行 `git status --short`，确认工作树是否干净。
2. 先读本 README，再读 `lib/star_home.dart`、`lib/main.dart`、`lib/my_test.dart`、`lib/rehab_training.dart`。
3. 不要重构大文件，先围绕用户指出的问题做局部修复。
4. 不要把真实 Key 写入代码、日志、README 或测试。
5. 除非用户明确要求，不要执行 `flutter build apk`。

## 下一步建议

- 优先打磨对话模式体验：底部转录面板、帮我理解入口、卡顿候选质量、退出与重连。
- 优先修复补词质量：让提示词、上下文和候选类型严格匹配。
- 继续统一 UI：图标、按钮、卡片、导航栏、字体层级。
- 让“语桥记忆”更多参与推荐，但不要无限堆积展示；页面只展示近期和高价值记忆。
- 词语花园继续补齐训练闭环：难度设置、常错词退出机制、训练总结解释。
