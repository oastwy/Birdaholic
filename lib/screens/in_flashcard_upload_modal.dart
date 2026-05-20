import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/species.dart';
import '../services/admin_upload_service.dart';
import '../services/pack_manager.dart';
import '../services/server_media_service.dart';
import '../services/storage.dart';

enum UploadKind { image, audio }

class InFlashcardUploadModal {
  /// 弹出 modal，返回 true 表示有内容被处理（本地或服务器），false 取消。
  static Future<bool> show({
    required BuildContext context,
    required Species currentBird,
    required StorageService storage,
    required PackManager packManager,
    required UploadKind kind,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _UploadModalContent(
          currentBird: currentBird,
          storage: storage,
          packManager: packManager,
          kind: kind,
        ),
      ),
    );
    return result == true;
  }
}

class _UploadModalContent extends StatefulWidget {
  final Species currentBird;
  final StorageService storage;
  final PackManager packManager;
  final UploadKind kind;

  const _UploadModalContent({
    required this.currentBird,
    required this.storage,
    required this.packManager,
    required this.kind,
  });

  @override
  State<_UploadModalContent> createState() => _UploadModalContentState();
}

class _UploadModalContentState extends State<_UploadModalContent> {
  final _contributorCtrl = TextEditingController();
  final _featuresCtrl = TextEditingController();
  final List<File> _files = [];
  int _difficulty = 1;
  bool _ccChecked = false;
  bool _uploading = false;
  int _progress = 0;
  String? _resultMessage;
  bool _resultOk = false;

  List<ServerImageMedia> _existingImages = const [];
  bool _existingLoaded = false;

  @override
  void initState() {
    super.initState();
    _contributorCtrl.text = widget.storage.getContributorName();
    if (widget.kind == UploadKind.image) {
      _loadExistingImages();
    } else {
      _existingLoaded = true;
    }
  }

  @override
  void dispose() {
    _contributorCtrl.dispose();
    _featuresCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingImages() async {
    try {
      final media = await ServerMediaService()
          .fetchSpeciesMedia(widget.currentBird.sci);
      if (!mounted) return;
      setState(() {
        _existingImages = media?.images ?? const [];
        _existingLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _existingLoaded = true);
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        type: widget.kind == UploadKind.image
            ? FileType.image
            : FileType.custom,
        allowedExtensions: widget.kind == UploadKind.audio
            ? ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg']
            : null,
      );
      if (result == null) return;
      setState(() {
        for (final f in result.files) {
          if (f.path != null) _files.add(File(f.path!));
        }
      });
    } catch (e) {
      _snack('选取文件失败：$e');
    }
  }

  bool get _canUpload =>
      _ccChecked &&
      _files.isNotEmpty &&
      _contributorCtrl.text.trim().isNotEmpty &&
      !_uploading;

  String get _uploadButtonText {
    if (widget.storage.isAdminMode) return '直接上传到服务器';
    if (widget.storage.isBetaMode) return '提交上传（等管理员审核）';
    return '仅保存到本地数据包';
  }

  Future<void> _doUpload() async {
    if (!_canUpload) return;
    await widget.storage.setContributorName(_contributorCtrl.text.trim());

    final token = widget.storage.getAdminUploadToken();
    final hasToken = token.isNotEmpty;
    final sci = widget.currentBird.sci;
    final contributor = _contributorCtrl.text.trim();

    setState(() {
      _uploading = true;
      _progress = 0;
      _resultMessage = null;
    });

    final svc = AdminUploadService();
    var successCount = 0;
    String? lastError;
    for (var i = 0; i < _files.length; i++) {
      final file = _files[i];
      try {
        if (hasToken) {
          await svc.uploadFile(
            sci: sci,
            contributor: contributor,
            filePath: file.path,
            token: token,
            difficulty: _difficulty,
          );
        } else {
          // 仅本地保存
          if (widget.kind == UploadKind.image) {
            await widget.packManager.replaceSpeciesImageFromFile(
              widget.currentBird,
              file.path,
            );
          } else {
            await widget.packManager.addSpeciesAudioFromFile(
              widget.currentBird,
              file.path,
            );
          }
        }
        successCount++;
      } catch (e) {
        lastError = '$e';
      }
      if (mounted) setState(() => _progress = i + 1);
    }

    // 识别特征
    final features = _featuresCtrl.text.trim();
    if (hasToken && features.isNotEmpty) {
      try {
        await svc.uploadIdentificationFeatures(
          species: widget.currentBird,
          features: features,
          token: token,
        );
      } catch (e) {
        lastError ??= '$e';
      }
    }

    if (!mounted) return;
    setState(() {
      _uploading = false;
      _resultOk = successCount == _files.length;
      if (!hasToken) {
        _resultMessage = successCount > 0
            ? '已保存到本地数据包（$successCount 个）。如需分享给其它用户，请联系管理员获取上传 Token。'
            : (lastError ?? '保存失败');
      } else if (widget.storage.isBetaMode) {
        _resultMessage = successCount > 0
            ? '已提交 $successCount 个文件，等待管理员审核。'
            : (lastError ?? '上传失败');
      } else {
        _resultMessage = successCount > 0
            ? '已上传 $successCount 个文件到服务器。'
            : (lastError ?? '上传失败');
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openCcUrl() async {
    final uri =
        Uri.parse('https://creativecommons.org/licenses/by/4.0/deed.zh-hans');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSpeciesRow(),
                    if (widget.kind == UploadKind.image &&
                        _existingLoaded) ...[
                      const SizedBox(height: 14),
                      _buildExistingImagesStrip(),
                    ],
                    const SizedBox(height: 16),
                    _label('作者署名 *'),
                    TextField(
                      controller: _contributorCtrl,
                      decoration: const InputDecoration(
                        hintText: '录音者 / 摄影者姓名',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    _label('难度（默认 1 星）'),
                    Row(
                      children: [
                        for (var i = 1; i <= 5; i++)
                          IconButton(
                            iconSize: 26,
                            onPressed: _uploading
                                ? null
                                : () => setState(() => _difficulty = i),
                            icon: Icon(
                              i <= _difficulty
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: i <= _difficulty
                                  ? Colors.amber
                                  : Colors.grey,
                            ),
                          ),
                      ],
                    ),
                    if (widget.kind == UploadKind.image) ...[
                      const SizedBox(height: 14),
                      _label('识别特征（可选）'),
                      TextField(
                        controller: _featuresCtrl,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(
                          hintText: '描述该鸟种关键识别特征…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _label(
                        widget.kind == UploadKind.image ? '选取图片 *' : '选取音频 *'),
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickFiles,
                      icon: Icon(widget.kind == UploadKind.image
                          ? Icons.image_outlined
                          : Icons.audiotrack_outlined),
                      label: Text(widget.kind == UploadKind.image
                          ? '选择本地图片'
                          : '选择本地音频'),
                    ),
                    for (var i = 0; i < _files.length; i++)
                      ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.insert_drive_file_outlined),
                        title: Text(
                          _files[i].path.split(Platform.pathSeparator).last,
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _uploading
                              ? null
                              : () =>
                                  setState(() => _files.removeAt(i)),
                        ),
                      ),
                    const SizedBox(height: 14),
                    _buildCcRow(),
                    const SizedBox(height: 14),
                    _buildUploadButton(),
                    if (_uploading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _files.isEmpty
                            ? null
                            : _progress / _files.length,
                      ),
                      const SizedBox(height: 4),
                      Text('进度 $_progress / ${_files.length}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                    if (_resultMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _resultOk
                              ? Colors.green[50]
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _resultOk
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: _resultOk ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_resultMessage!,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Row(
        children: [
          Icon(
            widget.kind == UploadKind.image
                ? Icons.image_outlined
                : Icons.audiotrack_outlined,
            color: const Color(0xFF2d7d32),
          ),
          const SizedBox(width: 8),
          Text(
            widget.kind == UploadKind.image ? '上传图片' : '上传音频',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _uploading
                ? null
                : () => Navigator.pop(context, _resultOk),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeciesRow() {
    final b = widget.currentBird;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4EC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.flutter_dash_outlined, color: Color(0xFF2d5016)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: b.cn.isEmpty ? b.en : b.cn,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                TextSpan(
                  text: '  ${b.sci}',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExistingImagesStrip() {
    final count = _existingImages.length;
    final tooMany = count >= 20;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('当前已有 $count 张图片',
                style: TextStyle(
                    fontSize: 12,
                    color: tooMany ? Colors.orange[800] : Colors.grey[700],
                    fontWeight: tooMany ? FontWeight.w700 : null)),
            if (tooMany) ...[
              const SizedBox(width: 4),
              Icon(Icons.warning_amber_outlined,
                  size: 16, color: Colors.orange[800]),
              const SizedBox(width: 4),
              Text('建议先确认现有照片是否够用',
                  style: TextStyle(
                      fontSize: 11, color: Colors.orange[800])),
            ],
          ],
        ),
        if (count > 0) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final img = _existingImages[i];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    img.url,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 70,
                      height: 70,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image,
                          color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCcRow() {
    return GestureDetector(
      onTap: _uploading ? null : () => setState(() => _ccChecked = !_ccChecked),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: _ccChecked
                ? const Color(0xFF2d7d32)
                : Colors.grey[400]!,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _ccChecked,
              onChanged: _uploading
                  ? null
                  : (v) => setState(() => _ccChecked = v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '我确认拥有该媒体的版权，并以 CC BY 4.0 协议授权 Birdaholic 使用',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: _openCcUrl,
                    child: const Text(
                      '了解 CC BY 4.0 →',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2d7d32),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadButton() {
    final canUpload = _canUpload;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: canUpload ? _doUpload : null,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: Text(_uploadButtonText),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}
