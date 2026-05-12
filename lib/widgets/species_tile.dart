import 'package:flutter/material.dart';
import '../models/species.dart';

/// 鸟种列表项
class SpeciesTile extends StatelessWidget {
  final Species species;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback? onDelete;
  final VoidCallback? onDownload;
  final bool showFavorite;
  final bool showDelete;
  final bool showDownload;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  const SpeciesTile({
    super.key,
    required this.species,
    required this.onTap,
    this.isFavorite = false,
    required this.onFavoriteToggle,
    this.onDelete,
    this.onDownload,
    this.showFavorite = true,
    this.showDelete = true,
    this.showDownload = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrailingActions = showFavorite ||
        (showDelete && onDelete != null) ||
        (showDownload && onDownload != null);
    final habitatText =
        species.habitat.startsWith('ebird:') ? '' : species.habitat;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (onSelectedChanged != null)
                Checkbox(
                  value: selected,
                  onChanged: (value) => onSelectedChanged!(value ?? false),
                )
              else
                const SizedBox(width: 4),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      species.cn,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      species.en.isNotEmpty ? species.en : species.sci,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      species.sci,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (habitatText.isNotEmpty)
                          Text(
                            habitatText,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color:
                                species.hasAudio
                                    ? Colors.green[50]
                                    : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            species.hasAudio ? '已下载音频' : '未下载',
                            style: TextStyle(
                              fontSize: 10,
                              color:
                                  species.hasAudio
                                      ? Colors.green[700]
                                      : Colors.grey[500],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasTrailingActions)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showDownload && onDownload != null)
                      IconButton(
                        icon: const Icon(Icons.cloud_download_outlined),
                        tooltip: '从服务器下载',
                        onPressed: onDownload,
                      ),
                    if (showFavorite)
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          color: isFavorite ? Colors.amber : Colors.grey[400],
                        ),
                        onPressed: onFavoriteToggle,
                      ),
                    if (showDelete && onDelete != null)
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: Colors.red[300],
                        ),
                        onPressed: onDelete,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
