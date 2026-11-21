class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.type,
    this.tmdbId,
    this.originalTitle,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.voteAverage,
    this.marvel = false,
    this.marvelOrder,
    this.marvelPhase,
    this.episodes = const [],
  });

  final String id;
  final String title;
  final String type; // movie | tv
  final int? tmdbId;
  final String? originalTitle;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final double? voteAverage;
  final bool marvel;
  final int? marvelOrder;
  final String? marvelPhase;
  final List<Episode> episodes;

  bool get isShow => type == 'tv' || episodes.isNotEmpty;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final episodesRaw = json['episodes'];
    return MediaItem(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Untitled',
      type: (json['type'] as String?) ?? 'movie',
      tmdbId: _asInt(json['tmdbId']),
      originalTitle: json['originalTitle'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      overview: json['overview'] as String?,
      voteAverage: _asDouble(json['voteAverage']),
      marvel: json['marvel'] == true,
      marvelOrder: _asInt(json['marvelOrder']),
      marvelPhase: json['marvelPhase'] as String?,
      episodes: episodesRaw is List
          ? episodesRaw
              .whereType<Map>()
              .map((e) => Episode.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    this.season,
    this.episode,
    this.originalTitle,
  });

  final String id;
  final String title;
  final int? season;
  final int? episode;
  final String? originalTitle;

  String get label {
    if (season != null && episode != null) {
      final s = season!.toString().padLeft(2, '0');
      final e = episode!.toString().padLeft(2, '0');
      return 'S${s}E$e · $title';
    }
    return title;
  }

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Episode',
      season: _asInt(json['season']),
      episode: _asInt(json['episode']),
      originalTitle: json['originalTitle'] as String?,
    );
  }
}

class Library {
  const Library({
    this.movies = const [],
    this.shows = const [],
    this.marvel = const [],
  });

  final List<MediaItem> movies;
  final List<MediaItem> shows;
  final List<MediaItem> marvel;

  factory Library.fromJson(Map<String, dynamic> json) {
    List<MediaItem> parse(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return Library(
      movies: parse('movies'),
      shows: parse('shows'),
      marvel: parse('marvel'),
    );
  }

  List<MediaItem> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    bool match(MediaItem m) =>
        m.title.toLowerCase().contains(q) ||
        (m.overview?.toLowerCase().contains(q) ?? false);
    return [
      ...movies.where(match),
      ...shows.where(match),
      ...marvel.where(match),
    ];
  }
}

class MobileUpdateInfo {
  const MobileUpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    this.sha256,
    this.notes = '',
    this.mandatory = false,
    this.publishedAt,
  });

  final String versionName;
  final int versionCode;
  final Uri apkUrl;
  final String? sha256;
  final String notes;
  final bool mandatory;
  final String? publishedAt;

  factory MobileUpdateInfo.fromJson(Map<String, dynamic> json, {required Uri apkUrl}) {
    final remote = json['apkUrl'] as String?;
    return MobileUpdateInfo(
      versionName: (json['versionName'] as String?) ?? '',
      versionCode: _asInt(json['versionCode']) ?? 0,
      apkUrl: (remote != null && remote.startsWith('http'))
          ? Uri.parse(remote)
          : apkUrl,
      sha256: json['sha256'] as String?,
      notes: (json['notes'] as String?) ?? '',
      mandatory: json['mandatory'] == true,
      publishedAt: json['publishedAt'] as String?,
    );
  }
}

class SubtitleTrackInfo {
  const SubtitleTrackInfo({
    required this.index,
    required this.source,
    required this.kind,
    required this.supported,
    this.language,
    this.title,
    this.codec,
  });

  final dynamic index;
  final String source; // embedded | file
  final String kind; // text | image | unknown
  final bool supported;
  final String? language;
  final String? title;
  final String? codec;

  bool get isExternal => source == 'file' || index.toString().startsWith('f');

  String get label {
    final lang = (language == null || language == 'und') ? null : language;
    final base = title?.trim().isNotEmpty == true
        ? (lang != null ? '$lang · $title' : title!)
        : (lang ?? 'Track $index');
    if (!supported && kind == 'image') return '$base (image)';
    return base;
  }

  factory SubtitleTrackInfo.fromJson(Map<String, dynamic> json) {
    return SubtitleTrackInfo(
      index: json['index'],
      source: (json['source'] as String?) ?? 'embedded',
      kind: (json['kind'] as String?) ?? 'text',
      supported: json['supported'] != false,
      language: json['language'] as String?,
      title: json['title'] as String?,
      codec: json['codec'] as String?,
    );
  }
}

class MediaMetadata {
  const MediaMetadata({
    this.duration,
    this.videoCodec,
    this.audioCodec,
    this.width,
    this.height,
    this.playMode,
    this.subtitles = const [],
  });

  final double? duration;
  final String? videoCodec;
  final String? audioCodec;
  final int? width;
  final int? height;
  final String? playMode;
  final List<SubtitleTrackInfo> subtitles;

  factory MediaMetadata.fromJson(Map<String, dynamic> json) {
    final subs = json['subtitles'];
    return MediaMetadata(
      duration: _asDouble(json['duration']),
      videoCodec: json['videoCodec'] as String?,
      audioCodec: json['audioCodec'] as String?,
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      playMode: json['playMode'] as String?,
      subtitles: subs is List
          ? subs
              .whereType<Map>()
              .map((e) => SubtitleTrackInfo.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
