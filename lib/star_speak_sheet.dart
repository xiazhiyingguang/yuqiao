part of 'star_home.dart';

class StarPhrase {
  const StarPhrase({
    required this.text,
    required this.icon,
    required this.color,
  });

  final String text;
  final IconData icon;
  final Color color;
}

class _StarExpressionGroup {
  const _StarExpressionGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.phrases,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<StarPhrase> phrases;
}

class _StarFamilyContact {
  const _StarFamilyContact({
    required this.name,
    required this.phone,
    required this.message,
  });

  final String name;
  final String phone;
  final String message;

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'message': message,
      };

  static _StarFamilyContact? fromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final name = decoded['name']?.toString().trim() ?? '';
      final phone = decoded['phone']?.toString().trim() ?? '';
      final message = decoded['message']?.toString().trim() ?? '';
      if (name.isEmpty) return null;
      return _StarFamilyContact(
        name: name,
        phone: phone,
        message: message.isEmpty ? '请帮我联系家人' : message,
      );
    } catch (_) {
      return null;
    }
  }
}

enum _StarSpeakView { quick, board, familySetup, familyConfirm }

const List<StarPhrase> kStarPhrases = [
  StarPhrase(
    text: '是',
    icon: Icons.check_circle_rounded,
    color: Color(0xFF7A9E9F),
  ),
  StarPhrase(
    text: '不是',
    icon: Icons.cancel_rounded,
    color: Color(0xFFD77F8B),
  ),
  StarPhrase(
    text: '请慢一点',
    icon: Icons.speed_rounded,
    color: Color(0xFF8D9DC2),
  ),
  StarPhrase(
    text: '请再说一次',
    icon: Icons.replay_rounded,
    color: Color(0xFFD7A86E),
  ),
  StarPhrase(
    text: '我想喝水',
    icon: Icons.local_drink_rounded,
    color: Color(0xFF4E8FD8),
  ),
  StarPhrase(
    text: '我不舒服',
    icon: Icons.favorite_rounded,
    color: Color(0xFFD08C60),
  ),
];

const List<_StarExpressionGroup> _starExpressionGroups = [
  _StarExpressionGroup(
    title: '身体不舒服',
    icon: Icons.healing_rounded,
    color: Color(0xFFD77F8B),
    phrases: [
      StarPhrase(
        text: '我头疼',
        icon: Icons.psychology_alt_rounded,
        color: Color(0xFFD77F8B),
      ),
      StarPhrase(
        text: '我肚子不舒服',
        icon: Icons.sick_rounded,
        color: Color(0xFFD77F8B),
      ),
      StarPhrase(
        text: '我胸闷',
        icon: Icons.favorite_rounded,
        color: Color(0xFFD77F8B),
      ),
      StarPhrase(
        text: '我想休息一下',
        icon: Icons.hotel_rounded,
        color: Color(0xFFD77F8B),
      ),
    ],
  ),
  _StarExpressionGroup(
    title: '吃喝',
    icon: Icons.local_dining_rounded,
    color: Color(0xFFD7A86E),
    phrases: [
      StarPhrase(
        text: '我想喝水',
        icon: Icons.local_drink_rounded,
        color: Color(0xFFD7A86E),
      ),
      StarPhrase(
        text: '我想吃饭',
        icon: Icons.rice_bowl_rounded,
        color: Color(0xFFD7A86E),
      ),
      StarPhrase(
        text: '请给我温水',
        icon: Icons.thermostat_rounded,
        color: Color(0xFFD7A86E),
      ),
      StarPhrase(
        text: '我不想吃了',
        icon: Icons.no_food_rounded,
        color: Color(0xFFD7A86E),
      ),
    ],
  ),
  _StarExpressionGroup(
    title: '如厕',
    icon: Icons.wc_rounded,
    color: Color(0xFF7A9E9F),
    phrases: [
      StarPhrase(
        text: '我想上厕所',
        icon: Icons.wc_rounded,
        color: Color(0xFF7A9E9F),
      ),
      StarPhrase(
        text: '请带我去卫生间',
        icon: Icons.accessible_forward_rounded,
        color: Color(0xFF7A9E9F),
      ),
      StarPhrase(
        text: '请等我一下',
        icon: Icons.hourglass_bottom_rounded,
        color: Color(0xFF7A9E9F),
      ),
      StarPhrase(
        text: '我需要纸巾',
        icon: Icons.clean_hands_rounded,
        color: Color(0xFF7A9E9F),
      ),
    ],
  ),
  _StarExpressionGroup(
    title: '求助',
    icon: Icons.volunteer_activism_rounded,
    color: Color(0xFF8D9DC2),
    phrases: [
      StarPhrase(
        text: '请帮我一下',
        icon: Icons.volunteer_activism_rounded,
        color: Color(0xFF8D9DC2),
      ),
      StarPhrase(
        text: '请扶我一下',
        icon: Icons.accessibility_new_rounded,
        color: Color(0xFF8D9DC2),
      ),
      StarPhrase(
        text: '请写下来',
        icon: Icons.edit_note_rounded,
        color: Color(0xFF8D9DC2),
      ),
      StarPhrase(
        text: '请再说一遍',
        icon: Icons.replay_rounded,
        color: Color(0xFF8D9DC2),
      ),
    ],
  ),
  _StarExpressionGroup(
    title: '家人',
    icon: Icons.family_restroom_rounded,
    color: Color(0xFFD08C60),
    phrases: [
      StarPhrase(
        text: '我想联系家人',
        icon: Icons.contact_phone_rounded,
        color: Color(0xFFD08C60),
      ),
      StarPhrase(
        text: '请叫家人过来',
        icon: Icons.groups_rounded,
        color: Color(0xFFD08C60),
      ),
      StarPhrase(
        text: '我想回家',
        icon: Icons.home_rounded,
        color: Color(0xFFD08C60),
      ),
      StarPhrase(
        text: '请告诉家人我没事',
        icon: Icons.favorite_rounded,
        color: Color(0xFFD08C60),
      ),
    ],
  ),
  _StarExpressionGroup(
    title: '医院',
    icon: Icons.local_hospital_rounded,
    color: Color(0xFF4E8FD8),
    phrases: [
      StarPhrase(
        text: '我想问医生',
        icon: Icons.medical_services_rounded,
        color: Color(0xFF4E8FD8),
      ),
      StarPhrase(
        text: '我什么时候吃药',
        icon: Icons.medication_rounded,
        color: Color(0xFF4E8FD8),
      ),
      StarPhrase(
        text: '请帮我叫护士',
        icon: Icons.local_hospital_rounded,
        color: Color(0xFF4E8FD8),
      ),
      StarPhrase(
        text: '我想做康复训练',
        icon: Icons.fitness_center_rounded,
        color: Color(0xFF4E8FD8),
      ),
    ],
  ),
  _StarExpressionGroup(
    title: '情绪',
    icon: Icons.sentiment_satisfied_alt_rounded,
    color: Color(0xFF9B8DD7),
    phrases: [
      StarPhrase(
        text: '我有点着急',
        icon: Icons.sentiment_very_dissatisfied_rounded,
        color: Color(0xFF9B8DD7),
      ),
      StarPhrase(
        text: '我有点害怕',
        icon: Icons.front_hand_rounded,
        color: Color(0xFF9B8DD7),
      ),
      StarPhrase(
        text: '我现在好多了',
        icon: Icons.sentiment_satisfied_alt_rounded,
        color: Color(0xFF9B8DD7),
      ),
      StarPhrase(
        text: '谢谢你',
        icon: Icons.favorite_border_rounded,
        color: Color(0xFF9B8DD7),
      ),
    ],
  ),
  _StarExpressionGroup(
    title: '常用句',
    icon: Icons.chat_bubble_rounded,
    color: Color(0xFF6EA8A1),
    phrases: [
      StarPhrase(
        text: '请慢一点',
        icon: Icons.speed_rounded,
        color: Color(0xFF6EA8A1),
      ),
      StarPhrase(
        text: '我听不清',
        icon: Icons.hearing_disabled_rounded,
        color: Color(0xFF6EA8A1),
      ),
      StarPhrase(
        text: '我不知道',
        icon: Icons.help_outline_rounded,
        color: Color(0xFF6EA8A1),
      ),
      StarPhrase(
        text: '请给我一点时间',
        icon: Icons.timer_rounded,
        color: Color(0xFF6EA8A1),
      ),
    ],
  ),
];

class _StarSpeakSheet extends StatefulWidget {
  const _StarSpeakSheet({
    required this.phrases,
    required this.onSpeak,
  });

  final List<StarPhrase> phrases;
  final Future<void> Function(StarPhrase phrase) onSpeak;

  @override
  State<_StarSpeakSheet> createState() => _StarSpeakSheetState();
}

class _StarSpeakSheetState extends State<_StarSpeakSheet> {
  static const String _contactStorageKey = 'star_family_contact_v1';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  _StarSpeakView _view = _StarSpeakView.quick;
  _StarFamilyContact? _contact;
  String _speakingText = '';
  bool _loadingContact = true;
  bool _savingContact = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContact());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadContact() async {
    final raw = await SensitiveLocalStore.readString(
      _contactStorageKey,
      legacySharedPreferencesKey: _contactStorageKey,
    );
    final contact = _StarFamilyContact.fromJson(raw);
    if (!mounted) return;
    setState(() {
      _contact = contact;
      _loadingContact = false;
    });
  }

  Future<void> _saveContact() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final message = _messageController.text.trim();
    if (name.isEmpty) {
      _showLocalMessage('请先填写家属姓名');
      return;
    }
    setState(() => _savingContact = true);
    final contact = _StarFamilyContact(
      name: name,
      phone: phone,
      message: message.isEmpty ? '请帮我联系家人' : message,
    );
    await SensitiveLocalStore.writeString(
      _contactStorageKey,
      jsonEncode(contact.toJson()),
    );
    if (!mounted) return;
    setState(() {
      _contact = contact;
      _savingContact = false;
      _view = _StarSpeakView.familyConfirm;
    });
  }

  void _showLocalMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          duration: const Duration(milliseconds: 950),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2E3038).withValues(alpha: .92),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
  }

  Future<void> _handleSpeak(StarPhrase phrase) async {
    if (_speakingText.isNotEmpty) return;
    setState(() => _speakingText = phrase.text);
    try {
      await widget.onSpeak(phrase);
    } finally {
      if (mounted) {
        setState(() => _speakingText = '');
      }
    }
  }

  void _openFamilyContact() {
    if (_loadingContact) return;
    final contact = _contact;
    if (contact == null) {
      _nameController.clear();
      _phoneController.clear();
      _messageController.text = '请帮我联系家人';
      setState(() => _view = _StarSpeakView.familySetup);
      return;
    }
    setState(() => _view = _StarSpeakView.familyConfirm);
  }

  void _editFamilyContact() {
    final contact = _contact;
    _nameController.text = contact?.name ?? '';
    _phoneController.text = contact?.phone ?? '';
    _messageController.text = contact?.message ?? '请帮我联系家人';
    setState(() => _view = _StarSpeakView.familySetup);
  }

  Future<void> _speakFamilyHelp() async {
    final contact = _contact;
    if (contact == null) {
      _openFamilyContact();
      return;
    }
    await _handleSpeak(
      StarPhrase(
        text: contact.message,
        icon: Icons.contact_phone_rounded,
        color: const Color(0xFFD08C60),
      ),
    );
  }

  Future<void> _copyPhone() async {
    final phone = _contact?.phone.trim() ?? '';
    if (phone.isEmpty) {
      _showLocalMessage('还没有填写电话');
      return;
    }
    await Clipboard.setData(ClipboardData(text: phone));
    _showLocalMessage('已复制电话：$phone');
  }

  Future<void> _callFamilyContact() async {
    final rawPhone = _contact?.phone.trim() ?? '';
    final phone = _dialablePhoneNumber(rawPhone);
    if (phone.isEmpty) {
      _showLocalMessage('请先填写家属电话');
      _editFamilyContact();
      return;
    }
    HapticFeedback.mediumImpact();
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        _showLocalMessage('当前设备无法打开电话');
      }
    } catch (_) {
      _showLocalMessage('拨号失败，请检查电话应用');
    }
  }

  String _dialablePhoneNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];
      final isDigit = char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
      if (isDigit || (char == '+' && buffer.isEmpty)) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  String get _title {
    return switch (_view) {
      _StarSpeakView.quick => '星语',
      _StarSpeakView.board => '更多表达',
      _StarSpeakView.familySetup => '配置家人',
      _StarSpeakView.familyConfirm => '联系家人',
    };
  }

  String get _subtitle {
    return switch (_view) {
      _StarSpeakView.quick => '选一句你想说的话',
      _StarSpeakView.board => '按场景点一句，马上播报',
      _StarSpeakView.familySetup => '先保存一个最常联系的人',
      _StarSpeakView.familyConfirm => '确认后播报求助句',
    };
  }

  bool get _canGoBack => _view != _StarSpeakView.quick;

  void _goBack() {
    if (_view == _StarSpeakView.familyConfirm) {
      setState(() => _view = _StarSpeakView.quick);
      return;
    }
    setState(() => _view = _StarSpeakView.quick);
  }

  Widget _buildCurrentView() {
    return switch (_view) {
      _StarSpeakView.quick => _buildQuickView(),
      _StarSpeakView.board => _buildExpressionBoard(),
      _StarSpeakView.familySetup => _buildFamilySetup(),
      _StarSpeakView.familyConfirm => _buildFamilyConfirm(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final panelWidth = math.min(media.size.width - 24, 440.0);
    final panelMaxHeight = math.max(
      460.0,
      media.size.height - media.padding.top - media.padding.bottom - 48.0,
    );
    return SafeArea(
      minimum: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: panelWidth,
                maxHeight: panelMaxHeight,
              ),
              child: Container(
                width: panelWidth,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .90),
                  borderRadius: BorderRadius.circular(34),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .90)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7E8BA3).withValues(alpha: .22),
                      blurRadius: 38,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StarSheetHeader(
                        title: _title,
                        subtitle: _subtitle,
                        canGoBack: _canGoBack,
                        onBack: _goBack,
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey<_StarSpeakView>(_view),
                          child: _buildCurrentView(),
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
  }

  Widget _buildQuickView() {
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.phrases.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.16,
          ),
          itemBuilder: (context, index) {
            final phrase = widget.phrases[index];
            return _StarPhraseCard(
              phrase: phrase,
              speaking: _speakingText == phrase.text,
              disabled:
                  _speakingText.isNotEmpty && _speakingText != phrase.text,
              onTap: () => _handleSpeak(phrase),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StarBoardActionButton(
                icon: Icons.apps_rounded,
                label: '更多表达',
                onTap: () => setState(() => _view = _StarSpeakView.board),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StarBoardActionButton(
                icon: Icons.contact_phone_rounded,
                label: '联系家人',
                onTap: _openFamilyContact,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpressionBoard() {
    return Column(
      children: [
        for (final group in _starExpressionGroups) ...[
          _StarExpressionGroupCard(
            group: group,
            speakingText: _speakingText,
            onSpeak: _handleSpeak,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildFamilySetup() {
    return Column(
      children: [
        _StarTextField(
          controller: _nameController,
          label: '家属姓名',
          hint: '例如：女儿、小王、妈妈',
          icon: Icons.person_rounded,
        ),
        const SizedBox(height: 12),
        _StarTextField(
          controller: _phoneController,
          label: '电话',
          hint: '可选，先保存备用',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _StarTextField(
          controller: _messageController,
          label: '求助句',
          hint: '例如：请帮我联系家人',
          icon: Icons.record_voice_over_rounded,
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _savingContact ? null : _saveContact,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: const Color(0xFFD08C60),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: _savingContact
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _savingContact ? '保存中' : '保存并继续',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyConfirm() {
    final contact = _contact;
    if (_loadingContact) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFD08C60)),
        ),
      );
    }
    if (contact == null) {
      return Column(
        children: [
          const _StarEmptyNotice(
            icon: Icons.contact_phone_rounded,
            text: '还没有配置联系人',
          ),
          const SizedBox(height: 14),
          _StarBoardActionButton(
            icon: Icons.add_rounded,
            label: '现在配置',
            onTap: _editFamilyContact,
          ),
        ],
      );
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1E7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: .86)),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Color(0xFFD08C60),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.contact_phone_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2E3038),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contact.phone.isEmpty ? '未填写电话' : contact.phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7D6C5E),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _editFamilyContact,
                icon: const Icon(Icons.edit_rounded),
                color: const Color(0xFF7D6C5E),
                tooltip: '修改联系人',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StarFamilyMessageCard(
          message: contact.message,
          speaking: _speakingText == contact.message,
          onSpeak: _speakFamilyHelp,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StarBoardActionButton(
                icon: Icons.call_rounded,
                label: '拨打电话',
                onTap: _callFamilyContact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StarBoardActionButton(
                icon: Icons.volume_up_rounded,
                label: '播报求助',
                onTap: _speakFamilyHelp,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _StarBoardActionButton(
            icon: Icons.copy_rounded,
            label: '复制电话',
            onTap: _copyPhone,
          ),
        ),
      ],
    );
  }
}

class _StarSheetHeader extends StatelessWidget {
  const _StarSheetHeader({
    required this.title,
    required this.subtitle,
    required this.canGoBack,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final bool canGoBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (canGoBack) ...[
          _StarCircleButton(
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
          ),
          const SizedBox(width: 10),
        ] else
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE2A8),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB43F).withValues(alpha: .18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF2E3038),
              size: 28,
            ),
          ),
        if (!canGoBack) const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2E3038),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7D8490),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StarExpressionGroupCard extends StatelessWidget {
  const _StarExpressionGroupCard({
    required this.group,
    required this.speakingText,
    required this.onSpeak,
  });

  final _StarExpressionGroup group;
  final String speakingText;
  final Future<void> Function(StarPhrase phrase) onSpeak;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: group.color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .82)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(group.icon, size: 22, color: group.color),
              const SizedBox(width: 8),
              Text(
                group.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2E3038),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: group.phrases.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              childAspectRatio: 1.82,
            ),
            itemBuilder: (context, index) {
              final phrase = group.phrases[index];
              return _StarMiniPhraseButton(
                phrase: phrase,
                speaking: speakingText == phrase.text,
                disabled:
                    speakingText.isNotEmpty && speakingText != phrase.text,
                onTap: () => onSpeak(phrase),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StarPhraseCard extends StatelessWidget {
  const _StarPhraseCard({
    required this.phrase,
    required this.speaking,
    required this.disabled,
    required this.onTap,
  });

  final StarPhrase phrase;
  final bool speaking;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: speaking ? 1.035 : 1,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: disabled
                ? const Color(0xFFF0F1F4)
                : phrase.color.withValues(alpha: speaking ? .25 : .16),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color:
                  speaking ? phrase.color : Colors.white.withValues(alpha: .84),
              width: speaking ? 2.2 : 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: phrase.color.withValues(alpha: speaking ? .22 : .10),
                blurRadius: speaking ? 22 : 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: disabled ? .50 : .78),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: .9)),
                ),
                child: Icon(
                  speaking ? Icons.volume_up_rounded : phrase.icon,
                  color: disabled
                      ? const Color(0xFF9AA0AA)
                      : const Color(0xFF2E3038),
                  size: 27,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  phrase.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: phrase.text.length <= 2 ? 27 : 22,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                    color: disabled
                        ? const Color(0xFF9AA0AA)
                        : const Color(0xFF2E3038),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StarMiniPhraseButton extends StatelessWidget {
  const _StarMiniPhraseButton({
    required this.phrase,
    required this.speaking,
    required this.disabled,
    required this.onTap,
  });

  final StarPhrase phrase;
  final bool speaking;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: disabled
              ? const Color(0xFFF1F1F1)
              : Colors.white.withValues(alpha: speaking ? .96 : .70),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: speaking
                ? phrase.color
                : Colors.white.withValues(alpha: disabled ? .45 : .82),
            width: speaking ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              speaking ? Icons.volume_up_rounded : phrase.icon,
              color: disabled ? const Color(0xFFA9A9A9) : phrase.color,
              size: 22,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                phrase.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  color: disabled
                      ? const Color(0xFFA9A9A9)
                      : const Color(0xFF2E3038),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarFamilyMessageCard extends StatelessWidget {
  const _StarFamilyMessageCard({
    required this.message,
    required this.speaking,
    required this.onSpeak,
  });

  final String message;
  final bool speaking;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSpeak,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: speaking
              ? const Color(0xFFD08C60).withValues(alpha: .18)
              : Colors.white.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: speaking
                ? const Color(0xFFD08C60)
                : Colors.white.withValues(alpha: .86),
            width: speaking ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              speaking
                  ? Icons.volume_up_rounded
                  : Icons.record_voice_over_rounded,
              color: const Color(0xFFD08C60),
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2E3038),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarTextField extends StatelessWidget {
  const _StarTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: Color(0xFF2E3038),
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFFD08C60)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: .72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .86)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .86)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFD08C60), width: 2),
        ),
      ),
    );
  }
}

class _StarEmptyNotice extends StatelessWidget {
  const _StarEmptyNotice({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: const Color(0xFFD08C60)),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2E3038),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarCircleButton extends StatelessWidget {
  const _StarCircleButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .70),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: .86)),
        ),
        child: Icon(icon, color: const Color(0xFF2E3038)),
      ),
    );
  }
}

class _StarBoardActionButton extends StatelessWidget {
  const _StarBoardActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F5F1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .86)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF4E5A6A)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF4E5A6A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
