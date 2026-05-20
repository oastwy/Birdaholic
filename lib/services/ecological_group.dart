/// 六大生态类群分组：游禽 / 涉禽 / 陆禽 / 猛禽 / 攀禽 / 鸣禽
///
/// 按 AviList 的 order（拉丁名）/ family（中文名兼容）映射到一个类群。
/// 少数边界情况按 family 单独处理（典型：鹭科属 Pelecaniformes 但生态上是涉禽）。
class EcologicalGroup {
  final String code;
  final String label;
  final String emoji;
  final int order;

  const EcologicalGroup({
    required this.code,
    required this.label,
    required this.emoji,
    required this.order,
  });
}

class EcologicalGroups {
  static const swimming = EcologicalGroup(
      code: 'swimming', label: '游禽', emoji: '🦆', order: 1);
  static const wading = EcologicalGroup(
      code: 'wading', label: '涉禽', emoji: '🦩', order: 2);
  static const ground = EcologicalGroup(
      code: 'ground', label: '陆禽', emoji: '🐓', order: 3);
  static const raptor = EcologicalGroup(
      code: 'raptor', label: '猛禽', emoji: '🦅', order: 4);
  static const climbing = EcologicalGroup(
      code: 'climbing', label: '攀禽', emoji: '🦜', order: 5);
  static const singing = EcologicalGroup(
      code: 'singing', label: '鸣禽', emoji: '🐦', order: 6);

  static const List<EcologicalGroup> all = [
    swimming,
    wading,
    ground,
    raptor,
    climbing,
    singing,
  ];

  // 拉丁目名 → 生态类群（大写不敏感）
  static const Map<String, String> _orderToGroup = {
    // 游禽
    'ANSERIFORMES': 'swimming',
    'GAVIIFORMES': 'swimming',
    'PODICIPEDIFORMES': 'swimming',
    'SPHENISCIFORMES': 'swimming',
    'PROCELLARIIFORMES': 'swimming',
    'PHAETHONTIFORMES': 'swimming',
    'SULIFORMES': 'swimming',
    // 涉禽
    'CICONIIFORMES': 'wading',
    'GRUIFORMES': 'wading',
    'CHARADRIIFORMES': 'wading',
    'OTIDIFORMES': 'wading',
    'EURYPYGIFORMES': 'wading',
    'PHOENICOPTERIFORMES': 'wading',
    'MESITORNITHIFORMES': 'wading',
    // 陆禽
    'GALLIFORMES': 'ground',
    'TINAMIFORMES': 'ground',
    'STRUTHIONIFORMES': 'ground',
    'CASUARIIFORMES': 'ground',
    'APTERYGIFORMES': 'ground',
    'RHEIFORMES': 'ground',
    'COLUMBIFORMES': 'ground',
    'PTEROCLIFORMES': 'ground',
    'PTEROCLIDIFORMES': 'ground',
    // 猛禽
    'ACCIPITRIFORMES': 'raptor',
    'STRIGIFORMES': 'raptor',
    'FALCONIFORMES': 'raptor',
    'CATHARTIFORMES': 'raptor',
    'CARIAMIFORMES': 'raptor',
    // 攀禽（含啄木鸟、佛法僧、鹃形、鹦鹉、雨燕、夜鹰等"非游非涉非陆非猛非鸣"）
    'PICIFORMES': 'climbing',
    'CORACIIFORMES': 'climbing',
    'BUCEROTIFORMES': 'climbing',
    'TROGONIFORMES': 'climbing',
    'COLIIFORMES': 'climbing',
    'CUCULIFORMES': 'climbing',
    'PSITTACIFORMES': 'climbing',
    'LEPTOSOMIFORMES': 'climbing',
    'GALBULIFORMES': 'climbing',
    'MUSOPHAGIFORMES': 'climbing',
    'APODIFORMES': 'climbing',
    'CAPRIMULGIFORMES': 'climbing',
    'NYCTIBIIFORMES': 'climbing',
    'AEGOTHELIFORMES': 'climbing',
    'PODARGIFORMES': 'climbing',
    'STEATORNITHIFORMES': 'climbing',
    'OPISTHOCOMIFORMES': 'climbing',
    // 鸣禽
    'PASSERIFORMES': 'singing',
  };

  // 中文目名 → 类群（兜底，处理旧数据用中文 order 的情况）
  static const Map<String, String> _cnOrderToGroup = {
    '雁形目': 'swimming',
    '潜鸟目': 'swimming',
    '䴙䴘目': 'swimming',
    '企鹅目': 'swimming',
    '鹱形目': 'swimming',
    '鹲形目': 'swimming',
    '鲣鸟目': 'swimming',
    '鹳形目': 'wading',
    '鹤形目': 'wading',
    '鸻形目': 'wading',
    '鸨形目': 'wading',
    '日鳽目': 'wading',
    '红鹳目': 'wading',
    '拟鹑目': 'wading',
    '鸡形目': 'ground',
    '鴂形目': 'ground',
    '鸵鸟目': 'ground',
    '鹤鸵目': 'ground',
    '无翼鸟目': 'ground',
    '美洲鸵目': 'ground',
    '鸽形目': 'ground',
    '沙鸡目': 'ground',
    '鹰形目': 'raptor',
    '鸮形目': 'raptor',
    '隼形目': 'raptor',
    '美洲鹫目': 'raptor',
    '叫鹤目': 'raptor',
    '啄木鸟目': 'climbing',
    '䴕形目': 'climbing',
    '佛法僧目': 'climbing',
    '犀鸟目': 'climbing',
    '咬鹃目': 'climbing',
    '鼠鸟目': 'climbing',
    '鹃形目': 'climbing',
    '鹦形目': 'climbing',
    '鹦鹉目': 'climbing',
    '蕉鹃目': 'climbing',
    '雨燕目': 'climbing',
    '夜鹰目': 'climbing',
    '林鸱目': 'climbing',
    '裸鼻鸱目': 'climbing',
    '蟆口鸱目': 'climbing',
    '油鸱目': 'climbing',
    '麝雉目': 'climbing',
    '卷尾鹎目': 'climbing',
    '鹟䴕目': 'climbing',
    '雀形目': 'singing',
  };

  // family 例外（少数生态归属与目不一致的科）
  static const Map<String, String> _familyOverride = {
    'Ardeidae': 'wading', // 鹭科：分类在鹈形目，生态是涉禽
    '鹭科': 'wading',
    'Threskiornithidae': 'wading', // 鹮科
    '鹮科': 'wading',
    'Pelecanidae': 'swimming',
    '鹈鹕科': 'swimming',
  };

  /// 根据 species 的 order（拉丁/中文皆可）和 family（拉丁/中文）解析生态类群。
  /// 找不到返回 null。
  static EcologicalGroup? resolve({String? order, String? family}) {
    final f = (family ?? '').trim();
    if (f.isNotEmpty && _familyOverride.containsKey(f)) {
      return _byCode(_familyOverride[f]!);
    }
    final o = (order ?? '').trim();
    if (o.isEmpty) return null;
    // 大写拉丁优先
    final upper = o.toUpperCase();
    if (_orderToGroup.containsKey(upper)) {
      return _byCode(_orderToGroup[upper]!);
    }
    // 中文
    if (_cnOrderToGroup.containsKey(o)) {
      return _byCode(_cnOrderToGroup[o]!);
    }
    return null;
  }

  static EcologicalGroup _byCode(String code) =>
      all.firstWhere((g) => g.code == code);
}
