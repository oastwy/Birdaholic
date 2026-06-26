import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/species.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../widgets/audio_player_widget.dart';

/// 听声每日挑战：每天 5 道「听鸟鸣选鸟种」选择题（按日期固定，纯单机、不涉社交）。
class SoundChallengeScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  const SoundChallengeScreen({
    super.key,
    required this.packManager,
    required this.storage,
  });

  @override
  State<SoundChallengeScreen> createState() => _SoundChallengeScreenState();
}

class _Question {
  final Species species;
  final String audioPath;
  final String audioLabel;
  final String spectrogramPath; // 本地路径或网络 URL，空表示无声谱图
  final List<String> options; // 含正确答案的中文名
  const _Question({
    required this.species,
    required this.audioPath,
    required this.audioLabel,
    required this.spectrogramPath,
    required this.options,
  });
}

class _SoundChallengeScreenState extends State<SoundChallengeScreen> {
  static const _count = 5;
  static const _green = Color(0xFF2d5016);

  bool _loading = true;
  String? _error;
  List<_Question> _questions = const [];
  int _idx = 0;
  String? _selected;
  bool _answered = false;
  int _score = 0;
  bool _finished = false;
  bool _countsToday = true;

  final _audioKey = GlobalKey<AudioPlayerWidgetState>();

  @override
  void initState() {
    super.initState();
    _countsToday = !widget.storage.soundChallengeDoneToday;
    _prepare();
  }

  @override
  void dispose() {
    _audioKey.currentState?.stop();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final all = await widget.packManager.loadSpecies();
      final withAudio = <(Species, String, String, String)>[];
      for (final s in all) {
        if (s.audios.isEmpty || s.cn.isEmpty) continue;
        for (final a in s.audios) {
          final p = await widget.packManager.getResourcePath(a.file);
          if (p != null) {
            var spec = '';
            if (a.spectrogram.isNotEmpty) {
              final lp =
                  await widget.packManager.getResourcePath(a.spectrogram);
              if (lp != null) spec = lp;
            }
            if (spec.isEmpty && a.spectrogramUrl.isNotEmpty) {
              spec = a.spectrogramUrl;
            }
            withAudio.add((s, p, a.displayLabel, spec));
            break;
          }
        }
      }
      if (withAudio.length < 4) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '带鸟鸣的鸟种太少（至少要 4 种）。\n去「设置 → 数据包管理 → 更新已下载媒体」补充鸟鸣后再来。';
        });
        return;
      }
      // 按日期固定今天的题目与顺序
      final now = DateTime.now();
      final rnd = Random(now.year * 10000 + now.month * 100 + now.day);
      final pool = List.of(withAudio)..shuffle(rnd);
      final n = withAudio.length < _count ? withAudio.length : _count;
      final qs = <_Question>[];
      for (var i = 0; i < n; i++) {
        final (sp, path, label, spec) = pool[i];
        final distractors = _pickDistractors(sp, all, rnd);
        final options = [sp.cn, ...distractors]..shuffle(rnd);
        qs.add(_Question(
          species: sp,
          audioPath: path,
          audioLabel: label,
          spectrogramPath: spec,
          options: options,
        ));
      }
      if (!mounted) return;
      setState(() {
        _questions = qs;
        _loading = false;
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _audioKey.currentState?.autoPlay());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  String _genusOf(Species s) {
    final parts = s.sci.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  /// 干扰项尽量取关系近的物种：同属 > 同科 > 同目 > 全局，去重后取 3 个中文名。
  List<String> _pickDistractors(Species sp, List<Species> all, Random rnd) {
    final used = <String>{sp.cn};
    final result = <String>[];
    void addFrom(Iterable<Species> items) {
      final list = items.where((s) => s.cn.isNotEmpty && used.add(s.cn)).toList()
        ..shuffle(rnd);
      result.addAll(list.map((s) => s.cn));
    }

    final genus = _genusOf(sp);
    if (genus.isNotEmpty) addFrom(all.where((s) => _genusOf(s) == genus));
    if (sp.family.trim().isNotEmpty) {
      addFrom(all.where((s) => s.family == sp.family));
    }
    if (sp.order.trim().isNotEmpty) {
      addFrom(all.where((s) => s.order == sp.order));
    }
    addFrom(all);
    return result.take(3).toList();
  }

  void _select(String name) {
    if (_answered) return;
    setState(() {
      _selected = name;
      _answered = true;
      if (name == _questions[_idx].species.cn) _score++;
    });
  }

  void _next() {
    _audioKey.currentState?.stop();
    if (_idx + 1 >= _questions.length) {
      if (_countsToday) {
        widget.storage.recordSoundChallenge(_score, _questions.length);
      }
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _idx++;
      _selected = null;
      _answered = false;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _audioKey.currentState?.autoPlay());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('听声辨鸟 · 每日挑战')),
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
              Icon(Icons.graphic_eq, size: 56, color: Colors.grey[350]),
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
              Text('得分 $_score',
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Icon(Icons.headphones, size: 40, color: _green),
        const SizedBox(height: 8),
        const Text('听这段鸟鸣，是哪种鸟？',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AudioPlayerWidget(
            key: _audioKey,
            audioPaths: [q.audioPath],
            audioLabels: [q.audioLabel],
          ),
        ),
        if (q.spectrogramPath.isNotEmpty) ...[
          const SizedBox(height: 12),
          _spectrogram(q.spectrogramPath),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (final opt in q.options) _optionTile(q, opt),
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
                child: Text(
                    _idx + 1 >= _questions.length ? '看结果' : '下一题'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 声谱图（看波形辅助辨声）。本地图或网络图都支持，加载失败则隐藏。
  Widget _spectrogram(String path) {
    final isNet = path.startsWith('http://') || path.startsWith('https://');
    final img = isNet
        ? Image.network(path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink())
        : Image.file(File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 120,
          width: double.infinity,
          child: ColoredBox(color: Colors.grey.shade100, child: img),
        ),
      ),
    );
  }

  Widget _optionTile(_Question q, String opt) {
    final correct = q.species.cn;
    Color? bg;
    Color border = Colors.grey.shade300;
    Widget? trailing;
    if (_answered) {
      if (opt == correct) {
        bg = Colors.green.withValues(alpha: 0.12);
        border = Colors.green;
        trailing = const Icon(Icons.check_circle, color: Colors.green);
      } else if (opt == _selected) {
        bg = Colors.red.withValues(alpha: 0.10);
        border = Colors.red;
        trailing = const Icon(Icons.cancel, color: Colors.red);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: _answered ? null : () => _select(opt),
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
        ? '耳力惊人！🎧'
        : ratio >= 0.5
            ? '不错，继续练就更熟了'
            : '鸟鸣需要多听，明天再来挑战';
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
            if (!_countsToday) ...[
              const SizedBox(height: 8),
              Text('（今天已挑战过，本次为练习，不计入记录）',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(backgroundColor: _green),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
