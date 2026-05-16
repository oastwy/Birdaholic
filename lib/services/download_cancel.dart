class DownloadCanceledException implements Exception {
  const DownloadCanceledException();

  @override
  String toString() => '下载已取消';
}
