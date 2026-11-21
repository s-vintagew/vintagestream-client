import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:vs_core/vs_core.dart';

class PlayerScreen extends StatefulWidget {
  /// Library / server title playback.
  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.title,
    required this.api,
    required this.progress,
    this.settings,
    this.enableEdgeGestures = false,
  }) : streamUrl = null;

  /// Direct network URL playback (mpv-style open).
  const PlayerScreen.network({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.progress,
    this.settings,
    this.enableEdgeGestures = false,
  })  : mediaId = null,
        api = null;

  final String? mediaId;
  final String? streamUrl;
  final String title;
  final VintageStreamApi? api;
  final WatchProgressStore progress;
  final AppSettings? settings;

  /// Left vertical swipe = brightness, right = volume (Android).
  final bool enableEdgeGestures;

  bool get isNetworkStream => streamUrl != null && streamUrl!.isNotEmpty;

  String get progressKey => isNetworkStream ? 'net:${streamUrl!}' : mediaId!;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _PanGesture { none, undecided, seek, brightness, volume }

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _videoKey = GlobalKey<VideoState>();
  StreamSubscription<Duration>? _posSub;
  Timer? _hideTimer;
  bool _showUi = true;
  bool _ready = false;
  bool _landscapeLocked = true;
  /// Blocks taps/gestures until the user unlocks (accidental-touch guard).
  bool _controlsLocked = false;
  bool _showUnlockHint = false;
  String? _error;
  double _rate = 1.0;
  List<SubtitleTrackInfo> _sidecarSubs = const [];
  String? _activeSidecar;
  double _subtitleSize = AppSettings.defaultSubtitleSize;
  double _subtitleBottom = AppSettings.defaultSubtitleBottom;
  String _videoFitMode = AppSettings.defaultVideoFit;

  _PanGesture _panGesture = _PanGesture.none;
  double _gestureLevel = 0;
  double _gestureStartLevel = 0;
  double _gestureAccumDx = 0;
  double _gestureAccumDy = 0;
  Offset _panOrigin = Offset.zero;
  Duration _seekStart = Duration.zero;
  Duration _seekTarget = Duration.zero;
  Duration _seekDelta = Duration.zero;

  static const _rates = [0.75, 1.0, 1.25, 1.5, 2.0];
  /// Full-width horizontal drag covers this much seek time (mpv-style scrub).
  static const _seekWindow = Duration(seconds: 90);
  static const _axisLockPx = 12.0;
  static const _landscapeOnly = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  bool get _edgeGesturesActive =>
      widget.enableEdgeGestures && !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    final settings = widget.settings;
    if (settings != null) {
      _subtitleSize = settings.subtitleFontSize;
      _subtitleBottom = settings.subtitleBottomPadding;
      _videoFitMode = settings.videoFitMode;
    }
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'VintageStream',
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    _controller = VideoController(_player);
    if (_edgeGesturesActive) {
      VolumeController.instance.showSystemUI = false;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(_landscapeOnly);
    _start();
  }

  Future<void> _toggleOrientationLock() async {
    if (_landscapeLocked) {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      await SystemChrome.setPreferredOrientations(_landscapeOnly);
    }
    if (!mounted) return;
    setState(() => _landscapeLocked = !_landscapeLocked);
    _bumpUi();
  }

  Future<void> _start() async {
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('hwdec', 'auto');
        await platform.setProperty('keep-open', 'yes');
      }

      final String url;
      if (widget.isNetworkStream) {
        url = widget.streamUrl!;
      } else {
        final api = widget.api;
        final mediaId = widget.mediaId;
        if (api == null || mediaId == null) {
          throw StateError('Library playback needs api + mediaId');
        }
        try {
          final meta = await api.fetchMetadata(mediaId);
          _sidecarSubs = meta.subtitles.where((s) => s.isExternal).toList();
        } catch (_) {
          // Metadata is optional for playback.
        }
        url = api.urls.originalStream(mediaId).toString();
      }

      final progressKey = widget.progressKey;
      final resume = widget.progress.getPosition(progressKey);
      await _player.open(Media(url), play: true);
      if (resume != null && resume.inSeconds > 5) {
        await _player.seek(resume);
      }

      _posSub = _player.stream.position.listen((pos) {
        final duration = _player.state.duration;
        unawaited(widget.progress.savePosition(progressKey, pos, duration));
      });

      if (!mounted) return;
      setState(() => _ready = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applySubtitlePadding();
      });
      _bumpUi();
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    }
  }

  void _bumpUi() {
    if (_controlsLocked) {
      _showUnlockTemporarily();
      return;
    }
    setState(() => _showUi = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_player.state.playing) setState(() => _showUi = false);
    });
  }

  void _showUnlockTemporarily() {
    setState(() => _showUnlockHint = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_controlsLocked) return;
      setState(() => _showUnlockHint = false);
    });
  }

  void _lockControls() {
    _hideTimer?.cancel();
    setState(() {
      _controlsLocked = true;
      _showUi = false;
      _showUnlockHint = true;
      _panGesture = _PanGesture.none;
    });
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_controlsLocked) return;
      setState(() => _showUnlockHint = false);
    });
  }

  void _unlockControls() {
    setState(() {
      _controlsLocked = false;
      _showUnlockHint = false;
      _showUi = true;
    });
    _bumpUi();
  }

  Future<void> _skip(int seconds) async {
    final next = _player.state.position + Duration(seconds: seconds);
    final clamped = next < Duration.zero ? Duration.zero : next;
    await _player.seek(clamped);
    _bumpUi();
  }

  Future<void> _setRate(double rate) async {
    await _player.setRate(rate);
    setState(() => _rate = rate);
  }

  void _onPanStart(DragStartDetails details) {
    if (_controlsLocked) {
      _panGesture = _PanGesture.none;
      return;
    }
    _panGesture = _PanGesture.undecided;
    _panOrigin = details.localPosition;
    _gestureAccumDx = 0;
    _gestureAccumDy = 0;
    _seekStart = _player.state.position;
    _seekTarget = _seekStart;
    _seekDelta = Duration.zero;
  }

  Future<void> _lockVerticalGesture(bool leftSide) async {
    try {
      if (leftSide) {
        final brightness = await ScreenBrightness.instance.application;
        _gestureStartLevel = brightness.clamp(0.0, 1.0);
        _panGesture = _PanGesture.brightness;
      } else {
        final volume = await VolumeController.instance.getVolume();
        _gestureStartLevel = volume.clamp(0.0, 1.0);
        _panGesture = _PanGesture.volume;
      }
      _gestureLevel = _gestureStartLevel;
    } catch (_) {
      _panGesture = _PanGesture.none;
    }
    if (mounted) setState(() {});
  }

  Future<void> _onPanUpdate(DragUpdateDetails details) async {
    if (_controlsLocked || _panGesture == _PanGesture.none) return;

    _gestureAccumDx += details.delta.dx;
    _gestureAccumDy += details.delta.dy;

    final size = MediaQuery.sizeOf(context);

    if (_panGesture == _PanGesture.undecided) {
      final adx = _gestureAccumDx.abs();
      final ady = _gestureAccumDy.abs();
      if (adx < _axisLockPx && ady < _axisLockPx) return;

      if (adx >= ady) {
        _panGesture = _PanGesture.seek;
        setState(() {});
      } else if (_edgeGesturesActive) {
        await _lockVerticalGesture(_panOrigin.dx < size.width / 2);
        if (!mounted) return;
      } else {
        // Vertical without edge gestures: ignore until release.
        return;
      }
    }

    if (_panGesture == _PanGesture.seek) {
      final duration = _player.state.duration;
      final windowMs = duration.inMilliseconds > 0
          ? (_seekWindow.inMilliseconds < duration.inMilliseconds
              ? _seekWindow.inMilliseconds
              : duration.inMilliseconds)
          : _seekWindow.inMilliseconds;
      final deltaMs = ((_gestureAccumDx / size.width) * windowMs).round();
      final startMs = _seekStart.inMilliseconds;
      final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : startMs + windowMs;
      final targetMs = (startMs + deltaMs).clamp(0, maxMs);
      _seekDelta = Duration(milliseconds: deltaMs);
      _seekTarget = Duration(milliseconds: targetMs);
      if (mounted) setState(() {});
      return;
    }

    if (_panGesture == _PanGesture.brightness || _panGesture == _PanGesture.volume) {
      final delta = -_gestureAccumDy / (size.height * 0.5);
      final next = (_gestureStartLevel + delta).clamp(0.0, 1.0);
      _gestureLevel = next;
      try {
        if (_panGesture == _PanGesture.brightness) {
          await ScreenBrightness.instance.setApplicationScreenBrightness(next);
        } else {
          await VolumeController.instance.setVolume(next);
        }
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_panGesture == _PanGesture.seek) {
      await _player.seek(_seekTarget);
      _bumpUi();
    }
    if (_panGesture != _PanGesture.none) {
      setState(() => _panGesture = _PanGesture.none);
    }
  }

  Future<void> _pickAudio() async {
    final tracks = _player.state.tracks.audio;
    if (tracks.isEmpty) return;
    final selected = await showModalBottomSheet<AudioTrack>(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      builder: (context) => ListView(
        children: [
          const ListTile(title: Text('Audio track', style: TextStyle(fontWeight: FontWeight.w700))),
          ...tracks.map(
            (t) => ListTile(
              title: Text(_audioLabel(t)),
              trailing: identical(_player.state.track.audio, t)
                  ? const Icon(Icons.check, color: Color(0xFFE50914))
                  : null,
              onTap: () => Navigator.pop(context, t),
            ),
          ),
        ],
      ),
    );
    if (selected != null) await _player.setAudioTrack(selected);
  }

  EdgeInsets get _subtitlePadding => EdgeInsets.fromLTRB(16, 0, 16, _subtitleBottom);

  BoxFit get _videoFit {
    switch (_videoFitMode) {
      case AppSettings.videoFitCrop:
        return BoxFit.cover;
      case AppSettings.videoFitStretch:
        return BoxFit.fill;
      case AppSettings.videoFitFit:
      default:
        return BoxFit.contain;
    }
  }

  IconData get _videoFitIcon {
    switch (_videoFitMode) {
      case AppSettings.videoFitCrop:
        return Icons.crop;
      case AppSettings.videoFitStretch:
        return Icons.open_in_full;
      case AppSettings.videoFitFit:
      default:
        return Icons.fit_screen;
    }
  }

  String get _videoFitLabel {
    switch (_videoFitMode) {
      case AppSettings.videoFitCrop:
        return 'Crop';
      case AppSettings.videoFitStretch:
        return 'Stretch';
      case AppSettings.videoFitFit:
      default:
        return 'Fit screen';
    }
  }

  SubtitleViewConfiguration get _subtitleConfig => SubtitleViewConfiguration(
        style: TextStyle(
          height: 1.4,
          fontSize: _subtitleSize,
          letterSpacing: 0,
          wordSpacing: 0,
          color: const Color(0xffffffff),
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0xCC000000)),
            Shadow(offset: Offset(1, 1), blurRadius: 2, color: Color(0x99000000)),
            Shadow(offset: Offset(-1, 0), blurRadius: 2, color: Color(0x66000000)),
          ],
        ),
        padding: _subtitlePadding,
      );

  void _applySubtitlePadding() {
    _videoKey.currentState?.setSubtitleViewPadding(
      _subtitlePadding,
      duration: Duration.zero,
    );
  }

  Future<void> _setSubtitleSize(double value) async {
    final clamped = value.clamp(AppSettings.minSubtitleSize, AppSettings.maxSubtitleSize);
    setState(() => _subtitleSize = clamped);
    await widget.settings?.setSubtitleFontSize(clamped);
  }

  Future<void> _setSubtitleBottom(double value) async {
    final clamped =
        value.clamp(AppSettings.minSubtitleBottom, AppSettings.maxSubtitleBottom);
    setState(() => _subtitleBottom = clamped);
    // media_kit caches subtitle padding in SubtitleViewState; config rebuild alone
    // does not move text — must call setSubtitleViewPadding.
    _applySubtitlePadding();
    await widget.settings?.setSubtitleBottomPadding(clamped);
  }

  Future<void> _setVideoFitMode(String mode) async {
    setState(() => _videoFitMode = mode);
    await widget.settings?.setVideoFitMode(mode);
    _bumpUi();
  }

  Future<void> _pickVideoFit() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Video size', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final mode in [
              AppSettings.videoFitFit,
              AppSettings.videoFitCrop,
              AppSettings.videoFitStretch,
            ])
              ListTile(
                leading: Icon(
                  mode == AppSettings.videoFitCrop
                      ? Icons.crop
                      : mode == AppSettings.videoFitStretch
                          ? Icons.open_in_full
                          : Icons.fit_screen,
                ),
                title: Text(
                  mode == AppSettings.videoFitCrop
                      ? 'Crop'
                      : mode == AppSettings.videoFitStretch
                          ? 'Stretch'
                          : 'Fit screen',
                ),
                subtitle: Text(
                  mode == AppSettings.videoFitCrop
                      ? 'Fill the screen; edges may be cut off'
                      : mode == AppSettings.videoFitStretch
                          ? 'Fill the screen; may distort aspect'
                          : 'Show the whole frame; may letterbox',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: _videoFitMode == mode
                    ? const Icon(Icons.check, color: Color(0xFFE50914))
                    : null,
                onTap: () => Navigator.pop(context, mode),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await _setVideoFitMode(selected);
  }

  Future<void> _applySubtitleChoice(_SubChoice selected) async {
    if (selected.off) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      setState(() => _activeSidecar = null);
      return;
    }
    if (selected.embedded != null) {
      await _player.setSubtitleTrack(selected.embedded!);
      setState(() => _activeSidecar = null);
      return;
    }
    if (selected.sidecar != null) {
      final api = widget.api;
      final mediaId = widget.mediaId;
      if (api == null || mediaId == null) return;
      final uri = api.urls.subtitleFile(mediaId, selected.sidecar!.index).toString();
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(uri, title: selected.sidecar!.label),
      );
      setState(() => _activeSidecar = selected.sidecar!.index.toString());
    }
  }

  Future<void> _pickSubtitle() async {
    final embedded = _player.state.tracks.subtitle;
    final selected = await showModalBottomSheet<_SubChoice>(
      context: context,
      backgroundColor: const Color(0xFF16161A),
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      title: Text(
                        'Subtitles',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        'Size  ${_subtitleSize.round()}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    Slider(
                      value: _subtitleSize,
                      min: AppSettings.minSubtitleSize,
                      max: AppSettings.maxSubtitleSize,
                      divisions: (AppSettings.maxSubtitleSize - AppSettings.minSubtitleSize)
                          .round(),
                      activeColor: const Color(0xFFE50914),
                      inactiveColor: Colors.white24,
                      onChanged: (value) {
                        setSheetState(() => _subtitleSize = value);
                        unawaited(_setSubtitleSize(value));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Position  ${_subtitleBottom.round()}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    Slider(
                      value: _subtitleBottom,
                      min: AppSettings.minSubtitleBottom,
                      max: AppSettings.maxSubtitleBottom,
                      divisions:
                          ((AppSettings.maxSubtitleBottom - AppSettings.minSubtitleBottom) / 4)
                              .round(),
                      activeColor: const Color(0xFFE50914),
                      inactiveColor: Colors.white24,
                      onChanged: (value) {
                        setSheetState(() => _subtitleBottom = value);
                        unawaited(_setSubtitleBottom(value));
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Higher position moves subtitles up from the bottom edge.',
                        style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Off'),
                      trailing: _player.state.track.subtitle.id == 'no' &&
                              _activeSidecar == null
                          ? const Icon(Icons.check, color: Color(0xFFE50914))
                          : null,
                      onTap: () => Navigator.pop(context, const _SubChoice.off()),
                    ),
                    ...embedded.map(
                      (t) => ListTile(
                        title: Text(_subLabel(t)),
                        trailing: identical(_player.state.track.subtitle, t) &&
                                _activeSidecar == null
                            ? const Icon(Icons.check, color: Color(0xFFE50914))
                            : null,
                        onTap: () => Navigator.pop(context, _SubChoice.embedded(t)),
                      ),
                    ),
                    ..._sidecarSubs.map(
                      (t) => ListTile(
                        title: Text('File · ${t.label}'),
                        trailing: _activeSidecar == t.index.toString()
                            ? const Icon(Icons.check, color: Color(0xFFE50914))
                            : null,
                        onTap: () => Navigator.pop(context, _SubChoice.sidecar(t)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (selected != null) await _applySubtitleChoice(selected);
  }

  String _audioLabel(AudioTrack t) {
    final parts = <String>[
      if (t.language != null && t.language!.isNotEmpty) t.language!,
      if (t.title != null && t.title!.isNotEmpty) t.title!,
      if (t.channels != null) '${t.channels}ch',
    ];
    return parts.isEmpty ? 'Audio ${t.id}' : parts.join(' · ');
  }

  String _subLabel(SubtitleTrack t) {
    final parts = <String>[
      if (t.language != null && t.language!.isNotEmpty) t.language!,
      if (t.title != null && t.title!.isNotEmpty) t.title!,
    ];
    return parts.isEmpty ? 'Subtitle ${t.id}' : parts.join(' · ');
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _posSub?.cancel();
    final pos = _player.state.position;
    final duration = _player.state.duration;
    unawaited(widget.progress.savePosition(widget.progressKey, pos, duration));
    if (_edgeGesturesActive) {
      unawaited(ScreenBrightness.instance.resetApplicationScreenBrightness());
    }
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _bumpUi,
              onDoubleTapDown: (details) {
                if (_controlsLocked) {
                  _showUnlockTemporarily();
                  return;
                }
                if (_panGesture != _PanGesture.none && _panGesture != _PanGesture.undecided) {
                  return;
                }
                final width = MediaQuery.sizeOf(context).width;
                if (details.localPosition.dx < width / 3) {
                  _skip(-10);
                } else if (details.localPosition.dx > width * 2 / 3) {
                  _skip(10);
                } else {
                  _player.playOrPause();
                  _bumpUi();
                }
              },
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onPanCancel: () {
                if (_panGesture != _PanGesture.none) {
                  setState(() => _panGesture = _PanGesture.none);
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Video(
                    key: _videoKey,
                    controller: _controller,
                    controls: NoVideoControls,
                    fit: _videoFit,
                    subtitleViewConfiguration: _subtitleConfig,
                  ),
                  if (!_ready)
                    const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))),
                  if (!_controlsLocked &&
                      (_panGesture == _PanGesture.seek ||
                          _panGesture == _PanGesture.brightness ||
                          _panGesture == _PanGesture.volume))
                    _buildGestureHud(),
                  if (_showUi && !_controlsLocked) _buildOverlay(),
                  if (_controlsLocked && _showUnlockHint) _buildUnlockHint(),
                ],
              ),
            ),
    );
  }

  Widget _buildUnlockHint() {
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Material(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(28),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: _unlockControls,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_open, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Unlock',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGestureHud() {
    if (_panGesture == _PanGesture.seek) {
      final sign = _seekDelta.isNegative ? '-' : '+';
      final absDelta = _seekDelta.abs();
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _seekDelta.isNegative ? Icons.fast_rewind : Icons.fast_forward,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$sign${_fmt(absDelta)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _fmt(_seekTarget),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final isBrightness = _panGesture == _PanGesture.brightness;
    final pct = (_gestureLevel * 100).round();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBrightness
                  ? (pct < 30 ? Icons.brightness_low : Icons.brightness_high)
                  : (pct == 0 ? Icons.volume_off : Icons.volume_up),
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: _gestureLevel,
                backgroundColor: Colors.white24,
                color: const Color(0xFFE50914),
              ),
            ),
            const SizedBox(width: 12),
            Text('$pct%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _player.state.playing,
      builder: (context, playingSnap) {
        return StreamBuilder<Duration>(
          stream: _player.stream.position,
          initialData: _player.state.position,
          builder: (context, posSnap) {
            return StreamBuilder<Duration>(
              stream: _player.stream.duration,
              initialData: _player.state.duration,
              builder: (context, durSnap) {
                final playing = playingSnap.data ?? false;
                final pos = posSnap.data ?? Duration.zero;
                final dur = durSnap.data ?? Duration.zero;
                final maxMs = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
                final posMs = pos.inMilliseconds.toDouble();
                final sliderValue = posMs < 0 ? 0.0 : (posMs > maxMs ? maxMs : posMs);
                return SafeArea(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                          ),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: _landscapeLocked ? 'Unlock rotation' : 'Lock landscape',
                            onPressed: _toggleOrientationLock,
                            icon: Icon(
                              _landscapeLocked ? Icons.screen_lock_rotation : Icons.screen_rotation,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Audio',
                            onPressed: _pickAudio,
                            icon: const Icon(Icons.audiotrack, color: Colors.white),
                          ),
                          IconButton(
                            tooltip: 'Subtitles',
                            onPressed: _pickSubtitle,
                            icon: const Icon(Icons.subtitles, color: Colors.white),
                          ),
                          PopupMenuButton<double>(
                            tooltip: 'Speed',
                            initialValue: _rate,
                            onSelected: _setRate,
                            itemBuilder: (context) => _rates
                                .map((r) => PopupMenuItem(value: r, child: Text('${r}x')))
                                .toList(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('${_rate}x', style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 36,
                            onPressed: () => _skip(-10),
                            icon: const Icon(Icons.replay_10, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 56,
                            onPressed: () {
                              _player.playOrPause();
                              _bumpUi();
                            },
                            icon: Icon(
                              playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 36,
                            onPressed: () => _skip(10),
                            icon: const Icon(Icons.forward_10, color: Colors.white),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Lock controls',
                              onPressed: _lockControls,
                              icon: const Icon(Icons.lock_outline, color: Colors.white),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Video size · $_videoFitLabel',
                              onPressed: _pickVideoFit,
                              icon: Icon(_videoFitIcon, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Expanded(
                              child: Slider(
                                value: sliderValue,
                                max: maxMs,
                                activeColor: const Color(0xFFE50914),
                                inactiveColor: Colors.white24,
                                onChanged: (value) {
                                  _player.seek(Duration(milliseconds: value.round()));
                                  _bumpUi();
                                },
                              ),
                            ),
                            Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

class _SubChoice {
  const _SubChoice.off()
      : off = true,
        embedded = null,
        sidecar = null;
  const _SubChoice.embedded(this.embedded)
      : off = false,
        sidecar = null;
  const _SubChoice.sidecar(this.sidecar)
      : off = false,
        embedded = null;

  final bool off;
  final SubtitleTrack? embedded;
  final SubtitleTrackInfo? sidecar;
}
