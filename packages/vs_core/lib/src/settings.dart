import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  AppSettings(this._prefs);

  /// Hint only — never applied unless the user saves a URL.
  static const serverUrlHint = 'https://stream.example.org';

  /// Public GitHub repo whose Releases host the Android APK (source of truth for OTA).
  static const defaultUpdateRepo = 's-vintagew/vintagestream-client';
  static const _baseUrlKey = 'base_url';
  static const _updateRepoKey = 'update_repo';
  static const _edgeGesturesKey = 'player_edge_gestures';
  static const _recentStreamsKey = 'recent_network_streams';
  static const _subtitleSizeKey = 'subtitle_font_size';
  static const _subtitleBottomKey = 'subtitle_bottom_padding';
  static const _videoFitKey = 'video_fit_mode';
  static const _maxRecentStreams = 12;
  static const defaultSubtitleSize = 32.0;
  static const defaultSubtitleBottom = 24.0;
  static const minSubtitleSize = 18.0;
  static const maxSubtitleSize = 64.0;
  static const minSubtitleBottom = 8.0;
  static const maxSubtitleBottom = 160.0;

  /// mpv-style video scaling: fit (contain), crop (cover), stretch (fill).
  static const videoFitFit = 'fit';
  static const videoFitCrop = 'crop';
  static const videoFitStretch = 'stretch';
  static const defaultVideoFit = videoFitFit;

  final SharedPreferences _prefs;

  static Future<AppSettings> open() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(prefs);
  }

  /// Empty until the user saves a server URL. No built-in default host.
  String get baseUrl {
    final value = _prefs.getString(_baseUrlKey);
    if (value == null) return '';
    return value.trim().replaceAll(RegExp(r'/+$'), '');
  }

  bool get hasServerUrl => baseUrl.isNotEmpty;

  Future<void> setBaseUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) {
      await _prefs.remove(_baseUrlKey);
      return;
    }
    await _prefs.setString(_baseUrlKey, cleaned);
  }

  String get updateRepo {
    final value = _prefs.getString(_updateRepoKey);
    if (value == null || value.trim().isEmpty) return defaultUpdateRepo;
    return value.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  Future<void> setUpdateRepo(String repo) async {
    final cleaned = repo.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    await _prefs.setString(
      _updateRepoKey,
      cleaned.isEmpty ? defaultUpdateRepo : cleaned,
    );
  }

  /// Vertical edge swipes: left = brightness, right = volume (Android player).
  bool get playerEdgeGestures => _prefs.getBool(_edgeGesturesKey) ?? false;

  Future<void> setPlayerEdgeGestures(bool enabled) async {
    await _prefs.setBool(_edgeGesturesKey, enabled);
  }

  /// Recent direct network stream URLs (mpv-style open).
  List<String> get recentNetworkStreams =>
      _prefs.getStringList(_recentStreamsKey) ?? const [];

  Future<void> rememberNetworkStream(String url) async {
    final cleaned = url.trim();
    if (cleaned.isEmpty) return;
    final next = <String>[
      cleaned,
      ...recentNetworkStreams.where((item) => item != cleaned),
    ];
    if (next.length > _maxRecentStreams) {
      next.removeRange(_maxRecentStreams, next.length);
    }
    await _prefs.setStringList(_recentStreamsKey, next);
  }

  Future<void> clearRecentNetworkStreams() async {
    await _prefs.remove(_recentStreamsKey);
  }

  /// Flutter subtitle text size (media_kit SubtitleView).
  double get subtitleFontSize {
    final value = _prefs.getDouble(_subtitleSizeKey);
    if (value == null) return defaultSubtitleSize;
    return value.clamp(minSubtitleSize, maxSubtitleSize);
  }

  Future<void> setSubtitleFontSize(double size) async {
    await _prefs.setDouble(
      _subtitleSizeKey,
      size.clamp(minSubtitleSize, maxSubtitleSize),
    );
  }

  /// Distance from the bottom edge; higher = subtitles sit higher on screen.
  double get subtitleBottomPadding {
    final value = _prefs.getDouble(_subtitleBottomKey);
    if (value == null) return defaultSubtitleBottom;
    return value.clamp(minSubtitleBottom, maxSubtitleBottom);
  }

  Future<void> setSubtitleBottomPadding(double padding) async {
    await _prefs.setDouble(
      _subtitleBottomKey,
      padding.clamp(minSubtitleBottom, maxSubtitleBottom),
    );
  }

  String get videoFitMode {
    final value = _prefs.getString(_videoFitKey);
    if (value == videoFitCrop || value == videoFitStretch || value == videoFitFit) {
      return value!;
    }
    return defaultVideoFit;
  }

  Future<void> setVideoFitMode(String mode) async {
    final next = (mode == videoFitCrop || mode == videoFitStretch)
        ? mode
        : videoFitFit;
    await _prefs.setString(_videoFitKey, next);
  }
}
