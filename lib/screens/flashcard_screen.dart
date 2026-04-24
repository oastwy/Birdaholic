import 'dart:math';

import 'package:flutter/material.dart';

import '../models/species.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/bird_card.dart';

/// 闪卡模式页面
class FlashcardScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  final int refreshToken;
  final bool isActive;

  const FlashcardScreen({
    super.key,
    required this.packManager,
    required this.storage,
    required this.refreshToken,
    required this.isActive,
  });

  @override
  State<FlashcardScreen> createState() => FlashcardScreenState();
}

class FlashcardScreenState extends State<FlashcardScreen> {
  List<Species> _allSpecies = [];
  List<Species> _deck = [];
  int _idx = 0;
  bool _revealed = false;
  bool _answered = false;
  bool _loading = true;
  String? _loadError;
  int _correctCount = 0;
  int _wrongCount = 0;

  String _filter = 'all';
  String _order = 'random';
  StudyMode _mode = StudyMode.review;

  final _cardKey = GlobalKey<BirdCardState>();
  final _audioKey = GlobalKey<AudioPlayerWidgetState>();

  @override
  void initState() {
    super.initState();
    _loadSpecies();
  }

  @override
  void didUpdateWidget(covariant FlashcardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        (!oldWidget.isActive && widget.isActive)) {
      _loadSpecies();
    }
  }

  Future<void> _loadSpecies() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final list = await widget.packManager.loadSpecies();
      if (!mounted) return;
      setState(() {
        _allSpecies = list;
        _loading = false;
      });
      _buildDeck();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allSpecies = [];
        _deck = [];
        _idx = 0;
        _revealed = false;
        _answered = false;
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  void _scheduleAutoPlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentBird == null || _isFinished) return;
      _audioKey.currentState?.autoPlay();
    });
  }

  void _resetCardFace() {
    _cardKey.currentState?.showFront();
    _revealed = false;
    _answered = false;
  }

  void _buildDeck() {
    var list = <Species>[..._allSpecies];

    switch (_filter) {
      case 'audio':
        list = list.where((s) => s.hasAudio).toList();
        break;
      case 'g1':
        list = list.where((s) => s.isGrade1).toList();
        break;
      case 'g2':
        list = list.where((s) => s.isGrade2).toList();
        break;
      case 'favorites':
        final favs = widget.storage.getFavorites();
        list = list.where((s) => favs.contains(s.cn)).toList();
        break;
      case 'unfamiliar':
        final unfamiliar = widget.storage.getUnfamiliarSpecies();
        list = list.where((s) => unfamiliar.contains(s.cn)).toList();
        break;
    }

    switch (_order) {
      case 'seq':
        int grade(Species s) => s.isGrade1 ? 0 : s.isGrade2 ? 1 : 2;
        list.sort((a, b) => grade(a).compareTo(grade(b)));
        break;
      case 'alpha':
        list.sort((a, b) => a.cn.compareTo(b.cn));
        break;
      case 'random':
      default:
        list.shuffle(Random());
        break;
    }

    setState(() {
      _deck = list;
      _idx = 0;
      _resetCardFace();
    });

    if (_deck.isNotEmpty) {
      _scheduleAutoPlay();
    }
  }

  Species? get _currentBird => _deck.isEmpty ? null : _deck[_idx];

  int get _remaining => _deck.isEmpty ? 0 : _deck.length - _idx - 1;

  bool get _isFinished => _deck.isNotEmpty && _idx == _deck.length - 1 && _answered;

  String get _deckSummary {
    switch (_filter) {
      case 'audio':
        return '当前牌组只包含可播放音频的鸟种';
      case 'g1':
        return '当前牌组聚焦国家一级保护鸟种';
      case 'g2':
        return '当前牌组聚焦国家二级保护鸟种';
      case 'favorites':
        return '当前牌组来自你的收藏';
      case 'unfamiliar':
        return '当前牌组用于强化不熟悉鸟种';
      default:
        return '当前牌组包含本数据包中的全部鸟种';
    }
  }

  Future<List<String>> _getAudioPaths() async {
    final bird = _currentBird;
    if (bird == null) return [];
    final paths = <String>[];
    for (final a in bird.audios) {
      final p = await widget.packManager.getResourcePath(a.file);
      if (p != null) paths.add(p);
    }
    return paths;
  }

  Future<String?> _getImagePath() async {
    final bird = _currentBird;
    if (bird == null || bird.image == null) return null;
    return widget.packManager.getResourcePath(bird.image!);
  }

  void _jumpToSpecies(Species target) {
    final di = _deck.indexWhere((s) => s.sci == target.sci);
    if (di >= 0) {
      setState(() {
        _idx = di;
        _resetCardFace();
      });
      _scheduleAutoPlay();
      return;
    }

    if (_allSpecies.any((s) => s.sci == target.sci)) {
      setState(() {
        _filter = 'all';
        _order = 'alpha';
      });
      _buildDeck();
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToSpecies(target));
    }
  }

  void _markCorrect() {
    if (_answered) return;
    final bird = _currentBird;
    if (bird == null) return;

    _answered = true;
    _correctCount++;
    widget.storage.markCorrect();
    widget.storage.markSpeciesKnown(bird.cn);

    setState(() {});

    if (!_revealed) {
      _reveal();
    }

    if (!_isFinished) {
      Future.delayed(const Duration(seconds: 1), _nextCard);
    }
  }

  void _markWrong() {
    if (_answered) return;
    final bird = _currentBird;
    if (bird == null) return;

    _answered = true;
    _wrongCount++;
    widget.storage.markWrong();
    widget.storage.markSpeciesUnknown(bird.cn);

    setState(() {});

    if (!_revealed) {
      _reveal();
    }

    if (!_isFinished) {
      Future.delayed(const Duration(milliseconds: 2500), _nextCard);
    }
  }

  void _nextCard() {
    if (_deck.isEmpty || _idx >= _deck.length - 1) return;
    setState(() {
      _idx++;
      _resetCardFace();
    });
    _scheduleAutoPlay();
  }

  void _reveal() {
    _revealed = !_revealed;
    _cardKey.currentState?.reveal();
    setState(() {});
  }

  void _toggleFav() {
    final bird = _currentBird;
    if (bird == null) return;
    widget.storage.toggleFavorite(bird.cn);
    setState(() {});
  }

  void startSession({
    required String filter,
    required StudyMode mode,
    String order = 'random',
  }) {
    setState(() {
      _filter = filter;
      _mode = mode;
      _order = order;
      _correctCount = 0;
      _wrongCount = 0;
    });
    _buildDeck();
  }

  void _restart() {
    setState(() {
      _correctCount = 0;
      _wrongCount = 0;
    });
    widget.storage.resetStats();
    _buildDeck();
  }

  /// 提供给外部跳转
  void jumpTo(Species target) => _jumpToSpecies(target);

  @override
  Widget build(BuildContext context) {
    final bird = _currentBird;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('模式:', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  SegmentedButton<StudyMode>(
                    segments: const [
                      ButtonSegment(
                        value: StudyMode.review,
                        label: Text('🧠 复习', style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: StudyMode.preview,
                        label: Text('📖 学习', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) {
                      setState(() {
                        _mode = v.first;
                        _correctCount = 0;
                        _wrongCount = 0;
                      });
                      _buildDeck();
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('筛选:', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 32,
                    child: DropdownButton<String>(
                      value: _filter,
                      isDense: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('全部')),
                        DropdownMenuItem(value: 'audio', child: Text('有效音频')),
                        DropdownMenuItem(value: 'g1', child: Text('一级')),
                        DropdownMenuItem(value: 'g2', child: Text('二级')),
                        DropdownMenuItem(value: 'favorites', child: Text('⭐ 收藏')),
                        DropdownMenuItem(value: 'unfamiliar', child: Text('📚 不熟悉')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _filter = v);
                        _buildDeck();
                      },
                    ),
                  ),
                  const Spacer(),
                  const Text('顺序:', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 32,
                    child: DropdownButton<String>(
                      value: _order,
                      isDense: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'random', child: Text('随机')),
                        DropdownMenuItem(value: 'seq', child: Text('按等级')),
                        DropdownMenuItem(value: 'alpha', child: Text('拼音')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _order = v);
                        _buildDeck();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_deck.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_idx + 1}/${_deck.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                Text('✓ $_correctCount', style: const TextStyle(color: Colors.green)),
                const SizedBox(width: 8),
                Text('✗ $_wrongCount', style: const TextStyle(color: Colors.red)),
                const SizedBox(width: 8),
                Text('剩余 $_remaining', style: TextStyle(color: Colors.grey[600])),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '📚 ${widget.storage.unfamiliarCount}',
                    style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                  ),
                ),
              ],
            ),
          ),
        if (_deck.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _deckSummary,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ),
        Expanded(
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : _loadError != null
                    ? _buildMissingPackView()
                    : bird == null
                        ? const Text(
                            '当前筛选下没有可学习的鸟种',
                            style: TextStyle(color: Colors.grey),
                          )
                        : _isFinished
                            ? _buildFinishedView()
                            : FutureBuilder<List<Object?>>(
                                future: Future.wait<Object?>([
                                  _getAudioPaths(),
                                  _getImagePath(),
                                ]),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) {
                                    return const CircularProgressIndicator();
                                  }
                                  final audioPaths = snapshot.data![0] as List<String>;
                                  final imagePath = snapshot.data![1] as String?;
                                  final labels =
                                      bird.audios.map((a) => a.displayLabel).toList();

                                  return SingleChildScrollView(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: BirdCard(
                                        key: _cardKey,
                                        species: bird,
                                        imagePath: imagePath,
                                        audioPaths: audioPaths,
                                        audioLabels: labels,
                                        audioPlayerKey: _audioKey,
                                        mode: _mode,
                                      ),
                                    ),
                                  );
                                },
                              ),
          ),
        ),
        if (bird != null && !_isFinished)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      widget.storage.isFavorite(bird.cn)
                          ? Icons.star
                          : Icons.star_border,
                      color: widget.storage.isFavorite(bird.cn)
                          ? Colors.amber
                          : Colors.grey,
                      size: 28,
                    ),
                    onPressed: _toggleFav,
                  ),
                  const SizedBox(width: 4),
                  _actionButton(
                    label: '✓ 认识',
                    color: Colors.green,
                    enabled: !_answered,
                    onPressed: _markCorrect,
                  ),
                  const SizedBox(width: 8),
                  if (_mode == StudyMode.review)
                    _actionButton(
                      label: _revealed ? '🔒 隐藏' : '👁️ 揭晓',
                      color: Colors.blueGrey,
                      onPressed: _reveal,
                    ),
                  if (_mode == StudyMode.review) const SizedBox(width: 8),
                  _actionButton(
                    label: '✗ 不认识',
                    color: Colors.red,
                    enabled: !_answered,
                    onPressed: _markWrong,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 28),
                    onPressed: _restart,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool enabled = true,
  }) {
    return ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        disabledBackgroundColor: color.withValues(alpha: 0.3),
      ),
      child: Text(label, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _buildMissingPackView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[350]),
          const SizedBox(height: 12),
          const Text(
            '还没有可用的数据包',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '请前往“数据包”页安装内置试用包、导入 ZIP，或使用在线导入功能开始学习。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration, size: 56, color: Colors.green[700]),
          const SizedBox(height: 12),
          const Text(
            '这一轮学习完成了',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '认识 $_correctCount 种，不认识 $_wrongCount 种。\n可以重来一轮，或切到“不熟悉”继续强化。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[700], height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.refresh),
            label: const Text('重新开始'),
          ),
        ],
      ),
    );
  }
}
