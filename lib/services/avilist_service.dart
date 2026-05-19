import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/avilist_species.dart';

class AviListService {
  static const _assetPath = 'assets/data/avilist_species.json';

  static List<AviListSpecies>? _cache;

  Future<List<AviListSpecies>> loadAllSpecies() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString(_assetPath);
    final data = jsonDecode(raw) as List<dynamic>;
    _cache = data
        .map((item) => AviListSpecies.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    return _cache!;
  }

  // sci (lowercase) → AviList sequence index, -1 if not found
  static Map<String, int>? _sciIndex;

  Future<Map<String, int>> _getSciIndex() async {
    if (_sciIndex != null) return _sciIndex!;
    final all = await loadAllSpecies();
    final map = <String, int>{};
    for (var i = 0; i < all.length; i++) {
      map[all[i].sci.trim().toLowerCase()] = i;
    }
    _sciIndex = map;
    return map;
  }

  Future<Map<String, int>> getSciIndexMap() => _getSciIndex();

  Future<int> aviListIndexOf(String sci) async {
    final idx = await _getSciIndex();
    return idx[sci.trim().toLowerCase()] ?? 999999;
  }

  Future<List<AviListSpecies>> search(
    String query, {
    int limit = 30,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return [];

    final all = await loadAllSpecies();
    final startsWith = <AviListSpecies>[];
    final contains = <AviListSpecies>[];

    for (final species in all) {
      final sci = species.sci.toLowerCase();
      final en = species.en.toLowerCase();
      final family = species.family.toLowerCase();

      final prefixMatch = sci.startsWith(normalized) || en.startsWith(normalized);
      final fuzzyMatch = sci.contains(normalized) ||
          en.contains(normalized) ||
          family.contains(normalized);

      if (prefixMatch) {
        startsWith.add(species);
      } else if (fuzzyMatch) {
        contains.add(species);
      }

      if (startsWith.length + contains.length >= limit * 3) {
        break;
      }
    }

    final merged = [...startsWith, ...contains];
    return merged.take(limit).toList(growable: false);
  }
}
