import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'urls.dart';

class VintageStreamApi {
  VintageStreamApi({
    required String baseUrl,
    http.Client? client,
  })  : urls = StreamUrls(baseUrl),
        _client = client ?? http.Client();

  final StreamUrls urls;
  final http.Client _client;

  Future<Library> fetchLibrary() async {
    final res = await _client.get(urls.library()).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw ApiException('Library failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw ApiException('Library response was not an object');
    }
    return Library.fromJson(body);
  }

  Future<MediaMetadata> fetchMetadata(String id) async {
    final res = await _client.get(urls.metadata(id)).timeout(const Duration(seconds: 45));
    if (res.statusCode != 200) {
      throw ApiException('Metadata failed (${res.statusCode})');
    }
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw ApiException('Metadata response was not an object');
    }
    return MediaMetadata.fromJson(body);
  }

  void close() => _client.close();
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
