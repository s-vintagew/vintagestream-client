import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vs_catalog/vs_catalog.dart';
import 'package:vs_core/vs_core.dart';
import 'package:vs_player/vs_player.dart';
import 'package:vs_ui/vs_ui.dart';

import 'app_update.dart';
import 'library_setup_pane.dart';
import 'settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final settings = await AppSettings.open();
  final progress = await WatchProgressStore.open();
  runApp(VintageStreamApp(settings: settings, progress: progress));
}

class VintageStreamApp extends StatefulWidget {
  const VintageStreamApp({
    super.key,
    required this.settings,
    required this.progress,
  });

  final AppSettings settings;
  final WatchProgressStore progress;

  @override
  State<VintageStreamApp> createState() => _VintageStreamAppState();
}

class _VintageStreamAppState extends State<VintageStreamApp> {
  VintageStreamApi? _api;
  final _navKey = GlobalKey<NavigatorState>();
  var _launchCheckStarted = false;

  @override
  void initState() {
    super.initState();
    _syncApiFromSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCheckLaunchUpdate());
  }

  void _syncApiFromSettings() {
    _api?.close();
    if (widget.settings.hasServerUrl) {
      _api = VintageStreamApi(baseUrl: widget.settings.baseUrl);
    } else {
      _api = null;
    }
  }

  void _rebuildApi() {
    setState(_syncApiFromSettings);
  }

  void _maybeCheckLaunchUpdate() {
    if (_launchCheckStarted) return;
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    _launchCheckStarted = true;
    AppUpdate.checkOnLaunch(ctx, widget.settings.updateRepo);
  }

  Future<void> _openSettings() async {
    final nav = _navKey.currentState;
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          onServerSaved: () {
            _rebuildApi();
            nav.popUntil((route) => route.isFirst);
          },
        ),
      ),
    );
    // Gesture toggle may have changed without a server save.
    if (mounted) setState(() {});
  }

  void _openNetwork() {
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Network stream', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          body: NetworkStreamScreen(
            settings: widget.settings,
            onPlay: _playNetwork,
          ),
        ),
      ),
    );
  }

  void _play(String mediaId, String title) {
    final api = _api;
    if (api == null) return;
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          mediaId: mediaId,
          title: title,
          api: api,
          progress: widget.progress,
          settings: widget.settings,
          enableEdgeGestures: widget.settings.playerEdgeGestures,
        ),
      ),
    );
  }

  void _playNetwork(String url) {
    final host = Uri.tryParse(url)?.host;
    final title = (host != null && host.isNotEmpty) ? host : 'Network stream';
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen.network(
          streamUrl: url,
          title: title,
          progress: widget.progress,
          settings: widget.settings,
          enableEdgeGestures: widget.settings.playerEdgeGestures,
        ),
      ),
    );
  }

  void _openMedia(MediaItem media) {
    final api = _api;
    if (api == null) return;
    _navKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ShowDetailsScreen(
          media: media,
          urls: api.urls,
          onPlay: _play,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    return MaterialApp(
      title: 'VintageStream',
      debugShowCheckedModeBanner: false,
      theme: VsTheme.dark(),
      navigatorKey: _navKey,
      home: api == null
          ? LibrarySetupPane(
              onOpenSettings: _openSettings,
              onOpenNetwork: _openNetwork,
            )
          : LibraryScreen(
              key: ValueKey(api.urls.baseUrl),
              api: api,
              onOpenMedia: _openMedia,
              onOpenSettings: _openSettings,
              onOpenNetwork: _openNetwork,
            ),
    );
  }
}
