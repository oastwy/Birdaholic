import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_upload_service.dart';
import '../services/ebird_service.dart';
import '../services/pack_manager.dart';
import '../services/pinyin.dart';
import '../services/storage.dart';
import '../utils/file_picker_guard.dart';

class _WorldBird {
  final String sci;
  final String en;
  final String zh;
  final String code;
  const _WorldBird({
    required this.sci,
    required this.en,
    required this.zh,
    required this.code,
  });
}

class _UploadResult {
  final String fileName;
  final bool success;
  final bool pending;
  final String? error;
  const _UploadResult({
    required this.fileName,
    required this.success,
    this.pending = false,
    this.error,
  });
}

class UploadSection extends StatefulWidget {
  final StorageService storage;
  final PackManager packManager;
  final VoidCallback onOpenReview; // admin only
  final VoidCallback onOpenUserManagement; // admin only
  final VoidCallback onOpenFeedbackReview; // admin only
  final VoidCallback onOpenServerMediaManager; // admin only
  final VoidCallback onBackToRoot;

  const UploadSection({
    super.key,
    required this.storage,
    required this.packManager,
    required this.onOpenReview,
    required this.onOpenUserManagement,
    required this.onOpenFeedbackReview,
    required this.onOpenServerMediaManager,
    required this.onBackToRoot,
  });

  @override
  State<UploadSection> createState() => _UploadSectionState();
}

class _UploadSectionState extends State<UploadSection> {
  List<_WorldBird> _allBirds = [];
  Set<String> _ebirdSciSet = {};
  bool _ebirdLoading = false;
  String _ebirdLabel = '';
  List<_WorldBird> _searchResults = [];
  _WorldBird? _selectedBird;

  final _speciesCtrl = TextEditingController();
  final _contributorCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _regionCtrl = TextEditingController(text: 'CN');
  final _featuresCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  Timer? _searchDebounce;

  final List<File> _selectedFiles = [];
  String? _selectedMediaType;
  String _audioType = 'call';
  int _difficulty = 1;

  SpeciesMediaCount? _selectedSpeciesCount;

  bool _uploading = false;
  bool _pickingFiles = false;
  int _uploadProgress = 0;
  List<_UploadResult> _uploadResults = [];

  UploadStats? _stats;
  bool _statsLoading = false;

  late final AdminUploadService _service;

  @override
  void initState() {
    super.initState();
    _service = AdminUploadService();
    _contributorCtrl.text = widget.storage.getContributorName();
    _locationCtrl.text = widget.storage.getUploadLocation();
    _loadWorldBirds();
    _refreshStats();
  }

  @override
  void dispose() {
    FilePickerGuard.forceReset();
    _speciesCtrl.dispose();
    _contributorCtrl.dispose();
    _locationCtrl.dispose();
    _regionCtrl.dispose();
    _featuresCtrl.dispose();
    _descriptionCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── 数据加载 ─────────────────────────────────────────────────

  Future<void> _loadWorldBirds() async {
    try {
      final raw = await rootBundle.loadString('assets/data/world_birds.json');
      final list = jsonDecode(raw) as List<dynamic>;
      final birds = list
          .whereType<Map<String, dynamic>>()
          .map((m) {
            return _WorldBird(
              sci: (m['sci'] as String? ?? '').trim(),
              en: (m['en'] as String? ?? '').trim(),
              zh: (m['zh'] as String? ?? '').trim(),
              code: (m['code'] as String? ?? '').trim(),
            );
          })
          .where((b) => b.sci.isNotEmpty)
          .toList();
      if (mounted) setState(() => _allBirds = birds);
    } catch (e) {
      // ignore
    }
  }

  Future<void> _refreshStats() async {
    final token = widget.storage.getAdminUploadToken();
    if (token.isEmpty) return;
    setState(() => _statsLoading = true);
    try {
      final stats = await _service.fetchStats(token: token);
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  // ── 物种搜索 ─────────────────────────────────────────────────

  List<_WorldBird> get _searchPool {
    if (_ebirdSciSet.isEmpty) return _allBirds;
    return _allBirds
        .where((b) => _ebirdSciSet.contains(b.sci.toLowerCase()))
        .toList();
  }

  void _onSpeciesChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      final q = value.trim().toLowerCase();
      if (q.isEmpty) {
        setState(() => _searchResults = []);
        return;
      }
      final pool = _searchPool;
      final results = <_WorldBird>[];
      for (final b in pool) {
        if (b.zh.contains(q) ||
            b.sci.toLowerCase().contains(q) ||
            b.en.toLowerCase().contains(q) ||
            b.code.toLowerCase() == q ||
            Pinyin.initials(b.zh).contains(q)) {
          results.add(b);
          if (results.length >= 12) break;
        }
      }
      if (mounted) setState(() => _searchResults = results);
    });
  }

  void _selectBird(_WorldBird b) {
    setState(() {
      _selectedBird = b;
      _speciesCtrl.text = '${b.zh.isEmpty ? b.en : b.zh} · ${b.sci}';
      _searchResults = [];
      _selectedSpeciesCount = null;
    });
    FocusScope.of(context).unfocus();
    _refreshSpeciesCount(b.sci);
  }

  Future<void> _refreshSpeciesCount(String sci) async {
    try {
      final c = await _service.fetchSpeciesMediaCount(sci: sci);
      if (!mounted || _selectedBird?.sci != sci) return;
      setState(() => _selectedSpeciesCount = c);
    } catch (_) {}
  }

  // ── 地区筛选 ────────────────────────────────────────────────

  Future<void> _applyRegionFilter() async {
    final code = _regionCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final ebirdKey = widget.storage.getEBirdApiKey();
    if (ebirdKey.isEmpty) {
      _showSnack('请先在设置里填写 eBird API Key');
      return;
    }
    setState(() {
      _ebirdLoading = true;
      _ebirdLabel = '';
    });
    try {
      final service = EBirdService(apiKey: ebirdKey);
      final matches = await service.fetchSpeciesMatches(code);
      final sciSet = matches
          .map((m) => m.scientificName.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (mounted) {
        setState(() {
          _ebirdSciSet = sciSet;
          _ebirdLabel = '已筛 ${sciSet.length} 种（$code）';
        });
      }
    } catch (e) {
      _showSnack('地区筛选失败：$e');
    } finally {
      if (mounted) setState(() => _ebirdLoading = false);
    }
  }

  void _clearRegion() {
    setState(() {
      _ebirdSciSet = {};
      _ebirdLabel = '';
    });
  }

  // ── 文件选择 ────────────────────────────────────────────────

  Future<void> _pickFiles(FileType type, List<String>? exts) async {
    if (_pickingFiles) return;
    final mediaType = type == FileType.image ? 'image' : 'audio';
    if (_selectedMediaType != null && _selectedMediaType != mediaType) {
      _showSnack('请分开上传图片和音频，避免标签混乱');
      return;
    }
    setState(() => _pickingFiles = true);
    try {
      final result = await FilePickerGuard.pickFiles(
        type: type,
        allowedExtensions: exts,
        allowMultiple: true,
      );
      if (result == null) return;
      setState(() {
        _selectedMediaType = mediaType;
        for (final f in result.files) {
          if (f.path != null) _selectedFiles.add(File(f.path!));
        }
      });
    } catch (e) {
      final message =
          '$e'.contains('multiple_request') ? '文件选择器还在打开，请稍等一下再试' : '$e';
      _showSnack('选取文件失败：$message');
    } finally {
      if (mounted) setState(() => _pickingFiles = false);
    }
  }

  void _removeFile(int i) {
    setState(() {
      _selectedFiles.removeAt(i);
      if (_selectedFiles.isEmpty) _selectedMediaType = null;
    });
  }

  // ── 上传 ─────────────────────────────────────────────────────

  bool _ccChecked = false;

  bool get _canUpload =>
      _selectedBird != null &&
      _contributorCtrl.text.trim().isNotEmpty &&
      _selectedFiles.isNotEmpty &&
      _ccChecked &&
      !_uploading;

  Future<void> _upload() async {
    if (!_canUpload) return;
    final token = widget.storage.getAdminUploadToken();
    if (token.isEmpty) {
      _showSnack('请先在设置里填写上传 Token');
      return;
    }
    await widget.storage.setContributorName(_contributorCtrl.text.trim());
    await widget.storage.setUploadLocation(_locationCtrl.text.trim());
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _uploadResults = [];
    });
    final sci = _selectedBird!.sci;
    final contributor = _contributorCtrl.text.trim();
    final isBeta = widget.storage.isBetaMode;
    final results = <_UploadResult>[];
    for (var i = 0; i < _selectedFiles.length; i++) {
      final file = _selectedFiles[i];
      final fname = file.path.split(Platform.pathSeparator).last;
      try {
        final resp = await _service.uploadFile(
          sci: sci,
          contributor: contributor,
          filePath: file.path,
          token: token,
          difficulty: _difficulty,
          description: _descriptionCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          mediaType: _selectedMediaType ?? '',
          audioType: _selectedMediaType == 'audio' ? _audioType : '',
          license: 'CC BY-NC 4.0',
        );
        final saved = (resp['saved'] as List?) ?? [];
        final failed = (resp['failed'] as List?) ?? [];
        if (saved.isNotEmpty) {
          if (widget.storage.isAdminMode) {
            final first = saved.first;
            final entry = first is Map && first['entry'] is Map
                ? Map<String, dynamic>.from(first['entry'] as Map)
                : <String, dynamic>{};
            if (_selectedMediaType == 'image') {
              await widget.packManager.addUploadedSpeciesImageFromFile(
                sci: sci,
                sourcePath: file.path,
                serverEntry: entry,
                difficulty: _difficulty,
              );
            } else if (_selectedMediaType == 'audio') {
              await widget.packManager.addUploadedSpeciesAudioFromFile(
                sci: sci,
                sourcePath: file.path,
                serverEntry: entry,
                audioType: _audioType,
              );
            }
          }
          results.add(_UploadResult(
            fileName: fname,
            success: true,
            pending: isBeta,
          ));
        } else if (failed.isNotEmpty) {
          final r = (failed.first as Map)['reason'] ?? '未知错误';
          results
              .add(_UploadResult(fileName: fname, success: false, error: '$r'));
        } else {
          results.add(const _UploadResult(
              fileName: '', success: false, error: '服务器无响应'));
        }
      } catch (e) {
        results
            .add(_UploadResult(fileName: fname, success: false, error: '$e'));
      }
      if (mounted) {
        setState(() {
          _uploadProgress = i + 1;
          _uploadResults = List.of(results);
        });
      }
    }
    // 识别特征
    final features = _featuresCtrl.text.trim();
    if (features.isNotEmpty) {
      try {
        // saveIdentificationFeatures 期望 species 对象，但这里只有 _WorldBird
        // 直接发 POST /api/features
        final uri = Uri.parse('${AdminUploadService().baseUrl}/api/features');
        final r = await HttpClient().postUrl(uri).then((req) async {
          req.headers.set('Authorization', 'Bearer $token');
          req.headers.contentType = ContentType.json;
          req.add(utf8.encode(jsonEncode({
            'sci': sci,
            'cn': _selectedBird!.zh,
            'en': _selectedBird!.en,
            'features': features,
            'token': token,
          })));
          return await req.close();
        });
        if (r.statusCode >= 200 && r.statusCode < 300) {
          results.add(const _UploadResult(fileName: '识别特征', success: true));
        } else {
          results.add(_UploadResult(
              fileName: '识别特征', success: false, error: 'HTTP ${r.statusCode}'));
        }
      } catch (e) {
        results
            .add(_UploadResult(fileName: '识别特征', success: false, error: '$e'));
      }
      if (mounted) setState(() => _uploadResults = List.of(results));
    }
    if (mounted) {
      setState(() {
        _uploading = false;
        _selectedFiles.clear();
        _selectedMediaType = null;
        _ccChecked = false;
      });
      _refreshStats();
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasToken = widget.storage.getAdminUploadToken().isNotEmpty;
    if (!hasToken) {
      return _buildNoTokenView();
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBackToRoot,
        ),
        title: const Text('上传数据'),
        actions: [
          if (widget.storage.isAdminMode)
            IconButton(
              tooltip: '审核待处理',
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.gavel_outlined),
                  if (_stats != null && _stats!.pendingTotal > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(minWidth: 16),
                        child: Text(
                          '${_stats!.pendingTotal}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: widget.onOpenReview,
            ),
          if (widget.storage.isAdminMode)
            IconButton(
              tooltip: '纠错审核',
              icon: const Icon(Icons.feedback_outlined),
              onPressed: widget.onOpenFeedbackReview,
            ),
          if (widget.storage.isAdminMode)
            IconButton(
              tooltip: '用户管理',
              icon: const Icon(Icons.group_outlined),
              onPressed: widget.onOpenUserManagement,
            ),
          if (widget.storage.isAdminMode)
            IconButton(
              tooltip: '服务器媒体管理',
              icon: const Icon(Icons.folder_delete_outlined),
              onPressed: widget.onOpenServerMediaManager,
            ),
          IconButton(
            tooltip: '刷新统计',
            icon: const Icon(Icons.refresh),
            onPressed: _statsLoading ? null : _refreshStats,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _statsCard(),
            const SizedBox(height: 14),
            _sectionHeader('地区筛选（可选）'),
            _regionSection(),
            const SizedBox(height: 16),
            _sectionHeader('物种 *'),
            _speciesSection(),
            if (_selectedBird != null && _selectedSpeciesCount != null)
              _speciesCountHint(),
            const SizedBox(height: 16),
            _sectionHeader('作者署名 *'),
            TextField(
              controller: _contributorCtrl,
              decoration: const InputDecoration(
                hintText: '录音者 / 摄影者姓名',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _sectionHeader('拍摄/录音地点（可选）'),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                hintText: '例：河北南堡 / 深圳湾 / 36.12, 120.32',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('难度评级'),
            _difficultyRow(),
            const SizedBox(height: 16),
            _sectionHeader(_selectedMediaType == 'audio'
                ? '描述（可选）'
                : '描述（可选） · 性别 / 年龄 / 羽况'),
            TextField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(
                hintText: '图片例：雄性成鸟夏羽；音频例：黎明鸣唱 / 飞行叫声',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_selectedMediaType == 'audio') ...[
              const SizedBox(height: 16),
              _sectionHeader('音频类型 *'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'call',
                    icon: Icon(Icons.record_voice_over_outlined),
                    label: Text('鸣叫 call'),
                  ),
                  ButtonSegment(
                    value: 'song',
                    icon: Icon(Icons.music_note_outlined),
                    label: Text('鸣唱 song'),
                  ),
                ],
                selected: {_audioType},
                onSelectionChanged: _uploading
                    ? null
                    : (values) => setState(() => _audioType = values.first),
              ),
            ],
            const SizedBox(height: 16),
            _sectionHeader('识别特征（可选）'),
            TextField(
              controller: _featuresCtrl,
              maxLines: 4,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: '描述该鸟种关键识别特征。例：体长 30cm，头黑顶白冠，喙橙红色…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _sectionHeader('选取文件 *'),
            _fileSection(),
            const SizedBox(height: 18),
            _uploadButton(),
            if (_uploadResults.isNotEmpty) ...[
              const SizedBox(height: 14),
              _resultList(),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildNoTokenView() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBackToRoot,
        ),
        title: const Text('上传数据'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text('需要先在「设置」里填写上传 Token', style: TextStyle(fontSize: 15)),
              SizedBox(height: 6),
              Text('设置后会自动获取你的身份（管理员 / 受邀用户）',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsCard() {
    final stats = _stats;
    final roleLabel = widget.storage.isAdminMode
        ? '管理员'
        : (widget.storage.isBetaMode ? '受邀用户' : '未识别');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[700]!, Colors.green[500]!],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                '我的上传 · $roleLabel',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (stats == null)
            const Text('—', style: TextStyle(color: Colors.white))
          else
            Row(
              children: [
                _statItem('已入库图片', stats.myImages.toString()),
                const SizedBox(width: 18),
                _statItem('已入库音频', stats.myAudio.toString()),
                const SizedBox(width: 18),
                _statItem('待审核', stats.myPending.toString()),
              ],
            ),
          if (widget.storage.isAdminMode) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: widget.onOpenReview,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gavel_outlined,
                        size: 20, color: Color(0xFF2d7d32)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stats != null && stats.pendingTotal > 0
                            ? '审核内测上传 · 有 ${stats.pendingTotal} 项待处理'
                            : '审核内测上传 · 当前无待处理',
                        style: const TextStyle(
                            color: Color(0xFF2d7d32),
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 20, color: Color(0xFF2d7d32)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
      ],
    );
  }

  Widget _speciesCountHint() {
    final c = _selectedSpeciesCount!;
    final total = c.images + c.audio;
    final overImg = c.images >= 20;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: overImg ? Colors.orange[50] : Colors.green[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: overImg ? Colors.orange[300]! : Colors.green[300]!),
        ),
        child: Row(
          children: [
            Icon(overImg ? Icons.warning_amber : Icons.photo_library_outlined,
                size: 16,
                color: overImg ? Colors.orange[700] : Colors.green[700]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                total == 0
                    ? '该物种暂时没有照片/音频，欢迎上传'
                    : overImg
                        ? '该物种已有 ${c.images} 张图片 · 已比较充足，建议优先补传其他物种'
                        : '该物种已有 ${c.images} 张图片 / ${c.audio} 个音频',
                style: TextStyle(
                  fontSize: 12,
                  color: overImg ? Colors.orange[900] : Colors.green[900],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    );
  }

  Widget _regionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _regionCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'eBird 代码：CN / CN-53 / AU…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _ebirdLoading ? null : _applyRegionFilter,
              child: _ebirdLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('应用'),
            ),
            if (_ebirdSciSet.isNotEmpty)
              IconButton(
                tooltip: '清除',
                onPressed: _clearRegion,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        if (_ebirdLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_ebirdLabel,
                style: TextStyle(fontSize: 12, color: Colors.green[700])),
          ),
      ],
    );
  }

  Widget _speciesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _speciesCtrl,
          decoration: InputDecoration(
            hintText: _selectedBird == null
                ? '搜索：白头鹤 / btn / Grus / Hooded'
                : '已选中，重新输入可重选',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: _selectedBird == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _selectedBird = null;
                      _speciesCtrl.clear();
                      _searchResults = [];
                    }),
                  ),
          ),
          onChanged: _onSpeciesChanged,
        ),
        if (_searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 250),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (ctx, i) {
                final b = _searchResults[i];
                return ListTile(
                  dense: true,
                  title: Text(b.zh.isEmpty ? b.en : b.zh,
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text('${b.en} · ${b.sci}',
                      style: const TextStyle(fontSize: 11)),
                  onTap: () => _selectBird(b),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _difficultyRow() {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed:
                _uploading ? null : () => setState(() => _difficulty = i),
            icon: Icon(
              i <= _difficulty
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: i <= _difficulty ? Colors.amber : Colors.grey,
            ),
            iconSize: 28,
          ),
        const SizedBox(width: 6),
        Text('$_difficulty / 5',
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _fileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_uploading || _pickingFiles)
                    ? null
                    : () => _pickFiles(FileType.image, null),
                icon: const Icon(Icons.image_outlined),
                label: const Text('选图片'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_uploading || _pickingFiles)
                    ? null
                    : () => _pickFiles(FileType.custom,
                        ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg']),
                icon: const Icon(Icons.audiotrack_outlined),
                label: const Text('选音频'),
              ),
            ),
          ],
        ),
        for (var i = 0; i < _selectedFiles.length; i++)
          ListTile(
            dense: true,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(
                _selectedFiles[i].path.split(Platform.pathSeparator).last,
                style: const TextStyle(fontSize: 13)),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _uploading ? null : () => _removeFile(i),
            ),
          ),
      ],
    );
  }

  Widget _uploadButton() {
    if (_uploading) {
      return Column(
        children: [
          LinearProgressIndicator(
            value: _selectedFiles.isEmpty
                ? null
                : _uploadProgress / _selectedFiles.length,
          ),
          const SizedBox(height: 6),
          Text('上传中 $_uploadProgress / ${_selectedFiles.length}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );
    }
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _ccChecked = !_ccChecked),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _ccChecked,
                onChanged: (v) => setState(() => _ccChecked = v ?? false),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse(
                          'https://creativecommons.org/licenses/by-nc/4.0/deed.zh-hans'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 12.5, height: 1.4),
                        children: [
                          TextSpan(text: '我确认拥有该媒体的版权，并以 '),
                          TextSpan(
                            text: 'CC BY-NC 4.0（署名-非商业性使用）',
                            style: TextStyle(
                              color: Color(0xFF2d5016),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          TextSpan(text: ' 协议授权 Birdaholic 使用'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _canUpload ? _upload : null,
            icon: const Icon(Icons.cloud_upload),
            label:
                Text(widget.storage.isBetaMode ? '提交上传（等管理员审核）' : '直接上传到服务器'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('上传结果',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          for (final r in _uploadResults)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    r.success
                        ? (r.pending ? Icons.hourglass_top : Icons.check_circle)
                        : Icons.error_outline,
                    size: 16,
                    color: r.success
                        ? (r.pending ? Colors.orange : Colors.green)
                        : Colors.red,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.success
                          ? (r.pending
                              ? '${r.fileName}  已进入审核队列'
                              : '${r.fileName}  上传成功')
                          : '${r.fileName}  ${r.error ?? "失败"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
