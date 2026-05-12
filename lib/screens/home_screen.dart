import 'package:flutter/material.dart';

import '../models/species.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../services/download_task_service.dart';
import '../widgets/bird_card.dart';
import 'about_screen.dart';
import 'favorites_screen.dart';
import 'flashcard_screen.dart';
import 'pack_manage_screen.dart';
import 'progress_screen.dart';
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
  final _flashcardKey = GlobalKey<FlashcardScreenState>();
  DownloadTaskStatus _lastTaskStatus =
      DownloadTaskService.instance.snapshot.status;

  static const _titles = ['开始学习', '闪卡学习', '鸟种列表', '收藏夹', '数据包', '关于鸟瘾'];

  /// 从列表页跳转到闪卡
  void jumpToFlashcard(Species species) {
    setState(() => _tab = 1);
    // 延迟一帧，等闪卡页面渲染完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flashcardKey.currentState?.jumpTo(species);
    });
  }

  void _startSession(String filter, StudyMode mode, PromptMode promptMode) {
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
            appBar: AppBar(
              title: _tab == 1 ? null : Text(_titles[_tab]),
              centerTitle: true,
              toolbarHeight: _tab == 1 ? 44 : null,
            ),
            body: Column(
              children: [
                if (task.isRunning || task.isFinished)
                  Material(
                    color: task.isFinished
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFE3F2FD),
                    child: InkWell(
                      onTap: () => setState(() => _tab = 0),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: Row(
                          children: [
                            Icon(
                              task.isFinished
                                  ? Icons.task_alt
                                  : Icons.cloud_download,
                              color: task.isFinished
                                  ? Colors.green[700]
                                  : Colors.blue[700],
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.isFinished
                                        ? (task.message ?? '后台下载已完成')
                                        : task.kind ==
                                                DownloadTaskKind.remotePack
                                            ? '后台下载中：${task.packName} · ${task.byteProgressLabel}'
                                            : '后台下载中：${task.packName} (${task.current}/${task.total})',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  if (!task.isFinished &&
                                      task.kind ==
                                          DownloadTaskKind.remotePack &&
                                      task.speedLabel.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '${task.speedLabel} · 剩余 ${task.etaLabel}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700]),
                                      ),
                                    ),
                                  if (!task.isFinished)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: LinearProgressIndicator(
                                          value: task.progress),
                                    ),
                                ],
                              ),
                            ),
                            if (task.isFinished)
                              IconButton(
                                onPressed:
                                    DownloadTaskService.instance.clearFinished,
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      ProgressScreen(
                        packManager: widget.packManager,
                        storage: widget.storage,
                        onStartSession: _startSession,
                        onJumpToFlashcard: jumpToFlashcard,
                        refreshToken: _packVersion,
                        isActive: _tab == 0,
                      ),
                      FlashcardScreen(
                        key: _flashcardKey,
                        packManager: widget.packManager,
                        storage: widget.storage,
                        refreshToken: _packVersion,
                        isActive: _tab == 1,
                      ),
                      SpeciesListScreen(
                        packManager: widget.packManager,
                        storage: widget.storage,
                        onJumpToFlashcard: jumpToFlashcard,
                        onPackChanged: _handlePackChanged,
                        refreshToken: _packVersion,
                        isActive: _tab == 2,
                      ),
                      FavoritesScreen(
                        packManager: widget.packManager,
                        storage: widget.storage,
                        onJumpToFlashcard: jumpToFlashcard,
                        refreshToken: _packVersion,
                        isActive: _tab == 3,
                      ),
                      PackManageScreen(
                        packManager: widget.packManager,
                        storage: widget.storage,
                        onPackChanged: _handlePackChanged,
                      ),
                      const AboutScreen(),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _tab,
              onTap: (i) => setState(() => _tab = i),
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
                  icon: Icon(Icons.star),
                  label: '收藏',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.folder_zip),
                  label: '数据包',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.info_outline),
                  label: '关于',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
