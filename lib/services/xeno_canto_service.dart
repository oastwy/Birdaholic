import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Xeno-Canto API v3 录音记录
class XCRecording {
  final String id;
  final String gen;
  final String sp;
  final String en;
  final String rec;
  final String cnt;
  final String loc;
  final String type; // "song", "call", "song, call" etc.
  final String q;    // quality rating A-E
  final String length;
  final String? fileUrl;    // download URL, null if restricted
  final String license;

  const XCRecording({
    required this.id,
    required this.gen,
    required this.sp,
    required this.en,
    required this.rec,
    required this.cnt,
    required this.loc,
    required this.type,
    required this.q,
    required this.length,
    this.fileUrl,
    required this.license,
  });

  factory XCRecording.fromJson(Map<String, dynamic> json) {
    return XCRecording(
      id: json['id'] as String? ?? '',
      gen: json['gen'] as String? ?? '',
      sp: json['sp'] as String? ?? '',
      en: json['en'] as String? ?? '',
      rec: json['rec'] as String? ?? '',
      cnt: json['cnt'] as String? ?? '',
      loc: json['loc'] as String? ?? '',
      type: json['type'] as String? ?? '',
      q: json['q'] as String? ?? '',
      length: json['length'] as String? ?? '',
      fileUrl: json['file'] as String?,
      license: json['lic'] as String? ?? '',
    );
  }

  /// 精确匹配 sound type（处理 "song, call" 等复合格式）
  bool hasType(String soundType) {
    return type.toLowerCase().contains(soundType.toLowerCase());
  }

  int get lengthSeconds {
    final parts = length.split(':');
    if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]) ?? 0;
      final seconds = int.tryParse(parts[1]) ?? 0;
      return minutes * 60 + seconds;
    }
    return int.tryParse(length) ?? 0;
  }
}

/// Xeno-Canto API v3 服务
class XenoCantoService {
  static const _baseUrl = 'https://xeno-canto.org/api/3/recordings';

  /// API key（从 xeno-canto.org/account 获取）
  final String apiKey;

  /// 下载进度回调
  void Function(int current, int total, String speciesName)? onProgress;

  XenoCantoService({required this.apiKey, this.onProgress});

  /// 按学名查询录音
  /// 返回录音列表，优先选 A 级质量、中国境内录音
  Future<List<XCRecording>> searchBySpecies(String scientificName) async {
    // 拆分学名: "Leiothrix lutea" -> gen=Leiothrix, sp=lutea
    final parts = scientificName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return [];

    final query = 'gen:${parts[0]}+sp:${parts[1]}+grp:birds+q:">C"';
    final url = '$_baseUrl?query=$query&key=$apiKey&per_page=20';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Xeno-Canto API 请求失败: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final recordings = (data['recordings'] as List<dynamic>)
        .map((r) => XCRecording.fromJson(r as Map<String, dynamic>))
        .toList();

    // 过滤掉受限物种（fileUrl 为 null）
    return recordings.where((r) => r.fileUrl != null).toList();
  }

  /// 下载音频文件到本地
  /// 返回本地文件路径，失败返回 null
  Future<String?> downloadAudio(
    XCRecording recording,
    String saveDir, {
    bool preferSong = true,
  }) async {
    if (recording.fileUrl == null) return null;

    // 构造完整下载 URL
    String fileUrlStr = recording.fileUrl!;
    if (fileUrlStr.startsWith('//')) {
      fileUrlStr = 'https:$fileUrlStr';
    }

    // 构造本地文件名: {XC编号}_{type}.mp3
    final soundType = _extractPrimaryType(recording.type);
    final fileName = '${recording.id}_$soundType.mp3';
    final filePath = '$saveDir/$fileName';

    // 如果已存在则跳过
    if (await File(filePath).exists()) return filePath;

    try {
      final response = await http.get(Uri.parse(fileUrlStr));
      if (response.statusCode != 200) return null;

      await File(filePath).writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      return null;
    }
  }

  /// 从录音列表中选择最佳的 song 和 call
  /// 返回 {song: recording?, call: recording?}
  Map<String, XCRecording?> pickBestRecordings(List<XCRecording> recordings) {
    XCRecording? songRec;
    XCRecording? callRec;

    // 优先高质量，同时尽量选择更短的片段以减小下载体积
    final sorted = List<XCRecording>.from(recordings)
      ..sort((a, b) {
        final qualityCompare = a.q.compareTo(b.q);
        if (qualityCompare != 0) return qualityCompare;
        return a.lengthSeconds.compareTo(b.lengthSeconds);
      });

    for (final r in sorted) {
      // 跳过受限物种
      if (r.fileUrl == null) continue;

      if (songRec == null && r.hasType('song')) {
        songRec = r;
      }
      if (callRec == null && r.hasType('call')) {
        callRec = r;
      }
      if (songRec != null && callRec != null) break;
    }

    return {'song': songRec, 'call': callRec};
  }

  /// 提取主要声音类型
  String _extractPrimaryType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('song')) return 'song';
    if (lower.contains('call')) return 'call';
    if (lower.contains('alarm')) return 'alarm';
    return 'other';
  }
}
