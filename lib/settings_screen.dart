import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vs_core/vs_core.dart';
import 'package:vs_ui/vs_ui.dart';

import 'app_update.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onServerSaved,
  });

  final AppSettings settings;
  final VoidCallback onServerSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _serverController;
  late final TextEditingController _repoController;
  late bool _edgeGestures;
  String _versionLabel = '';
  var _checkingUpdate = false;
  var _savingServer = false;
  String? _serverMessage;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.settings.baseUrl);
    _repoController = TextEditingController(text: widget.settings.updateRepo);
    _edgeGestures = widget.settings.playerEdgeGestures;
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _versionLabel = '${info.version}+${info.buildNumber}');
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    _repoController.dispose();
    super.dispose();
  }

  Future<void> _saveServerUrl() async {
    final raw = _serverController.text.trim();
    if (raw.isEmpty) {
      setState(() => _serverMessage = 'Enter a server URL first.');
      return;
    }
    setState(() {
      _savingServer = true;
      _serverMessage = null;
    });
    try {
      await widget.settings.setBaseUrl(raw);
      if (!mounted) return;
      widget.onServerSaved();
    } finally {
      if (mounted) setState(() => _savingServer = false);
    }
  }

  Future<void> _toggleEdgeGestures(bool value) async {
    setState(() => _edgeGestures = value);
    await widget.settings.setPlayerEdgeGestures(value);
  }

  Future<void> _checkUpdate() async {
    await widget.settings.setUpdateRepo(_repoController.text.trim());
    if (!mounted) return;
    setState(() => _checkingUpdate = true);
    try {
      await AppUpdate.checkManual(context, widget.settings.updateRepo);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Server URL', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _serverController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: AppSettings.serverUrlHint,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Required. Use your public host or a LAN address. Playback always requests the original file (no server transcode).',
            style: TextStyle(color: VsTheme.muted, height: 1.35),
          ),
          if (_serverMessage != null) ...[
            const SizedBox(height: 8),
            Text(_serverMessage!, style: const TextStyle(color: VsTheme.brandRed)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _savingServer ? null : _saveServerUrl,
            style: FilledButton.styleFrom(backgroundColor: VsTheme.brandRed),
            child: Text(_savingServer ? 'Saving…' : 'Save Server URL'),
          ),
          const SizedBox(height: 28),
          const Text('Player', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Brightness & volume swipes'),
            subtitle: const Text(
              'Android only. Left side vertical swipe = brightness, right side = volume. Off by default.',
              style: TextStyle(color: VsTheme.muted, height: 1.35),
            ),
            value: _edgeGestures,
            activeThumbColor: Colors.white,
            activeTrackColor: VsTheme.brandRed,
            onChanged: _toggleEdgeGestures,
          ),
          const SizedBox(height: 20),
          const Text('Update repo (GitHub)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _repoController,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: AppSettings.defaultUpdateRepo,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Public owner/name whose Releases host the APK. Tag releases as 0.2.0+2 and attach the APK asset.',
            style: TextStyle(color: VsTheme.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await widget.settings.setUpdateRepo(_repoController.text.trim());
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Update repo saved')),
              );
            },
            child: const Text('Save update repo'),
          ),
          const SizedBox(height: 24),
          const Text('App updates', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            _versionLabel.isEmpty ? 'Version …' : 'Installed $_versionLabel',
            style: const TextStyle(color: VsTheme.muted),
          ),
          const SizedBox(height: 8),
          const Text(
            'Updates come from GitHub Releases. Friends only need one install; later builds arrive in-app.',
            style: TextStyle(color: VsTheme.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _checkingUpdate ? null : _checkUpdate,
            icon: _checkingUpdate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: VsTheme.brandRed),
                  )
                : const Icon(Icons.system_update),
            label: Text(_checkingUpdate ? 'Checking…' : 'Check for updates'),
          ),
        ],
      ),
    );
  }
}
