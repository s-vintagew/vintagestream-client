import 'package:flutter_test/flutter_test.dart';
import 'package:vs_core/vs_core.dart';

void main() {
  test('library parse ignores server path', () {
    final library = Library.fromJson({
      'movies': [
        {
          'id': 'abc',
          'title': 'Test',
          'type': 'movie',
          'path': '/secret/disk/path.mkv',
          'posterPath': 'https://example.com/p.jpg',
        }
      ],
      'shows': [],
      'marvel': [],
    });
    expect(library.movies.single.id, 'abc');
    expect(library.movies.single.title, 'Test');
  });

  test('original stream url', () {
    final urls = StreamUrls('https://stream.example.org/');
    expect(
      urls.originalStream('id1').toString(),
      'https://stream.example.org/stream?id=id1&resolution=original',
    );
  });

  test('original download url', () {
    final urls = StreamUrls('https://stream.example.org/');
    expect(
      urls.originalDownload('id1').toString(),
      'https://stream.example.org/stream?id=id1&resolution=original&download=true',
    );
  });

  test('mobile update parse', () {
    final info = MobileUpdateInfo.fromJson(
      {
        'versionName': '0.2.0',
        'versionCode': 2,
        'sha256': 'abc',
        'notes': 'ota',
        'mandatory': false,
      },
      apkUrl: Uri.parse('https://github.com/example/repo/releases/download/0.2.0%2B2/app.apk'),
    );
    expect(info.versionCode, 2);
    expect(info.apkUrl.host, 'github.com');
  });
}
