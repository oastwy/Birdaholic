import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/custom_field.dart';
import '../models/survey_point.dart';
import '../providers/survey_provider.dart';
import 'survey_screen.dart';

class SurveyStartScreen extends StatefulWidget {
  const SurveyStartScreen({super.key});

  @override
  State<SurveyStartScreen> createState() => _SurveyStartScreenState();
}

class _SurveyStartScreenState extends State<SurveyStartScreen> {
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, String> _sel = {};
  SurveyPoint? _selectedPoint;
  LatLng? _manualLocation;
  bool _starting = false;
  final MapController _mapCtrl = MapController();
  bool _didFitPoints = false;

  @override
  void initState() {
    super.initState();
    final prov = context.read<SurveyProvider>();
    for (final f in prov.customFields) {
      if (f.type == FieldType.select) {
        _sel[f.id] = f.options.isNotEmpty ? f.options.first : '';
      } else {
        _ctrl[f.id] = TextEditingController(text: f.defaultValue);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collectValues(List<CustomField> fields) {
    final values = <String, String>{};
    for (final f in fields) {
      if (f.type == FieldType.select) {
        values[f.name] = _sel[f.id] ?? '';
      } else {
        values[f.name] = _ctrl[f.id]?.text ?? '';
      }
    }
    if (_selectedPoint != null) {
      values['位点名称'] = _selectedPoint!.name;
    }
    return values;
  }

  void _selectPoint(SurveyPoint p) {
    setState(() {
      _selectedPoint = p;
      _manualLocation = null;
    });
    _mapCtrl.move(LatLng(p.latitude, p.longitude), 14);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    final pos = prov.position;
    final fields = prov.customFields;
    final tiandituKey = prov.tiandituKey;

    // nearby points sorted by distance
    final nearby = pos != null
        ? prov.nearbyPoints(pos.latitude, pos.longitude)
        : <SurveyPoint>[];

    // map center: selected point > GPS > default (China center)
    final center = _selectedPoint != null
        ? LatLng(_selectedPoint!.latitude, _selectedPoint!.longitude)
        : pos != null
            ? LatLng(pos.latitude, pos.longitude)
            : const LatLng(32.0, 118.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('开始调查'),
        actions: [
          IconButton(
            icon: const Icon(Icons.place),
            tooltip: '管理位点',
            onPressed: () =>
                Navigator.pushNamed(context, '/survey_points')
                    .then((_) => prov.reloadSurveyPoints()),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Map ───────────────────────────────────────────────────────────
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                // fit to points after first load
                Builder(builder: (ctx) {
                  if (!_didFitPoints &&
                      prov.surveyPoints.length >= 2 &&
                      _selectedPoint == null &&
                      _manualLocation == null &&
                      pos == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      try {
                        final pts = prov.surveyPoints
                            .map((p) => LatLng(p.latitude, p.longitude))
                            .toList();
                        _mapCtrl.fitCamera(CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(pts),
                          padding: const EdgeInsets.all(40),
                        ));
                      } catch (_) {}
                      setState(() => _didFitPoints = true);
                    });
                  }
                  return const SizedBox.shrink();
                }),
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: pos != null ? 13 : 6,
                    onTap: (_, point) => setState(() {
                      _manualLocation = point;
                      _selectedPoint = null;
                    }),
                  ),
                  children: [
                    // Tianditu satellite layer
                    if (tiandituKey.isNotEmpty) ...[
                      TileLayer(
                        urlTemplate:
                            'https://t{s}.tianditu.gov.cn/img_w/wmts?'
                            'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
                            '&LAYER=img&STYLE=default&TILEMATRIXSET=w'
                            '&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}'
                            '&TILECOL={x}&tk=$tiandituKey',
                        subdomains: const [
                          '0','1','2','3','4','5','6','7'
                        ],
                        userAgentPackageName: 'com.birdsurvey.app',
                      ),
                      // Tianditu annotation layer (road/place labels)
                      TileLayer(
                        urlTemplate:
                            'https://t{s}.tianditu.gov.cn/cia_w/wmts?'
                            'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
                            '&LAYER=cia&STYLE=default&TILEMATRIXSET=w'
                            '&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}'
                            '&TILECOL={x}&tk=$tiandituKey',
                        subdomains: const [
                          '0','1','2','3','4','5','6','7'
                        ],
                        userAgentPackageName: 'com.birdsurvey.app',
                      ),
                    ] else
                      // Fallback: OSM street map
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.birdsurvey.app',
                      ),
                    // All survey point markers
                    MarkerLayer(
                      markers: [
                        // Survey points
                        ...prov.surveyPoints.map((p) => Marker(
                              point: LatLng(p.latitude, p.longitude),
                              width: 36,
                              height: 36,
                              child: GestureDetector(
                                onTap: () => _selectPoint(p),
                                child: Icon(
                                  Icons.place,
                                  color: _selectedPoint?.id == p.id
                                      ? Colors.orange
                                      : Colors.teal,
                                  size: 32,
                                  shadows: const [
                                    Shadow(
                                        color: Colors.white,
                                        blurRadius: 3)
                                  ],
                                ),
                              ),
                            )),
                        // Manual tapped location
                        if (_manualLocation != null)
                          Marker(
                            point: _manualLocation!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 36,
                              shadows: [
                                Shadow(color: Colors.white, blurRadius: 4)
                              ],
                            ),
                          ),
                        // Current GPS position
                        if (pos != null)
                          Marker(
                            point: LatLng(pos.latitude, pos.longitude),
                            width: 20,
                            height: 20,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4)
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // Locate-me button
                if (pos != null)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: FloatingActionButton.small(
                      heroTag: 'locateMe',
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue[700],
                      tooltip: '回到当前位置',
                      onPressed: () => _mapCtrl.move(
                          LatLng(pos.latitude, pos.longitude), 14),
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                // Tap-to-select hint (shown when no location selected)
                if (_manualLocation == null && _selectedPoint == null && pos == null)
                  Positioned(
                    bottom: 34,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '点击地图选择调查位置',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                // Manual location label
                if (_manualLocation != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '手动选点: ${_manualLocation!.latitude.toStringAsFixed(5)}, '
                        '${_manualLocation!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                // No Tianditu key hint
                if (tiandituKey.isEmpty)
                  Positioned(
                    bottom: 6,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '设置中填写天地图Key可显示卫星图',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                // Selected point label
                if (_selectedPoint != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '已选：${_selectedPoint!.name}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                // North-up + fullscreen buttons
                Positioned(
                  right: 8,
                  bottom: 36,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MapButton(
                        icon: Icons.explore,
                        tooltip: '回正北方',
                        onTap: () {
                          try { _mapCtrl.rotate(0); } catch (_) {}
                        },
                      ),
                      const SizedBox(height: 6),
                      _MapButton(
                        icon: Icons.fullscreen,
                        tooltip: '全屏选点',
                        onTap: () async {
                          final result =
                              await Navigator.push<LatLng>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _FullscreenMapPage(
                                initialCenter: center,
                                initialZoom: pos != null ? 13.0 : (prov.surveyPoints.isEmpty ? 6.0 : 10.0),
                                surveyPoints: prov.surveyPoints,
                                manualLocation: _manualLocation,
                                selectedPoint: _selectedPoint,
                                tiandituKey: tiandituKey,
                              ),
                            ),
                          );
                          if (result != null && mounted) {
                            setState(() {
                              _manualLocation = result;
                              _selectedPoint = null;
                            });
                            _mapCtrl.move(result, 14);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Form area ─────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Nearby points chips
                if (nearby.isNotEmpty) ...[
                  Text('附近位点',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: nearby.map((p) {
                      final selected = _selectedPoint?.id == p.id;
                      return ChoiceChip(
                        label: Text(
                          '${p.name}  ${p.distanceLabel}',
                          style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? Colors.white
                                  : Colors.teal[800]),
                        ),
                        selected: selected,
                        selectedColor: Colors.teal,
                        backgroundColor: Colors.teal[50],
                        onSelected: (_) => _selectPoint(p),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // No points hint
                if (prov.surveyPoints.isEmpty)
                  Card(
                    color: Colors.amber[50],
                    child: ListTile(
                      leading: const Icon(Icons.info_outline,
                          color: Colors.amber),
                      title: const Text('未导入调查位点',
                          style: TextStyle(fontSize: 13)),
                      subtitle: const Text('可在右上角导入CSV位点文件',
                          style: TextStyle(fontSize: 11)),
                      trailing: TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/survey_points')
                                .then((_) => prov.reloadSurveyPoints()),
                        child: const Text('去导入'),
                      ),
                    ),
                  ),

                if (fields.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('调查信息',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                  const SizedBox(height: 8),
                  ...fields.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FieldWidget(
                          field: f,
                          controller: _ctrl[f.id],
                          selectValue: _sel[f.id],
                          onSelectChanged: (v) =>
                              setState(() => _sel[f.id] = v),
                        ),
                      )),
                ],

                const SizedBox(height: 12),
                _LocationStatusBar(
                  pos: pos,
                  selectedPoint: _selectedPoint,
                  manualLocation: _manualLocation,
                  onRetryGps: () async {
                    // Clear manual selection and re-fetch GPS
                    setState(() {
                      _manualLocation = null;
                      _selectedPoint = null;
                    });
                    await prov.retryGps();
                  },
                  onClearManual: () =>
                      setState(() => _manualLocation = null),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _starting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.play_arrow),
                    label: Text(_starting
                        ? (_manualLocation != null || _selectedPoint != null
                            ? '正在启动...'
                            : '正在获取位置...')
                        : '开始调查'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _starting
                        ? null
                        : () async {
                            setState(() => _starting = true);
                            final values = _collectValues(fields);
                            // Determine manual coords: tapped point > selected survey point > GPS
                            double? manualLat, manualLon;
                            if (_manualLocation != null) {
                              manualLat = _manualLocation!.latitude;
                              manualLon = _manualLocation!.longitude;
                            } else if (_selectedPoint != null) {
                              manualLat = _selectedPoint!.latitude;
                              manualLon = _selectedPoint!.longitude;
                            }
                            await prov.startSurvey(
                              values,
                              manualLat: manualLat,
                              manualLon: manualLon,
                            );
                            if (context.mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SurveyScreen()),
                              );
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldWidget extends StatelessWidget {
  final CustomField field;
  final TextEditingController? controller;
  final String? selectValue;
  final void Function(String)? onSelectChanged;

  const _FieldWidget({
    required this.field,
    this.controller,
    this.selectValue,
    this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case FieldType.select:
        return DropdownButtonFormField<String>(
          value: selectValue,
          decoration: InputDecoration(
              labelText: field.name,
              border: const OutlineInputBorder(),
              isDense: true),
          items: field.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => onSelectChanged?.call(v ?? ''),
        );
      case FieldType.number:
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(
              labelText: field.name,
              border: const OutlineInputBorder(),
              isDense: true),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
        );
      case FieldType.text:
        return TextFormField(
          controller: controller,
          decoration: InputDecoration(
              labelText: field.name,
              border: const OutlineInputBorder(),
              isDense: true),
        );
    }
  }
}

// ── Location status bar ──────────────────────────────────────────────────────

class _LocationStatusBar extends StatelessWidget {
  final Position? pos;
  final SurveyPoint? selectedPoint;
  final LatLng? manualLocation;
  final VoidCallback onRetryGps;
  final VoidCallback onClearManual;

  const _LocationStatusBar({
    required this.pos,
    required this.selectedPoint,
    required this.manualLocation,
    required this.onRetryGps,
    required this.onClearManual,
  });

  @override
  Widget build(BuildContext context) {
    if (manualLocation != null) {
      return Card(
        color: Colors.red[50],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            const Icon(Icons.location_pin, color: Colors.red, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '手动选点: ${manualLocation!.latitude.toStringAsFixed(5)}, '
                '${manualLocation!.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: onClearManual,
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30)),
              child: const Text('清除', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: onRetryGps,
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30)),
              child: const Text('重试GPS', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      );
    }
    if (selectedPoint != null) {
      return Card(
        color: Colors.orange[50],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(Icons.place, color: Colors.orange[700], size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '位点: ${selectedPoint!.name}  '
                '(${selectedPoint!.latitude.toStringAsFixed(5)}, '
                '${selectedPoint!.longitude.toStringAsFixed(5)})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ]),
        ),
      );
    }
    if (pos != null) {
      return Card(
        color: Colors.blue[50],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(Icons.gps_fixed, color: Colors.blue[700], size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'GPS: ${pos!.latitude.toStringAsFixed(5)}, '
                '${pos!.longitude.toStringAsFixed(5)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ]),
        ),
      );
    }
    // No location at all
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.gps_off, color: Colors.amber, size: 18),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'GPS不可用 — 请点击地图选择位置，或重试GPS',
              style: TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onRetryGps,
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(60, 30)),
            child: const Text('重试GPS', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}

// ── Small map overlay button ─────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _MapButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Icon(icon, size: 20, color: Colors.grey[700]),
        ),
      ),
    );
  }
}

// ── Fullscreen map page ───────────────────────────────────────────────────────

class _FullscreenMapPage extends StatefulWidget {
  final LatLng initialCenter;
  final double initialZoom;
  final List<SurveyPoint> surveyPoints;
  final LatLng? manualLocation;
  final SurveyPoint? selectedPoint;
  final String tiandituKey;

  const _FullscreenMapPage({
    required this.initialCenter,
    required this.initialZoom,
    required this.surveyPoints,
    required this.tiandituKey,
    this.manualLocation,
    this.selectedPoint,
  });

  @override
  State<_FullscreenMapPage> createState() => _FullscreenMapPageState();
}

class _FullscreenMapPageState extends State<_FullscreenMapPage> {
  late LatLng? _picked;
  late SurveyPoint? _pickedPoint;
  final MapController _ctrl = MapController();

  @override
  void initState() {
    super.initState();
    _picked = widget.manualLocation;
    _pickedPoint = widget.selectedPoint;
  }

  @override
  Widget build(BuildContext context) {
    final label = _pickedPoint?.name ??
        (_picked != null
            ? '${_picked!.latitude.toStringAsFixed(5)}, ${_picked!.longitude.toStringAsFixed(5)}'
            : '点击地图选择位置');

    return Scaffold(
      appBar: AppBar(
        title: Text(label,
            style: const TextStyle(fontSize: 14),
            overflow: TextOverflow.ellipsis),
        actions: [
          if (_picked != null || _pickedPoint != null)
            TextButton(
              onPressed: () {
                final result = _pickedPoint != null
                    ? LatLng(_pickedPoint!.latitude, _pickedPoint!.longitude)
                    : _picked;
                Navigator.pop(context, result);
              },
              child: const Text('确认',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          IconButton(
            icon: const Icon(Icons.explore),
            tooltip: '回正北方',
            onPressed: () {
              try { _ctrl.rotate(0); } catch (_) {}
            },
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _ctrl,
        options: MapOptions(
          initialCenter: widget.initialCenter,
          initialZoom: widget.initialZoom,
          onTap: (_, point) => setState(() {
            _picked = point;
            _pickedPoint = null;
          }),
        ),
        children: [
          if (widget.tiandituKey.isNotEmpty) ...[
            TileLayer(
              urlTemplate: 'https://t{s}.tianditu.gov.cn/img_w/wmts?'
                  'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
                  '&LAYER=img&STYLE=default&TILEMATRIXSET=w'
                  '&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}'
                  '&TILECOL={x}&tk=${widget.tiandituKey}',
              subdomains: const ['0','1','2','3','4','5','6','7'],
              userAgentPackageName: 'com.birdsurvey.bird_survey_app',
            ),
            TileLayer(
              urlTemplate: 'https://t{s}.tianditu.gov.cn/cia_w/wmts?'
                  'SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
                  '&LAYER=cia&STYLE=default&TILEMATRIXSET=w'
                  '&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}'
                  '&TILECOL={x}&tk=${widget.tiandituKey}',
              subdomains: const ['0','1','2','3','4','5','6','7'],
              userAgentPackageName: 'com.birdsurvey.bird_survey_app',
            ),
          ] else
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.birdsurvey.bird_survey_app',
            ),
          MarkerLayer(
            markers: [
              ...widget.surveyPoints.map((p) => Marker(
                    point: LatLng(p.latitude, p.longitude),
                    width: 36,
                    height: 36,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _pickedPoint = p;
                        _picked = null;
                      }),
                      child: Icon(
                        Icons.place,
                        color: _pickedPoint?.id == p.id
                            ? Colors.orange
                            : Colors.teal,
                        size: 32,
                        shadows: const [
                          Shadow(color: Colors.white, blurRadius: 3)
                        ],
                      ),
                    ),
                  )),
              if (_picked != null)
                Marker(
                  point: _picked!,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.location_pin,
                      color: Colors.red, size: 36,
                      shadows: [Shadow(color: Colors.white, blurRadius: 4)]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
