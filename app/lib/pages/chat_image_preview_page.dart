import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uri_content/uri_content.dart';

class ChatImagePreviewPage extends StatefulWidget {
  final ChatAttachment attachment;

  const ChatImagePreviewPage({
    super.key,
    required this.attachment,
  });

  @override
  State<ChatImagePreviewPage> createState() => _ChatImagePreviewPageState();
}

class _ChatImagePreviewPageState extends State<ChatImagePreviewPage> with Refena {
  bool _startingDownload = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureLocalFile();
    });
  }

  Future<void> _ensureLocalFile() async {
    final hasLocalPath = await context.ref.notifier(chatProvider).hasLocalAttachmentFile(widget.attachment);
    if (!mounted || hasLocalPath) {
      return;
    }
    await _startDownload();
  }

  Future<void> _startDownload() async {
    if (_startingDownload) {
      return;
    }
    setState(() {
      _startingDownload = true;
    });
    try {
      await context.ref.notifier(chatProvider).requestAttachmentDownload(widget.attachment);
    } finally {
      if (mounted) {
        setState(() {
          _startingDownload = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = context.watch(
      chatProvider.select(
        (state) => state.messages
            .map((message) => message.attachment)
            .whereType<ChatAttachment>()
            .firstWhere(
              (candidate) => candidate.id == widget.attachment.id,
              orElse: () => widget.attachment,
            ),
      ),
    );
    final session = context.watch(serverProvider.select((state) => state?.session));
    final progressState = context.watch(progressProvider);
    final localPath = attachment.localPath;
    final hasLocalFile = _hasLocalFile(localPath);
    final progress = _activeDownloadProgress(session, progressState, attachment);

    return Scaffold(
      appBar: AppBar(
        title: Text(attachment.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Download',
            onPressed: hasLocalFile ? null : _startDownload,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: hasLocalFile ? () => _shareAttachment(context, attachment) : null,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Open',
            onPressed: hasLocalFile && localPath != null
                ? () async {
                    await openFile(context, attachment.fileType, localPath);
                  }
                : null,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: hasLocalFile && localPath != null
              ? InteractiveViewer(
                  key: const ValueKey('image-viewer'),
                  minScale: 0.5,
                  maxScale: 4,
                  child: _ImageBody(localPath: localPath),
                )
              : _DownloadState(
                  key: const ValueKey('download-state'),
                  pending: _startingDownload,
                  progress: progress,
                  errorText: attachment.downloadError,
                  onDownload: _startDownload,
                ),
        ),
      ),
    );
  }

  bool _hasLocalFile(String? localPath) {
    if (localPath == null) {
      return false;
    }
    if (localPath.startsWith('content://')) {
      return true;
    }
    return File(localPath).existsSync();
  }

  double? _activeDownloadProgress(
    dynamic session,
    dynamic progressState,
    ChatAttachment attachment,
  ) {
    if (session == null || session.sender.fingerprint != attachment.sourceFingerprint) {
      return null;
    }

    final files = session.files.values.toList(growable: false);
    for (final file in files) {
      final candidate = file.file;
      if (candidate.fileName == attachment.fileName && candidate.size == attachment.size) {
        return progressState.getProgress(sessionId: session.sessionId, fileId: candidate.id);
      }
    }
    return null;
  }

  Future<void> _shareAttachment(BuildContext context, ChatAttachment attachment) async {
    final localPath = attachment.localPath;
    if (localPath == null) {
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '${attachment.fileName} (${attachment.size.asReadableFileSize})',
          title: attachment.fileName,
          files: [XFile(localPath, name: attachment.fileName)],
          fileNameOverrides: [attachment.fileName],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        context.showSnackBar(e.toString());
      }
    }
  }
}

class _ImageBody extends StatelessWidget {
  final String localPath;

  const _ImageBody({required this.localPath});

  @override
  Widget build(BuildContext context) {
    if (localPath.startsWith('content://')) {
      return Image(
        image: ResizeImage.resizeIfNeeded(2048, null, _ContentUriImage(Uri.parse(localPath))),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }

    final file = File(localPath);
    return Image.file(
      file,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}

class _DownloadState extends StatelessWidget {
  final Future<void> Function() onDownload;
  final bool pending;
  final double? progress;
  final String? errorText;

  const _DownloadState({
    super.key,
    required this.onDownload,
    required this.pending,
    required this.progress,
    required this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusText = pending
        ? 'Downloading...'
        : progress != null
        ? 'Downloading ${(progress! * 100).toStringAsFixed(0)}%'
        : 'Waiting for download';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: pending ? null : progress),
          const SizedBox(height: 16),
          Text(statusText),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              errorText!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            Text('${(progress! * 100).toStringAsFixed(0)}%', style: TextStyle(color: scheme.outline)),
          ],
        ],
      ),
    );
  }
}

class _ContentUriImage extends ImageProvider<Uri> {
  final Uri uri;

  _ContentUriImage(this.uri);

  @override
  Future<Uri> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<Uri>(uri);
  }

  @override
  ImageStreamCompleter loadImage(Uri key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
    );
  }

  Future<Codec> _loadAsync(Uri key, ImageDecoderCallback decode) async {
    final bytes = await UriContent().from(key);
    return decode(await ImmutableBuffer.fromUint8List(bytes));
  }
}
