import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../services/pack_manager.dart';
import '../services/storage.dart';

/// 中国鸟选择题：看图选鸟种（4 选 1）。题库来自 assets/data/china_quiz_bank.json
/// （由 packager/build_china_quiz_bank.py 离线生成，覆盖中国 ~1490 种里有图的种）。
/// 纯单机练习、不涉社交。
class ChinaQuizScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  const ChinaQuizScreen({
    super.key,
    required this.packManager,
    required this.storage,
  });

  @override
  State<ChinaQuizScreen> createState() => _ChinaQuizScreenState();
}

class _Question {
  final String zh;
  final String imageUrl;
  final List<String> options;
  final int answer; // options 里正确项的下标
  const _Question({
    required this.zh,
    required this.imageUrl,
    required this.options,
    required this.answer,
  });

  factory _Question.fromJson(Map<String, dynamic> j) => _Question(
        zh: (j['zh'] as String?) ?? '',
        imageUrl: (j['image_url'] as String?) ?? '',
        options: ((j['options'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        answer: (j['answer'] as num?)?.toInt() ?? 0,
      );
}

class _ChinaQuizScreenState extends State<ChinaQuizScreen> {
  static const _green = Color(0xFF2d5016);
  static const _sessionCount = 10;

  bool _loading = true;
  String? _error;
  List<_Question> _questions = const [];
  int _idx = 0;
  int? _selected;
  bool _answered = false;
  int _score = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final raw = await rootBundle.loadString('assets/data/china_quiz_bank.json');
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(_Question.fromJson)
          .where((q) =>
              q.imageUrl.isNotEmpty && q.options.length == 4 && q.zh.isNotEmpty)
          .toList();
      if (list.length < 4) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '题库为空或损坏。';
        });
        return;
      }
      final rnd = Random();
      list.shuffle(rnd);
      final n = list.length < _sessionCount ? list.length : _sessionCount;
      if (!mounted) return;
      setState(() {
        _questions = list.take(n).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载题库失败：$e';
      });
    }
  }

  void _select(int i) {
    if (_answered) return;
    setState(() {
      _selected = i;
      _answered = true;
      if (i == _questions[_idx].answer) _score++;
    });
  }

  void _next() {
    if (_idx + 1 >= _questions.length) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _idx++;
      _selected = null;
      _answered = false;
    });
  }

  void _restart() {
    setState(() {
      _idx = 0;
      _selected = null;
      _answered = false;
      _score = 0;
      _finished = false;
      _loading = true;
    });
    _prepare();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('中国鸟选择题')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _finished
                  ? _buildResult()
                  : _buildQuestion(),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined,
                  size: 56, color: Colors.grey[350]),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
          ),
        ),
      );

  Widget _buildQuestion() {
    final q = _questions[_idx];
    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('第 ${_idx + 1} / ${_questions.length} 题',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('得分 $_score', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                q.imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Colors.grey.withValues(alpha: 0.08),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stack) => Container(
                  color: Colors.grey.withValues(alpha: 0.08),
                  child: Icon(Icons.broken_image_outlined,
                      size: 48, color: Colors.grey[400]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('这是哪种鸟？',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (var i = 0; i < q.options.length; i++) _optionTile(q, i),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _answered ? _next : null,
                style: FilledButton.styleFrom(backgroundColor: _green),
                child:
                    Text(_idx + 1 >= _questions.length ? '看结果' : '下一题'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionTile(_Question q, int i) {
    final opt = q.options[i];
    Color? bg;
    Color border = Colors.grey.shade300;
    Widget? trailing;
    if (_answered) {
      if (i == q.answer) {
        bg = Colors.green.withValues(alpha: 0.12);
        border = Colors.green;
        trailing = const Icon(Icons.check_circle, color: Colors.green);
      } else if (i == _selected) {
        bg = Colors.red.withValues(alpha: 0.10);
        border = Colors.red;
        trailing = const Icon(Icons.cancel, color: Colors.red);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: _answered ? null : () => _select(i),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1.4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(opt,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    final total = _questions.length;
    final ratio = total == 0 ? 0.0 : _score / total;
    final msg = ratio >= 0.8
        ? '辨识高手！👏'
        : ratio >= 0.5
            ? '不错，多练几组更熟'
            : '看图认鸟需要积累，继续加油';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ratio >= 0.8 ? Icons.emoji_events : Icons.military_tech,
                size: 64, color: ratio >= 0.8 ? Colors.amber[700] : _green),
            const SizedBox(height: 14),
            Text('$_score / $total',
                style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.w800, color: _green)),
            const SizedBox(height: 8),
            Text(msg, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _restart,
                style: FilledButton.styleFrom(backgroundColor: _green),
                child: const Text('再来一组'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
