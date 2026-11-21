import 'package:flutter/material.dart';
import 'package:vs_core/vs_core.dart';

import 'download.dart';
import 'package:vs_ui/vs_ui.dart';

class ShowDetailsScreen extends StatelessWidget {
  const ShowDetailsScreen({
    super.key,
    required this.media,
    required this.urls,
    required this.onPlay,
  });

  final MediaItem media;
  final StreamUrls urls;
  final void Function(String mediaId, String title) onPlay;

  bool get _isShow => media.isShow;

  @override
  Widget build(BuildContext context) {
    final backdrop = urls.resolvePoster(
      media.backdropPath ?? media.posterPath,
      fallbackId: media.id,
    );
    final seasons = <int>{};
    for (final ep in media.episodes) {
      if (ep.season != null) seasons.add(ep.season!);
    }
    final seasonList = seasons.toList()..sort();
    final overview = media.overview?.trim().isNotEmpty == true
        ? media.overview!
        : 'No overview available.';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(media.title, style: const TextStyle(fontSize: 16)),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop.isNotEmpty)
                    Image.network(backdrop, fit: BoxFit.cover)
                  else
                    const ColoredBox(color: VsTheme.card),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, VsTheme.scaffold],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(label: _isShow ? 'TV Series' : 'Movie'),
                  if (media.voteAverage != null && media.voteAverage! > 0)
                    _Chip(label: '★ ${media.voteAverage!.toStringAsFixed(1)}'),
                  if (_isShow && seasonList.isNotEmpty)
                    _Chip(
                      label: seasonList.length == 1
                          ? '1 Season'
                          : '${seasonList.length} Seasons',
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                overview,
                style: const TextStyle(color: VsTheme.muted, height: 1.4),
              ),
            ),
          ),
          if (!_isShow)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => onPlay(media.id, media.title),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => downloadMedia(
                          context,
                          urls: urls,
                          mediaId: media.id,
                          title: media.title,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.download),
                        label: const Text('Download', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (seasonList.isEmpty)
            SliverList.builder(
              itemCount: media.episodes.length,
              itemBuilder: (context, index) {
                final ep = media.episodes[index];
                return _EpisodeTile(
                  episode: ep,
                  onPlay: () => onPlay(ep.id, '${media.title} · ${ep.label}'),
                  onDownload: () => downloadMedia(
                    context,
                    urls: urls,
                    mediaId: ep.id,
                    title: ep.label,
                  ),
                );
              },
            )
          else
            for (final season in seasonList) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Season $season',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: media.episodes.where((e) => e.season == season).length,
                itemBuilder: (context, index) {
                  final eps = media.episodes.where((e) => e.season == season).toList()
                    ..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
                  final ep = eps[index];
                  return _EpisodeTile(
                    episode: ep,
                    onPlay: () => onPlay(ep.id, '${media.title} · ${ep.label}'),
                    onDownload: () => downloadMedia(
                      context,
                      urls: urls,
                      mediaId: ep.id,
                      title: ep.label,
                    ),
                  );
                },
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: VsTheme.card,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: VsTheme.muted),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.onPlay,
    required this.onDownload,
  });

  final Episode episode;
  final VoidCallback onPlay;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onPlay,
      leading: CircleAvatar(
        backgroundColor: VsTheme.card,
        child: Text(
          '${episode.episode ?? '?'}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(episode.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: episode.season != null && episode.episode != null
          ? Text('S${episode.season}E${episode.episode}')
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Download',
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined, color: VsTheme.muted),
          ),
          const Icon(Icons.play_circle_fill, color: VsTheme.brandRed, size: 30),
        ],
      ),
    );
  }
}
