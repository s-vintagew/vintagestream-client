import 'package:flutter/material.dart';
import 'package:vs_core/vs_core.dart';
import 'package:vs_ui/vs_ui.dart';

import 'media_card.dart';

typedef OpenMedia = void Function(MediaItem item);
typedef OpenSettings = VoidCallback;
typedef OpenNetwork = VoidCallback;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.api,
    required this.onOpenMedia,
    required this.onOpenSettings,
    required this.onOpenNetwork,
  });

  final VintageStreamApi api;
  final OpenMedia onOpenMedia;
  final OpenSettings onOpenSettings;
  final OpenNetwork onOpenNetwork;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Library? _library;
  Object? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final library = await widget.api.fetchLibrary();
      if (!mounted) return;
      setState(() {
        _library = library;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    final searching = _query.trim().isNotEmpty;
    final results = searching && library != null ? library.search(_query) : const <MediaItem>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('VintageStream', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Network stream',
            onPressed: widget.onOpenNetwork,
            icon: const Icon(Icons.podcasts_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(searching ? 64 : 112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search library',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              if (!searching)
                TabBar(
                  controller: _tabs,
                  indicatorColor: VsTheme.brandRed,
                  labelColor: Colors.white,
                  unselectedLabelColor: VsTheme.muted,
                  tabs: const [
                    Tab(text: 'Movies'),
                    Tab(text: 'TV'),
                    Tab(text: 'Marvel'),
                  ],
                ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: VsTheme.brandRed))
          : _error != null
              ? _ErrorPane(message: _error.toString(), onRetry: _load)
              : searching
                  ? _MediaGrid(
                      items: results,
                      urls: widget.api.urls,
                      emptyLabel: 'No matches',
                      showKind: true,
                      onTap: widget.onOpenMedia,
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _MediaGrid(
                          items: library!.movies,
                          urls: widget.api.urls,
                          emptyLabel: 'No movies',
                          onTap: widget.onOpenMedia,
                        ),
                        _MediaGrid(
                          items: library.shows,
                          urls: widget.api.urls,
                          emptyLabel: 'No shows',
                          onTap: widget.onOpenMedia,
                        ),
                        _MarvelPhasesView(
                          items: library.marvel,
                          urls: widget.api.urls,
                          onTap: widget.onOpenMedia,
                        ),
                      ],
                    ),
    );
  }
}

class _MarvelPhasesView extends StatelessWidget {
  const _MarvelPhasesView({
    required this.items,
    required this.urls,
    required this.onTap,
  });

  final List<MediaItem> items;
  final StreamUrls urls;
  final void Function(MediaItem item) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No Marvel titles', style: TextStyle(color: VsTheme.muted)));
    }

    final byPhase = <String, List<MediaItem>>{};
    for (final item in items) {
      final id = (item.marvelPhase == null || item.marvelPhase!.trim().isEmpty)
          ? 'folder'
          : item.marvelPhase!.trim();
      byPhase.putIfAbsent(id, () => <MediaItem>[]).add(item);
    }

    final phaseIds = byPhase.keys.toList()
      ..sort((a, b) {
        final cmp = _marvelPhaseSortKey(a).compareTo(_marvelPhaseSortKey(b));
        if (cmp != 0) return cmp;
        return a.compareTo(b);
      });

    final groups = <({String id, String label, List<MediaItem> items})>[];
    for (final id in phaseIds) {
      final list = List<MediaItem>.from(byPhase[id]!);
      list.sort((a, b) {
        final ao = a.marvelOrder ?? 1 << 30;
        final bo = b.marvelOrder ?? 1 << 30;
        final cmp = ao.compareTo(bo);
        if (cmp != 0) return cmp;
        return a.title.compareTo(b.title);
      });
      groups.add((id: id, label: _marvelPhaseLabel(id), items: list));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == groups.length - 1 ? 0 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: Text(
                  group.label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFBBF24),
                  ),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2 / 3,
                ),
                itemCount: group.items.length,
                itemBuilder: (context, i) {
                  final item = group.items[i];
                  return MediaCard(
                    item: item,
                    posterUrl: urls.resolvePoster(item.posterPath, fallbackId: item.id),
                    showKind: true,
                    onTap: () => onTap(item),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Sort key derived from server phase ids (phase-N first, then named buckets).
int _marvelPhaseSortKey(String id) {
  final match = RegExp(r'^phase-(\d+)$', caseSensitive: false).firstMatch(id);
  if (match != null) return int.parse(match.group(1)!);
  switch (id.toLowerCase()) {
    case 'series':
      return 1000;
    case 'other':
      return 1500;
    case 'folder':
      return 2000;
    default:
      return 3000;
  }
}

String _marvelPhaseLabel(String id) {
  final phase = RegExp(r'^phase-(\d+)$', caseSensitive: false).firstMatch(id);
  if (phase != null) return 'Phase ${phase.group(1)}';
  switch (id.toLowerCase()) {
    case 'series':
      return 'Series';
    case 'other':
      return 'More Marvel';
    case 'folder':
      return 'From the Marvel folder';
    default:
      return id
          .split(RegExp(r'[-_]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.items,
    required this.urls,
    required this.onTap,
    required this.emptyLabel,
    this.showKind = false,
  });

  final List<MediaItem> items;
  final StreamUrls urls;
  final void Function(MediaItem item) onTap;
  final String emptyLabel;
  final bool showKind;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyLabel, style: const TextStyle(color: VsTheme.muted)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 2 / 3,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MediaCard(
          item: item,
          posterUrl: urls.resolvePoster(item.posterPath, fallbackId: item.id),
          showKind: showKind,
          onTap: () => onTap(item),
        );
      },
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: VsTheme.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: VsTheme.muted)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: VsTheme.brandRed),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
