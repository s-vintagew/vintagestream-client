class StreamUrls {
  const StreamUrls(this.baseUrl);

  final String baseUrl;

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Uri library() => Uri.parse('$_root/api/library');

  Uri metadata(String id) => Uri.parse('$_root/api/metadata').replace(
        queryParameters: {'id': id},
      );

  Uri thumbnail(String id) => Uri.parse('$_root/api/thumbnail').replace(
        queryParameters: {'id': id},
      );

  /// Original file — no server transcode.
  Uri originalStream(String id) => Uri.parse('$_root/stream').replace(
        queryParameters: {
          'id': id,
          'resolution': 'original',
        },
      );

  /// Original file as an attachment download (Content-Disposition: attachment).
  Uri originalDownload(String id) => Uri.parse('$_root/stream').replace(
        queryParameters: {
          'id': id,
          'resolution': 'original',
          'download': 'true',
        },
      );

  /// Raw sidecar subtitle (.srt/.ass/…) — no FFmpeg.
  Uri subtitleFile(String id, dynamic index) =>
      Uri.parse('$_root/api/subtitle-file').replace(
        queryParameters: {
          'id': id,
          'index': index.toString(),
        },
      );

  String resolvePoster(String? posterPath, {String? fallbackId}) {
    if (posterPath == null || posterPath.isEmpty) {
      if (fallbackId == null) return '';
      return thumbnail(fallbackId).toString();
    }
    if (posterPath.startsWith('http://') || posterPath.startsWith('https://')) {
      return posterPath;
    }
    if (posterPath.startsWith('/')) return '$_root$posterPath';
    return '$_root/$posterPath';
  }
}
