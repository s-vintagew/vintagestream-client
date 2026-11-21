import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'models.dart';

/// Fetches Android update info from a public GitHub Releases "latest" release.
///
/// Expected release shape:
/// - Tag: `0.2.0+2` or `v0.2.0+2` (name + android versionCode)
/// - Asset: an `.apk` (optional extra `latest.json` overrides notes/sha256/mandatory)
class GitHubUpdateClient {
  GitHubUpdateClient({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  /// Returns null when the repo has no releases yet (404).
  Future<MobileUpdateInfo?> fetchLatest(String ownerRepo) async {
    final repo = ownerRepo.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (repo.isEmpty || !repo.contains('/')) {
      throw ApiException('GitHub update repo must look like owner/name');
    }

    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    final res = await _client
        .get(
          uri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'VintageStream-Android',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw ApiException('GitHub update check failed (${res.statusCode})');
    }

    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw ApiException('GitHub release response was not an object');
    }

    final assets = body['assets'];
    if (assets is! List) {
      throw ApiException('GitHub release has no assets');
    }

    final apk = _pickApk(assets);
    if (apk == null) {
      throw ApiException('Latest GitHub release has no .apk asset');
    }

    final parsed = _parseTag(body['tag_name'] as String? ?? '');
    var versionName = parsed.versionName;
    var versionCode = parsed.versionCode;
    var notes = (body['body'] as String?)?.trim() ?? '';
    String? sha256;
    var mandatory = false;

    final manifestAsset = _pickNamed(assets, 'latest.json');
    if (manifestAsset != null) {
      final manifestUrl = manifestAsset['browser_download_url'] as String?;
      if (manifestUrl != null && manifestUrl.isNotEmpty) {
        final mRes = await _client
            .get(Uri.parse(manifestUrl))
            .timeout(const Duration(seconds: 15));
        if (mRes.statusCode == 200) {
          final mBody = jsonDecode(mRes.body);
          if (mBody is Map<String, dynamic>) {
            final name = (mBody['versionName'] as String?)?.trim();
            if (name != null && name.isNotEmpty) versionName = name;
            versionCode = _asInt(mBody['versionCode']) ?? versionCode;
            sha256 = mBody['sha256'] as String?;
            if (mBody['notes'] is String) notes = (mBody['notes'] as String).trim();
            mandatory = mBody['mandatory'] == true;
            final overrideApk = mBody['apkUrl'] as String?;
            if (overrideApk != null && overrideApk.startsWith('http')) {
              return MobileUpdateInfo(
                versionName: versionName,
                versionCode: versionCode,
                apkUrl: Uri.parse(overrideApk),
                sha256: sha256,
                notes: notes,
                mandatory: mandatory,
                publishedAt: body['published_at'] as String?,
              );
            }
          }
        }
      }
    }

    if (versionName.isEmpty || versionCode < 1) {
      throw ApiException(
        'Release tag must look like 0.2.0+2 (got "${body['tag_name']}")',
      );
    }

    final apkUrl = apk['browser_download_url'] as String?;
    if (apkUrl == null || apkUrl.isEmpty) {
      throw ApiException('APK asset is missing a download URL');
    }

    return MobileUpdateInfo(
      versionName: versionName,
      versionCode: versionCode,
      apkUrl: Uri.parse(apkUrl),
      sha256: sha256,
      notes: notes,
      mandatory: mandatory,
      publishedAt: body['published_at'] as String?,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static Map<String, dynamic>? _pickApk(List<dynamic> assets) {
    Map<String, dynamic>? preferred;
    Map<String, dynamic>? legacy;
    Map<String, dynamic>? fallback;
    for (final raw in assets) {
      if (raw is! Map) continue;
      final asset = Map<String, dynamic>.from(raw);
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      if (!name.endsWith('.apk')) continue;
      if (name == 'vintagestream.apk') {
        preferred = asset;
        break;
      }
      if (name.contains('vintagestream')) {
        legacy ??= asset;
        continue;
      }
      fallback ??= asset;
    }
    return preferred ?? legacy ?? fallback;
  }

  static Map<String, dynamic>? _pickNamed(List<dynamic> assets, String fileName) {
    final want = fileName.toLowerCase();
    for (final raw in assets) {
      if (raw is! Map) continue;
      final asset = Map<String, dynamic>.from(raw);
      final name = (asset['name'] as String?)?.toLowerCase() ?? '';
      if (name == want) return asset;
    }
    return null;
  }

  static ({String versionName, int versionCode}) _parseTag(String tag) {
    var t = tag.trim();
    if (t.startsWith('v') || t.startsWith('V')) t = t.substring(1);
    final plus = t.lastIndexOf('+');
    if (plus <= 0 || plus == t.length - 1) {
      return (versionName: t, versionCode: 0);
    }
    final name = t.substring(0, plus).trim();
    final code = int.tryParse(t.substring(plus + 1).trim()) ?? 0;
    return (versionName: name, versionCode: code);
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
