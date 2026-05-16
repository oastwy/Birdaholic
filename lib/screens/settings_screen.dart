import 'package:flutter/material.dart';

import '../services/storage.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storage;
  final VoidCallback? onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.storage,
    this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _groupController;
  late int _groupSize;

  @override
  void initState() {
    super.initState();
    _groupSize = widget.storage.flashcardGroupSize;
    _groupController = TextEditingController(text: '$_groupSize');
  }

  @override
  void dispose() {
    _groupController.dispose();
    super.dispose();
  }

  Future<void> _setGroupSize(int value) async {
    final normalized = value.clamp(1, 100);
    await widget.storage.setFlashcardGroupSize(normalized);
    if (!mounted) return;
    setState(() {
      _groupSize = normalized;
      _groupController.text = '$normalized';
    });
    widget.onSettingsChanged?.call();
  }

  Future<void> _applyCustomGroupSize() async {
    final value = int.tryParse(_groupController.text.trim());
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 1-100 之间的数字')),
      );
      return;
    }
    await _setGroupSize(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已设置每组 $_groupSize 张')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.style_outlined, color: Color(0xFF2d5016)),
                    SizedBox(width: 8),
                    Text(
                      '闪卡设置',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('每组卡片数量'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('10 张'),
                      selected: _groupSize == 10,
                      onSelected: (_) => _setGroupSize(10),
                    ),
                    ChoiceChip(
                      label: const Text('20 张'),
                      selected: _groupSize == 20,
                      onSelected: (_) => _setGroupSize(20),
                    ),
                    ChoiceChip(
                      label: const Text('30 张'),
                      selected: _groupSize == 30,
                      onSelected: (_) => _setGroupSize(30),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _groupController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '自定义',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _applyCustomGroupSize(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _applyCustomGroupSize,
                      child: const Text('应用'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '当前每组 $_groupSize 张。修改后重新进入或刷新闪卡会按新组数推进。',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const AboutScreen(embedded: true),
      ],
    );
  }
}
