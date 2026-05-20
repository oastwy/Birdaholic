import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_field.dart';
import '../providers/survey_provider.dart';
import '../services/tide_service.dart';
import '../services/webdav_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ebirdCtrl;
  late TextEditingController _chaoxi365Ctrl;
  late TextEditingController _chaoxi365EndpointCtrl;
  late TextEditingController _stormCtrl;
  late TextEditingController _worldCtrl;
  late TextEditingController _tiandituCtrl;
  late TextEditingController _qweatherCtrl;
  late TideSource _selectedSource;
  String _exportTemplate = 'full';
  String _nestedParentFieldId = '';
  String _nestedChildFieldId = '';

  @override
  void initState() {
    super.initState();
    final prov = context.read<SurveyProvider>();
    _ebirdCtrl = TextEditingController(text: prov.ebirdApiKey);
    _chaoxi365Ctrl = TextEditingController(text: prov.chaoxi365Key);
    _chaoxi365EndpointCtrl = TextEditingController(
      text: prov.chaoxi365Endpoint,
    );
    _stormCtrl = TextEditingController(text: prov.stormglassKey);
    _worldCtrl = TextEditingController(text: prov.worldtidesKey);
    _tiandituCtrl = TextEditingController(text: prov.tiandituKey);
    _qweatherCtrl = TextEditingController(text: prov.qweatherKey);
    _selectedSource = prov.tideSource;
    _nestedParentFieldId = prov.nestedParentFieldId;
    _nestedChildFieldId = prov.nestedChildFieldId;
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _exportTemplate = prefs.getString('export_template') ?? 'full';
      });
    });
  }

  @override
  void dispose() {
    _ebirdCtrl.dispose();
    _chaoxi365Ctrl.dispose();
    _chaoxi365EndpointCtrl.dispose();
    _stormCtrl.dispose();
    _worldCtrl.dispose();
    _tiandituCtrl.dispose();
    _qweatherCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final prov = context.read<SurveyProvider>();
    await prov.saveSettings(
      ebird: _ebirdCtrl.text.trim(),
      chaoxi365: _chaoxi365Ctrl.text.trim(),
      chaoxi365Endpoint: _chaoxi365EndpointCtrl.text.trim(),
      stormglass: _stormCtrl.text.trim(),
      worldtides: _worldCtrl.text.trim(),
      tianditu: _tiandituCtrl.text.trim(),
      qweather: _qweatherCtrl.text.trim(),
      tideSource: _selectedSource,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('export_template', _exportTemplate);
    await prov.saveNestedFieldRelation(
      parentFieldId: _nestedParentFieldId,
      childFieldId: _nestedChildFieldId,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 潮汐数据源 ────────────────────────────────────────────────────
          _SectionHeader('潮汐数据来源'),
          ...TideSource.values.map(
            (src) => RadioListTile<TideSource>(
              title: Text(src.label),
              subtitle: _tideSourceSubtitle(src),
              value: src,
              groupValue: _selectedSource,
              activeColor: Colors.green[700],
              onChanged: (v) => setState(() => _selectedSource = v!),
            ),
          ),

          if (_selectedSource == TideSource.chaoxi365) ...[
            const SizedBox(height: 8),
            _ApiKeyField(
              controller: _chaoxi365Ctrl,
              label: '潮汐网 API Key',
              hint: '潮汐网 api.html → 免费版 → 申请/联系客服（100次/天）',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _chaoxi365EndpointCtrl,
              decoration: const InputDecoration(
                labelText: '潮汐网接口 URL 模板',
                helperText:
                    '支持 {lat} {lng}/{lon} {key} {date} {timestamp} 占位符；拿到官方文档后可在这里替换',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const _ApiGuideCard(
              title: '潮汐网 API 获取教程',
              lines: [
                '1. 打开 www.chaoxi365.com/api.html。',
                '2. 选择免费版，页面标注 100 次/天。',
                '3. 按页面联系方式申请 API Key 和接口文档。',
                '4. 把 Key 填入上方；如果官方 endpoint 与默认不同，替换 URL 模板。',
                '5. 当前解析兼容常见 JSON 字段：height/tideHeight/潮高、time/fxTime/时间。',
              ],
            ),
          ],
          if (_selectedSource == TideSource.stormglass) ...[
            const SizedBox(height: 8),
            _ApiKeyField(
              controller: _stormCtrl,
              label: 'Stormglass API Key',
              hint: '申请：stormglass.io（免费10次/天）',
            ),
            const _ApiGuideCard(
              title: 'Stormglass 获取教程',
              lines: [
                '1. 打开 stormglass.io 注册账号。',
                '2. 进入 Dashboard / API Keys 复制 Key。',
                '3. 免费额度较低，适合测试。',
              ],
            ),
          ],
          if (_selectedSource == TideSource.worldtides) ...[
            const SizedBox(height: 8),
            _ApiKeyField(
              controller: _worldCtrl,
              label: 'WorldTides API Key',
              hint: '申请：worldtides.info（免费100次/天）',
            ),
            const _ApiGuideCard(
              title: 'WorldTides 获取教程',
              lines: [
                '1. 打开 worldtides.info 注册账号。',
                '2. 在账户/API 页面复制 Key。',
                '3. 选择 WorldTides 数据源并保存。',
              ],
            ),
          ],
          if (_selectedSource == TideSource.local)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Card(
                color: Color(0xFFE8F5E9),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    '✓ 基于月球/太阳位置的天文潮汐计算，完全离线，无使用限制。\n'
                    '精度：±10~20 cm，适合野外调查。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),

          const Divider(height: 32),

          // ── 天地图 ────────────────────────────────────────────────────────
          _SectionHeader('天地图 API（卫星地图）'),
          const Text(
            '调查位点选择时显示卫星底图（WGS-84，坐标无偏移）。\n'
            '注册：tianditu.gov.cn → 控制台 → 新建应用（免费）',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _ApiKeyField(
            controller: _tiandituCtrl,
            label: '天地图 API Key（tk）',
            hint: '填写后地图显示卫星影像，未填则显示OSM街道图',
          ),
          const _ApiGuideCard(
            title: '天地图 Key 获取教程',
            lines: [
              '1. 打开 tianditu.gov.cn 并登录控制台。',
              '2. 新建应用，应用类型选安卓端。',
              '3. 包名填写 com.birdsurvey.bird_survey_app。',
              '4. 复制 tk 填入本页。',
            ],
          ),

          const Divider(height: 32),

          // ── 和风天气 ──────────────────────────────────────────────────────
          _SectionHeader('和风天气 API（自动记录天气）'),
          const Text(
            '调查开始时自动获取当地天气（天气状况、气温、风向风速、湿度），\n'
            '自动填入记录并在导出时写入"天气"列。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _ApiKeyField(
            controller: _qweatherCtrl,
            label: '和风天气 API Key',
            hint: '注册：dev.qweather.com（免费版 500次/天）',
          ),
          const _ApiGuideCard(
            title: '和风天气 Key 获取教程',
            lines: [
              '1. 打开 dev.qweather.com 注册账号。',
              '2. 进入控制台 → 项目管理 → 新建项目。',
              '3. 应用限制选"不限制"，复制 API KEY。',
              '4. 免费版天气实况 500次/天，够野外调查使用。',
            ],
          ),

          const Divider(height: 32),

          // ── eBird API ─────────────────────────────────────────────────────
          _SectionHeader('eBird API（附近鸟种功能）'),
          _ApiKeyField(
            controller: _ebirdCtrl,
            label: 'eBird API Key',
            hint: '登录 ebird.org → 账户设置 → 申请API Key（免费）',
          ),
          const _ApiGuideCard(
            title: 'eBird Key 获取教程',
            lines: [
              '1. 登录 ebird.org。',
              '2. 进入账户设置 / API Access。',
              '3. 申请并复制 API Key。',
              '4. 保存后可启用附近鸟种和历史频率功能。',
            ],
          ),

          const Divider(height: 32),

          // ── 调查自定义字段 ─────────────────────────────────────────────────
          _SectionHeader('调查自定义字段'),
          const Text(
            '在每次调查开始前填写，自动记入数据并导出至Excel。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _CustomFieldsEditor(
            getFields: (prov) => prov.customFields,
            saveFields: (prov, f) => prov.saveCustomFields(f),
            presets: _surveyFieldPresets,
          ),

          const Divider(height: 32),

          // ── 物种自定义字段 ─────────────────────────────────────────────────
          _SectionHeader('物种自定义字段'),
          const Text(
            '记录每个物种时可填写，例如行为、位置、性别/年龄等。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _CustomFieldsEditor(
            getFields: (prov) => prov.speciesFieldDefs,
            saveFields: (prov, f) => prov.saveSpeciesFieldDefs(f),
            presets: _speciesFieldPresets,
          ),
          const SizedBox(height: 12),
          Consumer<SurveyProvider>(
            builder: (context, prov, _) {
              final selectFields =
                  prov.speciesFieldDefs
                      .where(
                        (f) =>
                            f.type == FieldType.select && f.options.isNotEmpty,
                      )
                      .toList();
              if (selectFields.length < 2) {
                return const Text(
                  '添加至少两个“选项”字段后，可设置字段自动嵌套。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                );
              }
              String? safeParent =
                  selectFields.any((f) => f.id == _nestedParentFieldId)
                      ? _nestedParentFieldId
                      : null;
              String? safeChild =
                  selectFields.any((f) => f.id == _nestedChildFieldId)
                      ? _nestedChildFieldId
                      : null;
              return Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '字段自动嵌套',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '例：一级选“位置”，二级选“行为”，记录时会自动生成 岸边-觅食、水中-休息。',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: safeParent,
                        decoration: const InputDecoration(
                          labelText: '一级字段',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('不启用')),
                          ...selectFields.map(
                            (f) => DropdownMenuItem(
                              value: f.id,
                              child: Text(f.name),
                            ),
                          ),
                        ],
                        onChanged:
                            (v) => setState(() {
                              _nestedParentFieldId = v ?? '';
                              if (_nestedChildFieldId == _nestedParentFieldId) {
                                _nestedChildFieldId = '';
                              }
                            }),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: safeChild,
                        decoration: const InputDecoration(
                          labelText: '二级字段',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('不启用')),
                          ...selectFields
                              .where((f) => f.id != _nestedParentFieldId)
                              .map(
                                (f) => DropdownMenuItem(
                                  value: f.id,
                                  child: Text(f.name),
                                ),
                              ),
                        ],
                        onChanged:
                            (v) =>
                                setState(() => _nestedChildFieldId = v ?? ''),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const Divider(height: 32),

          _SectionHeader('导出模板'),
          RadioListTile<String>(
            title: const Text('完整科研版'),
            subtitle: const Text('包含目、科、保护等级、红色名录、IUCN、CITES 等列'),
            value: 'full',
            groupValue: _exportTemplate,
            activeColor: Colors.green[700],
            onChanged: (v) => setState(() => _exportTemplate = v!),
          ),
          RadioListTile<String>(
            title: const Text('简洁交付版'),
            subtitle: const Text('只保留基础信息、天气潮汐、记录人、物种、数量和自定义字段'),
            value: 'simple',
            groupValue: _exportTemplate,
            activeColor: Colors.green[700],
            onChanged: (v) => setState(() => _exportTemplate = v!),
          ),

          const Divider(height: 32),

          // ── WebDAV 云备份 ─────────────────────────────────────────────────
          _SectionHeader('云备份（WebDAV）'),
          const Text(
            '每次导出 Excel 后自动上传到 WebDAV 服务器。\n'
            '支持小米云盘（dav.jiami.net）、坚果云等。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const _WebDavEditor(),

          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('保存所有设置'),
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 24),

          // ── 关于 ──────────────────────────────────────────────────────────
          _SectionHeader('关于'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '中国鸟类调查 App',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text('• 内置500+种中国鸟类名录', style: TextStyle(fontSize: 12)),
                  Text('• eBird附近鸟种（按出现频率排序）', style: TextStyle(fontSize: 12)),
                  Text('• 自动GPS + 时间记录', style: TextStyle(fontSize: 12)),
                  Text('• 三种潮汐数据源可选', style: TextStyle(fontSize: 12)),
                  Text('• 自定义调查字段 + Excel导出', style: TextStyle(fontSize: 12)),
                  Text('• 语音识别搜索鸟种', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _tideSourceSubtitle(TideSource src) {
    switch (src) {
      case TideSource.stormglass:
        return const Text('需API Key · 实测数据', style: TextStyle(fontSize: 11));
      case TideSource.worldtides:
        return const Text('需API Key · 实测数据', style: TextStyle(fontSize: 11));
      case TideSource.chaoxi365:
        return const Text(
          '需API Key · 国内潮汐服务 · 试用解析',
          style: TextStyle(fontSize: 11),
        );
      case TideSource.local:
        return const Text('无需联网 · 天文预报', style: TextStyle(fontSize: 11));
    }
  }
}

class _ApiKeyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  const _ApiKeyField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.vpn_key),
        suffixIcon: IconButton(
          icon: const Icon(Icons.visibility_off, size: 18),
          onPressed: () {},
        ),
      ),
      obscureText: true,
    );
  }
}

class _ApiGuideCard extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _ApiGuideCard({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        color: const Color(0xFFF7F9F7),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(title, style: const TextStyle(fontSize: 13)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                lines.join('\n'),
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preset definitions ────────────────────────────────────────────────────────

class _FieldPreset {
  final String name;
  final FieldType type;
  final List<String> options;
  const _FieldPreset(this.name, this.type, [this.options = const []]);
}

const _surveyFieldPresets = [
  _FieldPreset('天气', FieldType.select, ['晴', '多云', '阴', '雨', '雾']),
  _FieldPreset('风力(级)', FieldType.number),
  _FieldPreset('风向', FieldType.select, [
    'N',
    'NE',
    'E',
    'SE',
    'S',
    'SW',
    'W',
    'NW',
  ]),
  _FieldPreset('调查员', FieldType.text),
  _FieldPreset('样点编号', FieldType.text),
  _FieldPreset('栖息地', FieldType.select, ['泥滩', '沙滩', '芦苇', '草甸', '农田', '其他']),
  _FieldPreset('能见度(km)', FieldType.number),
  _FieldPreset('备注', FieldType.text),
];

const _speciesFieldPresets = [
  _FieldPreset('行为', FieldType.select, ['觅食', '飞行', '休息', '鸣叫', '繁殖', '其他']),
  _FieldPreset('位置', FieldType.select, [
    '水面',
    '岸边',
    '泥滩',
    '草丛',
    '树上',
    '空中',
    '其他',
  ]),
  _FieldPreset('性别/年龄', FieldType.select, ['雄成鸟', '雌成鸟', '幼鸟', '亚成鸟', '不确定']),
  _FieldPreset('观测距离(m)', FieldType.number),
  _FieldPreset('数量估计', FieldType.select, ['精确', '目测', '鸣声']),
  _FieldPreset('羽色/换羽', FieldType.text),
];

// ── Custom Fields Editor ────────────────────────────────────────────────────

class _CustomFieldsEditor extends StatefulWidget {
  final List<CustomField> Function(SurveyProvider) getFields;
  final Future<void> Function(SurveyProvider, List<CustomField>) saveFields;
  final List<_FieldPreset> presets;

  const _CustomFieldsEditor({
    required this.getFields,
    required this.saveFields,
    required this.presets,
  });

  @override
  State<_CustomFieldsEditor> createState() => _CustomFieldsEditorState();
}

class _CustomFieldsEditorState extends State<_CustomFieldsEditor> {
  late List<CustomField> _fields;

  @override
  void initState() {
    super.initState();
    _fields = List.from(widget.getFields(context.read<SurveyProvider>()));
  }

  Future<void> _save() =>
      widget.saveFields(context.read<SurveyProvider>(), _fields);

  void _addField() async {
    final result = await showDialog<CustomField>(
      context: context,
      builder: (_) => const _FieldEditDialog(),
    );
    if (result != null && mounted) {
      setState(() => _fields.add(result));
      await _save();
    }
  }

  void _editField(int idx) async {
    final result = await showDialog<CustomField>(
      context: context,
      builder: (_) => _FieldEditDialog(existing: _fields[idx]),
    );
    if (result != null && mounted) {
      setState(() => _fields[idx] = result);
      await _save();
    }
  }

  void _removeField(int idx) async {
    setState(() => _fields.removeAt(idx));
    await _save();
  }

  void _reorder(int oldIdx, int newIdx) async {
    setState(() {
      if (newIdx > oldIdx) newIdx--;
      final item = _fields.removeAt(oldIdx);
      _fields.insert(newIdx, item);
    });
    await _save();
  }

  Future<void> _addPreset(_FieldPreset p) async {
    final field = CustomField(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: p.name,
      type: p.type,
      options: p.options,
    );
    setState(() => _fields.add(field));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_fields.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '暂无字段，点击下方添加',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _fields.length,
            onReorder: _reorder,
            itemBuilder: (_, i) {
              final f = _fields[i];
              return ListTile(
                key: ValueKey(f.id),
                leading: Icon(_fieldIcon(f.type), color: Colors.green[700]),
                title: Text(f.name),
                onTap: () => _editField(i),
                subtitle: Text(
                  _fieldTypeLabel(f.type) +
                      (f.type == FieldType.nestedSelect &&
                              f.nestedOptions.isNotEmpty
                          ? ': ${f.nestedOptions.entries.map((e) => '${e.key}>${e.value.join('/')}').join('；')}'
                          : f.options.isNotEmpty
                          ? ': ${f.options.join(' / ')}'
                          : ''),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      color: Colors.green[700],
                      onPressed: () => _editField(i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.red[400],
                      onPressed: () => _removeField(i),
                    ),
                    const Icon(Icons.drag_handle, color: Colors.grey),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('添加字段'),
          onPressed: _addField,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children:
              widget.presets
                  .map(
                    (p) =>
                        _PresetChip(label: p.name, onTap: () => _addPreset(p)),
                  )
                  .toList(),
        ),
      ],
    );
  }

  IconData _fieldIcon(FieldType t) {
    switch (t) {
      case FieldType.text:
        return Icons.text_fields;
      case FieldType.number:
        return Icons.numbers;
      case FieldType.select:
        return Icons.list;
      case FieldType.nestedSelect:
        return Icons.account_tree;
    }
  }

  String _fieldTypeLabel(FieldType t) {
    switch (t) {
      case FieldType.text:
        return '文本';
      case FieldType.number:
        return '数字';
      case FieldType.select:
        return '选项';
      case FieldType.nestedSelect:
        return '两级选项';
    }
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.green[50],
    );
  }
}

// ── Field Edit Dialog ────────────────────────────────────────────────────────

class _FieldEditDialog extends StatefulWidget {
  final CustomField? existing;
  const _FieldEditDialog({this.existing});

  @override
  State<_FieldEditDialog> createState() => _FieldEditDialogState();
}

class _FieldEditDialogState extends State<_FieldEditDialog> {
  final _nameCtrl = TextEditingController();
  final _optCtrl = TextEditingController();
  final _nestedCtrl = TextEditingController();
  FieldType _type = FieldType.text;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _type = existing.type;
      _optCtrl.text = existing.options.join(',');
      _nestedCtrl.text = existing.nestedOptions.entries
          .map((e) => '${e.key}:${e.value.join(',')}')
          .join('; ');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _optCtrl.dispose();
    _nestedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? '编辑自定义字段' : '添加自定义字段'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '字段名称',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<FieldType>(
            value: _type,
            decoration: const InputDecoration(
              labelText: '字段类型',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: FieldType.text, child: Text('文本')),
              DropdownMenuItem(value: FieldType.number, child: Text('数字')),
              DropdownMenuItem(value: FieldType.select, child: Text('选项（下拉）')),
              DropdownMenuItem(
                value: FieldType.nestedSelect,
                child: Text('两级选项'),
              ),
            ],
            onChanged: (v) => setState(() => _type = v!),
          ),
          if (_type == FieldType.select) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _optCtrl,
              decoration: const InputDecoration(
                labelText: '选项（用逗号分隔）',
                hintText: '例：晴,多云,雨',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (_type == FieldType.nestedSelect) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _nestedCtrl,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '两级选项',
                hintText: '例：岸边:觅食,休息; 水中:觅食,休息',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameCtrl.text.trim().isEmpty) return;
            final opts =
                _type == FieldType.select
                    ? _optCtrl.text
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList()
                    : <String>[];
            final nested =
                _type == FieldType.nestedSelect
                    ? _parseNestedOptions(_nestedCtrl.text)
                    : <String, List<String>>{};
            Navigator.pop(
              context,
              CustomField(
                id:
                    widget.existing?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                name: _nameCtrl.text.trim(),
                type: _type,
                options: opts,
                nestedOptions: nested,
              ),
            );
          },
          child: Text(_isEditing ? '保存' : '添加'),
        ),
      ],
    );
  }

  Map<String, List<String>> _parseNestedOptions(String raw) {
    final result = <String, List<String>>{};
    for (final group in raw.split(RegExp(r'[;；\n]'))) {
      final parts = group.split(RegExp(r'[:：]'));
      if (parts.length < 2) continue;
      final parent = parts.first.trim();
      final children =
          parts
              .sublist(1)
              .join(':')
              .split(RegExp(r'[,，/]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
      if (parent.isNotEmpty && children.isNotEmpty) result[parent] = children;
    }
    return result;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.green[700],
        ),
      ),
    );
  }
}

// ── WebDAV 配置编辑器 ──────────────────────────────────────────────────────────

class _WebDavEditor extends StatefulWidget {
  const _WebDavEditor();
  @override
  State<_WebDavEditor> createState() => _WebDavEditorState();
}

class _WebDavEditorState extends State<_WebDavEditor> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    WebDavConfig.load().then((c) {
      if (!mounted) return;
      setState(() {
        _urlCtrl.text = c.url;
        _userCtrl.text = c.username;
        _passCtrl.text = c.password;
      });
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = WebDavConfig(
      url: _urlCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
    await config.save();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('WebDAV 设置已保存')));
    }
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final config = WebDavConfig(
      url: _urlCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
    final err = await WebDavService.testConnection(config);
    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = err == null ? '✓ 连接成功' : '✗ $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://dav.jiami.net（小米云盘）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '手机号 / 邮箱',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '密码 / 应用密码',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testing ? null : _test,
                    child:
                        _testing
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _testResult!,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      _testResult!.startsWith('✓')
                          ? Colors.green[700]
                          : Colors.red[700],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '配置后每次导出Excel时自动上传。留空则不备份。\n'
              '小米云盘：设置→账号安全→应用密码 生成专用密码。',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
