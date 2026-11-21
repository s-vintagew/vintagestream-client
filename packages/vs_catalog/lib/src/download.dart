import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vs_core/vs_core.dart';
import 'package:vs_ui/vs_ui.dart';

Future<void> downloadMedia(
  BuildContext context, {
  required StreamUrls urls,
  required String mediaId,
  String? title,
}) async {
  final uri = urls.originalDownload(mediaId);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (ok) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          title == null || title.isEmpty
              ? 'Download started in your browser'
              : 'Downloading “$title”…',
        ),
        backgroundColor: VsTheme.card,
      ),
    );
  } else {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not start download'),
        backgroundColor: VsTheme.card,
      ),
    );
  }
}
