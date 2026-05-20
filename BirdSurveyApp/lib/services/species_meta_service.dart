import 'dart:convert';
import 'package:flutter/services.dart';

class SpeciesMeta {
  final String zh;
  final String latin;
  final String orderZh;
  final String orderEn;
  final String familyZh;
  final String familyEn;
  final String resident;   // 居留型
  final String provKey;    // 省重点
  final String sanYou;     // 三有
  final String natKey;     // 国重
  final String redList;    // 红色名录
  final String iucn;
  final String cites;

  const SpeciesMeta({
    required this.zh,
    required this.latin,
    required this.orderZh,
    required this.orderEn,
    required this.familyZh,
    required this.familyEn,
    required this.resident,
    required this.provKey,
    required this.sanYou,
    required this.natKey,
    required this.redList,
    required this.iucn,
    required this.cites,
  });

  factory SpeciesMeta.fromJson(Map<String, dynamic> j) => SpeciesMeta(
        zh: j['zh'] as String? ?? '',
        latin: j['latin'] as String? ?? '',
        orderZh: j['order_zh'] as String? ?? '',
        orderEn: j['order_en'] as String? ?? '',
        familyZh: j['family_zh'] as String? ?? '',
        familyEn: j['family_en'] as String? ?? '',
        resident: j['resident'] as String? ?? '',
        provKey: j['prov_key'] as String? ?? '',
        sanYou: j['san_you'] as String? ?? '',
        natKey: j['nat_key'] as String? ?? '',
        redList: j['red_list'] as String? ?? '',
        iucn: j['iucn'] as String? ?? '',
        cites: j['cites'] as String? ?? '',
      );

  // Export-ready map for CSV/Excel output
  Map<String, String> toExportMap() => {
        '拉丁名': latin,
        '目': orderZh,
        '目英文': orderEn,
        '科': familyZh,
        '科英文': familyEn,
        '居留型': resident,
        '省重点': provKey,
        '三有': sanYou,
        '国重': natKey,
        '红色名录': redList,
        'IUCN': iucn,
        'CITES': cites,
      };
}

class SpeciesMetaService {
  static Map<String, SpeciesMeta>? _index;

  static Future<void> init() async {
    if (_index != null) return;
    final raw = await rootBundle.loadString('assets/species_meta.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _index = {};
    for (final item in list) {
      final meta = SpeciesMeta.fromJson(item as Map<String, dynamic>);
      if (meta.zh.isNotEmpty) {
        _index![meta.zh] = meta;
      }
    }
  }

  /// Look up by Chinese name. Returns null if not found.
  static SpeciesMeta? lookup(String zhName) {
    return _index?[zhName];
  }

  static bool get isLoaded => _index != null;
}
