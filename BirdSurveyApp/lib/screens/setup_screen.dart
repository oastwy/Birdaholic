import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/survey_provider.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _tiandituCtrl = TextEditingController();
  final _ebirdCtrl = TextEditingController();
  bool _saving = false;
  bool _showTianditu = true;
  bool _showEbird = true;

  @override
  void dispose() {
    _tiandituCtrl.dispose();
    _ebirdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prov = context.read<SurveyProvider>();
    await prov.saveSettings(
      ebird: _ebirdCtrl.text.trim(),
      chaoxi365: prov.chaoxi365Key,
      chaoxi365Endpoint: prov.chaoxi365Endpoint,
      stormglass: prov.stormglassKey,
      worldtides: prov.worldtidesKey,
      tianditu: _tiandituCtrl.text.trim(),
      qweather: prov.qweatherKey,
      tideSource: prov.tideSource,
    );
    await prov.markSetupDone();
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  Future<void> _skip() async {
    final prov = context.read<SurveyProvider>();
    await prov.markSetupDone();
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[700],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.flutter_dash,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '中国鸟类调查',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '配置 API Key 以启用完整功能',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Tianditu section
              _SectionCard(
                icon: Icons.satellite_alt,
                iconColor: Colors.teal,
                title: '天地图卫星地图',
                subtitle: '卫星影像（可选，不填使用免费街道图）',
                badge: '可选',
                badgeColor: Colors.teal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '注册地址：tianditu.gov.cn → 控制台 → 新建应用\n'
                      '应用类型选「安卓端」，包名填 com.birdsurvey.bird_survey_app',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tiandituCtrl,
                      obscureText: !_showTianditu,
                      decoration: InputDecoration(
                        labelText: '天地图 API Key (tk)',
                        hintText: '粘贴你的 tk 值',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.vpn_key),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showTianditu
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed:
                              () => setState(
                                () => _showTianditu = !_showTianditu,
                              ),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // eBird section
              _SectionCard(
                icon: Icons.location_on,
                iconColor: Colors.orange,
                title: 'eBird 附近鸟种',
                subtitle: '调查时显示附近30天内记录的鸟种',
                badge: '选填',
                badgeColor: Colors.orange,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '注册地址：ebird.org → 账户 → API Access（免费）',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ebirdCtrl,
                      obscureText: !_showEbird,
                      decoration: InputDecoration(
                        labelText: 'eBird API Key',
                        hintText: '可跳过，稍后在设置中填写',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.vpn_key),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showEbird
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed:
                              () => setState(() => _showEbird = !_showEbird),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child:
                      _saving
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text(
                            '保存并开始使用',
                            style: TextStyle(fontSize: 16),
                          ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _skip,
                  child: const Text(
                    '暂时跳过',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11,
                      color: badgeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
