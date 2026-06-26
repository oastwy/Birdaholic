import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/audio_info.dart';
import '../models/data_pack.dart';
import '../models/species.dart';
import '../services/admin_upload_service.dart';
import '../services/ebird_service.dart';
import '../services/order_taxonomy.dart';
import '../services/pack_manager.dart';
import '../services/server_media_service.dart';
import '../services/storage.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/bird_card.dart';
import 'bird_preview_screen.dart';
import 'in_flashcard_upload_modal.dart';
import 'pack_manage_screen.dart';

enum AnswerMode {
  learning,
  review,
}

/// 牌组里的一张卡。audioIdx >= 0 表示这张卡只对应该物种的某一条音频
/// （听声模式下 call / song 各自成卡）；audioIdx == -1 表示不限定（图片模式
/// 或该物种只有一条音频时显示全部）。
class _DeckCard {
  final Species species;
  final int audioIdx;
  const _DeckCard(this.species, [this.audioIdx = -1]);

  _DeckCard withSpecies(Species s) => _DeckCard(s, audioIdx);
}

/// 闪卡模式页面
class FlashcardScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  final int refreshToken;
  final bool isActive;
  final ValueChanged<bool>? onFocusChanged;

  const FlashcardScreen({
    super.key,
    required this.packManager,
    required this.storage,
    required this.refreshToken,
    required this.isActive,
    this.onFocusChanged,
  });

  @override
  State<FlashcardScreen> createState() => FlashcardScreenState();
}

class FlashcardScreenState extends State<FlashcardScreen> {
  List<Species> _allSpecies = [];
  List<_DeckCard> _deck = [];
  // 筛选里切换数据包用：已安装包 + 当前激活包目录
  List<DataPack> _installedPacks = const [];
  String? _activePackDir;
  Set<String> _speciesWithAudioFiles = const {};
  Set<String> _speciesWithImageFiles = const {};
  int _idx = 0;
  bool _revealed = false;
  bool _answered = false;
  bool _loading = true;
  String? _loadError;
  String? _selectedChoiceSci;
  List<Species> _quizChoices = const [];
  final Map<String, List<Species>> _quizChoiceCache = {};

  String _filter = 'all';
  // 自定义牌组（到期复习 / 关卡 / 鸟单 等指定一批 sci 学习时用，_filter=='custom'）
  Set<String> _customScis = const {};
  String _customLabel = '自定义';
  String _order = 'random';
  // 「可能性」排序：近期 eBird 观测排名（sci 小写 → 名次，越小越可能遇到；空=未加载）
  Map<String, int> _likelihoodRank = const {};
  int _imageDifficultyFilter = 0; // 0=全部，1-5=只练该图片难度
  int _speciesDifficultyFilter = 0; // 0=全部，1-5=只练该物种难度（管理员评分）
  Set<String> _ebirdFilterSci = const {};
  String _ebirdFilterLabel = '';
  AnswerMode _answerMode = AnswerMode.review;
  StudyMode _mode = StudyMode.review;
  PromptMode _promptMode = PromptMode.audio;
  bool _focusMode = false;
  // 本次 app 启动后是否已在「闪卡筛选页」确认过配置；app 重启时随 State 重建归零，
  // 所以每次重启首次进入(打卡/复习)都停在筛选页，确认后本次会话不再弹。
  bool _configuredThisLaunch = false;

  int _correctCount = 0; // session totals (used in restart resets)
  int _wrongCount = 0;

  // Bird group tracking
  int get _groupSize => widget.storage.flashcardGroupSize;
  int _groupOffset = 0;
  bool _showGroupComplete = false;
  int _groupCorrect = 0;
  int _groupWrong = 0;
  final List<_DeckCard> _groupWrongSpecies = [];
  final Set<String> _answeredCardKeys = {};

  // Extra images from server for current bird
  List<String> _extraImagePaths = [];
  List<String> _extraImageCredits = [];
  String? _extraImagesForSci;
  final Map<String, List<String>> _serverSpectrogramCache = {};

  final _cardKey = GlobalKey<BirdCardState>();
  final _audioKey = GlobalKey<AudioPlayerWidgetState>();
  String? _lastAutoPlayKey;
  Offset? _studyPointerStart;
  Offset? _studyPointerLatest;
  bool _swipeCheckVisible = false;

  // Cached media future — only rebuilt when _idx or pack changes
  Future<List<Object?>>? _mediaFuture;
  int? _mediaFutureIdx;

  bool get _showAnswerOnEntry =>
      _answerMode == AnswerMode.learning && _mode == StudyMode.review;

  PromptMode get _effectivePromptMode => _promptMode;

  int get _groupEnd => (_groupOffset + _groupSize).clamp(0, _deck.length);

  bool get _isGroupFinished =>
      _deck.isNotEmpty && _idx >= _groupEnd - 1 && _answered;

  void _setFocusMode(bool value) {
    if (_focusMode == value) return;
    setState(() => _focusMode = value);
    widget.onFocusChanged?.call(value);
  }

  /// 可被「记住上次筛选」恢复的范围值（必须与筛选下拉的选项一致）。
  static const _restorableFilters = {
    'all',
    'studied',
    'unseen',
    'unfamiliar',
    'favorites',
    'lifer',
  };

  @override
  void initState() {
    super.initState();
    _ebirdFilterLabel = widget.storage.getEbirdFilterLabel();
    _ebirdFilterSci = widget.storage.getEbirdFilterSci();
    // 恢复上次打卡用的筛选（如「未学习」），只接受筛选下拉里有的值，避免下拉断言失败。
    final savedFilter = widget.storage.lastFlashcardFilter;
    if (_restorableFilters.contains(savedFilter)) {
      _filter = savedFilter;
    }
    _loadSpecies();
  }

  @override
  void didUpdateWidget(covariant FlashcardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadSpecies();
    }
    if (oldWidget.isActive && !widget.isActive) {
      _audioKey.currentState?.stop();
      _lastAutoPlayKey = null;
    }
  }

  @override
  void dispose() {
    _audioKey.currentState?.stop();
    super.dispose();
  }

  Future<void> _loadSpecies() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      // 闪卡按「当前选中的单个数据包」出题（不合并其它已启用包）；
      // 否则选了挪威包还会混进中国100。无激活包时退回合并加载。
      final active = await widget.packManager.getActivePackDir();
      final list = active != null
          ? await widget.packManager.loadSpeciesForPack(active)
          : await widget.packManager.loadSpecies();
      final media = await _buildMediaAvailability(list);
      List<DataPack> installed = const [];
      try {
        installed = await widget.packManager.getInstalledPacks();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _allSpecies = list;
        _installedPacks = installed;
        _activePackDir = active;
        _speciesWithAudioFiles = media.audioSpecies;
        _speciesWithImageFiles = media.imageSpecies;
        _loading = false;
      });
      _buildDeck();
      _fetchExtraImages();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allSpecies = [];
        _deck = [];
        _speciesWithAudioFiles = const {};
        _speciesWithImageFiles = const {};
        _idx = 0;
        _revealed = false;
        _answered = false;
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  Future<({Set<String> audioSpecies, Set<String> imageSpecies})>
      _buildMediaAvailability(List<Species> speciesList) async {
    final audioSpecies = <String>{};
    final imageSpecies = <String>{};

    for (final species in speciesList) {
      for (final audio in species.audios) {
        final path = await widget.packManager.getResourcePath(audio.file);
        if (path != null) {
          audioSpecies.add(species.sci);
          break;
        }
      }

      for (final image in species.imageFiles) {
        final path = await widget.packManager.getResourcePath(image);
        if (path != null) {
          imageSpecies.add(species.sci);
          break;
        }
      }
    }

    return (audioSpecies: audioSpecies, imageSpecies: imageSpecies);
  }

  void _scheduleAutoPlay({List<String>? audioPaths}) {
    if (!_focusMode) return;
    final bird = _currentBird;
    if (audioPaths != null && audioPaths.isEmpty) return;
    final playKey = audioPaths == null || bird == null
        ? null
        : '${bird.sci}|$_idx|${_mode.name}|${_effectivePromptMode.name}|${audioPaths.join('|')}';
    if (playKey != null && playKey == _lastAutoPlayKey) return;
    if (playKey != null) _lastAutoPlayKey = playKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentBird == null || _isFinished) return;
      if (!widget.isActive) return;
      if (_effectivePromptMode != PromptMode.audio) return;
      _audioKey.currentState?.autoPlay();
    });
  }

  void _resetCardFace() {
    _audioKey.currentState?.stop();
    _lastAutoPlayKey = null;
    if (_showAnswerOnEntry) {
      _cardKey.currentState?.showBack();
    } else {
      _cardKey.currentState?.showFront();
    }
    _revealed = _showAnswerOnEntry;
    _answered = false;
    _selectedChoiceSci = null;
    _quizChoices = const [];
    _mediaFutureIdx = null; // invalidate media cache on card change
  }

  void _buildDeck() {
    var list = <Species>[..._allSpecies];

    switch (_filter) {
      case 'studied':
        list = list.where((s) {
          final mastery = widget.storage.getMastery(s.cn);
          return mastery.knownCount > 0 || mastery.unknownCount > 0;
        }).toList();
        break;
      case 'unseen':
        list = list.where((s) {
          final mastery = widget.storage.getMastery(s.cn);
          return mastery.knownCount == 0 && mastery.unknownCount == 0;
        }).toList();
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
      case 'lifer':
        // 未见过（潜在新种）：不在我的观鸟清单里的种。清单只取一次，避免逐个解析 JSON。
        // 跨分类匹配：把每个种展开成等价学名组（郑四/eBird 任一写法在清单里即算已见）。
        final seenSet = widget.storage.getLifeList();
        list = list
            .where((s) => !widget.storage.lifeGroup(s.sci).any(seenSet.contains))
            .toList();
        break;
      case 'custom':
        list = list.where((s) => _customScis.contains(s.sci)).toList();
        break;
    }

    if (_ebirdFilterSci.isNotEmpty) {
      list = list
          .where((species) =>
              _ebirdFilterSci.contains(species.sci.trim().toLowerCase()))
          .toList();
    }

    // 物种难度筛选（与图片难度独立；按管理员评分，0=全部）。难度 0/未评按 1 处理。
    if (_speciesDifficultyFilter > 0) {
      list = list
          .where((s) => s.difficulty.clamp(1, 5) == _speciesDifficultyFilter)
          .toList();
    }

    list = list.where(_hasPromptMedia).toList();
    if (_effectivePromptMode == PromptMode.image &&
        _imageDifficultyFilter > 0) {
      list = list.where(_hasImageAtDifficulty).toList();
    }

    switch (_order) {
      case 'unseen':
        list.sort((a, b) {
          final ma = widget.storage.getMastery(a.cn);
          final mb = widget.storage.getMastery(b.cn);
          final ta = ma.knownCount + ma.unknownCount;
          final tb = mb.knownCount + mb.unknownCount;
          if (ta != tb) return ta.compareTo(tb);
          return a.cn.compareTo(b.cn);
        });
        break;
      case 'review_time':
        list.sort((a, b) {
          final ma = widget.storage.getMastery(a.cn);
          final mb = widget.storage.getMastery(b.cn);
          if (ma.lastTime.isEmpty && mb.lastTime.isEmpty) {
            return a.cn.compareTo(b.cn);
          }
          if (ma.lastTime.isEmpty) return -1;
          if (mb.lastTime.isEmpty) return 1;
          return ma.lastTime.compareTo(mb.lastTime);
        });
        break;
      case 'wrong':
        list.sort((a, b) {
          final ma = widget.storage.getMastery(a.cn);
          final mb = widget.storage.getMastery(b.cn);
          final wrong = mb.unknownCount.compareTo(ma.unknownCount);
          if (wrong != 0) return wrong;
          final totalA = ma.knownCount + ma.unknownCount;
          final totalB = mb.knownCount + mb.unknownCount;
          return totalA.compareTo(totalB);
        });
        break;
      case 'seq':
        int grade(Species s) => s.isGrade1
            ? 0
            : s.isGrade2
                ? 1
                : 2;
        list.sort((a, b) => grade(a).compareTo(grade(b)));
        break;
      case 'likelihood':
        // 可能性：近 30 天 eBird 观测越近名次越靠前；未上榜的排后，再按名称
        list.sort((a, b) {
          final ra = _likelihoodRank[StorageService.normalizeSci(a.sci)] ?? (1 << 30);
          final rb = _likelihoodRank[StorageService.normalizeSci(b.sci)] ?? (1 << 30);
          if (ra != rb) return ra.compareTo(rb);
          return a.cn.compareTo(b.cn);
        });
        break;
      case 'taxonomic':
        // 分类关系：目(分类序号) → 科 → 属种
        list.sort((a, b) {
          final wa = BirdOrderTaxonomy.info(a.order).sortWeight;
          final wb = BirdOrderTaxonomy.info(b.order).sortWeight;
          if (wa != wb) return wa.compareTo(wb);
          if (a.family != b.family) return a.family.compareTo(b.family);
          return a.sci.compareTo(b.sci);
        });
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
      _deck = _expandToCards(list);
      _idx = 0;
      _groupOffset = 0;
      _groupCorrect = 0;
      _groupWrong = 0;
      _groupWrongSpecies.clear();
      _answeredCardKeys.clear();
      _showGroupComplete = false;
      _quizChoiceCache.clear();
      _extraImagePaths = [];
      _extraImageCredits = [];
      _extraImagesForSci = null;
      _resetCardFace();
    });

    if (_deck.isNotEmpty) {
      _prepareQuizChoices();
      _scheduleAutoPlay();
    }
  }

  /// 把物种列表展开成牌组卡片。听声模式下，有多条音频的物种按 call/song
  /// 拆成多张卡（每张一条音频、一张频谱图）；其余情况一物种一张卡。
  List<_DeckCard> _expandToCards(List<Species> list) {
    if (_effectivePromptMode != PromptMode.audio) {
      return list.map((s) => _DeckCard(s)).toList();
    }
    final cards = <_DeckCard>[];
    for (final s in list) {
      final n = s.audios.length;
      if (n <= 1) {
        cards.add(_DeckCard(s));
      } else {
        for (var i = 0; i < n; i++) {
          cards.add(_DeckCard(s, i));
        }
      }
    }
    return cards;
  }

  Species? get _currentBird =>
      _deck.isEmpty ? null : _deck[_idx.clamp(0, _deck.length - 1)].species;

  /// 当前卡指定的音频索引（-1 表示不限定，显示该物种全部音频）。
  int get _currentCardAudioIdx =>
      _deck.isEmpty ? -1 : _deck[_idx.clamp(0, _deck.length - 1)].audioIdx;

  /// 当前卡要展示的音频列表：听声拆卡时只含一条，否则全部。
  List<AudioInfo> _cardAudios(Species bird) {
    final idx = _currentCardAudioIdx;
    if (idx >= 0 && idx < bird.audios.length) return [bird.audios[idx]];
    return bird.audios;
  }

  bool get _isFinished => _isGroupFinished;

  String get _deckSummary {
    final ebirdText = _ebirdFilterLabel.isEmpty ? '' : ' · $_ebirdFilterLabel';
    final promptText = _effectivePromptMode == PromptMode.audio ? '音频' : '图片';
    switch (_filter) {
      case 'studied':
        return '当前牌组：已学习 · $promptText$ebirdText';
      case 'unseen':
        return '当前牌组：未学习 · $promptText$ebirdText';
      case 'g1':
        return '当前牌组：国家一级保护 · $promptText$ebirdText';
      case 'g2':
        return '当前牌组：国家二级保护 · $promptText$ebirdText';
      case 'favorites':
        return '当前牌组：收藏 · $promptText$ebirdText';
      case 'unfamiliar':
        return '当前牌组：不熟悉 · $promptText$ebirdText';
      case 'lifer':
        return '当前牌组：未见过 · $promptText$ebirdText';
      case 'custom':
        return '当前牌组：$_customLabel · $promptText';
      default:
        return '当前牌组：全部 · $promptText$ebirdText';
    }
  }

  bool _hasPromptMedia(Species species) {
    return _effectivePromptMode == PromptMode.audio
        ? _speciesWithAudioFiles.contains(species.sci)
        : _speciesWithImageFiles.contains(species.sci);
  }

  bool _hasImageAtDifficulty(Species species) {
    if (_imageDifficultyFilter == 0) return true;
    final images = species.images.isNotEmpty
        ? species.images
        : species.image != null
            ? [
                SpeciesImageInfo(
                  file: species.image!,
                  credit: species.imageCredit,
                  difficulty: species.difficulty,
                )
              ]
            : const <SpeciesImageInfo>[];
    return images.any((image) => image.difficulty == _imageDifficultyFilter);
  }

  List<SpeciesImageInfo> _imageEntriesForStudy(Species species) {
    final entries = species.images.isNotEmpty
        ? species.images
        : species.image != null
            ? [
                SpeciesImageInfo(
                  file: species.image!,
                  credit: species.imageCredit,
                  difficulty: species.difficulty,
                )
              ]
            : const <SpeciesImageInfo>[];
    if (_imageDifficultyFilter == 0) return entries;
    return entries
        .where((image) => image.difficulty == _imageDifficultyFilter)
        .toList();
  }

  Future<
      ({
        String? path,
        String? file,
        String credit,
        List<String> extraPaths,
        List<String> extraFiles,
        List<String> extraCredits,
      })> _getStudyImages() async {
    final bird = _currentBird;
    if (bird == null) {
      return (
        path: null,
        file: null,
        credit: '',
        extraPaths: const <String>[],
        extraFiles: const <String>[],
        extraCredits: const <String>[],
      );
    }
    final entries = _imageEntriesForStudy(bird);
    final paths = <String>[];
    final files = <String>[];
    final credits = <String>[];
    for (final image in entries) {
      final path = await widget.packManager.getResourcePath(image.file);
      if (path != null) {
        paths.add(path);
        files.add(image.file);
        credits.add(image.credit.isNotEmpty ? image.credit : bird.imageCredit);
      }
    }
    if (paths.isEmpty) {
      return (
        path: null,
        file: null,
        credit: '',
        extraPaths: const <String>[],
        extraFiles: const <String>[],
        extraCredits: const <String>[],
      );
    }
    return (
      path: paths.first,
      file: files.first,
      credit: credits.first,
      extraPaths: paths.skip(1).toList(),
      extraFiles: files.skip(1).toList(),
      extraCredits: credits.skip(1).toList(),
    );
  }

  Future<List<String>> _getAudioPaths() async {
    final bird = _currentBird;
    if (bird == null) return [];
    final paths = <String>[];
    for (final a in _cardAudios(bird)) {
      final p = await widget.packManager.getResourcePath(a.file);
      if (p != null) paths.add(p);
    }
    return paths;
  }

  /// 返回与可播放音频列表（[_getAudioPaths]）一一对应的频谱图路径列表。
  /// 每个音频先取本地频谱图，再取内嵌 URL，最后按文件名匹配服务器频谱图兜底。
  /// 没有频谱图的位置返回空串，以保持索引对齐。
  Future<List<String>> _getAudioSpectrogramPaths() async {
    final bird = _currentBird;
    if (bird == null) return [];
    // 缓存键含当前卡音频索引，避免同物种 call/song 拆卡时互相串图
    final cacheKey = '${bird.sci}|$_currentCardAudioIdx';
    final cached = _serverSpectrogramCache[cacheKey];
    if (cached != null) return cached;

    ServerSpeciesMedia? media;
    var mediaFetched = false;
    final result = <String>[];
    for (final audio in _cardAudios(bird)) {
      // 与 _getAudioPaths 对齐：无法解析音频文件的项不计入
      final audioPath = await widget.packManager.getResourcePath(audio.file);
      if (audioPath == null) continue;

      var spec = '';
      if (audio.spectrogram.isNotEmpty) {
        final local =
            await widget.packManager.getResourcePath(audio.spectrogram);
        if (local != null) spec = local;
      }
      if (spec.isEmpty && audio.spectrogramUrl.isNotEmpty) {
        spec = audio.spectrogramUrl;
      }
      if (spec.isEmpty) {
        if (!mediaFetched) {
          mediaFetched = true;
          try {
            media = await ServerMediaService().fetchSpeciesMedia(bird.sci);
          } catch (_) {
            // 网络兜底尽力而为，音频闪卡仍可用
          }
        }
        if (media != null) {
          final localName = audio.file.split('/').last.trim();
          for (final m in media.audio) {
            if (m.spectrogramUrl.isNotEmpty &&
                m.file.split('/').last.trim() == localName) {
              spec = m.spectrogramUrl;
              break;
            }
          }
        }
      }
      result.add(spec);
    }
    // 仅当至少解析出一张频谱图时才缓存，避免把网络抖动导致的空结果钉死
    if (result.any((s) => s.isNotEmpty)) {
      _serverSpectrogramCache[cacheKey] = result;
    }
    return result;
  }

  void _jumpToSpecies(Species target) {
    final di = _deck.indexWhere((c) => c.species.sci == target.sci);
    if (di >= 0) {
      setState(() {
        _idx = di;
        _resetCardFace();
      });
      enterFocusMode();
      _prepareQuizChoices();
      _scheduleAutoPlay();
      return;
    }

    if (_allSpecies.any((s) => s.sci == target.sci)) {
      setState(() {
        _filter = 'all';
        _order = 'alpha';
      });
      enterFocusMode();
      _buildDeck();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToSpecies(target),
      );
    }
  }

  void _markCorrect({bool fromSwipe = false}) {
    if (_answered) return;
    final bird = _currentBird;
    if (bird == null) return;

    if (fromSwipe) {
      setState(() => _swipeCheckVisible = true);
      Future.delayed(const Duration(milliseconds: 500),
          () => mounted ? setState(() => _swipeCheckVisible = false) : null);
    }
    _recordAnswer(bird, isCorrect: true);
    if (!_isFinished) {
      Future.delayed(const Duration(milliseconds: 650), _nextCard);
    }
  }

  void _markWrong() {
    if (_answered) return;
    final bird = _currentBird;
    if (bird == null) return;

    _recordAnswer(bird, isCorrect: false);
    if (_mode == StudyMode.review) {
      _showAnswer();
      if (!_isFinished) {
        Future.delayed(const Duration(milliseconds: 1300), _nextCard);
      }
      return;
    }
    if (_mode == StudyMode.quiz && !_isFinished) {
      Future.delayed(const Duration(milliseconds: 850), _nextCard);
    }
  }

  void _recordAnswer(Species bird, {required bool isCorrect}) {
    if (_answered) return;
    final answerCard = _deck.isEmpty
        ? _DeckCard(bird)
        : _deck[_idx.clamp(0, _deck.length - 1).toInt()];
    final answerKey =
        '$_groupOffset|$_idx|${answerCard.species.sci}|${answerCard.audioIdx}';
    if (!_answeredCardKeys.add(answerKey)) return;

    _audioKey.currentState?.stop();
    _answered = true;
    if (isCorrect) {
      _correctCount++;
      _groupCorrect++;
      widget.storage.markCorrect();
      widget.storage.markSpeciesKnown(bird.cn);
    } else {
      _wrongCount++;
      _groupWrong++;
      if (!_groupWrongSpecies.any((c) =>
          c.species.sci == answerCard.species.sci &&
          c.audioIdx == answerCard.audioIdx)) {
        _groupWrongSpecies.add(answerCard);
      }
      widget.storage.markWrong();
      widget.storage.markSpeciesUnknown(bird.cn);
    }

    setState(() {});

    if (_isGroupFinished) {
      Future.delayed(
        _mode == StudyMode.review
            ? const Duration(milliseconds: 1300)
            : const Duration(milliseconds: 500),
        _triggerGroupComplete,
      );
    }
  }

  void _triggerGroupComplete() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _playCompleteSound();
    setState(() => _showGroupComplete = true);
  }

  void _playCompleteSound() {
    AudioPlayer().play(AssetSource('sounds/complete.m4a')).catchError((_) {});
  }

  void _answerQuizChoice(Species choice) {
    if (_answered) return;
    final bird = _currentBird;
    if (bird == null) return;

    _selectedChoiceSci = choice.sci;
    _recordAnswer(bird, isCorrect: choice.sci == bird.sci);
    setState(() => _revealed = true);
    if (!_isFinished) {
      Future.delayed(const Duration(milliseconds: 1300), _nextCard);
    }
  }

  void _prepareQuizChoices() {
    final bird = _currentBird;
    if (bird == null || _mode != StudyMode.quiz) {
      _quizChoices = const [];
      return;
    }
    final cacheKey = '${bird.sci}|${_promptMode.name}';
    final cached = _quizChoiceCache[cacheKey];
    if (cached != null) {
      _quizChoices = cached;
      return;
    }
    final candidates = _smartQuizCandidates(bird);
    final choices = <Species>[bird, ...candidates.take(3)]..shuffle(Random());
    _quizChoiceCache[cacheKey] = choices;
    _quizChoices = choices;
  }

  List<Species> _smartQuizCandidates(Species bird) {
    final pool = _allSpecies
        .where((species) => species.sci != bird.sci && _hasPromptMedia(species))
        .toList();
    final used = <String>{};
    final result = <Species>[];

    void addShuffled(Iterable<Species> items) {
      final list = items.where((item) => used.add(item.sci)).toList()
        ..shuffle(Random());
      result.addAll(list);
    }

    final genus = _genusOf(bird);
    if (genus.isNotEmpty) {
      addShuffled(pool.where((item) => _genusOf(item) == genus));
    }
    if (bird.family.trim().isNotEmpty) {
      addShuffled(pool.where((item) => item.family == bird.family));
    }
    if (bird.order.trim().isNotEmpty) {
      addShuffled(pool.where((item) => item.order == bird.order));
    }
    addShuffled(pool);
    return result;
  }

  String _genusOf(Species species) {
    final parts = species.sci.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  void _nextCard() {
    if (_deck.isEmpty || _idx >= _groupEnd - 1) return;
    setState(() {
      _audioKey.currentState?.stop();
      _idx++;
      _extraImagePaths = [];
      _extraImageCredits = [];
      _extraImagesForSci = null;
      _resetCardFace();
    });
    _prepareQuizChoices();
    _scheduleAutoPlay();
    _fetchExtraImages();
  }

  void _previousCard() {
    if (_deck.isEmpty || _idx <= 0) return;
    setState(() {
      _audioKey.currentState?.stop();
      _idx--;
      _resetCardFace();
    });
    _prepareQuizChoices();
    _scheduleAutoPlay();
  }

  Future<void> _fetchExtraImages() async {
    final bird = _currentBird;
    if (bird == null) return;
    if (_extraImagesForSci == bird.sci) return;
    _extraImagesForSci = bird.sci;
    try {
      final media = await ServerMediaService().fetchSpeciesMedia(bird.sci);
      if (!mounted || _extraImagesForSci != bird.sci) return;
      if (media == null) return;
      final localNames = bird.imageFiles.map((p) => p.split('/').last).toSet();
      final remoteImages = media.images.where((img) {
        final segments = Uri.tryParse(img.url)?.pathSegments ?? const [];
        final name = segments.isNotEmpty ? segments.last : img.file;
        return name.isEmpty || !localNames.contains(name);
      }).toList();
      setState(() {
        _extraImagePaths = remoteImages.map((img) => img.url).toList();
        _extraImageCredits =
            remoteImages.map((img) => img.contributor).toList();
      });
    } catch (_) {}
  }

  void _advanceGroup() {
    if (!mounted) return;
    final nextOffset = _groupOffset + _groupSize;
    if (nextOffset >= _deck.length) {
      // 全部完成
      setState(() {
        _showGroupComplete = false;
        _idx = _deck.length - 1;
        _answered = true;
      });
      return;
    }
    setState(() {
      _showGroupComplete = false;
      _groupOffset = nextOffset;
      _groupCorrect = 0;
      _groupWrong = 0;
      _groupWrongSpecies.clear();
      _answeredCardKeys.clear();
      _idx = nextOffset;
      _extraImagePaths = [];
      _extraImageCredits = [];
      _extraImagesForSci = null;
      _resetCardFace();
    });
    _prepareQuizChoices();
    _scheduleAutoPlay();
    _fetchExtraImages();
  }

  void _retryGroup() {
    if (!mounted) return;
    final end = _groupEnd;
    // Reshuffle the current group segment
    final groupSlice = _deck.sublist(_groupOffset, end).toList()
      ..shuffle(Random());
    for (var i = 0; i < groupSlice.length; i++) {
      _deck[_groupOffset + i] = groupSlice[i];
    }
    setState(() {
      _showGroupComplete = false;
      _groupCorrect = 0;
      _groupWrong = 0;
      _groupWrongSpecies.clear();
      _answeredCardKeys.clear();
      _idx = _groupOffset;
      _extraImagePaths = [];
      _extraImageCredits = [];
      _extraImagesForSci = null;
      _quizChoiceCache.clear();
      _resetCardFace();
    });
    _prepareQuizChoices();
    _scheduleAutoPlay();
    _fetchExtraImages();
  }

  void _reviewGroupWrongs() {
    if (!mounted || _groupWrongSpecies.isEmpty) return;
    final wrongs = _groupWrongSpecies.toList()..shuffle(Random());
    setState(() {
      _deck = wrongs;
      _groupOffset = 0;
      _idx = 0;
      _groupCorrect = 0;
      _groupWrong = 0;
      _groupWrongSpecies.clear();
      _answeredCardKeys.clear();
      _showGroupComplete = false;
      _extraImagePaths = [];
      _extraImageCredits = [];
      _extraImagesForSci = null;
      _quizChoiceCache.clear();
      _resetCardFace();
    });
    enterFocusMode();
    _prepareQuizChoices();
    _scheduleAutoPlay();
    _fetchExtraImages();
  }

  void _reveal() {
    if (_showAnswerOnEntry) return;
    if (_answered) return;
    _revealed = !_revealed;
    _cardKey.currentState?.reveal();
    setState(() {});
  }

  void _showAnswer() {
    if (_revealed) return;
    _revealed = true;
    _cardKey.currentState?.showBack();
    setState(() {});
  }

  void _toggleFav() {
    final bird = _currentBird;
    if (bird == null) return;
    widget.storage.toggleFavorite(bird.cn);
    setState(() {});
  }

  Future<void> _reportIssue() async {
    final bird = _currentBird;
    if (bird == null) return;

    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('记录纠错'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: '例如：这张图不清晰，或录音不对，或学名需要核对',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存到日记'),
          ),
        ],
      ),
    );

    if (saved != true || controller.text.trim().isEmpty) return;

    final feedbackContext = _buildFeedbackContext(bird);
    await widget.storage.addFeedbackEntry(
      message: controller.text,
      page: '闪卡学习',
      speciesCn: bird.cn,
      speciesSci: bird.sci,
    );
    final token = widget.storage.getAdminUploadToken();
    final clientId = await widget.storage.ensureFeedbackClientId();
    // 不论有无 token 都尝试推送给管理员（无 token 走匿名）
    AdminUploadService()
        .submitFeedback(
          token: token,
          clientId: clientId,
          message: controller.text,
          page: '闪卡学习',
          speciesCn: bird.cn,
          speciesSci: bird.sci,
          context: feedbackContext,
        )
        .ignore();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('已记录纠错并同步给管理员'),
    ));
  }

  Map<String, dynamic> _buildFeedbackContext(Species bird) {
    final context = <String, dynamic>{
      'question_type': _mode == StudyMode.quiz ? 'choice' : 'review',
      'prompt_mode': _effectivePromptMode.name,
      'question': _feedbackQuestionText,
      'correct_answer': _feedbackSpeciesLabel(bird),
      'deck': _deckSummary,
      'card_index': '${_idx - _groupOffset + 1}/${_groupEnd - _groupOffset}',
    };
    final cardContext = _cardKey.currentState?.feedbackContext();
    if (cardContext != null) {
      context.addAll(cardContext);
    }
    if (_mode == StudyMode.quiz) {
      context['options'] = _quizChoices.map(_feedbackSpeciesLabel).toList();
      if (_selectedChoiceSci != null) {
        Species? selected;
        for (final choice in _quizChoices) {
          if (choice.sci == _selectedChoiceSci) {
            selected = choice;
            break;
          }
        }
        context['selected_answer'] = selected == null
            ? _selectedChoiceSci
            : _feedbackSpeciesLabel(selected);
      }
    }
    return context;
  }

  String get _feedbackQuestionText {
    if (_mode == StudyMode.quiz) {
      return _effectivePromptMode == PromptMode.audio
          ? '选择题：这是什么鸟的声音？'
          : '选择题：这是什么鸟？';
    }
    return _effectivePromptMode == PromptMode.audio
        ? '复习题：这是什么鸟的声音？'
        : '复习题：这是什么鸟？';
  }

  String _feedbackSpeciesLabel(Species species) {
    final parts = <String>[
      if (species.cn.trim().isNotEmpty) species.cn.trim(),
      if (species.en.trim().isNotEmpty) species.en.trim(),
      species.sci.trim(),
    ].where((part) => part.isNotEmpty).toList();
    return parts.join(' · ');
  }

  Future<void> _editIdentificationNote() async {
    final bird = _currentBird;
    if (bird == null) return;

    final controller = TextEditingController(
      text: widget.storage.getSpeciesNote(bird.sci).isNotEmpty
          ? widget.storage.getSpeciesNote(bird.sci)
          : bird.identificationFeatures,
    );
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('识别特征：${bird.cn}'),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            helperMaxLines: 3,
            helperText: '建议来源：你自己的野外笔记、可靠图鉴描述、管理员审核后的团队经验。不要整段复制第三方内容。',
            hintText: '例如：白色眉纹明显；叫声短促上扬；常在灌丛边缘活动。',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          if (widget.storage.isAdminMode)
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'upload'),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('保存并推送'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('本地保存'),
          ),
        ],
      ),
    );
    if (action != 'save' && action != 'upload') return;

    try {
      await widget.storage.setSpeciesNote(bird.sci, controller.text);
      if (action == 'upload') {
        await _pushIdentificationFeatures(bird, controller.text);
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
        content: Text(action == 'upload' ? '识别特征已保存并推送' : '识别特征已保存'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别特征保存失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pushIdentificationFeatures(Species bird, String text) async {
    final token = widget.storage.getAdminUploadToken();
    if (token.isEmpty) throw Exception('管理员密钥为空');
    await AdminUploadService().uploadIdentificationFeatures(
      species: bird,
      features: text,
      token: token,
    );
  }

  /// 合并的「上传」入口：让用户选上传照片还是上传音频。
  Future<void> _uploadMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined,
                  color: Color(0xFF2d5016)),
              title: const Text('上传照片'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.library_music_outlined,
                  color: Color(0xFF2d5016)),
              title: const Text('上传音频'),
              onTap: () => Navigator.pop(ctx, 'audio'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'image') {
      await _uploadBirdImage();
    } else if (choice == 'audio') {
      await _uploadBirdAudio();
    }
  }

  Future<void> _uploadBirdImage() async {
    final bird = _currentBird;
    if (bird == null) return;
    final ok = await InFlashcardUploadModal.show(
      context: context,
      currentBird: bird,
      storage: widget.storage,
      packManager: widget.packManager,
      kind: UploadKind.image,
    );
    if (!ok || !mounted) return;
    await _loadSpecies();
    _jumpToSpecies(
      _allSpecies.firstWhere((s) => s.sci == bird.sci, orElse: () => bird),
    );
  }

  Future<void> _uploadBirdAudio() async {
    final bird = _currentBird;
    if (bird == null) return;
    final ok = await InFlashcardUploadModal.show(
      context: context,
      currentBird: bird,
      storage: widget.storage,
      packManager: widget.packManager,
      kind: UploadKind.audio,
    );
    if (!ok || !mounted) return;
    await _loadSpecies();
    _jumpToSpecies(
      _allSpecies.firstWhere((s) => s.sci == bird.sci, orElse: () => bird),
    );
  }

  /// 地点 / 数据包变了，「可能性」排名作废：清空排名缓存；若当前正按可能性排序，退回随机。
  void _resetLikelihoodOnContextChange() {
    _likelihoodRank = const {};
    if (_order == 'likelihood') _order = 'random';
  }

  /// 选「可能性」排序：用上次 eBird 地区码 / 经纬度查近 30 天观测，按最近观测排名。
  /// 需先做过地点筛选（地区代码或经纬度）+ 有 API Key。
  Future<void> _selectLikelihoodOrder() async {
    final region = widget.storage.getEbirdFilterRegion();
    final coordsStr = widget.storage.getEbirdFilterCoords();
    if (region.isEmpty && coordsStr.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('「可能性」需先做 eBird 地点筛选（地区代码或经纬度）'),
        ));
      }
      return; // 不改 _order，下拉回弹
    }
    final apiKey = widget.storage.getEBirdApiKey();
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('「可能性」需要 eBird API Key（在设置里填写）'),
        ));
      }
      return;
    }
    setState(() => _order = 'likelihood');
    try {
      final service = EBirdService(apiKey: apiKey);
      final List<String> ordered;
      if (region.isNotEmpty) {
        ordered = await service.fetchRecentObsBySci(region);
      } else {
        final p = coordsStr.split(',');
        final lat = double.tryParse(p.isNotEmpty ? p[0] : '') ?? 0;
        final lng = double.tryParse(p.length > 1 ? p[1] : '') ?? 0;
        final dist = p.length > 2 ? (int.tryParse(p[2]) ?? 25) : 25;
        ordered =
            await service.fetchRecentObsByCoords(lat, lng, distanceKm: dist);
      }
      final rank = <String, int>{};
      for (var i = 0; i < ordered.length; i++) {
        // 与 _buildDeck 查表 key 一致：二名归一化（eBird 可能返回亚种三名）
        rank.putIfAbsent(StorageService.normalizeSci(ordered[i]), () => i);
      }
      if (!mounted) return;
      setState(() => _likelihoodRank = rank);
      _buildDeck(); // 纯排序：整包保留，近期 eBird 观测到的种排到前面
      // 统计本包里有多少种与该地区近期观测重合（仅作反馈 + 判断排序是否有意义）
      final overlap = _deck
          .map((c) => StorageService.normalizeSci(c.species.sci))
          .toSet()
          .where((n) => _likelihoodRank.containsKey(n))
          .length;
      if (overlap == 0) {
        // 整包跟该地区近期记录无交集 → 排序没效果，提示并可去下载覆盖该地区的包（不动牌组）
        await _promptLikelihoodInsufficient();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已把该地区近 30 天最可能遇到的 $overlap 种排到前面'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _order = 'random');
      _buildDeck();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('「可能性」获取失败：$e，已用随机'),
      ));
    }
  }

  /// 「可能性」整包与该地区近期记录无交集：排序没效果，提示并可去「数据包管理」下载/启用
  /// 覆盖该地区的包。整包仍保留（无交集时退化为名称序），不清空、不强制改顺序。
  Future<void> _promptLikelihoodInsufficient() async {
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('该地区数据不足'),
        content: const Text(
            '当前数据包里，没有任何鸟出现在该地区近 30 天的 eBird 记录中，'
            '「可能性」排序暂时没有效果。\n'
            '可以去「数据包管理」下载 / 启用覆盖该地区的数据包，再用「可能性」。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('知道了')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去下载数据包')),
        ],
      ),
    );
    if (go == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PackManageScreen(
            packManager: widget.packManager,
            storage: widget.storage,
          ),
        ),
      );
      if (mounted) await _loadSpecies();
    }
  }

  Future<void> _applyEBirdDeckFilter() async {
    final regionNames = await EBirdService.loadRegionNames();
    if (!mounted) return;
    final controller = TextEditingController(text: _ebirdFilterLabel);
    final coordController = TextEditingController();
    // 时间范围：full=完整名录 / recent=近 N 天 / date=指定历史日期
    var timeMode = 'full';
    var backDays = 14;
    DateTime? histDate;
    var suggestions = <MapEntry<String, String>>[];

    final query = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final history = widget.storage.getEbirdLocationHistory();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'eBird 地点筛选',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '输入国家/地区/热点代码，或直接填经纬度，把当前闪卡范围收窄到这个地点出现过的鸟种。',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: '地点、热点或地区代码',
                        hintText: '湖北、云南、日本、CN-42、L3124991',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onChanged: (value) => setModal(() {
                        suggestions =
                            EBirdService.searchRegions(value, regionNames);
                      }),
                      onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            for (final s in suggestions)
                              ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                title: Text(s.value),
                                trailing: Text(s.key,
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[500])),
                                onTap: () => setModal(() {
                                  controller.text = s.value;
                                  suggestions = [];
                                }),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: coordController,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: '经纬度筛选（可选）',
                        hintText: '纬度, 经度, 半径km，例如 24.7,97.6,25',
                        helperText: '填写后优先按经纬度筛选；半径不填默认 25km。',
                        prefixIcon: const Icon(Icons.explore_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.pop(ctx, '__current_location__'),
                        icon: const Icon(Icons.my_location),
                        label: const Text('使用当前位置'),
                      ),
                    ),
                    if (history.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('最近用过',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700])),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: history.map((loc) {
                          return InputChip(
                            label: Text(loc),
                            onPressed: () =>
                                setModal(() => controller.text = loc),
                            onDeleted: () async {
                              await widget.storage
                                  .removeEbirdLocationHistory(loc);
                              setModal(() {});
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text('常用地点',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700])),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: EBirdService.presets.take(8).map((preset) {
                        return ActionChip(
                          label: Text(preset.label),
                          onPressed: () =>
                              setModal(() => controller.text = preset.code),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text('时间范围',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700])),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('完整名录'),
                          selected: timeMode == 'full',
                          onSelected: (_) => setModal(() => timeMode = 'full'),
                        ),
                        ChoiceChip(
                          label: const Text('近期记录'),
                          selected: timeMode == 'recent',
                          onSelected: (_) =>
                              setModal(() => timeMode = 'recent'),
                        ),
                        ChoiceChip(
                          label: Text(histDate == null
                              ? '指定日期'
                              : '${histDate!.year}-${histDate!.month.toString().padLeft(2, '0')}-${histDate!.day.toString().padLeft(2, '0')}'),
                          selected: timeMode == 'date',
                          onSelected: (_) async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: histDate ??
                                  DateTime.now()
                                      .subtract(const Duration(days: 1)),
                              firstDate: DateTime(1900),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setModal(() {
                                histDate = picked;
                                timeMode = 'date';
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (timeMode == 'recent') ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [7, 14, 30].map((d) {
                          return ChoiceChip(
                            label: Text('近 $d 天'),
                            selected: backDays == d,
                            onSelected: (_) => setModal(() => backDays = d),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, '__clear__'),
                          child: const Text('清除地点'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            final coords = coordController.text.trim();
                            Navigator.pop(
                              ctx,
                              coords.isNotEmpty
                                  ? coords
                                  : controller.text.trim(),
                            );
                          },
                          child: const Text('应用'),
                        ),
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
    controller.dispose();
    coordController.dispose();
    if (query == null) return;
    if (query == '__clear__') {
      await widget.storage.clearEbirdFilter();
      setState(() {
        _ebirdFilterSci = const {};
        _ebirdFilterLabel = '';
        _resetLikelihoodOnContextChange();
      });
      _buildDeck();
      return;
    }
    if (query.trim().isEmpty) return;
    if (timeMode == 'date' && histDate == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择历史日期')),
      );
      return;
    }
    final apiKey = widget.storage.getEBirdApiKey();
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置页填写 eBird API key')));
      return;
    }

    // 中文地名 → eBird 代码（如「湖北」→ CN-42）；代码/坐标原样。
    final loc = query == '__current_location__'
        ? query
        : EBirdService.resolveToRegionCode(query, regionNames);

    try {
      setState(() => _loading = true);
      final service = EBirdService(apiKey: apiKey);
      final coords = loc == '__current_location__'
          ? await _getCurrentCoordinates()
          : _parseCoordinates(loc);
      final Set<EbirdSpeciesMatch> matches;
      if (coords != null) {
        // 经纬度只支持近期；完整名录/指定日期时退化为近 backDays 天。
        matches = await service.fetchNearbySpeciesMatches(
          latitude: coords.$1,
          longitude: coords.$2,
          distanceKm: coords.$3,
          backDays: timeMode == 'recent' ? backDays : 30,
        );
      } else if (timeMode == 'recent') {
        matches =
            await service.fetchRecentSpeciesMatches(loc, backDays: backDays);
      } else if (timeMode == 'date') {
        matches = await service.fetchHistoricSpeciesMatches(
          loc,
          year: histDate!.year,
          month: histDate!.month,
          day: histDate!.day,
        );
      } else {
        matches = await service.fetchSpeciesMatches(loc);
      }
      final sciSet = await _matchEBirdToScientificNames(matches);
      if (!mounted) return;
      final normCode = EBirdService.normalizeLocationCode(loc);
      var placeLabel = coords == null
          ? EBirdService.regionDisplayName(normCode, regionNames)
          : '${coords.$1.toStringAsFixed(3)},${coords.$2.toStringAsFixed(3)}';
      // 本地「代码→中文名」表查不到的(如外国子地区 NO-03)，用 eBird API 反查真实地名，
      // 避免界面上裸显地区代码。
      if (coords == null && placeLabel == normCode) {
        final apiName = await service.fetchRegionName(normCode);
        if (apiName != null && apiName.isNotEmpty) placeLabel = apiName;
      }
      final timeSuffix = timeMode == 'recent'
          ? ' · 近$backDays天'
          : timeMode == 'date'
              ? ' · ${histDate!.year}-${histDate!.month.toString().padLeft(2, '0')}-${histDate!.day.toString().padLeft(2, '0')}'
              : '';
      final label = '$placeLabel$timeSuffix';
      await widget.storage.saveEbirdFilter(label, sciSet);
      // 记住地区码供「可能性」排序按地区查近期观测；经纬度筛选时清空（坐标不适用）。
      final region = coords == null ? normCode : '';
      await widget.storage.setEbirdFilterRegion(region);
      // 坐标筛选也记下，供「可能性」按附近近期观测排序
      await widget.storage.setEbirdFilterCoords(
          coords == null ? '' : '${coords.$1},${coords.$2},${coords.$3}');
      if (coords == null) {
        await widget.storage.addEbirdLocationHistory(placeLabel);
      }
      if (!mounted) return;
      setState(() {
        _ebirdFilterSci = sciSet;
        _ebirdFilterLabel = label;
        // 地点变了，旧可能性排名作废：清排名并把「可能性」退回随机——否则 _order 仍是
        // 'likelihood' 但排名为空，_buildDeck 会静默按拼音字母排，而 UI 仍显示「可能性」。
        _resetLikelihoodOnContextChange();
      });
      _buildDeck();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已按 $label 匹配 ${sciSet.length} 种')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('eBird 筛选失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  (double, double, int)? _parseCoordinates(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'[,，\s]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    final dist = parts.length >= 3 ? int.tryParse(parts[2]) ?? 25 : 25;
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return (lat, lng, dist.clamp(1, 50));
  }

  Future<(double, double, int)> _getCurrentCoordinates() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('手机定位服务未开启');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) throw Exception('未授予定位权限');
    if (permission == LocationPermission.deniedForever) {
      throw Exception('定位权限已被永久拒绝，请到系统设置中开启');
    }
    final position = await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 20),
          ),
        );
    return (position.latitude, position.longitude, 25);
  }

  Future<Set<String>> _matchEBirdToScientificNames(
    Set<EbirdSpeciesMatch> matches,
  ) async {
    final raw = await rootBundle.loadString('assets/data/world_birds.json');
    final data = jsonDecode(raw) as List<dynamic>;
    final byCode = <String, String>{};
    final bySci = <String>{};
    for (final value in data) {
      final item = value as Map<String, dynamic>;
      final sci = (item['sci'] as String? ?? '').trim().toLowerCase();
      if (sci.isEmpty) continue;
      bySci.add(sci);
      final code = (item['code'] as String? ?? '').trim().toLowerCase();
      if (code.isNotEmpty) byCode[code] = sci;
    }
    return matches
        .map((match) {
          final byMatchedCode = byCode[match.code.trim().toLowerCase()];
          if (byMatchedCode != null) return byMatchedCode;
          final sci = match.scientificName.trim().toLowerCase();
          return bySci.contains(sci) ? sci : '';
        })
        .where((sci) => sci.isNotEmpty)
        .toSet();
  }

  void startSession({
    required String filter,
    required StudyMode mode,
    PromptMode promptMode = PromptMode.audio,
    String order = 'random',
  }) {
    // 沿用上次打卡的筛选（如「未学习」），没有存过才用调用方给的默认值。
    final savedFilter = widget.storage.lastFlashcardFilter;
    setState(() {
      _filter = _restorableFilters.contains(savedFilter) ? savedFilter : filter;
      _answerMode = AnswerMode.review;
      _mode = mode;
      _promptMode = promptMode;
      _order = order;
      _correctCount = 0;
      _wrongCount = 0;
      _quizChoiceCache.clear();
    });
    _buildDeck();
    // 本次启动首次进入 → 停在「闪卡筛选页」；确认过(或用户设了"直接全屏")→ 进全屏沿用上次配置。
    if (_configuredThisLaunch || widget.storage.flashcardStartFullscreen) {
      enterFocusMode();
    }
  }

  /// 学习指定的一批物种（到期复习 / 关卡 / 鸟单）。不走「记住上次筛选」。
  void startCustomSession({
    required List<String> scis,
    String label = '自定义',
    PromptMode promptMode = PromptMode.audio,
  }) {
    setState(() {
      _customScis = scis.toSet();
      _customLabel = label;
      _filter = 'custom';
      _answerMode = AnswerMode.review;
      _mode = StudyMode.review;
      _promptMode = promptMode;
      _order = 'random';
      _correctCount = 0;
      _wrongCount = 0;
      _quizChoiceCache.clear();
    });
    _buildDeck();
    // 与打卡一致：本次启动首次进入停在筛选页，确认后(或设了"直接全屏")才进全屏。
    if (_configuredThisLaunch || widget.storage.flashcardStartFullscreen) {
      enterFocusMode();
    }
  }

  void enterFocusMode() {
    if (!mounted || _focusMode) return;
    _setFocusMode(true);
    _scheduleAutoPlay();
  }

  /// 从「打卡设置」窗口点「开始」进全屏：记一笔「已配置」，下次打卡直接全屏沿用上次设置。
  void _startFromWindow() {
    _configuredThisLaunch = true; // 本次会话内之后打卡/复习直接全屏沿用，重启后重新弹一次
    enterFocusMode();
  }

  void exitFocusMode() {
    if (!mounted || !_focusMode) return;
    _setFocusMode(false);
  }

  /// 单个难度下拉：species=true 物种难度（按物种评分），false 图片难度（按图评分）。
  Widget _difficultyDropdown({
    required bool species,
    StateSetter? sheetSetState,
  }) {
    final countByDifficulty = <int, int>{};
    int total = 0;
    for (final sp in _allSpecies) {
      if (species) {
        final d = sp.difficulty.clamp(1, 5);
        countByDifficulty[d] = (countByDifficulty[d] ?? 0) + 1;
        total++;
      } else {
        for (final img in sp.images) {
          final d = img.difficulty.clamp(1, 5);
          countByDifficulty[d] = (countByDifficulty[d] ?? 0) + 1;
          total++;
        }
      }
    }
    final current = species ? _speciesDifficultyFilter : _imageDifficultyFilter;
    String labelFor(int value) {
      if (value == 0) return '全部 ($total)';
      final count = countByDifficulty[value] ?? 0;
      return '${List.filled(value, '⭐').join()} ($count)';
    }
    return DropdownButtonFormField<int>(
      value: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: species ? '物种难度' : '图片难度',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: List.generate(
        6,
        (i) => DropdownMenuItem<int>(value: i, child: Text(labelFor(i))),
      ),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          if (species) {
            _speciesDifficultyFilter = value;
          } else {
            _imageDifficultyFilter = value;
          }
        });
        sheetSetState?.call(() {});
        _buildDeck();
      },
    );
  }

  /// 难度筛选：物种难度始终可设（按物种评分、与图/音模式无关）；图片难度只在图片模式
  /// 显示（只对图生效）。这样音频模式也能看到/清除物种难度，不会被静默过滤到空牌组。
  Widget _difficultySelector([StateSetter? sheetSetState]) {
    final showImage = _effectivePromptMode == PromptMode.image;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child:
              _difficultyDropdown(species: true, sheetSetState: sheetSetState),
        ),
        if (showImage) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _difficultyDropdown(
                species: false, sheetSetState: sheetSetState),
          ),
        ],
      ],
    );
  }

  void _restart() {
    setState(() {
      _correctCount = 0;
      _wrongCount = 0;
      _groupOffset = 0;
      _groupCorrect = 0;
      _groupWrong = 0;
      _groupWrongSpecies.clear();
      _answeredCardKeys.clear();
      _showGroupComplete = false;
    });
    _buildDeck();
  }

  /// 提供给外部跳转
  void jumpTo(Species target) => _jumpToSpecies(target);

  /// 独立的「闪卡筛选页」（非全屏时显示）。点「开始」才进学习页（全屏）。
  Widget _buildFilterPage() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) return Center(child: _buildMissingPackView());
    void refresh(VoidCallback fn, {bool rebuildDeck = true}) {
      setState(fn);
      if (rebuildDeck) _buildDeck();
    }

    final total = _deck.length;
    final beginner = widget.storage.isBeginnerMode;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('闪卡筛选',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    total == 0 ? '当前范围没有可练习的题目' : '$_deckSummary · 共 $total 张',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  // #8 数据包 + 地点 并列一行
                  if (!beginner) ...[
                    Row(
                      children: [
                        if (_installedPacks.length > 1) ...[
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '数据包',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              value: _installedPacks
                                      .any((p) => p.packDir == _activePackDir)
                                  ? _activePackDir
                                  : null,
                              hint: const Text('选择'),
                              items: [
                                for (final p in _installedPacks)
                                  DropdownMenuItem(
                                    value: p.packDir,
                                    child: Text(p.name,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1),
                                  ),
                              ],
                              onChanged: (dir) async {
                                if (dir == null || dir == _activePackDir) {
                                  return;
                                }
                                await widget.packManager.setActivePack(dir);
                                _activePackDir = dir;
                                await widget.storage.clearEbirdFilter();
                                setState(() {
                                  _correctCount = 0;
                                  _wrongCount = 0;
                                  _ebirdFilterSci = const {};
                                  _ebirdFilterLabel = '';
                                  _resetLikelihoodOnContextChange();
                                });
                                await _loadSpecies();
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          // 地点筛选改成跟「数据包」下拉一样的方框（OutlineInputBorder + label）格式
                          child: InkWell(
                            onTap: _applyEBirdDeckFilter,
                            borderRadius: BorderRadius.circular(4),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: '地点筛选',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                      _ebirdFilterSci.isEmpty
                                          ? Icons.place_outlined
                                          : Icons.place,
                                      size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _ebirdFilterSci.isEmpty
                                          ? '选择地点'
                                          : _ebirdFilterLabel,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_ebirdFilterSci.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('清除地点'),
                          onPressed: () async {
                            await widget.storage.clearEbirdFilter();
                            refresh(() {
                              _ebirdFilterSci = const {};
                              _ebirdFilterLabel = '';
                              _resetLikelihoodOnContextChange();
                            });
                            _buildDeck();
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  // #9 学习模式 / 测试模式（整行，去「模式」标签）
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AnswerMode>(
                      segments: const [
                        ButtonSegment(
                            value: AnswerMode.learning,
                            label: Text('学习模式')),
                        ButtonSegment(
                            value: AnswerMode.review, label: Text('测试模式')),
                      ],
                      selected: {_answerMode},
                      onSelectionChanged: (v) => refresh(() {
                        _answerMode = v.first;
                        _correctCount = 0;
                        _wrongCount = 0;
                        _resetCardFace();
                      }, rebuildDeck: false),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // #10 判断题 / 选择题（一行，去「题型」标签）
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<StudyMode>(
                      segments: const [
                        ButtonSegment(
                            value: StudyMode.review, label: Text('判断题')),
                        ButtonSegment(
                            value: StudyMode.quiz, label: Text('选择题')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (v) => refresh(() {
                        _mode = v.first;
                        _correctCount = 0;
                        _wrongCount = 0;
                        _resetCardFace();
                      }),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // #11 音频闪卡 / 图片闪卡（去「出题」标签）
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<PromptMode>(
                      segments: const [
                        ButtonSegment(
                          value: PromptMode.audio,
                          icon: Icon(Icons.headphones, size: 16),
                          label: Text('音频闪卡'),
                        ),
                        ButtonSegment(
                          value: PromptMode.image,
                          icon: Icon(Icons.image_outlined, size: 16),
                          label: Text('图片闪卡'),
                        ),
                      ],
                      selected: {_promptMode},
                      onSelectionChanged: (v) => refresh(() {
                        _promptMode = v.first;
                        _correctCount = 0;
                        _wrongCount = 0;
                        _resetCardFace();
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _difficultySelector(),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _filter,
                    decoration: const InputDecoration(
                      labelText: '范围',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('全部')),
                      DropdownMenuItem(value: 'studied', child: Text('已学习')),
                      DropdownMenuItem(value: 'unseen', child: Text('未学习')),
                      DropdownMenuItem(value: 'unfamiliar', child: Text('不熟悉')),
                      DropdownMenuItem(value: 'favorites', child: Text('收藏')),
                      DropdownMenuItem(
                          value: 'lifer', child: Text('未见过（潜在新种）')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      refresh(() => _filter = v);
                      widget.storage.setLastFlashcardFilter(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  // #12 顺序：随机 / 分类关系（目科属种）。原「按目筛选」已移除。
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: const ['taxonomic', 'likelihood'].contains(_order)
                        ? _order
                        : 'random',
                    decoration: const InputDecoration(
                      labelText: '顺序',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'random', child: Text('随机')),
                      DropdownMenuItem(
                          value: 'taxonomic',
                          child: Text('分类关系（目科属种）')),
                      DropdownMenuItem(
                          value: 'likelihood',
                          child: Text('可能性（近期 eBird 观测）')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == 'likelihood') {
                        _selectLikelihoodOrder();
                      } else {
                        refresh(() => _order = v);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: total == 0 ? null : _startFromWindow,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2d7d32)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                    _answerMode == AnswerMode.learning ? '开始学习' : '开始打卡'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 学习页里的快捷操作行（收藏/识别特征/上传/纠错/重来）。
  Widget _buildStudyActions() {
    final bird = _currentBird;
    if (bird == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundIconAction(
            icon: widget.storage.isFavorite(bird.cn)
                ? Icons.star
                : Icons.star_border,
            activeColor:
                widget.storage.isFavorite(bird.cn) ? Colors.amber : Colors.grey,
            tooltip: '收藏',
            onPressed: _toggleFav,
          ),
          _roundIconAction(
            icon: Icons.help_outline,
            tooltip: '识别特征',
            onPressed: _editIdentificationNote,
          ),
          _roundIconAction(
            icon: Icons.upload_outlined,
            tooltip: '上传',
            onPressed: _uploadMedia,
          ),
          _roundIconAction(
            icon: Icons.bug_report_outlined,
            tooltip: '纠错',
            onPressed: _reportIssue,
          ),
          _roundIconAction(
            icon: Icons.refresh,
            tooltip: '重来',
            onPressed: _restart,
          ),
        ],
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    // 打开筛选前载入已安装数据包，供「数据包」下拉切换
    try {
      _installedPacks = await widget.packManager.getInstalledPacks();
      _activePackDir = await widget.packManager.getActivePackDir();
    } catch (_) {
      _installedPacks = const [];
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sheetSetState) {
          void refresh(VoidCallback fn, {bool rebuildDeck = true}) {
            setState(fn);
            sheetSetState(() {});
            if (rebuildDeck) _buildDeck();
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '闪卡筛选',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  if (_installedPacks.length > 1 &&
                      !widget.storage.isBeginnerMode) ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '数据包',
                        border: OutlineInputBorder(),
                      ),
                      value: _installedPacks
                              .any((p) => p.packDir == _activePackDir)
                          ? _activePackDir
                          : null,
                      hint: const Text('选择数据包'),
                      items: [
                        for (final p in _installedPacks)
                          DropdownMenuItem(
                            value: p.packDir,
                            child: Text(p.name,
                                overflow: TextOverflow.ellipsis, maxLines: 1),
                          ),
                      ],
                      onChanged: (dir) async {
                        if (dir == null || dir == _activePackDir) return;
                        await widget.packManager.setActivePack(dir);
                        _activePackDir = dir;
                        await widget.storage.clearEbirdFilter();
                        sheetSetState(() {});
                        setState(() {
                          _correctCount = 0;
                          _wrongCount = 0;
                          _ebirdFilterSci = const {};
                          _ebirdFilterLabel = '';
                          _resetLikelihoodOnContextChange();
                        });
                        await _loadSpecies(); // 重载该包物种并重建牌组
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!widget.storage.isBeginnerMode) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.place_outlined, size: 18),
                          label: Text(
                            _ebirdFilterSci.isEmpty
                                ? '地点筛选'
                                : _ebirdFilterLabel,
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _applyEBirdDeckFilter();
                          },
                        ),
                        if (_ebirdFilterSci.isNotEmpty)
                          ActionChip(
                            avatar: const Icon(Icons.clear, size: 18),
                            label: const Text('清除地点'),
                            onPressed: () async {
                              await widget.storage.clearEbirdFilter();
                              refresh(() {
                                _ebirdFilterSci = const {};
                                _ebirdFilterLabel = '';
                                _resetLikelihoodOnContextChange();
                              });
                              _buildDeck();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text('模式',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SegmentedButton<AnswerMode>(
                    segments: const [
                      ButtonSegment(
                          value: AnswerMode.learning, label: Text('学习')),
                      ButtonSegment(
                          value: AnswerMode.review, label: Text('测试')),
                    ],
                    selected: {_answerMode},
                    onSelectionChanged: (v) => refresh(
                      () {
                        _answerMode = v.first;
                        _correctCount = 0;
                        _wrongCount = 0;
                        _resetCardFace();
                      },
                      rebuildDeck: false,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('题型',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SegmentedButton<StudyMode>(
                    segments: const [
                      ButtonSegment(value: StudyMode.review, label: Text('判断')),
                      ButtonSegment(value: StudyMode.quiz, label: Text('选择')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) => refresh(() {
                      _mode = v.first;
                      _correctCount = 0;
                      _wrongCount = 0;
                      _resetCardFace();
                    }),
                  ),
                  const SizedBox(height: 12),
                  const Text('出题',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SegmentedButton<PromptMode>(
                    segments: const [
                      ButtonSegment(
                        value: PromptMode.audio,
                        icon: Icon(Icons.headphones, size: 16),
                        label: Text('音频'),
                      ),
                      ButtonSegment(
                        value: PromptMode.image,
                        icon: Icon(Icons.image_outlined, size: 16),
                        label: Text('图片'),
                      ),
                    ],
                    selected: {_promptMode},
                    onSelectionChanged: (v) => refresh(() {
                      _promptMode = v.first;
                      _correctCount = 0;
                      _wrongCount = 0;
                      _resetCardFace();
                    }),
                  ),
                  const SizedBox(height: 12),
                  _difficultySelector(sheetSetState),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _filter,
                    decoration: const InputDecoration(
                      labelText: '范围',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('全部')),
                      DropdownMenuItem(value: 'studied', child: Text('已学习')),
                      DropdownMenuItem(value: 'unseen', child: Text('未学习')),
                      DropdownMenuItem(value: 'unfamiliar', child: Text('不熟悉')),
                      DropdownMenuItem(value: 'favorites', child: Text('收藏')),
                      DropdownMenuItem(
                          value: 'lifer', child: Text('未见过（潜在新种）')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      refresh(() => _filter = v);
                      widget.storage.setLastFlashcardFilter(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: const ['taxonomic', 'likelihood'].contains(_order)
                        ? _order
                        : 'random',
                    decoration: const InputDecoration(
                      labelText: '顺序',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'random', child: Text('随机')),
                      DropdownMenuItem(
                          value: 'taxonomic',
                          child: Text('分类关系（目科属种）')),
                      DropdownMenuItem(
                          value: 'likelihood',
                          child: Text('可能性（近期 eBird 观测）')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == 'likelihood') {
                        _selectLikelihoodOrder();
                      } else {
                        refresh(() => _order = v);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startFromWindow();
                      },
                      icon: const Icon(Icons.fullscreen),
                      label: Text(
                        _answerMode == AnswerMode.learning ? '开始学习' : '开始打卡',
                      ),
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

  @override
  Widget build(BuildContext context) {
    final bird = _currentBird;

    // 非全屏 = 独立「闪卡筛选页」；全屏 = 学习页。两者分开，不再是同一视图大小切换。
    if (!_focusMode) return _buildFilterPage();

    return Column(
      children: [
        if (!_focusMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Icon(
                  _effectivePromptMode == PromptMode.audio
                      ? Icons.headphones
                      : Icons.image_outlined,
                  size: 18,
                  color: const Color(0xFF2d5016),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _deckSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _startFromWindow,
                  icon: const Icon(Icons.fullscreen, size: 18),
                  label: Text(
                    _answerMode == AnswerMode.learning ? '开始学习' : '开始打卡',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2d5016),
                  ),
                ),
              ],
            ),
          ),
        if (_focusMode) _buildFocusHeader(),
        if (!_focusMode && _deck.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '第 ${_groupOffset ~/ _groupSize + 1} 组  ${_idx - _groupOffset + 1}/${_groupEnd - _groupOffset}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    Text('✓ $_groupCorrect',
                        style:
                            const TextStyle(color: Colors.green, fontSize: 13)),
                    const SizedBox(width: 6),
                    Text('✗ $_groupWrong',
                        style:
                            const TextStyle(color: Colors.red, fontSize: 13)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '📚 ${widget.storage.unfamiliarCount}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.orange[700]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: _groupEnd > _groupOffset
                      ? (_idx - _groupOffset + 1) / (_groupEnd - _groupOffset)
                      : 0,
                  backgroundColor: Colors.grey[200],
                  color: const Color(0xFF2d7d32),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
        ],
        if (!_focusMode && _deck.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _deckSummary,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  _effectivePromptMode == PromptMode.image
                      ? '手势：左右切换同一物种照片；到边界后切换物种。上滑认识，下滑不认识。'
                      : '手势：上滑认识，下滑不认识；底部按钮切换上一种/下一种。',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(child: _buildMissingPackView())
                  : bird == null
                      ? Center(
                          child: Text(
                            '当前范围没有可用的${_effectivePromptMode == PromptMode.audio ? '音频' : '图片'}题目',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : _showGroupComplete
                          ? Center(child: _buildGroupCompleteView())
                          : FutureBuilder<List<Object?>>(
                              future: () {
                                if (_mediaFutureIdx != _idx) {
                                  _mediaFutureIdx = _idx;
                                  _mediaFuture = Future.wait<Object?>([
                                    _getAudioPaths(),
                                    _getAudioSpectrogramPaths(),
                                    _getStudyImages(),
                                  ]);
                                }
                                return _mediaFuture!;
                              }(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                final audioPaths =
                                    snapshot.data![0] as List<String>;
                                final spectrogramPaths =
                                    snapshot.data![1] as List<String>;
                                final studyImage = snapshot.data![2] as ({
                                  String? path,
                                  String? file,
                                  String credit,
                                  List<String> extraPaths,
                                  List<String> extraFiles,
                                  List<String> extraCredits,
                                });
                                final imagePath = studyImage.path;
                                final extraImagePaths = [
                                  ...studyImage.extraPaths,
                                  if (_imageDifficultyFilter == 0)
                                    ..._extraImagePaths,
                                ];
                                final extraImageSourceFiles = [
                                  ...studyImage.extraFiles,
                                  if (_imageDifficultyFilter == 0)
                                    ...const <String>[],
                                ];
                                final extraImageCredits = [
                                  ...studyImage.extraCredits,
                                  if (_imageDifficultyFilter == 0)
                                    ..._extraImageCredits,
                                ];
                                final labels = _cardAudios(bird)
                                    .map((a) => a.displayLabel)
                                    .toList();
                                _scheduleAutoPlay(audioPaths: audioPaths);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: _studyGestureSurface(
                                    enabled: _mode == StudyMode.review,
                                    child: _mode == StudyMode.quiz
                                        ? _buildQuizLayout(
                                            bird: bird,
                                            imagePath: imagePath,
                                            imageSourceFile: studyImage.file,
                                            imageCredit: studyImage.credit,
                                            audioPaths: audioPaths,
                                            labels: labels,
                                            audioSpectrogramPaths:
                                                spectrogramPaths,
                                            extraImagePaths: extraImagePaths,
                                            extraImageSourceFiles:
                                                extraImageSourceFiles,
                                            extraImageCredits:
                                                extraImageCredits,
                                          )
                                        : _buildCardScroller(
                                            bird: bird,
                                            imagePath: imagePath,
                                            imageSourceFile: studyImage.file,
                                            imageCredit: studyImage.credit,
                                            audioPaths: audioPaths,
                                            labels: labels,
                                            audioSpectrogramPaths:
                                                spectrogramPaths,
                                            extraImagePaths: extraImagePaths,
                                            extraImageSourceFiles:
                                                extraImageSourceFiles,
                                            extraImageCredits:
                                                extraImageCredits,
                                          ),
                                  ),
                                );
                              },
                            ),
        ),
        if (_focusMode && bird != null && !_isFinished) _buildStudyActions(),
        if (_focusMode &&
            bird != null &&
            !_isFinished &&
            _mode != StudyMode.quiz)
          _buildFocusAnswerDock(),
        if (!_focusMode && bird != null && !_isFinished)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _roundIconAction(
                        icon: widget.storage.isFavorite(bird.cn)
                            ? Icons.star
                            : Icons.star_border,
                        activeColor: widget.storage.isFavorite(bird.cn)
                            ? Colors.amber
                            : Colors.grey,
                        tooltip: '收藏',
                        onPressed: _toggleFav,
                      ),
                      _roundIconAction(
                        icon: Icons.help_outline,
                        tooltip: '识别特征',
                        onPressed: _editIdentificationNote,
                      ),
                      _roundIconAction(
                        icon: Icons.upload_outlined,
                        tooltip: '上传',
                        onPressed: _uploadMedia,
                      ),
                      _roundIconAction(
                        icon: Icons.tune,
                        tooltip: '筛选',
                        onPressed: _openFilterSheet,
                      ),
                      _roundIconAction(
                        icon: Icons.bug_report_outlined,
                        tooltip: '纠错',
                        onPressed: _reportIssue,
                      ),
                      _roundIconAction(
                        icon: Icons.refresh,
                        tooltip: '重来',
                        onPressed: _restart,
                      ),
                    ],
                  ),
                  if (_mode != StudyMode.quiz) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            label: '上一种',
                            color: Colors.grey[700]!,
                            enabled: _idx > 0,
                            onPressed: _previousCard,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            label: _isFinished ? '已完成' : '下一种',
                            color: const Color(0xFF2d5016),
                            enabled: !_isFinished,
                            onPressed: _nextCard,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 选择题选项里居中显示的鸟名行，按设置选中的形式（中文/英文/拉丁名）。
  List<Widget> _quizChoiceNameLines(Species choice, Color? color) {
    final modes = widget.storage.quizNameModes;
    final lines = <Widget>[];
    void add(String text, TextStyle style) {
      if (text.trim().isEmpty) return;
      lines.add(Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: style,
      ));
    }

    if (modes.contains('cn')) {
      add(
          choice.cn,
          TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1.15,
              color: color));
    }
    if (modes.contains('en')) {
      add(
          choice.en,
          TextStyle(
              fontSize: 13, height: 1.15, color: color ?? Colors.grey[700]));
    }
    if (modes.contains('sci')) {
      add(
          choice.sci,
          TextStyle(
              fontSize: 12,
              height: 1.15,
              fontStyle: FontStyle.italic,
              color: color ?? Colors.grey[600]));
    }
    if (lines.isEmpty) {
      final fallback = choice.cn.isNotEmpty
          ? choice.cn
          : (choice.en.isNotEmpty ? choice.en : choice.sci);
      add(fallback,
          TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color));
    }
    return lines;
  }

  Widget _buildQuizChoices(Species bird) {
    if (_quizChoices.length < 2) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          '选择题至少需要 2 个鸟种，当前数据包太小。',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '选择题',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            // 选项用可滚动列表 + 固定行高，避免在非全屏（空间被压缩）时
            // 每个选项被 Expanded 压成极矮、文字看不见的“空框”。
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _quizChoices.map((choice) {
                  final selected = _selectedChoiceSci == choice.sci;
                  final correct = choice.sci == bird.sci;
                  final color = !_answered
                      ? null
                      : correct
                          ? Colors.green
                          : selected
                              ? Colors.red
                              : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed:
                          _answered ? null : () => _answerQuizChoice(choice),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: color,
                        side: color == null ? null : BorderSide(color: color),
                        backgroundColor: color?.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      // 居中显示，名字形式由设置决定（中文/英文/拉丁名可多选）
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _quizChoiceNameLines(choice, color),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            if (_answered)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (_selectedChoiceSci == bird.sci
                          ? Colors.green
                          : Colors.orange)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedChoiceSci == bird.sci
                        ? Colors.green
                        : Colors.orange,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _selectedChoiceSci == bird.sci
                          ? Icons.check_circle
                          : Icons.info_outline,
                      size: 16,
                      color: _selectedChoiceSci == bird.sci
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _selectedChoiceSci == bird.sci
                          ? '正确！${bird.cn}'
                          : '正确答案：${bird.cn}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _selectedChoiceSci == bird.sci
                            ? Colors.green[700]
                            : Colors.orange[800],
                      ),
                    ),
                  ],
                ),
              ),
            if (!_answered)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton(
                  onPressed: () {
                    final b = _currentBird;
                    if (b == null) return;
                    setState(() => _selectedChoiceSci = null);
                    _recordAnswer(b, isCorrect: false);
                    _showAnswer();
                    if (!_isFinished) {
                      Future.delayed(
                          const Duration(milliseconds: 1300), _nextCard);
                    }
                  },
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.grey[600]),
                  child: const Text('我不会，直接告诉我答案'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusHeader() {
    final total = _groupEnd - _groupOffset;
    final current = total <= 0 ? 0 : _idx - _groupOffset + 1;
    final progress = total <= 0 ? 0.0 : current / total;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: exitFocusMode,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('退出'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2d5016),
                  ),
                ),
                Expanded(
                  child: Text(
                    total <= 0 ? _deckSummary : '第 $current/$total 张',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _openFilterSheet,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('筛选'),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 4,
                backgroundColor: Colors.grey[200],
                color: const Color(0xFF2d7d32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizLayout({
    required Species bird,
    required String? imagePath,
    required String? imageSourceFile,
    required String imageCredit,
    required List<String> audioPaths,
    required List<String> labels,
    required List<String> audioSpectrogramPaths,
    required List<String> extraImagePaths,
    required List<String> extraImageSourceFiles,
    required List<String> extraImageCredits,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            SizedBox(
              height: constraints.maxHeight * 0.42,
              child: Center(
                child: _gestureCard(
                  bird: bird,
                  imagePath: imagePath,
                  imageSourceFile: imageSourceFile,
                  imageCredit: imageCredit,
                  audioPaths: audioPaths,
                  labels: labels,
                  audioSpectrogramPaths: audioSpectrogramPaths,
                  extraImagePaths: extraImagePaths,
                  extraImageSourceFiles: extraImageSourceFiles,
                  extraImageCredits: extraImageCredits,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _buildQuizChoices(bird)),
          ],
        );
      },
    );
  }

  Widget _buildCardScroller({
    required Species bird,
    required String? imagePath,
    required String? imageSourceFile,
    required String imageCredit,
    required List<String> audioPaths,
    required List<String> labels,
    required List<String> audioSpectrogramPaths,
    required List<String> extraImagePaths,
    required List<String> extraImageSourceFiles,
    required List<String> extraImageCredits,
  }) {
    if (_focusMode) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 430,
                      maxHeight: constraints.maxHeight,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _mode == StudyMode.review &&
                              !_answered &&
                              !_showAnswerOnEntry
                          ? _reveal
                          : null,
                      child: _gestureCard(
                        bird: bird,
                        imagePath: imagePath,
                        imageSourceFile: imageSourceFile,
                        imageCredit: imageCredit,
                        audioPaths: audioPaths,
                        labels: labels,
                        audioSpectrogramPaths: audioSpectrogramPaths,
                        extraImagePaths: extraImagePaths,
                        extraImageSourceFiles: extraImageSourceFiles,
                        extraImageCredits: extraImageCredits,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 132),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap:
                _mode == StudyMode.review && !_answered && !_showAnswerOnEntry
                    ? _reveal
                    : null,
            child: _gestureCard(
              bird: bird,
              imagePath: imagePath,
              imageSourceFile: imageSourceFile,
              imageCredit: imageCredit,
              audioPaths: audioPaths,
              labels: labels,
              audioSpectrogramPaths: audioSpectrogramPaths,
              extraImagePaths: extraImagePaths,
              extraImageSourceFiles: extraImageSourceFiles,
              extraImageCredits: extraImageCredits,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gestureCard({
    required Species bird,
    required String? imagePath,
    required String? imageSourceFile,
    required String imageCredit,
    required List<String> audioPaths,
    required List<String> labels,
    required List<String> audioSpectrogramPaths,
    required List<String> extraImagePaths,
    required List<String> extraImageSourceFiles,
    required List<String> extraImageCredits,
  }) {
    return Stack(
      children: [
        BirdCard(
          key: _cardKey,
          species: bird,
          imagePath: imagePath,
          imageSourceFile: imageSourceFile,
          imageCredit: imageCredit,
          audioPaths: audioPaths,
          audioLabels: labels,
          audioSpectrogramPaths: audioSpectrogramPaths,
          audioPlayerKey: _audioKey,
          onPreviousSpecies: _mode == StudyMode.quiz ? null : _previousCard,
          onNextSpecies: _mode == StudyMode.quiz ? null : _nextCard,
          mode: _mode,
          promptMode: _effectivePromptMode,
          initiallyShowAnswer: _showAnswerOnEntry,
          extraImagePaths: extraImagePaths,
          extraImageSourceFiles: extraImageSourceFiles,
          extraImageCredits: extraImageCredits,
          isFocused: _focusMode,
          isAdmin: widget.storage.isAdminMode,
          onDifficultyChanged: (diff) async {
            final packDir = await widget.packManager
                .findWritablePackDirForSpecies(bird.sci);
            if (packDir == null) return;
            await widget.packManager.saveSpeciesDifficulty(
              packDir,
              bird.sci,
              diff,
            );
            if (widget.storage.isAdminMode) {
              AdminUploadService()
                  .setDifficulty(
                    sci: bird.sci,
                    difficulty: diff,
                    token: widget.storage.getAdminUploadToken(),
                  )
                  .ignore();
            }
            if (!mounted) return;
            setState(() {
              final i = _allSpecies.indexWhere((s) => s.sci == bird.sci);
              if (i >= 0) {
                _allSpecies[i] = _allSpecies[i].copyWith(difficulty: diff);
              }
              for (var j = 0; j < _deck.length; j++) {
                if (_deck[j].species.sci == bird.sci) {
                  _deck[j] = _deck[j]
                      .withSpecies(_deck[j].species.copyWith(difficulty: diff));
                }
              }
            });
          },
          onImageDifficultyChanged: (imageFile, diff) async {
            final packDir = await widget.packManager
                .findWritablePackDirForSpecies(bird.sci);
            if (packDir == null) return;
            await widget.packManager.saveSpeciesImageDifficulty(
              packDir,
              bird.sci,
              imageFile,
              diff,
            );
            if (widget.storage.isAdminMode) {
              AdminUploadService()
                  .setImageDifficulty(
                    sci: bird.sci,
                    file: imageFile,
                    difficulty: diff,
                    token: widget.storage.getAdminUploadToken(),
                  )
                  .ignore();
            }
            if (!mounted) return;
            setState(() {
              final i = _allSpecies.indexWhere((s) => s.sci == bird.sci);
              if (i >= 0) {
                final updatedImages = _allSpecies[i].images.map((img) {
                  return img.file == imageFile
                      ? SpeciesImageInfo(
                          file: img.file,
                          credit: img.credit,
                          contributor: img.contributor,
                          contributorUrl: img.contributorUrl,
                          source: img.source,
                          license: img.license,
                          difficulty: diff,
                        )
                      : img;
                }).toList();
                _allSpecies[i] = _allSpecies[i].copyWith(images: updatedImages);
              }
              final j = _deck.indexWhere((c) => c.species.sci == bird.sci);
              if (j >= 0) {
                final updatedImages = _deck[j].species.images.map((img) {
                  return img.file == imageFile
                      ? SpeciesImageInfo(
                          file: img.file,
                          credit: img.credit,
                          contributor: img.contributor,
                          contributorUrl: img.contributorUrl,
                          source: img.source,
                          license: img.license,
                          difficulty: diff,
                        )
                      : img;
                }).toList();
                _deck[j] = _deck[j].withSpecies(
                    _deck[j].species.copyWith(images: updatedImages));
              }
            });
          },
          onLearnMore: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BirdPreviewScreen(
                  species: bird,
                  packManager: widget.packManager,
                  storage: widget.storage,
                ),
              ),
            );
          },
        ),
        if (_swipeCheckVisible)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _swipeCheckVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _studyGestureSurface({
    required bool enabled,
    required Widget child,
  }) {
    if (!enabled) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _studyPointerStart = event.position;
        _studyPointerLatest = event.position;
      },
      onPointerMove: (event) {
        _studyPointerLatest = event.position;
      },
      onPointerCancel: (_) {
        _studyPointerStart = null;
        _studyPointerLatest = null;
      },
      onPointerUp: (_) => _finishStudyPointer(),
      child: child,
    );
  }

  void _finishStudyPointer() {
    final start = _studyPointerStart;
    final latest = _studyPointerLatest;
    _studyPointerStart = null;
    _studyPointerLatest = null;
    if (start == null || latest == null || _mode == StudyMode.quiz) return;
    final delta = latest - start;
    final dx = delta.dx;
    final dy = delta.dy;

    if (dx.abs() > 64 &&
        dx.abs() > dy.abs() * 1.35 &&
        _effectivePromptMode == PromptMode.audio) {
      if (dx < 0) {
        _nextCard();
      } else {
        _previousCard();
      }
      return;
    }

    if (_answered || dy.abs() < 70 || dy.abs() < dx.abs() * 1.35) return;
    if (dy < 0) {
      _markCorrect(fromSwipe: true);
    } else {
      _markWrong();
    }
  }

  Widget _buildFocusAnswerDock() {
    final canGrade = _revealed || _showAnswerOnEntry || _answered;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: canGrade
            ? Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: '不认识',
                      color: Colors.red[600]!,
                      enabled: !_answered,
                      onPressed: _markWrong,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _actionButton(
                      label: '认识',
                      color: const Color(0xFF2d7d32),
                      enabled: !_answered,
                      onPressed: _markCorrect,
                    ),
                  ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                child: _actionButton(
                  label: '看答案',
                  color: const Color(0xFF2d5016),
                  onPressed: _showAnswer,
                ),
              ),
      ),
    );
  }

  Widget _roundIconAction({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? activeColor,
  }) {
    return IconButton(
      icon: Icon(icon, size: 25, color: activeColor),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
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
            '请前往“设置 > 数据包管理”安装内置包、导入 ZIP，或使用在线下载功能开始预习和打卡。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCompleteView() {
    final groupNum = _groupOffset ~/ _groupSize + 1;
    final hasMore = _groupOffset + _groupSize < _deck.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF2d7d32),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2d7d32).withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '第 $groupNum 组完成！',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2d5016),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '本组：认识 $_groupCorrect 种　不认识 $_groupWrong 种',
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
          if (_correctCount + _wrongCount > _groupCorrect + _groupWrong) ...[
            const SizedBox(height: 4),
            Text(
              '累计：认识 $_correctCount 种　不认识 $_wrongCount 种',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _retryGroup,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重学本组'),
              ),
              if (_groupWrongSpecies.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _reviewGroupWrongs,
                  icon: const Icon(Icons.priority_high_rounded, size: 18),
                  label: const Text('复习错题'),
                ),
              FilledButton.icon(
                onPressed: hasMore ? _advanceGroup : _restart,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2d7d32),
                ),
                icon: Icon(
                  hasMore ? Icons.arrow_forward_rounded : Icons.celebration,
                  size: 18,
                ),
                label: Text(hasMore ? '继续下一组' : '全部完成，重新开始'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
