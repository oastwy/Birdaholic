class BirdOrderInfo {
  final String code;
  final String label;
  final String shortLabel;
  final int sortWeight;

  const BirdOrderInfo({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.sortWeight,
  });
}

class BirdOrderTaxonomy {
  static const _orders = <String, BirdOrderInfo>{
    'ANSERIFORMES': BirdOrderInfo(
        code: 'ANSERIFORMES', label: '雁形目', shortLabel: '雁', sortWeight: 10),
    'GAVIIFORMES': BirdOrderInfo(
        code: 'GAVIIFORMES', label: '潜鸟目', shortLabel: '潜', sortWeight: 11),
    'PODICIPEDIFORMES': BirdOrderInfo(
        code: 'PODICIPEDIFORMES',
        label: '䴙䴘目',
        shortLabel: '䴙',
        sortWeight: 12),
    'SPHENISCIFORMES': BirdOrderInfo(
        code: 'SPHENISCIFORMES', label: '企鹅目', shortLabel: '企', sortWeight: 13),
    'PROCELLARIIFORMES': BirdOrderInfo(
        code: 'PROCELLARIIFORMES',
        label: '鹱形目',
        shortLabel: '鹱',
        sortWeight: 14),
    'PHAETHONTIFORMES': BirdOrderInfo(
        code: 'PHAETHONTIFORMES',
        label: '鹲形目',
        shortLabel: '鹲',
        sortWeight: 15),
    'SULIFORMES': BirdOrderInfo(
        code: 'SULIFORMES', label: '鲣鸟目', shortLabel: '鲣', sortWeight: 16),
    'PELECANIFORMES': BirdOrderInfo(
        code: 'PELECANIFORMES', label: '鹈形目', shortLabel: '鹈', sortWeight: 17),
    'CICONIIFORMES': BirdOrderInfo(
        code: 'CICONIIFORMES', label: '鹳形目', shortLabel: '鹳', sortWeight: 18),
    'PHOENICOPTERIFORMES': BirdOrderInfo(
        code: 'PHOENICOPTERIFORMES',
        label: '红鹳目',
        shortLabel: '红',
        sortWeight: 19),
    'GALLIFORMES': BirdOrderInfo(
        code: 'GALLIFORMES', label: '鸡形目', shortLabel: '鸡', sortWeight: 30),
    'TINAMIFORMES': BirdOrderInfo(
        code: 'TINAMIFORMES', label: '䳍形目', shortLabel: '䳍', sortWeight: 31),
    'STRUTHIONIFORMES': BirdOrderInfo(
        code: 'STRUTHIONIFORMES',
        label: '鸵鸟目',
        shortLabel: '鸵',
        sortWeight: 32),
    'RHEIFORMES': BirdOrderInfo(
        code: 'RHEIFORMES', label: '美洲鸵目', shortLabel: '美', sortWeight: 33),
    'CASUARIIFORMES': BirdOrderInfo(
        code: 'CASUARIIFORMES', label: '鹤鸵目', shortLabel: '鹤', sortWeight: 34),
    'APTERYGIFORMES': BirdOrderInfo(
        code: 'APTERYGIFORMES', label: '无翼鸟目', shortLabel: '无', sortWeight: 35),
    'COLUMBIFORMES': BirdOrderInfo(
        code: 'COLUMBIFORMES', label: '鸽形目', shortLabel: '鸽', sortWeight: 50),
    'PTEROCLIFORMES': BirdOrderInfo(
        code: 'PTEROCLIFORMES', label: '沙鸡目', shortLabel: '沙', sortWeight: 51),
    'CUCULIFORMES': BirdOrderInfo(
        code: 'CUCULIFORMES', label: '鹃形目', shortLabel: '鹃', sortWeight: 52),
    'CAPRIMULGIFORMES': BirdOrderInfo(
        code: 'CAPRIMULGIFORMES',
        label: '夜鹰目',
        shortLabel: '夜',
        sortWeight: 53),
    'STEATORNITHIFORMES': BirdOrderInfo(
        code: 'STEATORNITHIFORMES',
        label: '油鸱目',
        shortLabel: '油',
        sortWeight: 54),
    'NYCTIBIIFORMES': BirdOrderInfo(
        code: 'NYCTIBIIFORMES', label: '林鸱目', shortLabel: '林', sortWeight: 55),
    'PODARGIFORMES': BirdOrderInfo(
        code: 'PODARGIFORMES', label: '蟆口鸱目', shortLabel: '蟆', sortWeight: 56),
    'AEGOTHELIFORMES': BirdOrderInfo(
        code: 'AEGOTHELIFORMES',
        label: '裸鼻鸱目',
        shortLabel: '裸',
        sortWeight: 57),
    'APODIFORMES': BirdOrderInfo(
        code: 'APODIFORMES', label: '雨燕目', shortLabel: '雨', sortWeight: 58),
    'GRUIFORMES': BirdOrderInfo(
        code: 'GRUIFORMES', label: '鹤形目', shortLabel: '鹤', sortWeight: 70),
    'OTIDIFORMES': BirdOrderInfo(
        code: 'OTIDIFORMES', label: '鸨形目', shortLabel: '鸨', sortWeight: 71),
    'CHARADRIIFORMES': BirdOrderInfo(
        code: 'CHARADRIIFORMES', label: '鸻形目', shortLabel: '鸻', sortWeight: 72),
    'EURYPYGIFORMES': BirdOrderInfo(
        code: 'EURYPYGIFORMES', label: '日鳽目', shortLabel: '日', sortWeight: 73),
    'ACCIPITRIFORMES': BirdOrderInfo(
        code: 'ACCIPITRIFORMES', label: '鹰形目', shortLabel: '鹰', sortWeight: 90),
    'FALCONIFORMES': BirdOrderInfo(
        code: 'FALCONIFORMES', label: '隼形目', shortLabel: '隼', sortWeight: 91),
    'STRIGIFORMES': BirdOrderInfo(
        code: 'STRIGIFORMES', label: '鸮形目', shortLabel: '鸮', sortWeight: 92),
    'CARIAMIFORMES': BirdOrderInfo(
        code: 'CARIAMIFORMES', label: '叫鹤目', shortLabel: '叫', sortWeight: 93),
    'BUCEROTIFORMES': BirdOrderInfo(
        code: 'BUCEROTIFORMES', label: '犀鸟目', shortLabel: '犀', sortWeight: 110),
    'CORACIIFORMES': BirdOrderInfo(
        code: 'CORACIIFORMES', label: '佛法僧目', shortLabel: '佛', sortWeight: 111),
    'PICIFORMES': BirdOrderInfo(
        code: 'PICIFORMES', label: '䴕形目', shortLabel: '䴕', sortWeight: 112),
    'TROGONIFORMES': BirdOrderInfo(
        code: 'TROGONIFORMES', label: '咬鹃目', shortLabel: '咬', sortWeight: 113),
    'LEPTOSOMIFORMES': BirdOrderInfo(
        code: 'LEPTOSOMIFORMES',
        label: '鹃三宝鸟目',
        shortLabel: '宝',
        sortWeight: 114),
    'MUSOPHAGIFORMES': BirdOrderInfo(
        code: 'MUSOPHAGIFORMES',
        label: '蕉鹃目',
        shortLabel: '蕉',
        sortWeight: 115),
    'COLIIFORMES': BirdOrderInfo(
        code: 'COLIIFORMES', label: '鼠鸟目', shortLabel: '鼠', sortWeight: 116),
    'OPISTHOCOMIFORMES': BirdOrderInfo(
        code: 'OPISTHOCOMIFORMES',
        label: '麝雉目',
        shortLabel: '麝',
        sortWeight: 117),
    'PSITTACIFORMES': BirdOrderInfo(
        code: 'PSITTACIFORMES', label: '鹦形目', shortLabel: '鹦', sortWeight: 130),
    'PASSERIFORMES': BirdOrderInfo(
        code: 'PASSERIFORMES', label: '雀形目', shortLabel: '雀', sortWeight: 150),
  };

  static BirdOrderInfo info(String order) {
    final key = order.trim().toUpperCase();
    return _orders[key] ??
        BirdOrderInfo(
          code: key,
          label: order,
          shortLabel: order.trim().isEmpty ? '?' : order.trim()[0],
          sortWeight: 999,
        );
  }

  static String label(String order) => info(order).label;

  static String shortLabel(String order) => info(order).shortLabel;

  static List<String> sortOrders(Iterable<String> orders) {
    final list = orders
        .map((order) => order.trim())
        .where((order) => order.isNotEmpty)
        .toSet()
        .toList();
    list.sort((a, b) {
      final ai = info(a);
      final bi = info(b);
      final byWeight = ai.sortWeight.compareTo(bi.sortWeight);
      if (byWeight != 0) return byWeight;
      return ai.label.compareTo(bi.label);
    });
    return list;
  }
}
