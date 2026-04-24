import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Wikimedia Commons 图片搜索与下载服务
/// 使用 Wikimedia API 按学名搜索鸟类图片
class WikimediaService {
  static const _apiBase = 'https://commons.wikimedia.org/w/api.php';
  static const _thumbWidth = 640;

  /// 按学名搜索 Wikimedia Commons 上的图片
  /// 返回图片 URL 列表
  Future<List<String>> searchImages(String scientificName, {int limit = 5}) async {
    final query = scientificName.replaceAll(RegExp(r'\s+'), '_');
    final url = '$_apiBase?'
        'action=query'
        '&generator=categorymembers'
        '&gcmtitle=Category:$query'
        '&gcmtype=file'
        '&gcmlimit=$limit'
        '&prop=imageinfo'
        '&iiprop=url|size'
        '&iiurlwidth=$_thumbWidth'
        '&format=json';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final queryResult = data['query'] as Map<String, dynamic>?;
    if (queryResult == null) return [];

    final pages = queryResult['pages'] as Map<String, dynamic>?;
    if (pages == null) return [];

    final urls = <String>[];
    for (final page in pages.values) {
      final infoList = page['imageinfo'] as List<dynamic>?;
      if (infoList != null && infoList.isNotEmpty) {
        final info = infoList[0] as Map<String, dynamic>;
        // 优先取缩略图
        final thumbUrl = info['thumburl'] as String?;
        final origUrl = info['url'] as String?;
        // 只取图片类型
        final mime = info['mime'] as String? ?? '';
        if (mime.startsWith('image/')) {
          urls.add(thumbUrl ?? origUrl ?? '');
        }
      }
    }

    return urls.where((u) => u.isNotEmpty).toList();
  }

  /// 按文件名直接搜索（备用方案）
  Future<List<String>> searchByTitle(String scientificName, {int limit = 3}) async {
    final url = '$_apiBase?'
        'action=query'
        '&list=search'
        '&srsearch=${Uri.encodeComponent(scientificName)}'
        '&srnamespace=6'
        '&srlimit=$limit'
        '&srprop=title'
        '&format=json';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final search = data['query'] as Map<String, dynamic>?;
    if (search == null) return [];

    final results = search['search'] as List<dynamic>? ?? [];
    if (results.isEmpty) return [];

    // 获取图片 URL
    final titles = results
        .map((r) => r['title'] as String)
        .where((t) => t.startsWith('File:'))
        .toList();

    if (titles.isEmpty) return [];

    final titleParam = titles.map((t) => Uri.encodeComponent(t)).join('|');
    final infoUrl = '$_apiBase?'
        'action=query'
        '&titles=$titleParam'
        '&prop=imageinfo'
        '&iiprop=url|mime'
        '&iiurlwidth=$_thumbWidth'
        '&format=json';

    final infoResp = await http.get(Uri.parse(infoUrl));
    if (infoResp.statusCode != 200) return [];

    final infoData = jsonDecode(infoResp.body) as Map<String, dynamic>;
    final infoQuery = infoData['query'] as Map<String, dynamic>?;
    if (infoQuery == null) return [];

    final infoPages = infoQuery['pages'] as Map<String, dynamic>? ?? {};
    final urls = <String>[];
    for (final page in infoPages.values) {
      final infoList = page['imageinfo'] as List<dynamic>?;
      if (infoList != null && infoList.isNotEmpty) {
        final info = infoList[0] as Map<String, dynamic>;
        final mime = info['mime'] as String? ?? '';
        if (mime.startsWith('image/')) {
          urls.add(info['thumburl'] as String? ?? info['url'] as String? ?? '');
        }
      }
    }

    return urls.where((u) => u.isNotEmpty).toList();
  }

  /// 下载图片到本地
  /// 返回本地文件路径，失败返回 null
  Future<String?> downloadImage(String imageUrl, String savePath) async {
    if (await File(savePath).exists()) return savePath;

    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) return null;

      // 确保目录存在
      await File(savePath).parent.create(recursive: true);
      await File(savePath).writeAsBytes(response.bodyBytes);
      return savePath;
    } catch (e) {
      return null;
    }
  }

  /// 综合搜索：先按分类，再按标题
  Future<String?> searchAndDownload(
    String scientificName,
    String savePath, {
    int timeoutSeconds = 10,
  }) async {
    // 方案1：按分类搜索
    var urls = await searchImages(scientificName);
    if (urls.isEmpty) {
      // 方案2：按标题搜索
      urls = await searchByTitle(scientificName);
    }

    if (urls.isEmpty) return null;

    // 下载第一张
    for (final url in urls) {
      final result = await downloadImage(url, savePath);
      if (result != null) return result;
    }

    return null;
  }
}
