import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vs_core/vs_core.dart';
import 'package:vs_ui/vs_ui.dart';

typedef PlayNetworkStream = void Function(String url);

class NetworkStreamScreen extends StatefulWidget {
  const NetworkStreamScreen({
    super.key,
    required this.settings,
    required this.onPlay,
  });

  final AppSettings settings;
  final PlayNetworkStream onPlay;

  @override
  State<NetworkStreamScreen> createState() => _NetworkStreamScreenState();
}

class _NetworkStreamScreenState extends State<NetworkStreamScreen> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Paste a stream URL first.';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a full URL (http, https, rtsp, …).';
    }
    final scheme = uri.scheme.toLowerCase();
    const allowed = {
      'http',
      'https',
      'rtsp',
      'rtsps',
      'rtmp',
      'rtmps',
      'udp',
      'tcp',
      'mms',
      'mmsh',
    };
    if (!allowed.contains(scheme)) {
      return 'Unsupported scheme: $scheme';
    }
    return null;
  }

  Future<void> _play([String? override]) async {
    final raw = (override ?? _controller.text).trim();
    final problem = _validate(raw);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _controller.text = raw;
    });
    await widget.settings.rememberNetworkStream(raw);
    if (!mounted) return;
    setState(() {});
    widget.onPlay(raw);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  Future<void> _clearRecent() async {
    await widget.settings.clearRecentNetworkStreams();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final recent = widget.settings.recentNetworkStreams;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text('Network stream', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Open any direct media URL with libmpv — same idea as mpv https://…',
          style: TextStyle(color: VsTheme.muted, height: 1.35),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          maxLines: 3,
          minLines: 1,
          onSubmitted: (_) => _play(),
          decoration: const InputDecoration(
            hintText: 'https://example.com/video.mkv',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: VsTheme.brandRed)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _play(),
                style: FilledButton.styleFrom(backgroundColor: VsTheme.brandRed),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text('Recent', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            if (recent.isNotEmpty)
              TextButton(
                onPressed: _clearRecent,
                child: const Text('Clear'),
              ),
          ],
        ),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No recent streams yet.', style: TextStyle(color: VsTheme.muted)),
          )
        else
          ...recent.map(
            (url) => Card(
              color: VsTheme.card,
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: const Icon(Icons.play_circle_outline, color: VsTheme.brandRed),
                title: Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                onTap: () => _play(url),
                trailing: IconButton(
                  tooltip: 'Use this URL',
                  icon: const Icon(Icons.north_west, size: 18),
                  onPressed: () {
                    setState(() {
                      _controller.text = url;
                      _error = null;
                    });
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
