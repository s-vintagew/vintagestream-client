import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vs_core/vs_core.dart';
import 'package:vs_ui/vs_ui.dart';

class AppUpdate {
  AppUpdate._();

  static Future<({PackageInfo installed, MobileUpdateInfo? remote})> probe(
    String updateRepo,
  ) async {
    final installed = await PackageInfo.fromPlatform();
    final client = GitHubUpdateClient();
    try {
      final remote = await client.fetchLatest(updateRepo);
      return (installed: installed, remote: remote);
    } finally {
      client.close();
    }
  }

  static bool isNewer(MobileUpdateInfo remote, PackageInfo installed) {
    final localCode = int.tryParse(installed.buildNumber) ?? 0;
    return remote.versionCode > localCode;
  }

  /// Startup check: silent when nothing is published or already current.
  static Future<void> checkOnLaunch(
    BuildContext context,
    String updateRepo,
  ) async {
    try {
      final result = await probe(updateRepo);
      final remote = result.remote;
      if (remote == null || !isNewer(remote, result.installed)) return;
      if (!context.mounted) return;
      await offer(context, remote, installed: result.installed);
    } catch (_) {
      // Offline / no GitHub release yet — ignore on launch.
    }
  }

  /// Settings / manual check with user-visible feedback.
  static Future<void> checkManual(
    BuildContext context,
    String updateRepo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await probe(updateRepo);
      if (!context.mounted) return;
      final remote = result.remote;
      if (remote == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No GitHub release published yet'),
            backgroundColor: VsTheme.card,
          ),
        );
        return;
      }
      if (!isNewer(remote, result.installed)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'You’re on the latest build (${result.installed.version}+${result.installed.buildNumber})',
            ),
            backgroundColor: VsTheme.card,
          ),
        );
        return;
      }
      await offer(context, remote, installed: result.installed);
    } catch (err) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Update check failed: $err'),
          backgroundColor: VsTheme.card,
        ),
      );
    }
  }

  static Future<void> offer(
    BuildContext context,
    MobileUpdateInfo remote, {
    required PackageInfo installed,
  }) async {
    final notes = remote.notes.trim().isEmpty ? 'Bug fixes and improvements.' : remote.notes.trim();
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: !remote.mandatory,
      builder: (context) => AlertDialog(
        backgroundColor: VsTheme.card,
        title: Text('Update ${remote.versionName}'),
        content: Text(
          'Installed: ${installed.version}+${installed.buildNumber}\n'
          'Available: ${remote.versionName}+${remote.versionCode}\n\n'
          '$notes\n\n'
          'The APK downloads from GitHub Releases, then Android asks you to install it.',
        ),
        actions: [
          if (!remote.mandatory)
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: VsTheme.brandRed),
            child: const Text('Download & install'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await install(context, remote);
  }

  static Future<void> install(BuildContext context, MobileUpdateInfo remote) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DownloadProgressDialog(
          apkUrl: remote.apkUrl.toString(),
          sha256: remote.sha256,
          onDone: () {
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          },
        );
      },
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({
    required this.apkUrl,
    required this.onDone,
    this.sha256,
  });

  final String apkUrl;
  final String? sha256;
  final VoidCallback onDone;

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  StreamSubscription<OtaEvent>? _sub;
  int _progress = 0;
  String _status = 'Downloading…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      _sub = OtaUpdate()
          .execute(
            widget.apkUrl,
            destinationFilename: 'VintageStream.apk',
            sha256checksum: (widget.sha256 == null || widget.sha256!.isEmpty)
                ? null
                : widget.sha256,
          )
          .listen(
            (event) {
              if (!mounted) return;
              setState(() {
                switch (event.status) {
                  case OtaStatus.DOWNLOADING:
                    _status = 'Downloading…';
                    _progress = int.tryParse(event.value ?? '') ?? _progress;
                  case OtaStatus.INSTALLING:
                    _status = 'Opening installer…';
                    _progress = 100;
                  case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                    _error = 'Install permission was denied';
                  case OtaStatus.CHECKSUM_ERROR:
                    _error = 'Downloaded APK failed checksum verification';
                  case OtaStatus.DOWNLOAD_ERROR:
                    _error = 'Download failed${event.value != null ? ': ${event.value}' : ''}';
                  case OtaStatus.INTERNAL_ERROR:
                    _error = 'Update failed${event.value != null ? ': ${event.value}' : ''}';
                  case OtaStatus.CANCELED:
                    _error = 'Download canceled';
                  default:
                    break;
                }
              });
              if (event.status == OtaStatus.INSTALLING) {
                Future<void>.delayed(const Duration(milliseconds: 600), widget.onDone);
              }
            },
            onError: (Object err) {
              if (!mounted) return;
              setState(() => _error = err.toString());
            },
          );
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VsTheme.card,
      title: Text(_error == null ? 'Downloading update' : 'Update failed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error == null) ...[
            LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress / 100,
              color: VsTheme.brandRed,
              backgroundColor: Colors.white12,
            ),
            const SizedBox(height: 12),
            Text('$_status${_progress > 0 ? ' · $_progress%' : ''}'),
          ] else
            Text(_error!, style: const TextStyle(color: VsTheme.muted, height: 1.35)),
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: widget.onDone,
            child: const Text('Close'),
          ),
      ],
    );
  }
}
