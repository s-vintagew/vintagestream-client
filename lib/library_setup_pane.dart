import 'package:flutter/material.dart';
import 'package:vs_ui/vs_ui.dart';

/// Shown when no server URL is saved yet. Network stream still works.
class LibrarySetupPane extends StatelessWidget {
  const LibrarySetupPane({
    super.key,
    required this.onOpenSettings,
    required this.onOpenNetwork,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenNetwork;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VintageStream', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Network stream',
            onPressed: onOpenNetwork,
            icon: const Icon(Icons.podcasts_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dns_outlined, size: 48, color: VsTheme.muted),
              const SizedBox(height: 16),
              const Text(
                'Enter your VintageStream server URL to load the library. Use the network icon to open a direct stream URL.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VsTheme.muted, height: 1.4),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onOpenSettings,
                style: FilledButton.styleFrom(backgroundColor: VsTheme.brandRed),
                child: const Text('Set server URL'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
