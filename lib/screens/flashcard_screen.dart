import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

enum AnswerMode {
  learning,
  review,
}

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
  String _order = 'random';
  String _taxonomicOrder = 'all';
  int _imageDifficultyFilter = 0;
  Set<String> _ebirdFilterSci = const {};
  String _ebirdFilterLabel = '';
  AnswerMode _answerMode = AnswerMode.review;
  StudyMode _mode = StudyMode.review;
  PromptMode _promptMode = PromptMode.audio;
  bool _showAdvancedControls = false;

  int _correctCount = 0; // session totals (used in restart resets)
  int _wrongCount = 0;

  // Bird group tracking
  int get _groupSize => widget.storage.flashcardGroupSize;
  int _groupOffset = 0;
  bool _showGroupComplete = false;
  int _groupCorrect = 0;
  int _groupWrong = 0;

  // Extra images from server for current bird
  List<String> _extraImagePaths = [];
  List<String> _extraImageCredits = [];
  String? _extraImagesForSci;

  final _cardKey = GlobalKey<BirdCardState>();
  final _audioKey = GlobalKey<AudioPlayerWidgetState>();
  String? _swipeFeedbackText;
  bool _swipeFeedbackVisible = false;
  Offset? _cardPointerStart;
  Offset? _cardPointerLatest;

  bool get _showAnswerOnEntry =>
      _answerMode == AnswerMode.learning && _mode == StudyMode.review;

  PromptMode get _effectivePromptMode => _promptMode;

  int get _groupEnd => (_groupOffset + _groupSize).clamp(0, _deck.length);

  bool get _isGroupFinished =>
      _deck.isNotEmpty && _idx >= _groupEnd - 1 && _answered;

  @override
  void initState() {
    super.initState();
    _loadSpecies();
  }

  @override
  void didUpdateWidget(covariant FlashcardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
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
      final media = await _buildMediaAvailability(list);
      if (!mounted) return;
      setState(() {
        _allSpecies = list;
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

  void _scheduleAutoPlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentBird == null || _isFinished) return;
      if (_effectivePromptMode != PromptMode.audio) return;
      _audioKey.currentState?.autoPlay();
    });
  }

  void _resetCardFace() {
    _audioKey.currentState?.stop();
    if (_showAnswerOnEntry) {
      _cardKey.currentState?.showBack();
    } else {
      _cardKey.currentState?.showFront();
    }
    _revealed = _showAnswerOnEntry;
    _answered = false;
    _selectedChoiceSci = null;
    _quizChoices = const [];
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
    }

    if (_ebirdFilterSci.isNotEmpty) {
      list = list
          .where((species) =>
              _ebirdFilterSci.contains(species.sci.trim().toLowerCase()))
          .toList();
    }

    list = list.where(_hasPromptMedia).toList();
    if (_effectivePromptMode == PromptMode.image &&
        _imageDifficultyFilter > 0) {
      list = list.where(_hasImageAtDifficulty).toList();
    }

    if (_taxonomicOrder != 'all') {
      list = list.where((s) => s.order == _taxonomicOrder).toList();
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
      _groupOffset = 0;
      _groupCorrect = 0;
      _groupWrong = 0;
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

  Species? get _currentBird => _deck.isEmpty ? null : _deck[_idx];

  bool get _isFinished => _isGroupFinished;

  String get _deckSummary {
    final orderText = _taxonomicOrder == 'all' ? '' : ' · $_taxonomicOrder';
    final ebirdText = _ebirdFilterLabel.isEmpty ? '' : ' · $_ebirdFilterLabel';
    final promptText = _effectivePromptMode == PromptMode.audio ? '音频' : '图片';
    switch (_filter) {
      case 'studied':
        return '当前牌组：已学习 · $promptText$orderText$ebirdText';
      case 'unseen':
        return '当前牌组：未学习 · $promptText$orderText$ebirdText';
      case 'g1':
        return '当前牌组：国家一级保护 · $promptText$orderText$ebirdText';
      case 'g2':
        return '当前牌组：国家二级保护 · $promptText$orderText$ebirdText';
      case 'favorites':
        return '当前牌组：收藏 · $promptText$orderText$ebirdText';
      case 'unfamiliar':
        return '当前牌组：不熟悉 · $promptText$orderText$ebirdText';
      default:
        return '当前牌组：全部 · $promptText$orderText$ebirdText';
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

  List<String> get _availableOrders {
    final orders = _allSpecies
        .map((species) => species.order)
        .where((order) => order.trim().isNotEmpty)
        .toSet();
    return BirdOrderTaxonomy.sortOrders(orders);
  }

  String _orderLabel(String order) => BirdOrderTaxonomy.label(order);

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

  void _jumpToSpecies(Species target) {
    final di = _deck.indexWhere((s) => s.sci == target.sci);
    if (di >= 0) {
      setState(() {
        _idx = di;
        _resetCardFace();
      });
      _prepareQuizChoices();
      _scheduleAutoPlay();
      return;
    }

    if (_allSpecies.any((s) => s.sci == target.sci)) {
      setState(() {
        _filter = 'all';
        _order = 'alpha';
      });
      _buildDeck();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToSpecies(target),
      );
    }
  }

  void _markCorrect() {
    if (_answered) return;
    final bird = _currentBird;
    if (bird == null) return;

    _recordAnswer(bird, isCorrect: true);
    if (!_isFinished) {
      Future.delayed(const Duration(milliseconds: 700), _nextCard);
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
        Future.delayed(const Duration(milliseconds: 1500), _nextCard);
      }
      return;
    }
    if (_mode == StudyMode.quiz && !_isFinished) {
      Future.delayed(const Duration(milliseconds: 900), _nextCard);
    }
  }

  void _showSwipeFeedback(bool correct) {
    setState(() {
      _swipeFeedbackText = correct ? '认识' : '不认识';
      _swipeFeedbackVisible = true;
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _swipeFeedbackVisible = false);
    });
  }

  void _recordAnswer(Species bird, {required bool isCorrect}) {
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
      widget.storage.markWrong();
      widget.storage.markSpeciesUnknown(bird.cn);
    }

    setState(() {});

    if (_isGroupFinished) {
      Future.delayed(
        _mode == StudyMode.review
            ? const Duration(milliseconds: 1600)
            : const Duration(milliseconds: 400),
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
    if (!_isFinished) {
      Future.delayed(const Duration(milliseconds: 1100), _nextCard);
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

    await widget.storage.addFeedbackEntry(
      message: controller.text,
      page: '闪卡学习',
      speciesCn: bird.cn,
      speciesSci: bird.sci,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存到纠错日记')));
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

  Future<void> _uploadBirdImage() async {
    final bird = _currentBird;
    if (bird == null) return;

    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;

    try {
      await widget.packManager.replaceSpeciesImageFromFile(bird, path);
      if (widget.storage.isAdminMode) {
        await AdminUploadService().uploadMedia(
          species: bird,
          filePath: path,
          token: widget.storage.getAdminUploadToken(),
        );
      }
      await _loadSpecies();
      final updated = _allSpecies.firstWhere(
        (species) => species.sci == bird.sci,
        orElse: () => bird,
      );
      _jumpToSpecies(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
        content: Text(
            widget.storage.isAdminMode ? '鸟图已保存到当前数据包，并推送到服务器' : '鸟图已保存到当前数据包'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传鸟图失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _uploadBirdAudio() async {
    final bird = _currentBird;
    if (bird == null) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;

    try {
      await widget.packManager.addSpeciesAudioFromFile(bird, path);
      if (widget.storage.isAdminMode) {
        await AdminUploadService().uploadMedia(
          species: bird,
          filePath: path,
          token: widget.storage.getAdminUploadToken(),
        );
      }
      await _loadSpecies();
      final updated = _allSpecies.firstWhere(
        (species) => species.sci == bird.sci,
        orElse: () => bird,
      );
      _jumpToSpecies(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
        content: Text(
            widget.storage.isAdminMode ? '音频已保存到当前数据包，并推送到服务器' : '音频已保存到当前数据包'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传音频失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _applyEBirdDeckFilter() async {
    final apiKey = widget.storage.getEBirdApiKey();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置页填写 eBird API key')));
      return;
    }

    final controller = TextEditingController(text: _ebirdFilterLabel);
    final query = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'eBird 地点筛选',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '输入国家、地区或热点代码，把当前闪卡范围收窄到这个地点出现过的鸟种。',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '例如 中国、云南、那邦、CN、CN-53、L3124991',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: EBirdService.presets.take(8).map((preset) {
                  return ActionChip(
                    label: Text(preset.label),
                    onPressed: () => Navigator.pop(ctx, preset.code),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, '__clear__'),
                    child: const Text('清除地点'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: const Text('应用'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (query == null) return;
    if (query == '__clear__') {
      setState(() {
        _ebirdFilterSci = const {};
        _ebirdFilterLabel = '';
      });
      _buildDeck();
      return;
    }
    if (query.trim().isEmpty) return;

    try {
      setState(() => _loading = true);
      final matches = await EBirdService(apiKey: apiKey).fetchSpeciesMatches(
        query,
      );
      final sciSet = await _matchEBirdToScientificNames(matches);
      if (!mounted) return;
      setState(() {
        _ebirdFilterSci = sciSet;
        _ebirdFilterLabel = EBirdService.normalizeLocationCode(query);
      });
      _buildDeck();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已按 $_ebirdFilterLabel 匹配 ${sciSet.length} 种')),
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
    setState(() {
      _filter = filter;
      _answerMode = AnswerMode.learning;
      _mode = mode;
      _promptMode = promptMode;
      _order = order;
      _taxonomicOrder = 'all';
      _correctCount = 0;
      _wrongCount = 0;
      _quizChoiceCache.clear();
    });
    _buildDeck();
  }

  Widget _difficultySelector() {
    String labelFor(int value) {
      if (value == 0) return '全部';
      return List.filled(value, '⭐').join();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('难度:', style: TextStyle(fontSize: 13)),
          ...List.generate(6, (i) {
            final selected = _imageDifficultyFilter == i;
            return ChoiceChip(
              label: Text(
                labelFor(i),
                style: TextStyle(
                  fontSize: i == 0 ? 12 : 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              selected: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selectedColor: const Color(0xFF2d5016).withValues(alpha: 0.16),
              onSelected: (_) {
                setState(() => _imageDifficultyFilter = i);
                _buildDeck();
              },
            );
          }),
        ],
      ),
    );
  }

  void _restart() {
    setState(() {
      _correctCount = 0;
      _wrongCount = 0;
      _groupOffset = 0;
      _groupCorrect = 0;
      _groupWrong = 0;
      _showGroupComplete = false;
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
                    onPressed: _applyEBirdDeckFilter,
                    icon: Icon(
                      Icons.place_outlined,
                      size: 18,
                      color: _ebirdFilterSci.isEmpty
                          ? const Color(0xFF2d5016)
                          : Colors.white,
                    ),
                    label: Text(
                      _ebirdFilterSci.isEmpty ? '地点筛选' : _ebirdFilterLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _ebirdFilterSci.isEmpty
                          ? const Color(0xFF2d5016)
                          : Colors.white,
                      backgroundColor: _ebirdFilterSci.isEmpty
                          ? const Color(0xFF2d5016).withValues(alpha: 0.08)
                          : const Color(0xFF2d5016),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _showAdvancedControls = !_showAdvancedControls,
                    ),
                    icon: Icon(
                      _showAdvancedControls ? Icons.expand_less : Icons.tune,
                      size: 18,
                    ),
                    label: Text(_showAdvancedControls ? '收起' : '筛选'),
                  ),
                ],
              ),
              if (_showAdvancedControls) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const SizedBox(
                      width: 44,
                      child: Text('模式:', style: TextStyle(fontSize: 13)),
                    ),
                    SegmentedButton<AnswerMode>(
                        segments: const [
                          ButtonSegment(
                            value: AnswerMode.learning,
                            label: Text('学习', style: TextStyle(fontSize: 12)),
                          ),
                          ButtonSegment(
                            value: AnswerMode.review,
                            label: Text('复习', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        selected: {
                          _answerMode
                        },
                        onSelectionChanged: (v) {
                          setState(() {
                            _answerMode = v.first;
                            _correctCount = 0;
                            _wrongCount = 0;
                            _resetCardFace();
                          });
                        },
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const SizedBox(
                      width: 44,
                      child: Text('题型:', style: TextStyle(fontSize: 13)),
                    ),
                    SegmentedButton<StudyMode>(
                        segments: const [
                          ButtonSegment(
                            value: StudyMode.review,
                            label: Text('判断', style: TextStyle(fontSize: 12)),
                          ),
                          ButtonSegment(
                            value: StudyMode.quiz,
                            label: Text('选择', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        selected: {
                          _mode
                        },
                        onSelectionChanged: (v) {
                          setState(() {
                            _mode = v.first;
                            _correctCount = 0;
                            _wrongCount = 0;
                            _resetCardFace();
                          });
                          _buildDeck();
                        },
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const SizedBox(
                      width: 44,
                      child: Text('出题:', style: TextStyle(fontSize: 13)),
                    ),
                    SegmentedButton<PromptMode>(
                        segments: const [
                          ButtonSegment(
                            value: PromptMode.audio,
                            icon: Icon(Icons.headphones, size: 16),
                            label: Text('音频', style: TextStyle(fontSize: 12)),
                          ),
                          ButtonSegment(
                            value: PromptMode.image,
                            icon: Icon(Icons.image_outlined, size: 16),
                            label: Text('图片', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        selected: {
                          _promptMode
                        },
                        onSelectionChanged: (v) {
                          setState(() {
                            _promptMode = v.first;
                            _correctCount = 0;
                            _wrongCount = 0;
                            _resetCardFace();
                          });
                          _buildDeck();
                        },
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )),
                  ],
                ),
                const SizedBox(height: 6),
                _difficultySelector(),
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
                          DropdownMenuItem(
                              value: 'studied', child: Text('已学习')),
                          DropdownMenuItem(value: 'unseen', child: Text('未学习')),
                          DropdownMenuItem(
                            value: 'unfamiliar',
                            child: Text('不熟悉'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _filter = v);
                          _buildDeck();
                        },
                      ),
                    ),
                    const Spacer(),
                    if (_availableOrders.isNotEmpty) ...[
                      const Text('目:', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 32,
                        width: 96,
                        child: DropdownButton<String>(
                          value: _taxonomicOrder,
                          isExpanded: true,
                          isDense: true,
                          underline: const SizedBox(),
                          items: [
                            const DropdownMenuItem(
                                value: 'all', child: Text('全部')),
                            ..._availableOrders.map(
                              (order) => DropdownMenuItem(
                                value: order,
                                child: Text(_orderLabel(order),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _taxonomicOrder = v);
                            _buildDeck();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
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
                          DropdownMenuItem(
                              value: 'review_time', child: Text('久未复习')),
                          DropdownMenuItem(value: 'wrong', child: Text('错误多')),
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
            ],
          ),
        ),
        if (_deck.isNotEmpty) ...[
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
        if (_deck.isNotEmpty)
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
                              future: Future.wait<Object?>([
                                _getAudioPaths(),
                                _getStudyImages(),
                              ]),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                final audioPaths =
                                    snapshot.data![0] as List<String>;
                                final studyImage = snapshot.data![1] as ({
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
                                final labels = bird.audios
                                    .map((a) => a.displayLabel)
                                    .toList();

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  child: _mode == StudyMode.quiz
                                      ? _buildQuizLayout(
                                          bird: bird,
                                          imagePath: imagePath,
                                          imageSourceFile: studyImage.file,
                                          imageCredit: studyImage.credit,
                                          audioPaths: audioPaths,
                                          labels: labels,
                                          extraImagePaths: extraImagePaths,
                                          extraImageSourceFiles:
                                              extraImageSourceFiles,
                                          extraImageCredits: extraImageCredits,
                                        )
                                      : _buildCardScroller(
                                          bird: bird,
                                          imagePath: imagePath,
                                          imageSourceFile: studyImage.file,
                                          imageCredit: studyImage.credit,
                                          audioPaths: audioPaths,
                                          labels: labels,
                                          extraImagePaths: extraImagePaths,
                                          extraImageSourceFiles:
                                              extraImageSourceFiles,
                                          extraImageCredits: extraImageCredits,
                                        ),
                                );
                              },
                            ),
        ),
        if (bird != null && !_isFinished)
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
                        icon: Icons.add_photo_alternate_outlined,
                        tooltip: '上传鸟图',
                        onPressed: _uploadBirdImage,
                      ),
                      _roundIconAction(
                        icon: Icons.library_music_outlined,
                        tooltip: '上传音频',
                        onPressed: _uploadBirdAudio,
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
            Text(
              _answered ? '答案：${bird.cn}' : '选择题',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
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
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: OutlinedButton(
                        onPressed:
                            _answered ? null : () => _answerQuizChoice(choice),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: color,
                          side: color == null ? null : BorderSide(color: color),
                          backgroundColor: color?.withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  flex: 4,
                                  child: Text(
                                    choice.cn.isNotEmpty
                                        ? choice.cn
                                        : choice.en,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                                if (choice.en.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    flex: 5,
                                    child: Text(
                                      choice.en,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.1,
                                        color: color ?? Colors.grey[700],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
    required List<String> extraImagePaths,
    required List<String> extraImageSourceFiles,
    required List<String> extraImageCredits,
  }) {
    return SingleChildScrollView(
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
    required List<String> extraImagePaths,
    required List<String> extraImageSourceFiles,
    required List<String> extraImageCredits,
  }) {
    return Stack(
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _startCardPointer,
          onPointerMove: _updateCardPointer,
          onPointerUp: (_) => _finishCardPointer(),
          onPointerCancel: (_) => _clearCardPointer(),
          child: BirdCard(
            key: _cardKey,
            species: bird,
            imagePath: imagePath,
            imageSourceFile: imageSourceFile,
            imageCredit: imageCredit,
            audioPaths: audioPaths,
            audioLabels: labels,
            audioPlayerKey: _audioKey,
            onPreviousSpecies: _previousCard,
            onNextSpecies: _nextCard,
            mode: _mode,
            promptMode: _effectivePromptMode,
            initiallyShowAnswer: _showAnswerOnEntry,
            extraImagePaths: extraImagePaths,
            extraImageSourceFiles: extraImageSourceFiles,
            extraImageCredits: extraImageCredits,
            isAdmin: widget.storage.isAdminMode,
            onDifficultyChanged: (diff) async {
              final packDir = await widget.packManager.getActivePackDir();
              if (packDir == null) return;
              await widget.packManager
                  .saveSpeciesDifficulty(packDir, bird.sci, diff);
              await _loadSpecies();
            },
            onImageDifficultyChanged: (imageFile, diff) async {
              final packDir = await widget.packManager.getActivePackDir();
              if (packDir == null) return;
              await widget.packManager.saveSpeciesImageDifficulty(
                packDir,
                bird.sci,
                imageFile,
                diff,
              );
              await _loadSpecies();
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
        ),
        // 滑动反馈浮层
        if (_swipeFeedbackText != null)
          AnimatedOpacity(
            opacity: _swipeFeedbackVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  decoration: BoxDecoration(
                    color:
                        (_swipeFeedbackText == '认识' ? Colors.green : Colors.red)
                            .withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _swipeFeedbackText == '认识' ? '认识 ✓' : '不认识 ✗',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _startCardPointer(PointerDownEvent event) {
    _cardPointerStart = event.position;
    _cardPointerLatest = event.position;
  }

  void _updateCardPointer(PointerMoveEvent event) {
    _cardPointerLatest = event.position;
  }

  void _finishCardPointer() {
    final start = _cardPointerStart;
    final latest = _cardPointerLatest;
    _clearCardPointer();
    if (start == null || latest == null) return;
    final delta = latest - start;
    final dx = delta.dx;
    final dy = delta.dy;
    if (dy.abs() < 54 || dy.abs() < dx.abs() * 1.35) return;
    if (dy < 0) {
      _showSwipeFeedback(true);
      _markCorrect();
    } else {
      _showSwipeFeedback(false);
      _markWrong();
    }
  }

  void _clearCardPointer() {
    _cardPointerStart = null;
    _cardPointerLatest = null;
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
            '请前往“数据包”页安装内置试用包、导入 ZIP，或使用在线导入功能开始学习。',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _retryGroup,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重学本组'),
              ),
              if (hasMore) ...[
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _advanceGroup,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2d7d32),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('继续下一组'),
                ),
              ] else ...[
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _restart,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2d7d32),
                  ),
                  icon: const Icon(Icons.celebration, size: 18),
                  label: const Text('全部完成，重新开始'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
