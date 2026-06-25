import 'dart:io';

import 'package:flutter/material.dart';

import 'personal_objects.dart';

class PersonalObjectEditSheet extends StatefulWidget {
  const PersonalObjectEditSheet({
    super.key,
    required this.initialName,
    required this.initialCategory,
    required this.initialDescription,
    required this.initialExpressions,
    this.initialNote = '',
    this.title = '记住这个物品',
  });

  final String title;
  final String initialName;
  final String initialCategory;
  final String initialDescription;
  final List<String> initialExpressions;
  final String initialNote;

  @override
  State<PersonalObjectEditSheet> createState() =>
      _PersonalObjectEditSheetState();
}

class _PersonalObjectEditSheetState extends State<PersonalObjectEditSheet> {
  static const _categories = [
    '饮食',
    '生活用品',
    '衣物',
    '电子设备',
    '钥匙证件',
    '康复用品',
    '其他',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _expressionsController;
  late final TextEditingController _noteController;
  late String _category;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController =
        TextEditingController(text: widget.initialDescription);
    _expressionsController =
        TextEditingController(text: widget.initialExpressions.join('、'));
    _noteController = TextEditingController(text: widget.initialNote);
    _category = _categories.contains(widget.initialCategory)
        ? widget.initialCategory
        : '其他';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _expressionsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameController.text.trim().isEmpty) return;
    final expressions = _expressionsController.text
        .split(RegExp(r'[、,，;；\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    Navigator.of(context).pop(
      PersonalObjectDraft(
        displayName: _nameController.text,
        category: _category,
        visualDescription: _descriptionController.text,
        commonExpressions: expressions,
        note: _noteController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: const Color(0xFFF7F8FB),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4D7DE),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 18),
                _field('名称', _nameController, hint: '例如：我的蓝色水杯'),
                const SizedBox(height: 14),
                const Text(
                  '类型',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: _inputDecoration(),
                  items: _categories
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _category = value ?? '其他'),
                ),
                const SizedBox(height: 14),
                _field(
                  '外观特征',
                  _descriptionController,
                  hint: '例如：蓝色杯身，白色杯盖',
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                _field(
                  '常用表达',
                  _expressionsController,
                  hint: '用顿号分隔，例如：我要喝水、帮我拿水杯',
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                _field('备注', _noteController, hint: '选填', maxLines: 2),
                const SizedBox(height: 14),
                const Text(
                  '参考照片保存在本机。再次拍照识别时，最多会选取 3 张相关参考照片发送给 Qwen 进行匹配。',
                  style: TextStyle(
                    color: Color(0xFF6E6E73),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      '保存个人物品',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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

  Widget _field(
    String label,
    TextEditingController controller, {
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          maxLines: maxLines,
          textInputAction:
              maxLines == 1 ? TextInputAction.next : TextInputAction.newline,
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration([String? hint]) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class PersonalObjectManagementPage extends StatefulWidget {
  const PersonalObjectManagementPage({
    super.key,
    required this.store,
    required this.onAdd,
    required this.onChanged,
  });

  final PersonalObjectStore store;
  final Future<void> Function() onAdd;
  final Future<void> Function() onChanged;

  @override
  State<PersonalObjectManagementPage> createState() =>
      _PersonalObjectManagementPageState();
}

class _PersonalObjectManagementPageState
    extends State<PersonalObjectManagementPage> {
  List<PersonalObject> _objects = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final objects = await widget.store.loadAll();
    if (!mounted) return;
    setState(() {
      _objects = objects;
      _loading = false;
    });
  }

  Future<void> _add() async {
    await widget.onAdd();
    await _reload();
  }

  Future<void> _edit(PersonalObject object) async {
    final draft = await showModalBottomSheet<PersonalObjectDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PersonalObjectEditSheet(
        title: '编辑个人物品',
        initialName: object.displayName,
        initialCategory: object.category,
        initialDescription: object.visualDescription,
        initialExpressions: object.commonExpressions,
        initialNote: object.note,
      ),
    );
    if (draft == null) return;
    await widget.store.update(object, draft);
    await widget.onChanged();
    await _reload();
  }

  Future<void> _delete(PersonalObject object) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${object.displayName}”？'),
        content: const Text('参考照片和物品信息会从本机删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.delete(object);
    await widget.onChanged();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('我的物品'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '拍照添加',
            onPressed: _add,
            icon: const Icon(Icons.add_a_photo_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _objects.isEmpty
              ? _EmptyPersonalObjects(onAdd: _add)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: _objects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final object = _objects[index];
                    final imageFile = File(object.referenceImagePath);
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _edit(object),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 76,
                                  height: 76,
                                  child: imageFile.existsSync()
                                      ? Image.file(imageFile, fit: BoxFit.cover)
                                      : const ColoredBox(
                                          color: Color(0xFFE8EBF2),
                                          child:
                                              Icon(Icons.inventory_2_rounded),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      object.displayName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      object.category,
                                      style: const TextStyle(
                                        color: Color(0xFF6E6E73),
                                      ),
                                    ),
                                    if (object
                                        .commonExpressions.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        object.commonExpressions
                                            .take(2)
                                            .join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF8E8E93),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) => value == 'edit'
                                    ? _edit(object)
                                    : _delete(object),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('编辑')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('删除')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _EmptyPersonalObjects extends StatelessWidget {
  const _EmptyPersonalObjects({required this.onAdd});

  final Future<void> Function() onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 54,
              color: Color(0xFF7A93FF),
            ),
            const SizedBox(height: 14),
            const Text(
              '还没有个人物品',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '拍摄水杯、钥匙或背包，识别后可以设置专属名称和常用表达。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6E6E73), height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('拍照添加'),
            ),
          ],
        ),
      ),
    );
  }
}
