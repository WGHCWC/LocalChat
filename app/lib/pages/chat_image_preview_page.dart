import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
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
    final localPath = attachment.localPath;
    final hasLocalFile = _hasLocalFile(localPath);

    return Scaffold(
      appBar: basicLocalSendAppbar(
        attachment.fileName,
        actions: [
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
              : const _MissingImageState(key: ValueKey('missing-image-state')),
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

class _MissingImageState extends StatelessWidget {
  const _MissingImageState({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            'Image file is not available.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
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
