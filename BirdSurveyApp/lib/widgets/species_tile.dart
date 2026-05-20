import 'package:flutter/material.dart';
import '../models/bird_species.dart';

/// A select-type species field shown inline on the tile.
class QuickField {
  final String id;
  final String name;
  final List<String> options;
  final String currentValue;
  final Map<String, int> optionCounts;
  final Map<String, List<String>> nestedOptions;
  final Map<String, Map<String, int>> nestedCounts;
  final void Function(String) onChanged;
  final void Function(String) onIncrement;
  final void Function(String)? onCountEdit;
  final void Function(String parent, String child)? onNestedIncrement;
  final void Function(String parent, String child)? onNestedCountEdit;
  const QuickField({
    required this.id,
    required this.name,
    required this.options,
    required this.currentValue,
    this.optionCounts = const {},
    this.nestedOptions = const {},
    this.nestedCounts = const {},
    required this.onChanged,
    required this.onIncrement,
    this.onCountEdit,
    this.onNestedIncrement,
    this.onNestedCountEdit,
  });
}

class SpeciesTile extends StatelessWidget {
  final BirdSpecies species;
  final int count;
  final int ebirdFreq;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Called when the user taps the count circle to type a number directly.
  final VoidCallback? onCountEdit;
  final String note;
  final VoidCallback? onNote;

  /// Pre-resolved non-empty custom field values for display chips.
  final Map<String, String> speciesAttrs;

  /// Select-type fields shown as inline chip rows (only when count > 0).
  final List<QuickField> quickFields;

  const SpeciesTile({
    super.key,
    required this.species,
    required this.count,
    this.ebirdFreq = 0,
    required this.onIncrement,
    required this.onDecrement,
    this.onCountEdit,
    this.note = '',
    this.onNote,
    this.speciesAttrs = const {},
    this.quickFields = const [],
  });

  @override
  Widget build(BuildContext context) {
    final hasCount = count > 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: hasCount ? const Color(0xFFE8F5E9) : null,
      child: InkWell(
        onTap: onIncrement,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // ── Species info ──
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              species.zh,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: hasCount ? Colors.green[800] : null,
                              ),
                            ),
                            if (ebirdFreq > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '附近$ebirdFreq只',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          species.en,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          '${species.sci} · ${species.family}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        // display-only attrs (non-select or when no quickFields)
                        if (speciesAttrs.isNotEmpty && quickFields.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children:
                                  speciesAttrs.entries.map((e) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.teal[50],
                                        border: Border.all(
                                          color: Colors.teal.shade200,
                                          width: 0.8,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${e.key}: ${e.value}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.teal[800],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ),
                        if (note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.notes,
                                  size: 12,
                                  color: Colors.amber[700],
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    note,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.amber[800],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ── Count controls ──
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onNote != null)
                        GestureDetector(
                          onTap: onNote,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              (note.isNotEmpty || speciesAttrs.isNotEmpty)
                                  ? Icons.edit_note
                                  : Icons.add_comment_outlined,
                              size: 18,
                              color:
                                  (note.isNotEmpty || speciesAttrs.isNotEmpty)
                                      ? Colors.teal[600]
                                      : Colors.grey[400],
                            ),
                          ),
                        ),
                      if (hasCount)
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 22,
                          ),
                          color: Colors.red[400],
                          onPressed: onDecrement,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      GestureDetector(
                        onTap: onCountEdit,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: hasCount ? Colors.green : Colors.grey[200],
                            shape: BoxShape.circle,
                            border:
                                onCountEdit != null
                                    ? Border.all(
                                      color: Colors.green.shade700,
                                      width: 1.5,
                                    )
                                    : null,
                          ),
                          child: Center(
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color:
                                    hasCount ? Colors.white : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.add_circle,
                        color: Colors.green[600],
                        size: 28,
                      ),
                    ],
                  ),
                ],
              ),
              // ── Inline select-field chip rows ──
              if (quickFields.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        quickFields.map((f) {
                          if (f.nestedOptions.isNotEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${f.name}：',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  ...f.nestedOptions.entries.map((parent) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 52,
                                            child: Text(
                                              parent.key,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Wrap(
                                              spacing: 4,
                                              runSpacing: 2,
                                              children:
                                                  parent.value.map((child) {
                                                    final optionCount =
                                                        f.nestedCounts[parent
                                                            .key]?[child] ??
                                                        0;
                                                    return GestureDetector(
                                                      onTap:
                                                          () => f
                                                              .onNestedIncrement
                                                              ?.call(
                                                                parent.key,
                                                                child,
                                                              ),
                                                      onLongPress:
                                                          () => f
                                                              .onNestedCountEdit
                                                              ?.call(
                                                                parent.key,
                                                                child,
                                                              ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              optionCount > 0
                                                                  ? Colors.teal
                                                                  : Colors
                                                                      .grey[100],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                optionCount > 0
                                                                    ? Colors
                                                                        .teal
                                                                    : Colors
                                                                        .grey
                                                                        .shade300,
                                                            width: 0.8,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          optionCount > 0
                                                              ? '$child $optionCount'
                                                              : child,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                optionCount > 0
                                                                    ? Colors
                                                                        .white
                                                                    : Colors
                                                                        .grey[700],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '${f.name}：',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    children:
                                        f.options.map((opt) {
                                          final selected =
                                              f.currentValue == opt;
                                          final optionCount =
                                              f.optionCounts[opt] ?? 0;
                                          final hasOptionCount =
                                              optionCount > 0;
                                          return GestureDetector(
                                            onTap: () => f.onIncrement(opt),
                                            onLongPress:
                                                f.onCountEdit == null
                                                    ? null
                                                    : () => f.onCountEdit!(opt),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    hasOptionCount || selected
                                                        ? Colors.teal
                                                        : Colors.grey[100],
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color:
                                                      hasOptionCount || selected
                                                          ? Colors.teal
                                                          : Colors
                                                              .grey
                                                              .shade300,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                optionCount > 0
                                                    ? '$opt $optionCount'
                                                    : opt,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      hasOptionCount || selected
                                                          ? Colors.white
                                                          : Colors.grey[700],
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
