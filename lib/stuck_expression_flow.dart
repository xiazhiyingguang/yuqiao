enum StuckExpressionIntent { help, discomfort, object, question, situation }

extension StuckExpressionIntentLabel on StuckExpressionIntent {
  String get label => switch (this) {
        StuckExpressionIntent.help => '要人帮忙',
        StuckExpressionIntent.discomfort => '表达不舒服',
        StuckExpressionIntent.object => '要东西',
        StuckExpressionIntent.question => '问问题',
        StuckExpressionIntent.situation => '说明情况',
      };

  String get sentenceIntent => switch (this) {
        StuckExpressionIntent.help => '向他人请求帮助',
        StuckExpressionIntent.discomfort => '表达身体或情绪上的不舒服',
        StuckExpressionIntent.object => '说明自己想要某个东西或想使用某个东西',
        StuckExpressionIntent.question => '向别人提出一个问题',
        StuckExpressionIntent.situation => '说明当前发生的事情或自己的情况',
      };
}

enum StuckExpressionSlot {
  target,
  action,
  object,
  subject,
  feeling,
  bodyPart,
  detail,
  degree,
  time,
  place,
  helper,
  communication,
}

extension StuckExpressionSlotLabel on StuckExpressionSlot {
  String get key => name;

  String get label => switch (this) {
        StuckExpressionSlot.target => '寻找对象',
        StuckExpressionSlot.action => '动作',
        StuckExpressionSlot.object => '相关对象',
        StuckExpressionSlot.subject => '描述对象',
        StuckExpressionSlot.feeling => '感受',
        StuckExpressionSlot.bodyPart => '身体部位',
        StuckExpressionSlot.detail => '补充信息',
        StuckExpressionSlot.degree => '程度',
        StuckExpressionSlot.time => '时间',
        StuckExpressionSlot.place => '地点',
        StuckExpressionSlot.helper => '沟通方式',
        StuckExpressionSlot.communication => '表达方式',
      };
}

class StuckCandidate {
  const StuckCandidate({
    required this.text,
    required this.semanticGroup,
    required this.slot,
    this.isModelGenerated = false,
  });

  final String text;
  final String semanticGroup;
  final StuckExpressionSlot slot;
  final bool isModelGenerated;
}

class StuckStepDefinition {
  const StuckStepDefinition({
    required this.slot,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.vocabularyCategories,
    this.optional = false,
  });

  final StuckExpressionSlot slot;
  final String title;
  final String subtitle;
  final List<StuckCandidate> options;
  final Set<String> vocabularyCategories;
  final bool optional;
}

class StuckSelection {
  const StuckSelection({required this.slot, required this.candidate});

  final StuckExpressionSlot slot;
  final StuckCandidate candidate;
}

class StuckExpressionSession {
  StuckExpressionSession({required this.intent, this.seedFragment = ''});

  final StuckExpressionIntent intent;
  String seedFragment;
  final Map<StuckExpressionSlot, StuckSelection> _selections = {};
  final Set<StuckExpressionSlot> _skipped = {};

  List<StuckStepDefinition> get activeSteps => StuckFlowCatalog.stepsFor(this);

  List<StuckSelection> get selections => activeSteps
      .map((step) => _selections[step.slot])
      .whereType<StuckSelection>()
      .toList(growable: false);

  Set<StuckExpressionSlot> get skipped => Set.unmodifiable(_skipped);

  StuckStepDefinition? get currentStep {
    for (final step in activeSteps) {
      if (!_selections.containsKey(step.slot) &&
          !_skipped.contains(step.slot)) {
        return step;
      }
    }
    return null;
  }

  String? valueOf(StuckExpressionSlot slot) =>
      _selections[slot]?.candidate.text;

  StuckCandidate? candidateOf(StuckExpressionSlot slot) =>
      _selections[slot]?.candidate;

  void select(StuckCandidate candidate) {
    _selections[candidate.slot] = StuckSelection(
      slot: candidate.slot,
      candidate: candidate,
    );
    _skipped.remove(candidate.slot);
  }

  void skipCurrent() {
    final step = currentStep;
    if (step != null && step.optional) _skipped.add(step.slot);
  }

  void clearFrom(StuckExpressionSlot slot) {
    final steps = activeSteps;
    final index = steps.indexWhere((step) => step.slot == slot);
    if (index < 0) return;
    final keep = steps.take(index).map((step) => step.slot).toSet();
    _selections.removeWhere((key, _) => !keep.contains(key));
    _skipped.removeWhere((key) => !keep.contains(key));
  }

  bool get canFinish => StuckFlowCatalog.canFinish(this);
}

class StuckFlowCatalog {
  static bool isPlausibleCandidate(
    StuckExpressionSlot slot,
    String text,
  ) {
    final clean = text.trim();
    if (clean.isEmpty ||
        clean.length > 18 ||
        RegExp(r'[。！？!?]').hasMatch(clean)) {
      return false;
    }
    return switch (slot) {
      StuckExpressionSlot.place => RegExp(
          r'家|医院|超市|学校|公园|药店|餐厅|公司|小区|楼|房间|厕所|车站|地铁|这里|外面|店$|院$|馆$|站$|场$|园$|室$|楼$',
        ).hasMatch(clean),
      StuckExpressionSlot.time =>
        RegExp(r'现在|刚才|今天|明天|昨天|早上|中午|晚上|一会|最近|一直|时候|周|月|年').hasMatch(clean),
      StuckExpressionSlot.bodyPart =>
        RegExp(r'头|脸|眼|肩|手|胸|肚|腹|腰|腿|脚|背|喉咙|脖子').hasMatch(clean),
      StuckExpressionSlot.feeling =>
        RegExp(r'累|疼|痛|冷|热|怕|难过|高兴|着急|晕|麻|恶心|舒服|孤单').hasMatch(clean),
      StuckExpressionSlot.degree =>
        RegExp(r'一点|轻微|比较|很|非常|严重|明显|越来越|不太').hasMatch(clean),
      StuckExpressionSlot.action =>
        RegExp(r'找|拿|打开|关闭|关上|去|回|吃|喝|休息|陪|说|看|买|用|告诉|完成|弄|等').hasMatch(clean),
      StuckExpressionSlot.helper => clean.length <= 8 &&
          !RegExp(r'^(我想|我要|请|帮我|能不能|可以|麻烦|是不是|哪里|怎么)').hasMatch(clean) &&
          RegExp(r'妈妈|爸爸|家人|朋友|老师|医生|护士|工作人员|同事|治疗师|身边的人|照顾者|护工|他|她|你$')
              .hasMatch(clean),
      StuckExpressionSlot.communication =>
        RegExp(r'帮我|请|你|哪里|怎么|自己|不用').hasMatch(clean),
      StuckExpressionSlot.target ||
      StuckExpressionSlot.object ||
      StuckExpressionSlot.subject =>
        !RegExp(r'^(我想|我要|请|帮我|能不能|是不是)').hasMatch(clean),
      StuckExpressionSlot.detail => true,
    };
  }

  static List<StuckStepDefinition> stepsFor(StuckExpressionSession session) {
    return switch (session.intent) {
      StuckExpressionIntent.help => _helpSteps(session),
      StuckExpressionIntent.discomfort => _feelingSteps(session),
      StuckExpressionIntent.object => _objectNeedSteps,
      StuckExpressionIntent.question => _questionSteps,
      StuckExpressionIntent.situation => _describeSteps,
    };
  }

  static bool canFinish(StuckExpressionSession session) {
    return switch (session.intent) {
      StuckExpressionIntent.help => _helpCanFinish(session),
      StuckExpressionIntent.discomfort =>
        session.valueOf(StuckExpressionSlot.feeling)?.isNotEmpty == true,
      StuckExpressionIntent.object =>
        session.valueOf(StuckExpressionSlot.object)?.isNotEmpty == true,
      StuckExpressionIntent.question =>
        session.valueOf(StuckExpressionSlot.communication)?.isNotEmpty == true,
      StuckExpressionIntent.situation =>
        session.valueOf(StuckExpressionSlot.subject)?.isNotEmpty == true &&
            session.valueOf(StuckExpressionSlot.action)?.isNotEmpty == true,
    };
  }

  static bool _helpCanFinish(StuckExpressionSession session) {
    return session.valueOf(StuckExpressionSlot.helper)?.isNotEmpty == true ||
        session.valueOf(StuckExpressionSlot.action)?.isNotEmpty == true;
  }

  static List<StuckStepDefinition> _helpSteps(
    StuckExpressionSession session,
  ) {
    final action = session.valueOf(StuckExpressionSlot.action) ?? '';
    final complement = _requestComplementSlot(action);
    return [
      _requestHelperStep,
      _requestActionStep,
      switch (complement) {
        StuckExpressionSlot.place => _requestPlaceStep,
        StuckExpressionSlot.detail => _requestDetailStep,
        _ => _requestObjectStep,
      },
      _requestTimeStep,
    ];
  }

  static List<StuckStepDefinition> _feelingSteps(
    StuckExpressionSession session,
  ) {
    final feeling = session.valueOf(StuckExpressionSlot.feeling) ?? '';
    final needsBodyPart = feeling.isEmpty ||
        !['害怕', '难过', '高兴', '着急', '孤单'].any(feeling.contains);
    return [
      _feelingStep,
      if (needsBodyPart) _bodyPartStep,
      _degreeStep,
      _feelingTimeStep,
      _feelingNeedStep,
    ];
  }

  static const _objectNeedSteps = [
    _requestObjectStep,
    _objectNeedActionStep,
    _requestHelperStep,
    _requestTimeStep,
  ];

  static const _questionSteps = [
    _questionTypeStep,
    _questionTargetStep,
    _requestHelperStep,
  ];

  static StuckExpressionSlot _requestComplementSlot(String action) {
    if (action.contains('去') || action.contains('带我')) {
      return StuckExpressionSlot.place;
    }
    if (_selfContainedActions.any(action.contains)) {
      return StuckExpressionSlot.detail;
    }
    return StuckExpressionSlot.object;
  }

  static const _selfContainedActions = ['陪我', '等我', '慢一点', '再说一遍'];

  static const _requestActionStep = StuckStepDefinition(
    slot: StuckExpressionSlot.action,
    title: '你想做什么？',
    subtitle: '先选择动作或请求方向',
    vocabularyCategories: {'活动', '常用句'},
    options: [
      StuckCandidate(
          text: '帮我拿', semanticGroup: '拿取', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '帮我打开', semanticGroup: '打开', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '陪陪我', semanticGroup: '陪伴', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '带我去', semanticGroup: '前往', slot: StuckExpressionSlot.action),
    ],
  );

  static const _requestObjectStep = StuckStepDefinition(
    slot: StuckExpressionSlot.object,
    title: '和什么东西有关？',
    subtitle: '补充动作需要的对象',
    vocabularyCategories: {'物品', '饮食'},
    options: [
      StuckCandidate(
          text: '水杯', semanticGroup: '饮水', slot: StuckExpressionSlot.object),
      StuckCandidate(
          text: '手机', semanticGroup: '电子设备', slot: StuckExpressionSlot.object),
      StuckCandidate(
          text: '衣服', semanticGroup: '衣物', slot: StuckExpressionSlot.object),
      StuckCandidate(
          text: '门', semanticGroup: '设施', slot: StuckExpressionSlot.object),
    ],
  );

  static const _objectNeedActionStep = StuckStepDefinition(
    slot: StuckExpressionSlot.action,
    title: '你想怎么用它？',
    subtitle: '可以是想要、拿来、打开、买一个，也可以直接整理成句',
    optional: true,
    vocabularyCategories: {'活动', '常用句'},
    options: [
      StuckCandidate(
          text: '我想要这个', semanticGroup: '想要', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '帮我拿一下', semanticGroup: '拿取', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '我想用一下', semanticGroup: '使用', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '在哪里买', semanticGroup: '购买', slot: StuckExpressionSlot.action),
    ],
  );

  static const _questionTypeStep = StuckStepDefinition(
    slot: StuckExpressionSlot.communication,
    title: '你想问什么？',
    subtitle: '先选问题方向，后面可以补充对象',
    vocabularyCategories: {'常用句', '地点', '活动'},
    options: [
      StuckCandidate(
          text: '这个是什么',
          semanticGroup: '确认事物',
          slot: StuckExpressionSlot.communication),
      StuckCandidate(
          text: '在哪里',
          semanticGroup: '询问位置',
          slot: StuckExpressionSlot.communication),
      StuckCandidate(
          text: '怎么做',
          semanticGroup: '询问方法',
          slot: StuckExpressionSlot.communication),
      StuckCandidate(
          text: '什么时候',
          semanticGroup: '询问时间',
          slot: StuckExpressionSlot.communication),
    ],
  );

  static const _questionTargetStep = StuckStepDefinition(
    slot: StuckExpressionSlot.target,
    title: '问题和谁或什么有关？',
    subtitle: '不确定可以跳过，让 AI 根据前面的问题整理',
    optional: true,
    vocabularyCategories: {'人物', '物品', '地点', '活动'},
    options: [
      StuckCandidate(
          text: '这个东西', semanticGroup: '物品', slot: StuckExpressionSlot.target),
      StuckCandidate(
          text: '这里', semanticGroup: '地点', slot: StuckExpressionSlot.target),
      StuckCandidate(
          text: '今天的安排', semanticGroup: '安排', slot: StuckExpressionSlot.target),
      StuckCandidate(
          text: '刚才那句话', semanticGroup: '对话', slot: StuckExpressionSlot.target),
    ],
  );

  static const _requestPlaceStep = StuckStepDefinition(
    slot: StuckExpressionSlot.place,
    title: '你想去哪里？',
    subtitle: '选择目的地',
    vocabularyCategories: {'地点'},
    options: [
      StuckCandidate(
          text: '家里', semanticGroup: '回家', slot: StuckExpressionSlot.place),
      StuckCandidate(
          text: '楼下', semanticGroup: '楼层', slot: StuckExpressionSlot.place),
      StuckCandidate(
          text: '公园', semanticGroup: '户外', slot: StuckExpressionSlot.place),
      StuckCandidate(
          text: '超市', semanticGroup: '购物', slot: StuckExpressionSlot.place),
    ],
  );

  static const _requestDetailStep = StuckStepDefinition(
    slot: StuckExpressionSlot.detail,
    title: '还想补充什么？',
    subtitle: '不需要时可以直接整理成句',
    optional: true,
    vocabularyCategories: {'常用句', '感受'},
    options: [
      StuckCandidate(
          text: '一会儿', semanticGroup: '短时间', slot: StuckExpressionSlot.detail),
      StuckCandidate(
          text: '慢一点', semanticGroup: '速度', slot: StuckExpressionSlot.detail),
      StuckCandidate(
          text: '我有点着急', semanticGroup: '急迫', slot: StuckExpressionSlot.detail),
      StuckCandidate(
          text: '不用着急', semanticGroup: '从容', slot: StuckExpressionSlot.detail),
    ],
  );

  static const _requestHelperStep = StuckStepDefinition(
    slot: StuckExpressionSlot.helper,
    title: '想请谁帮忙？',
    subtitle: '不指定人物可以跳过',
    optional: true,
    vocabularyCategories: {'人物'},
    options: [
      StuckCandidate(
          text: '家人', semanticGroup: '家人', slot: StuckExpressionSlot.helper),
      StuckCandidate(
          text: '朋友', semanticGroup: '朋友', slot: StuckExpressionSlot.helper),
      StuckCandidate(
          text: '工作人员',
          semanticGroup: '工作人员',
          slot: StuckExpressionSlot.helper),
      StuckCandidate(
          text: '身边的人', semanticGroup: '其他人', slot: StuckExpressionSlot.helper),
    ],
  );

  static const _requestTimeStep = StuckStepDefinition(
    slot: StuckExpressionSlot.time,
    title: '什么时候？',
    subtitle: '不重要时可以跳过',
    optional: true,
    vocabularyCategories: {},
    options: [
      StuckCandidate(
          text: '现在', semanticGroup: '立即', slot: StuckExpressionSlot.time),
      StuckCandidate(
          text: '等一会儿', semanticGroup: '稍后', slot: StuckExpressionSlot.time),
      StuckCandidate(
          text: '今天', semanticGroup: '今天', slot: StuckExpressionSlot.time),
      StuckCandidate(
          text: '明天', semanticGroup: '明天', slot: StuckExpressionSlot.time),
    ],
  );

  static const _feelingStep = StuckStepDefinition(
    slot: StuckExpressionSlot.feeling,
    title: '你现在是什么感受？',
    subtitle: '身体和情绪都可以表达',
    vocabularyCategories: {'感受'},
    options: [
      StuckCandidate(
          text: '有点累', semanticGroup: '疲劳', slot: StuckExpressionSlot.feeling),
      StuckCandidate(
          text: '有点疼', semanticGroup: '疼痛', slot: StuckExpressionSlot.feeling),
      StuckCandidate(
          text: '觉得冷', semanticGroup: '温度', slot: StuckExpressionSlot.feeling),
      StuckCandidate(
          text: '有点害怕', semanticGroup: '情绪', slot: StuckExpressionSlot.feeling),
    ],
  );

  static const _bodyPartStep = StuckStepDefinition(
    slot: StuckExpressionSlot.bodyPart,
    title: '身体哪里最明显？',
    subtitle: '和身体无关时可以跳过',
    optional: true,
    vocabularyCategories: {'感受'},
    options: [
      StuckCandidate(
          text: '头', semanticGroup: '头部', slot: StuckExpressionSlot.bodyPart),
      StuckCandidate(
          text: '肩膀', semanticGroup: '上肢', slot: StuckExpressionSlot.bodyPart),
      StuckCandidate(
          text: '肚子', semanticGroup: '腹部', slot: StuckExpressionSlot.bodyPart),
      StuckCandidate(
          text: '腿', semanticGroup: '下肢', slot: StuckExpressionSlot.bodyPart),
    ],
  );

  static const _degreeStep = StuckStepDefinition(
    slot: StuckExpressionSlot.degree,
    title: '这种感受有多明显？',
    subtitle: '不确定时可以跳过',
    optional: true,
    vocabularyCategories: {},
    options: [
      StuckCandidate(
          text: '一点点', semanticGroup: '轻微', slot: StuckExpressionSlot.degree),
      StuckCandidate(
          text: '比较明显', semanticGroup: '中等', slot: StuckExpressionSlot.degree),
      StuckCandidate(
          text: '很明显', semanticGroup: '强烈', slot: StuckExpressionSlot.degree),
      StuckCandidate(
          text: '越来越明显', semanticGroup: '加重', slot: StuckExpressionSlot.degree),
    ],
  );

  static const _feelingTimeStep = StuckStepDefinition(
    slot: StuckExpressionSlot.time,
    title: '什么时候开始的？',
    subtitle: '不记得可以跳过',
    optional: true,
    vocabularyCategories: {},
    options: [
      StuckCandidate(
          text: '刚刚', semanticGroup: '刚发生', slot: StuckExpressionSlot.time),
      StuckCandidate(
          text: '今天', semanticGroup: '今天', slot: StuckExpressionSlot.time),
      StuckCandidate(
          text: '昨晚', semanticGroup: '昨晚', slot: StuckExpressionSlot.time),
      StuckCandidate(
          text: '有一段时间了', semanticGroup: '持续', slot: StuckExpressionSlot.time),
    ],
  );

  static const _feelingNeedStep = StuckStepDefinition(
    slot: StuckExpressionSlot.action,
    title: '你现在希望怎么做？',
    subtitle: '可以直接整理感受，也可以补充需要',
    optional: true,
    vocabularyCategories: {'活动', '常用句'},
    options: [
      StuckCandidate(
          text: '想休息一下', semanticGroup: '休息', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '想喝点水', semanticGroup: '饮水', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '请陪陪我', semanticGroup: '陪伴', slot: StuckExpressionSlot.action),
      StuckCandidate(
          text: '想告诉家人', semanticGroup: '告知', slot: StuckExpressionSlot.action),
    ],
  );

  static const _describeSteps = [
    StuckStepDefinition(
      slot: StuckExpressionSlot.subject,
      title: '你想说谁或什么？',
      subtitle: '先确定事情的主角',
      vocabularyCategories: {'人物', '物品', '饮食'},
      options: [
        StuckCandidate(
            text: '我', semanticGroup: '自己', slot: StuckExpressionSlot.subject),
        StuckCandidate(
            text: '家人', semanticGroup: '人物', slot: StuckExpressionSlot.subject),
        StuckCandidate(
            text: '手机', semanticGroup: '物品', slot: StuckExpressionSlot.subject),
        StuckCandidate(
            text: '这件事',
            semanticGroup: '事件',
            slot: StuckExpressionSlot.subject),
      ],
    ),
    StuckStepDefinition(
      slot: StuckExpressionSlot.action,
      title: '发生了什么？',
      subtitle: '选择最接近的动作或变化',
      vocabularyCategories: {'活动', '常用句'},
      options: [
        StuckCandidate(
            text: '找不到了',
            semanticGroup: '丢失',
            slot: StuckExpressionSlot.action),
        StuckCandidate(
            text: '弄坏了', semanticGroup: '损坏', slot: StuckExpressionSlot.action),
        StuckCandidate(
            text: '已经完成了',
            semanticGroup: '完成',
            slot: StuckExpressionSlot.action),
        StuckCandidate(
            text: '想告诉你',
            semanticGroup: '告知',
            slot: StuckExpressionSlot.action),
      ],
    ),
    StuckStepDefinition(
      slot: StuckExpressionSlot.object,
      title: '还和什么有关？',
      subtitle: '没有其他对象可以跳过',
      optional: true,
      vocabularyCategories: {'人物', '物品', '地点', '活动'},
      options: [
        StuckCandidate(
            text: '家里的东西',
            semanticGroup: '物品',
            slot: StuckExpressionSlot.object),
        StuckCandidate(
            text: '一位朋友',
            semanticGroup: '人物',
            slot: StuckExpressionSlot.object),
        StuckCandidate(
            text: '刚才的事情',
            semanticGroup: '事件',
            slot: StuckExpressionSlot.object),
        StuckCandidate(
            text: '我的安排',
            semanticGroup: '计划',
            slot: StuckExpressionSlot.object),
      ],
    ),
    StuckStepDefinition(
      slot: StuckExpressionSlot.time,
      title: '大概是什么时候？',
      subtitle: '不重要时可以跳过',
      optional: true,
      vocabularyCategories: {},
      options: [
        StuckCandidate(
            text: '刚才', semanticGroup: '刚刚', slot: StuckExpressionSlot.time),
        StuckCandidate(
            text: '今天早上', semanticGroup: '早上', slot: StuckExpressionSlot.time),
        StuckCandidate(
            text: '昨天', semanticGroup: '昨天', slot: StuckExpressionSlot.time),
        StuckCandidate(
            text: '最近', semanticGroup: '近期', slot: StuckExpressionSlot.time),
      ],
    ),
    StuckStepDefinition(
      slot: StuckExpressionSlot.place,
      title: '事情发生在哪里？',
      subtitle: '不需要地点时可以跳过',
      optional: true,
      vocabularyCategories: {'地点'},
      options: [
        StuckCandidate(
            text: '家里', semanticGroup: '家', slot: StuckExpressionSlot.place),
        StuckCandidate(
            text: '外面', semanticGroup: '室外', slot: StuckExpressionSlot.place),
        StuckCandidate(
            text: '路上', semanticGroup: '途中', slot: StuckExpressionSlot.place),
        StuckCandidate(
            text: '这里', semanticGroup: '当前地点', slot: StuckExpressionSlot.place),
      ],
    ),
  ];
}
