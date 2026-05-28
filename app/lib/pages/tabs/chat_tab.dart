import 'dart:async';
import 'dart:io';

import 'package:common/model/file_type.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/chat_image_preview_page.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:share_plus/share_plus.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> with Refena {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ensureRef((ref) async {
      await ref.notifier(chatProvider).initialize();
      await ref.notifier(chatProvider).syncOnlineMembers();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _clearMessageSelection() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch(chatProvider);
    final myFingerprint = context.watch(
      deviceFullInfoProvider.select((device) => device.fingerprint),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chatroom'),
            Text(
              '${chat.members.length} members',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (chat.syncing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          PopupMenuButton<_ChatMenuAction>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) async {
              switch (action) {
                case _ChatMenuAction.sync:
                  await context.ref.notifier(chatProvider).syncOnlineMembers();
                  break;
                case _ChatMenuAction.members:
                  if (!context.mounted) {
                    return;
                  }
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => _MemberManagementSheet(
                      key: const ValueKey('chat-member-management-sheet'),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ChatMenuAction.members,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.group),
                  title: Text('User management'),
                ),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.sync,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sync),
                  title: Text('Sync now'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (chat.errorMessage != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                chat.errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          Expanded(
            child: _DesktopChatDropTarget(
              onSendFiles: (files) => context.ref.notifier(chatProvider).sendAttachments(files),
              child: chat.messages.isEmpty
                  ? _EmptyConversation(
                      hasMembers: chat.members.isNotEmpty,
                      onManageUsers: () async {
                        await showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => _MemberManagementSheet(
                            key: const ValueKey('chat-member-management-sheet'),
                          ),
                        );
                      },
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _clearMessageSelection,
                      child: NotificationListener<ScrollStartNotification>(
                        onNotification: (_) {
                          _clearMessageSelection();
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                          itemCount: chat.messages.length,
                          itemBuilder: (context, index) {
                            final message = chat.messages[index];
                            final isMine = message.senderFingerprint == myFingerprint;
                            return _MessageBubble(
                              message: message,
                              isMine: isMine,
                              onClearSelection: _clearMessageSelection,
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
          _Composer(
            controller: _controller,
            onSendText: (text) => context.ref.notifier(chatProvider).sendText(text),
            onSendFiles: (files) => context.ref.notifier(chatProvider).sendAttachments(files),
          ),
        ],
      ),
    );
  }
}

class _DesktopChatDropTarget extends StatefulWidget {
  final Widget child;
  final Future<void> Function(List<CrossFile> files) onSendFiles;

  const _DesktopChatDropTarget({
    required this.child,
    required this.onSendFiles,
  });

  @override
  State<_DesktopChatDropTarget> createState() => _DesktopChatDropTargetState();
}

class _DesktopChatDropTargetState extends State<_DesktopChatDropTarget> {
  bool _dragging = false;
  bool _sending = false;

  bool get _enabled => !kIsWeb && checkPlatformIsDesktop();

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return widget.child;
    }

    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragging = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragging = false;
        });
      },
      onDragDone: (event) async {
        setState(() {
          _dragging = false;
          _sending = true;
        });
        try {
          final files = <CrossFile>[];
          for (final file in event.files) {
            try {
              files.add(await CrossFileConverters.convertXFile(file));
            } catch (_) {
              // Directories or unsupported drop items are ignored.
            }
          }
          if (files.isNotEmpty) {
            await widget.onSendFiles(files);
          }
        } finally {
          if (mounted) {
            setState(() {
              _sending = false;
            });
          }
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            ignoring: !_dragging && !_sending,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _dragging || _sending ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.88),
                  border: Border.all(color: scheme.primary, width: 2),
                ),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sending ? Icons.upload_file : Icons.file_upload_outlined,
                            color: scheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _sending ? 'Sending files...' : 'Drop files to send',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ChatMenuAction { members, sync }

enum _MessageContextAction { copy, share }

class _EmptyConversation extends StatelessWidget {
  final bool hasMembers;
  final Future<void> Function() onManageUsers;

  const _EmptyConversation({
    required this.hasMembers,
    required this.onManageUsers,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              hasMembers ? 'No messages yet' : 'Add users to start chatting',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              hasMembers ? 'Send a message or share a file from the input bar below.' : 'Open the top-right menu and manage users first.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onManageUsers,
              icon: const Icon(Icons.group),
              label: const Text('User management'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final VoidCallback onClearSelection;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = isMine ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final textColor = isMine ? scheme.onPrimaryContainer : scheme.onSurface;
    final crossAlign = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final rowAlign = isMine ? MainAxisAlignment.end : MainAxisAlignment.start;
    final contextData = _contextDataForMessage(message);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: crossAlign,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              '${message.senderAlias}  ${_formatTime(message.sentAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Row(
            mainAxisAlignment: rowAlign,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GestureDetector(
                  onTap: onClearSelection,
                  onLongPressStart: contextData == null
                      ? null
                      : (details) => _showCopyMenu(
                          context: context,
                          position: details.globalPosition,
                          message: contextData,
                        ),
                  onSecondaryTapDown: contextData == null
                      ? null
                      : (details) => _showCopyMenu(
                          context: context,
                          position: details.globalPosition,
                          message: contextData,
                        ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: DefaultTextStyle(
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge!.copyWith(color: textColor),
                        child: switch (message.kind) {
                          ChatMessageKind.text => SelectableText(
                            message.text ?? '',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge!.copyWith(color: textColor),
                          ),
                          ChatMessageKind.attachment when attachment != null && attachment.fileType == FileType.image => _ImageAttachmentCard(
                            attachment: attachment,
                            textColor: textColor,
                            onClearSelection: onClearSelection,
                          ),
                          ChatMessageKind.attachment when attachment != null => _AttachmentCard(
                            attachment: attachment,
                            textColor: textColor,
                            onClearSelection: onClearSelection,
                          ),
                          _ => const SizedBox.shrink(),
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(int timestamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  _MessageContextData? _contextDataForMessage(ChatMessage message) {
    switch (message.kind) {
      case ChatMessageKind.text:
        final text = message.text;
        return text == null || text.isEmpty ? null : _MessageContextData.text(text);
      case ChatMessageKind.attachment:
        final attachment = message.attachment;
        return attachment == null ? null : _MessageContextData.attachment(attachment);
    }
  }
}

class _AttachmentCard extends StatelessWidget {
  final ChatAttachment attachment;
  final Color textColor;
  final VoidCallback onClearSelection;

  const _AttachmentCard({
    required this.attachment,
    required this.textColor,
    required this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) => _showCopyMenu(
        context: context,
        position: details.globalPosition,
        message: _MessageContextData.attachment(attachment),
      ),
      child: InkWell(
        onTap: () async {
          onClearSelection();
          final notifier = context.ref.notifier(chatProvider);
          if (await notifier.hasLocalAttachmentFile(attachment)) {
            if (!context.mounted) {
              return;
            }
            await notifier.openLocalAttachment(context, attachment);
            return;
          }
          await notifier.requestAttachmentDownload(attachment);
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconForFileType(attachment.fileType), color: textColor),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      attachment.size.asReadableFileSize,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: textColor.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForFileType(FileType fileType) {
    switch (fileType) {
      case FileType.image:
        return Icons.image_outlined;
      case FileType.video:
        return Icons.movie_outlined;
      case FileType.pdf:
        return Icons.picture_as_pdf_outlined;
      case FileType.text:
        return Icons.subject;
      case FileType.apk:
        return Icons.android;
      case FileType.other:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _ImageAttachmentCard extends StatelessWidget {
  final ChatAttachment attachment;
  final Color textColor;
  final VoidCallback onClearSelection;

  const _ImageAttachmentCard({
    required this.attachment,
    required this.textColor,
    required this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocalFile = _hasLocalFile(attachment.localPath);
    return GestureDetector(
      onLongPressStart: (details) => _showCopyMenu(
        context: context,
        position: details.globalPosition,
        message: _MessageContextData.attachment(attachment),
      ),
      child: InkWell(
        onTap: () {
          onClearSelection();
          unawaited(_openImage(context));
        },
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AspectRatio(
                  aspectRatio: 1.1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                    child: hasLocalFile
                        ? _ImageAttachmentPreview(
                            attachment: attachment,
                            localPath: attachment.localPath!,
                          )
                        : _ImageAttachmentThumbnail(
                            attachment: attachment,
                            textColor: textColor,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                attachment.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                attachment.size.asReadableFileSize,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textColor.withValues(alpha: 0.75),
                ),
              ),
            ],
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

  Future<void> _openImage(BuildContext context) async {
    final notifier = context.ref.notifier(chatProvider);
    if (!await notifier.hasLocalAttachmentFile(attachment)) {
      await notifier.requestAttachmentDownload(attachment);
      return;
    }
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatImagePreviewPage(attachment: attachment),
      ),
    );
  }
}

class _ImageAttachmentPreview extends StatelessWidget {
  final ChatAttachment attachment;
  final String localPath;

  const _ImageAttachmentPreview({
    required this.attachment,
    required this.localPath,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(localPath);
    if (!file.existsSync()) {
      return const Center(child: Icon(Icons.broken_image_outlined));
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}

class _ImageAttachmentThumbnail extends StatelessWidget {
  final ChatAttachment attachment;
  final Color textColor;

  const _ImageAttachmentThumbnail({
    required this.attachment,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnail = attachment.thumbnail;
    if (thumbnail != null) {
      return Image.memory(thumbnail, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (attachment.downloadPending) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text('Downloading...', style: TextStyle(color: textColor)),
          ],
        ),
      );
    }
    if (attachment.downloadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            attachment.downloadError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    return const Center(child: Icon(Icons.image_outlined));
  }
}

String _attachmentCopyText(ChatAttachment attachment) {
  return '${attachment.fileName} (${attachment.size.asReadableFileSize})';
}

class _MessageContextData {
  final ChatAttachment? attachment;
  final String? text;

  const _MessageContextData._({required this.attachment, required this.text});

  factory _MessageContextData.text(String text) {
    return _MessageContextData._(attachment: null, text: text);
  }

  factory _MessageContextData.attachment(ChatAttachment attachment) {
    return _MessageContextData._(attachment: attachment, text: null);
  }

  String get copyText {
    if (attachment != null) {
      return _attachmentCopyText(attachment!);
    }
    return text ?? '';
  }
}

void _showCopyMenu({
  required BuildContext context,
  required Offset position,
  required _MessageContextData message,
}) {
  unawaited(
    _showCopyMenuAsync(
      context: context,
      position: position,
      message: message,
    ),
  );
}

Future<void> _showCopyMenuAsync({
  required BuildContext context,
  required Offset position,
  required _MessageContextData message,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final action = await showMenu<_MessageContextAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem(
        value: _MessageContextAction.copy,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.content_copy),
          title: Text(t.general.copy),
        ),
      ),
      const PopupMenuItem(
        value: _MessageContextAction.share,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.ios_share),
          title: Text('Share'),
        ),
      ),
    ],
  );

  switch (action) {
    case _MessageContextAction.copy:
      await _copyMessageContext(message);
      if (context.mounted && checkPlatformIsDesktop()) {
        context.showSnackBar(t.general.copiedToClipboard);
      }
      break;
    case _MessageContextAction.share:
      await _shareMessageContext(message);
      break;
    case null:
      break;
  }
}

Future<void> _copyMessageContext(_MessageContextData message) async {
  final attachment = message.attachment;
  final localPath = attachment?.localPath;
  if (attachment != null && localPath != null && !localPath.startsWith('content://')) {
    final file = File(localPath);
    if (file.existsSync()) {
      final copiedFiles = await Pasteboard.writeFiles([localPath]);
      if (copiedFiles) {
        return;
      }
      if (attachment.fileType == FileType.image) {
        try {
          await Pasteboard.writeImage(await file.readAsBytes());
          return;
        } catch (_) {
          // Fall back to text below.
        }
      }
    }
  }

  await Clipboard.setData(ClipboardData(text: message.copyText));
}

Future<void> _shareMessageContext(_MessageContextData message) async {
  final attachment = message.attachment;
  final localPath = attachment?.localPath;
  if (attachment != null && localPath != null && !localPath.startsWith('content://') && File(localPath).existsSync()) {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _attachmentCopyText(attachment),
          title: attachment.fileName,
          files: [XFile(localPath, name: attachment.fileName)],
          fileNameOverrides: [attachment.fileName],
        ),
      );
      return;
    } catch (_) {
      // Fall back to text below.
    }
  }

  await SharePlus.instance.share(
    ShareParams(
      text: message.copyText,
      title: attachment?.fileName,
    ),
  );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final Future<void> Function(String text) onSendText;
  final Future<void> Function(List<CrossFile> files) onSendFiles;

  const _Composer({
    required this.controller,
    required this.onSendText,
    required this.onSendFiles,
  });

  Future<void> _sendCurrentText() async {
    final text = controller.text;
    controller.clear();
    await onSendText(text);
  }

  @override
  Widget build(BuildContext context) {
    final composer = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Send file',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () async {
            final files = await openFiles();
            if (files.isEmpty) {
              return;
            }
            final crossFiles = <CrossFile>[];
            for (final file in files) {
              crossFiles.add(await CrossFileConverters.convertXFile(file));
            }
            await onSendFiles(crossFiles);
          },
        ),
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(hintText: 'Message'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _sendCurrentText,
          child: const Text('Send'),
        ),
      ],
    );

    final wrappedComposer = checkPlatformIsDesktop()
        ? Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): _SendMessageIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _SendMessageIntent: CallbackAction<_SendMessageIntent>(
                  onInvoke: (_) {
                    unawaited(_sendCurrentText());
                    return null;
                  },
                ),
              },
              child: composer,
            ),
          )
        : composer;

    return SafeArea(
      top: false,
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: wrappedComposer,
      ),
    );
  }
}

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class _MemberManagementSheet extends StatelessWidget {
  const _MemberManagementSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final members = context.watch(
      chatProvider.select((state) => state.members),
    );
    final nearbyDevicesState = context.watch(nearbyDevicesProvider);
    final onlineNearbyDevices = nearbyDevicesState.allDevices.values.where((device) => device.ip != null).toList(growable: false);
    final chatNotifier = context.ref.notifier(chatProvider);
    final onlineDevices = chatNotifier.onlineNonMemberDevices();
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text(
                    'User management',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text(
                    'Members',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (members.isEmpty)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('No users in chatroom'),
                    )
                  else
                    ...members.map((member) {
                      final isOnline = chatNotifier.isMemberOnline(
                        member.fingerprint,
                      );
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _StatusAvatar(
                          icon: Icons.person_outline,
                          online: isOnline,
                        ),
                        title: Text(member.alias),
                        subtitle: Text(member.ip ?? 'Offline'),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          onPressed: () => context.ref.notifier(chatProvider).removeMember(member.fingerprint),
                          icon: const Icon(Icons.person_remove_outlined),
                        ),
                      );
                    }),
                  const SizedBox(height: 18),
                  Text(
                    'Online devices',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (onlineNearbyDevices.isEmpty)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('No LAN devices discovered'),
                    )
                  else if (onlineDevices.isEmpty)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('No online devices available to add'),
                    )
                  else
                    ...onlineDevices.map((device) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DeviceListTile(
                          device: device,
                          info: 'Tap to add',
                          onTap: () => context.ref.notifier(chatProvider).addMember(device),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusAvatar extends StatelessWidget {
  final IconData icon;
  final bool online;

  const _StatusAvatar({required this.icon, required this.online});

  @override
  Widget build(BuildContext context) {
    final dotColor = online ? Colors.green : Colors.grey;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(child: Icon(icon)),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
