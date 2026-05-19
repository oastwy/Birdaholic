import 'package:flutter/material.dart';

import '../models/species.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../services/download_task_service.dart';
import '../widgets/bird_card.dart';
import 'flashcard_screen.dart';
import 'news_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';
import 'species_list_screen.dart';

/// 主页 - 底部导航
class HomeScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;

  const HomeScreen({
    super.key,
    required this.packManager,
    required this.storage,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _packVersion = 0;
  bool _flashcardFocus = false;
  final _flashcardKey = GlobalKey<FlashcardScreenState>();
  DownloadTaskStatus _lastTaskStatus =
      DownloadTaskService.instance.snapshot.status;

  static const _titles = ['总览', '闪卡学习', '鸟种', '资讯', '设置'];

  void jumpToPreview() {
    setState(() {
      _tab = 2;
      _flashcardFocus = false;
    });
  }

  /// 从列表页跳转到闪卡
  void jumpToFlashcard(Species species) {
    setState(() => _tab = 1);
    // 延迟一帧，等闪卡页面渲染完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flashcardKey.currentState?.enterFocusMode();
      _flashcardKey.currentState?.jumpTo(species);
    });
  }

  void _startSession(String filter, StudyMode mode, PromptMode promptMode) {
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flashcardKey.currentState?.enterFocusMode();
      _flashcardKey.currentState?.startSession(
        filter: filter,
        mode: mode,
        promptMode: promptMode,
      );
    });
  }

  void _handlePackChanged() {
    setState(() {
      _packVersion++;
      _tab = 0;
      _flashcardFocus = false;
    });
  }

  @override
  void initState() {
    super.initState();
    DownloadTaskService.instance.addListener(_handleDownloadStateChanged);
  }

  @override
  void dispose() {
    DownloadTaskService.instance.removeListener(_handleDownloadStateChanged);
    super.dispose();
  }

  void _handleDownloadStateChanged() {
    final status = DownloadTaskService.instance.snapshot.status;
    if (_lastTaskStatus != DownloadTaskStatus.completed &&
        status == DownloadTaskStatus.completed) {
      _handlePackChanged();
    }
    _lastTaskStatus = status;
  }

  Widget _buildDownloadMiniStatus(
    BuildContext context,
    DownloadTaskSnapshot task,
  ) {
    final color = task.isFinished
        ? (task.status == DownloadTaskStatus.failed
            ? Colors.red[700]!
            : Colors.green[700]!)
        : Colors.blue[700]!;
    final title = task.isFinished
        ? (task.status == DownloadTaskStatus.failed
            ? '下载失败'
            : task.status == DownloadTaskStatus.canceled
                ? '已取消'
                : '下载完成')
        : task.kind == DownloadTaskKind.remotePack
            ? task.byteProgressLabel
            : '${task.current}/${task.total}';
    final subtitle = task.isFinished
        ? '点开查看'
        : task.kind == DownloadTaskKind.remotePack
            ? [
                if (task.speedLabel.isNotEmpty) task.speedLabel,
                if (task.etaLabel.isNotEmpty) task.etaLabel,
              ].join(' · ')
            : task.currentSpecies;

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showDownloadDetails(task),
        child: Container(
          width: 210,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                task.isFinished ? Icons.task_alt : Icons.cloud_download,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    if (!task.isFinished) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: task.progress,
                          minHeight: 4,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (task.isRunning)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: DownloadTaskService.instance.cancel,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16),
                  ),
                )
              else if (task.isFinished)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: DownloadTaskService.instance.clearFinished,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDownloadDetails(DownloadTaskSnapshot task) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final isRemote = task.kind == DownloadTaskKind.remotePack;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.isFinished ? '后台下载结果' : '后台下载中',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(task.packName, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 8),
                if (task.isFinished)
                  Text(task.message ?? '下载已结束')
                else if (isRemote)
                  Text(
                    '${task.byteProgressLabel}'
                    '${task.speedLabel.isEmpty ? '' : '\n速度 ${task.speedLabel} · 剩余 ${task.etaLabel}'}'
                    '${task.statusMessage.isEmpty ? '' : '\n${task.statusMessage}'}',
                  )
                else
                  Text(
                    '正在下载：${task.currentSpecies.isEmpty ? '准备中' : task.currentSpecies}\n'
                    '进度：${task.current}/${task.total}',
                  ),
                if (!task.isFinished) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: task.progress),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() => _tab = 0);
                      },
                      icon: const Icon(Icons.dashboard_outlined),
                      label: const Text('去总览'),
                    ),
                    const Spacer(),
                    if (!task.isFinished)
                      TextButton.icon(
                        onPressed: () {
                          DownloadTaskService.instance.cancel();
                          Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('取消下载'),
                      ),
                    if (task.isFinished)
                      FilledButton(
                        onPressed: () {
                          DownloadTaskService.instance.clearFinished();
                          Navigator.pop(ctx);
                        },
                        child: const Text('知道了'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadTaskService.instance,
      builder: (context, _) {
        final task = DownloadTaskService.instance.snapshot;

        return PopScope(
          canPop: _tab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _tab != 0) {
              setState(() => _tab = 0);
            }
          },
          child: Scaffold(
            appBar: _tab == 1 && _flashcardFocus
                ? null
                : AppBar(
                    title: _tab == 1 ? null : Text(_titles[_tab]),
                    centerTitle: true,
                    toolbarHeight: _tab == 1 ? 44 : null,
                  ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      ProgressScreen(
                        packManager: widget.packManager,
                        storage: widget.storage,
                        onStartSession: _startSession,
                        onJumpToFlashcard: jumpToFlashcard,
                        onJumpToPreview: jumpToPreview,
                        refreshToken: _packVersion,
                        isActive: _tab == 0,
                      ),
                      FlashcardScreen(
                        key: _flashcardKey,
                        packManager: widget.packManager,
                        storage: widget.storage,
                        refreshToken: _packVersion,
                        isActive: _tab == 1,
                        onFocusChanged: (value) {
                          if (_flashcardFocus == value) return;
                          setState(() => _flashcardFocus = value);
                        },
                      ),
                      SpeciesListScreen(
                        packManager: widget.packManager,
                        storage: widget.storage,
                        onJumpToFlashcard: jumpToFlashcard,
                        onPackChanged: _handlePackChanged,
                        refreshToken: _packVersion,
                        isActive: _tab == 2,
                      ),
                      const NewsScreen(),
                      SettingsScreen(
                        packManager: widget.packManager,
                        storage: widget.storage,
                        onSettingsChanged: () => setState(() {}),
                        onPackChanged: _handlePackChanged,
                      ),
                    ],
                  ),
                ),
                if (task.isRunning || task.isFinished)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _buildDownloadMiniStatus(context, task),
                  ),
              ],
            ),
            bottomNavigationBar: _tab == 1 && _flashcardFocus
                ? null
                : BottomNavigationBar(
                    currentIndex: _tab,
                    onTap: (i) {
                      setState(() {
                        _tab = i;
                        if (i != 1) _flashcardFocus = false;
                      });
                      if (i == 1) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _flashcardKey.currentState?.enterFocusMode(),
                        );
                      }
                    },
                    type: BottomNavigationBarType.fixed,
                    selectedItemColor: const Color(0xFF2d5016),
                    unselectedItemColor: Colors.grey,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.dashboard_rounded),
                        label: '总览',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.headphones),
                        label: '闪卡',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.list),
                        label: '鸟种',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.newspaper_outlined),
                        label: '资讯',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings_outlined),
                        label: '设置',
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
