import 'dart:async';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
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
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:share_plus/share_plus.dart';

class ChatTab extends StatefulWidget {
  final List<ChatShellDestination> shellDestinations;

  const ChatTab({this.shellDestinations = const [], super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class ChatShellDestination {
  final IconData icon;
  final String label;
  final VoidCallback onSelected;

  const ChatShellDestination({
    required this.icon,
    required this.label,
    required this.onSelected,
  });
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool selectingMessages;
  final int selectedMessageCount;
  final int onlineMemberCount;
  final bool syncing;
  final bool messagesEmpty;
  final List<ChatShellDestination> shellDestinations;
  final VoidCallback onExitSelection;
  final VoidCallback onSelectAllMessages;
  final Future<void> Function()? onDeleteSelectedMessages;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onShowMembers;

  const _ChatAppBar({
    required this.selectingMessages,
    required this.selectedMessageCount,
    required this.onlineMemberCount,
    required this.syncing,
    required this.messagesEmpty,
    required this.shellDestinations,
    required this.onExitSelection,
    required this.onSelectAllMessages,
    required this.onDeleteSelectedMessages,
    required this.onSyncNow,
    required this.onShowMembers,
  });

  static const double _macTrafficLightPadding = 72;

  @override
  Size get preferredSize => const Size.fromHeight(localSendAppBarHeight);

  @override
  Widget build(BuildContext context) {
    final isMacOs = checkPlatform([TargetPlatform.macOS]);
    return AppBar(
      toolbarHeight: localSendAppBarHeight,
      automaticallyImplyLeading: false,
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      titleSpacing: 12,
      leadingWidth: isMacOs ? _macTrafficLightPadding + (selectingMessages ? 48 : 0) : null,
      leading: _buildLeading(isMacOs),
      title: _buildTitle(context, isMacOs),
      actions: [
        if (selectingMessages) ...[
          TextButton.icon(
            style: compactAppBarButtonStyle(),
            onPressed: messagesEmpty ? null : onSelectAllMessages,
            icon: const Icon(Icons.select_all),
            label: const Text('Select all'),
          ),
          IconButton(
            constraints: const BoxConstraints.tightFor(
              width: localSendAppBarHeight,
              height: localSendAppBarHeight,
            ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDeleteSelectedMessages,
          ),
        ] else ...[
          if (syncing)
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
          IconButton(
            constraints: const BoxConstraints.tightFor(
              width: localSendAppBarHeight,
              height: localSendAppBarHeight,
            ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: 'Sync now',
            onPressed: syncing ? null : onSyncNow,
            icon: const Icon(Icons.sync),
          ),
          PopupMenuButton<Object>(
            padding: EdgeInsets.zero,
            icon: const SizedBox.square(
              dimension: localSendAppBarHeight,
              child: Icon(Icons.more_horiz),
            ),
            onSelected: (action) async {
              if (action is int) {
                shellDestinations[action].onSelected();
                return;
              }

              if (action == _ChatMenuAction.members) {
                await onShowMembers();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _ChatMenuAction.members,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.group),
                  title: Text('User management'),
                ),
              ),
              if (shellDestinations.isNotEmpty) const PopupMenuDivider(),
              for (final (index, destination) in shellDestinations.indexed)
                PopupMenuItem(
                  value: index,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(destination.icon),
                    title: Text(
                      destination.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTitle(BuildContext context, bool isMacOs) {
    final title = selectingMessages
        ? Text(
            '$selectedMessageCount selected',
            overflow: TextOverflow.ellipsis,
          )
        : Text(
            '$onlineMemberCount online',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          );

    if (!isMacOs) {
      return title;
    }

    return SizedBox(
      width: double.infinity,
      height: localSendAppBarHeight,
      child: MoveWindow(
        child: Align(alignment: Alignment.centerLeft, child: title),
      ),
    );
  }

  Widget? _buildLeading(bool isMacOs) {
    if (!selectingMessages) {
      return isMacOs ? MoveWindow(child: const SizedBox.expand()) : null;
    }

    final closeButton = IconButton(
      constraints: const BoxConstraints.tightFor(
        width: localSendAppBarHeight,
        height: localSendAppBarHeight,
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      tooltip: 'Close',
      icon: const Icon(Icons.close),
      onPressed: onExitSelection,
    );

    if (!isMacOs) {
      return closeButton;
    }

    return Row(
      children: [
        MoveWindow(
          child: const SizedBox(
            width: _macTrafficLightPadding,
            height: localSendAppBarHeight,
          ),
        ),
        closeButton,
      ],
    );
  }
}

class _ChatTabState extends State<ChatTab> with Refena {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _selectedMessageIds = {};
  bool _selectingMessages = false;
  String? _lastRenderedMessageId;
  int _lastRenderedMessageCount = 0;
  bool _hasAutoScrolledInitialMessages = false;
  bool _scrollToBottomAfterOwnSend = false;

  static const double _bottomAutoScrollThreshold = 96;

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

  void _startMessageSelection(String messageId) {
    _clearMessageSelection();
    setState(() {
      _selectingMessages = true;
      _selectedMessageIds
        ..clear()
        ..add(messageId);
    });
  }

  void _toggleMessageSelection(String messageId) {
    if (!_selectingMessages) {
      return;
    }
    setState(() {
      if (!_selectedMessageIds.add(messageId)) {
        _selectedMessageIds.remove(messageId);
      }
    });
  }

  void _selectAllMessages(List<ChatMessage> messages) {
    setState(() {
      _selectingMessages = true;
      _selectedMessageIds
        ..clear()
        ..addAll(messages.map((message) => message.id));
    });
  }

  void _exitMessageSelection() {
    setState(() {
      _selectingMessages = false;
      _selectedMessageIds.clear();
    });
  }

  Future<void> _deleteSelectedMessages() async {
    final ids = _selectedMessageIds.toSet();
    if (ids.isEmpty) {
      return;
    }

    await context.ref.notifier(chatProvider).deleteMessages(ids);
    if (!mounted) {
      return;
    }
    _exitMessageSelection();
  }

  bool _isNearMessageListBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }

    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= _bottomAutoScrollThreshold;
  }

  void _scrollMessagesToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    _scrollController.jumpTo(position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch(chatProvider);
    final myFingerprint = context.watch(
      deviceFullInfoProvider.select((device) => device.fingerprint),
    );

    final currentMessageCount = chat.messages.length;
    final currentLastMessageId = chat.messages.isEmpty ? null : chat.messages.last.id;
    final isInitialMessageLoad = currentLastMessageId != null && !_hasAutoScrolledInitialMessages;
    final hasNewTrailingMessage =
        currentLastMessageId != null &&
        _lastRenderedMessageId != null &&
        currentMessageCount > _lastRenderedMessageCount &&
        currentLastMessageId != _lastRenderedMessageId;
    final shouldAutoScroll = isInitialMessageLoad || _scrollToBottomAfterOwnSend || (hasNewTrailingMessage && _isNearMessageListBottom());
    final staleSelectedIds = _selectingMessages
        ? _selectedMessageIds.difference(
            chat.messages.map((message) => message.id).toSet(),
          )
        : const <String>{};

    _lastRenderedMessageId = currentLastMessageId;
    _lastRenderedMessageCount = currentMessageCount;
    if (currentLastMessageId == null) {
      _hasAutoScrolledInitialMessages = false;
    } else if (isInitialMessageLoad) {
      _hasAutoScrolledInitialMessages = true;
    }
    if (_scrollToBottomAfterOwnSend) {
      _scrollToBottomAfterOwnSend = false;
    }

    if (shouldAutoScroll || staleSelectedIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (shouldAutoScroll) {
          _scrollMessagesToBottom();
        }
        if (staleSelectedIds.isNotEmpty) {
          setState(() {
            _selectedMessageIds.removeAll(staleSelectedIds);
          });
        }
      });
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: _ChatAppBar(
        selectingMessages: _selectingMessages,
        selectedMessageCount: _selectedMessageIds.length,
        onlineMemberCount: chat.members.where((member) => member.ip != null).length,
        syncing: chat.syncing,
        messagesEmpty: chat.messages.isEmpty,
        shellDestinations: widget.shellDestinations,
        onExitSelection: _exitMessageSelection,
        onSelectAllMessages: () => _selectAllMessages(chat.messages),
        onDeleteSelectedMessages: _selectedMessageIds.isEmpty ? null : _deleteSelectedMessages,
        onSyncNow: () async => context.ref.notifier(chatProvider).syncOnlineMembers(),
        onShowMembers: () async {
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
        },
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
              onSendFiles: _sendFiles,
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
                              isSelectionMode: _selectingMessages,
                              isSelected: _selectedMessageIds.contains(
                                message.id,
                              ),
                              onClearSelection: _clearMessageSelection,
                              onEnterSelection: _startMessageSelection,
                              onToggleSelection: _toggleMessageSelection,
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
          _Composer(
            controller: _controller,
            onSendText: _sendText,
            onSendFiles: _sendFiles,
          ),
        ],
      ),
    );
  }

  Future<void> _sendText(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    _scrollToBottomAfterOwnSend = true;
    await context.ref.notifier(chatProvider).sendText(text);
  }

  Future<void> _sendFiles(List<CrossFile> files) async {
    if (files.isEmpty) {
      return;
    }
    _scrollToBottomAfterOwnSend = true;
    await context.ref.notifier(chatProvider).sendAttachments(files);
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
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

enum _ChatMenuAction { members }

enum _MessageContextAction { select, copy, share, showInFolder }

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
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onClearSelection;
  final ValueChanged<String> onEnterSelection;
  final ValueChanged<String> onToggleSelection;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onClearSelection,
    required this.onEnterSelection,
    required this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment;
    final hasImagePreview = attachment != null && _hasLocalAttachmentPath(attachment.localPath) && _hasThumbnailPreview(attachment.thumbnailPath);
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = _messageUserColor(message.senderFingerprint, scheme);
    final textColor = _readableTextColor(bubbleColor, scheme);
    final crossAlign = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final contextData = _contextDataForMessage(message);
    final checkbox = Checkbox(
      value: isSelected,
      onChanged: (_) => onToggleSelection(message.id),
    );
    final messageCell = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? Color.alphaBlend(
                  scheme.secondary.withValues(alpha: 0.16),
                  bubbleColor,
                )
              : bubbleColor,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: scheme.secondary, width: 2) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: GestureDetector(
            onTap: isSelectionMode ? () => onToggleSelection(message.id) : onClearSelection,
            onLongPressStart: contextData == null
                ? null
                : (details) => _showCopyMenu(
                    context: context,
                    position: details.globalPosition,
                    message: contextData,
                    onSelect: onEnterSelection,
                  ),
            onSecondaryTapDown: contextData == null
                ? null
                : (details) => _showCopyMenu(
                    context: context,
                    position: details.globalPosition,
                    message: contextData,
                    onSelect: onEnterSelection,
                  ),
            child: DefaultTextStyle(
              style: Theme.of(
                context,
              ).textTheme.bodyLarge!.copyWith(color: textColor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${message.senderAlias}  ${_formatTime(message.sentAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: textColor.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  switch (message.kind) {
                    ChatMessageKind.text when isSelectionMode => Text(
                      message.text ?? '',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge!.copyWith(color: textColor),
                    ),
                    ChatMessageKind.text => SelectableText(
                      message.text ?? '',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge!.copyWith(color: textColor),
                    ),
                    ChatMessageKind.attachment when attachment != null && attachment.fileType == FileType.image && hasImagePreview =>
                      _ImageAttachmentCard(
                        attachment: attachment,
                        textColor: textColor,
                        isSelectionMode: isSelectionMode,
                        onClearSelection: onClearSelection,
                        onToggleSelection: () => onToggleSelection(message.id),
                        onEnterSelection: onEnterSelection,
                      ),
                    ChatMessageKind.attachment when attachment != null => _AttachmentCard(
                      attachment: attachment,
                      textColor: textColor,
                      isSelectionMode: isSelectionMode,
                      onClearSelection: onClearSelection,
                      onToggleSelection: () => onToggleSelection(message.id),
                      onEnterSelection: onEnterSelection,
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSelectionMode)
            SizedBox(
              width: 48,
              child: Align(alignment: Alignment.topLeft, child: checkbox),
            ),
          Expanded(
            child: Align(
              alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: crossAlign,
                children: [messageCell],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _messageUserColor(String senderFingerprint, ColorScheme scheme) {
    final hue = _stableHue(senderFingerprint);
    final saturation = scheme.brightness == Brightness.dark ? 0.30 : 0.42;
    final lightness = scheme.brightness == Brightness.dark ? 0.28 : 0.86;
    final userColor = HSLColor.fromAHSL(
      1,
      hue,
      saturation,
      lightness,
    ).toColor();
    return Color.alphaBlend(
      userColor.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.84 : 0.92,
      ),
      scheme.surface,
    );
  }

  double _stableHue(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return (hash % 360).toDouble();
  }

  Color _readableTextColor(Color background, ColorScheme scheme) {
    final whiteContrast = _contrastRatio(Colors.white, background);
    final blackContrast = _contrastRatio(Colors.black, background);
    if (whiteContrast >= 4.5 || blackContrast >= 4.5) {
      return whiteContrast >= blackContrast ? Colors.white : Colors.black;
    }
    return scheme.onSurface;
  }

  double _contrastRatio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance ? foregroundLuminance : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance ? backgroundLuminance : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
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
        return text == null || text.isEmpty ? null : _MessageContextData.text(message.id, text);
      case ChatMessageKind.attachment:
        final attachment = message.attachment;
        return attachment == null ? null : _MessageContextData.attachment(attachment);
    }
  }
}

bool _hasLocalAttachmentPath(String? localPath) {
  if (localPath == null) {
    return false;
  }
  if (localPath.startsWith('content://')) {
    return true;
  }
  return File(localPath).existsSync();
}

bool _hasThumbnailPreview(String? thumbnailPath) {
  if (thumbnailPath == null) {
    return false;
  }
  return File(thumbnailPath).existsSync();
}

class _AttachmentCard extends StatelessWidget {
  final ChatAttachment attachment;
  final Color textColor;
  final bool isSelectionMode;
  final VoidCallback onClearSelection;
  final VoidCallback onToggleSelection;
  final ValueChanged<String> onEnterSelection;

  const _AttachmentCard({
    required this.attachment,
    required this.textColor,
    required this.isSelectionMode,
    required this.onClearSelection,
    required this.onToggleSelection,
    required this.onEnterSelection,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) => _showCopyMenu(
        context: context,
        position: details.globalPosition,
        message: _MessageContextData.attachment(attachment),
        onSelect: onEnterSelection,
      ),
      onSecondaryTapDown: (details) => _showCopyMenu(
        context: context,
        position: details.globalPosition,
        message: _MessageContextData.attachment(attachment),
        onSelect: onEnterSelection,
      ),
      child: InkWell(
        onTap: () async {
          if (isSelectionMode) {
            onToggleSelection();
            return;
          }
          onClearSelection();
          await _openAttachment(context, attachment);
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
  final bool isSelectionMode;
  final VoidCallback onClearSelection;
  final VoidCallback onToggleSelection;
  final ValueChanged<String> onEnterSelection;

  const _ImageAttachmentCard({
    required this.attachment,
    required this.textColor,
    required this.isSelectionMode,
    required this.onClearSelection,
    required this.onToggleSelection,
    required this.onEnterSelection,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) => _showCopyMenu(
        context: context,
        position: details.globalPosition,
        message: _MessageContextData.attachment(attachment),
        onSelect: onEnterSelection,
      ),
      onSecondaryTapDown: (details) => _showCopyMenu(
        context: context,
        position: details.globalPosition,
        message: _MessageContextData.attachment(attachment),
        onSelect: onEnterSelection,
      ),
      child: InkWell(
        onTap: () {
          if (isSelectionMode) {
            onToggleSelection();
            return;
          }
          onClearSelection();
          unawaited(_openImage(context));
        },
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AspectRatio(
                  aspectRatio: 1.1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    child: _ImageAttachmentPreview(
                      attachment: attachment,
                      localPath: attachment.localPath!,
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

  Future<void> _openImage(BuildContext context) async {
    await _openAttachment(context, attachment);
  }
}

Future<void> _openAttachment(
  BuildContext context,
  ChatAttachment attachment,
) async {
  final notifier = context.ref.notifier(chatProvider);
  if (attachment.fileType == FileType.image) {
    final resolvedAttachment = await notifier.resolveAttachmentForPreview(
      attachment,
    );
    if (resolvedAttachment == null) {
      await notifier.requestAttachmentDownload(attachment);
      return;
    }
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatImagePreviewPage(attachment: resolvedAttachment),
      ),
    );
    return;
  }

  if (await notifier.hasLocalAttachmentFile(attachment)) {
    if (!context.mounted) {
      return;
    }
    await notifier.openLocalAttachment(context, attachment);
    return;
  }

  await notifier.requestAttachmentDownload(attachment);
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
    final thumbnailPath = attachment.thumbnailPath;
    if (thumbnailPath != null) {
      final thumbnailFile = File(thumbnailPath);
      if (thumbnailFile.existsSync()) {
        return Image.file(
          thumbnailFile,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
        );
      }
    }
    if (localPath.startsWith('content://')) {
      return const Center(child: Icon(Icons.image_outlined));
    }
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

String _attachmentCopyText(ChatAttachment attachment) {
  return '${attachment.fileName} (${attachment.size.asReadableFileSize})';
}

class _MessageContextData {
  final String messageId;
  final ChatAttachment? attachment;
  final String? text;

  const _MessageContextData._({
    required this.messageId,
    required this.attachment,
    required this.text,
  });

  factory _MessageContextData.text(String messageId, String text) {
    return _MessageContextData._(
      messageId: messageId,
      attachment: null,
      text: text,
    );
  }

  factory _MessageContextData.attachment(ChatAttachment attachment) {
    return _MessageContextData._(
      messageId: attachment.messageId,
      attachment: attachment,
      text: null,
    );
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
  required ValueChanged<String> onSelect,
}) {
  unawaited(
    _showCopyMenuAsync(
      context: context,
      position: position,
      message: message,
      onSelect: onSelect,
    ),
  );
}

Future<void> _showCopyMenuAsync({
  required BuildContext context,
  required Offset position,
  required _MessageContextData message,
  required ValueChanged<String> onSelect,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final showInFolderFile = _localAttachmentFileForFolder(message);
  final action = await showMenu<_MessageContextAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      const PopupMenuItem(
        value: _MessageContextAction.select,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.checklist),
          title: Text('Select'),
        ),
      ),
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
      if (showInFolderFile != null)
        const PopupMenuItem(
          value: _MessageContextAction.showInFolder,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_open),
            title: Text('Show in folder'),
          ),
        ),
    ],
  );

  switch (action) {
    case _MessageContextAction.select:
      onSelect(message.messageId);
      break;
    case _MessageContextAction.copy:
      await _copyMessageContext(message);
      if (context.mounted && checkPlatformIsDesktop()) {
        context.showSnackBar(t.general.copiedToClipboard);
      }
      break;
    case _MessageContextAction.share:
      await _shareMessageContext(message);
      break;
    case _MessageContextAction.showInFolder:
      if (showInFolderFile == null) {
        return;
      }
      await openFolder(
        folderPath: showInFolderFile.parent.path,
        fileName: showInFolderFile.path.fileName,
      );
      break;
    case null:
      break;
  }
}

File? _localAttachmentFileForFolder(_MessageContextData message) {
  if (!checkPlatformIsDesktop()) {
    return null;
  }

  final localPath = message.attachment?.localPath;
  if (localPath == null || localPath.isEmpty || localPath.startsWith('content://')) {
    return null;
  }

  final file = File(localPath);
  return file.existsSync() ? file : null;
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
    ShareParams(text: message.copyText, title: attachment?.fileName),
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
        FilledButton(onPressed: _sendCurrentText, child: const Text('Send')),
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
