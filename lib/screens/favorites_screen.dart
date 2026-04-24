import 'package:flutter/material.dart';
import '../models/species.dart';
import '../services/pack_manager.dart';
import '../services/storage.dart';
import '../widgets/species_tile.dart';

/// 收藏夹页面
class FavoritesScreen extends StatefulWidget {
  final PackManager packManager;
  final StorageService storage;
  final void Function(Species) onJumpToFlashcard;
  final int refreshToken;
  final bool isActive;

  const FavoritesScreen({
    super.key,
    required this.packManager,
    required this.storage,
    required this.onJumpToFlashcard,
    required this.refreshToken,
    required this.isActive,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Species> _allSpecies = [];

  @override
  void initState() {
    super.initState();
    _loadSpecies();
  }

  @override
  void didUpdateWidget(covariant FavoritesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        (!oldWidget.isActive && widget.isActive)) {
      _loadSpecies();
    }
  }

  Future<void> _loadSpecies() async {
    try {
      final list = await widget.packManager.loadSpecies();
      if (mounted) setState(() => _allSpecies = list);
    } catch (_) {
      if (mounted) {
        setState(() => _allSpecies = []);
      }
    }
  }

  List<Species> get _favorites {
    final favs = widget.storage.getFavorites();
    return _allSpecies.where((s) => favs.contains(s.cn)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final favs = _favorites;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text('已收藏 ${favs.length} 种',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        Expanded(
          child: favs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text('暂无收藏',
                          style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 4),
                      Text('点击 ⭐ 收藏难记鸟种',
                          style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: favs.length,
                  itemBuilder: (context, i) {
                    final s = favs[i];
                    return SpeciesTile(
                      species: s,
                      onTap: () => widget.onJumpToFlashcard(s),
                      isFavorite: true,
                      onFavoriteToggle: () {
                        widget.storage.toggleFavorite(s.cn);
                        setState(() {});
                      },
                      onDelete: null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
