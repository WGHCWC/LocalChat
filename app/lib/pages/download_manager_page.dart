import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:common/model/file_status.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/custom_progress_bar.dart';
import 'package:localsend_app/widget/dialogs/cancel_session_dialog.dart';
import 'package:localsend_app/widget/dialogs/file_info_dialog.dart';
import 'package:localsend_app/widget/dialogs/history_clear_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:path/path.dart' as path;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _HistoryOption {
  open,
  showInFolder,
  info,
  delete;

  String get label {
    return switch (this) {
      _HistoryOption.open => t.receiveHistoryPage.entryActions.open,
      _HistoryOption.showInFolder => t.receiveHistoryPage.entryActions.showInFolder,
      _HistoryOption.info => t.receiveHistoryPage.entryActions.info,
      _HistoryOption.delete => t.receiveHistoryPage.entryActions.deleteFromHistory,
    };
  }
}

const _historyOptionsAll = _HistoryOption.values;
final _historyOptionsWithoutOpen = [_HistoryOption.info, _HistoryOption.delete];

class DownloadManagerPage extends StatelessWidget {
  const DownloadManagerPage({super.key});

  Future<void> _openHistoryEntry(
    BuildContext context,
    ReceiveHistoryEntry entry,
    Dispatcher<ReceiveHistoryService, List<ReceiveHistoryEntry>> dispatcher,
  ) async {
    final filePath = entry.path;
    if (filePath == null) {
      return;
    }

    await openFile(context, entry.fileType, filePath, onDeleteTap: () => dispatcher.dispatchAsync(RemoveHistoryEntryAction(entry.id)));
  }

  @override
  Widget build(BuildContext context) {
    final receiveSession = context.watch(serverProvider.select((state) => state?.session));
    final receiveHistory = context.watch(receiveHistoryProvider);
    final chat = context.watch(chatProvider);
    final myFingerprint = context.watch(deviceFullInfoProvider.select((device) => device.fingerprint));
    final onlineFingerprints = {
      for (final device in context.watch(nearbyDevicesProvider).allDevices.values)
        if (_isUsableIp(device.ip)) device.fingerprint,
    };
    final remoteAttachments = chat.messages
        .map((message) => message.attachment)
        .whereType<ChatAttachment>()
        .where((attachment) => attachment.localPath == null && attachment.sourceFingerprint != myFingerprint)
        .toList(growable: false);

    return Stack(
      children: [
        ResponsiveListView(
          maxWidth: 860,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
          tabletPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            const SizedBox(height: 12),
            Text('Downloads', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              '${_activeCount(receiveSession)} active - ${receiveHistory.length} completed - ${remoteAttachments.length} available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Current',
              action: receiveSession == null
                  ? null
                  : TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                      onPressed: () async {
                        final confirmed = await context.pushBottomSheet(() => const CancelSessionDialog()) == true;
                        if (confirmed && context.mounted) {
                          context.ref.notifier(serverProvider).cancelSession();
                        }
                      },
                      icon: const Icon(Icons.close),
                      label: Text(t.general.cancel),
                    ),
            ),
            const SizedBox(height: 8),
            if (receiveSession == null)
              _EmptyState(icon: Icons.download_done, title: 'No active downloads')
            else
              _ActiveReceiveCard(session: receiveSession),
            const SizedBox(height: 28),
            _SectionHeader(title: 'Chat attachments', action: null),
            const SizedBox(height: 8),
            if (remoteAttachments.isEmpty)
              _EmptyState(icon: Icons.attach_file, title: 'No remote attachments')
            else
              ...remoteAttachments.map(
                (attachment) => _RemoteAttachmentTile(attachment: attachment, online: onlineFingerprints.contains(attachment.sourceFingerprint)),
              ),
            const SizedBox(height: 28),
            _SectionHeader(
              title: 'Completed',
              action: receiveHistory.isEmpty
                  ? null
                  : TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                      onPressed: () async {
                        final result = await showDialog(context: context, builder: (_) => const HistoryClearDialog());
                        if (context.mounted && result == true) {
                          await context.redux(receiveHistoryProvider).dispatchAsync(RemoveAllHistoryEntriesAction());
                        }
                      },
                      icon: const Icon(Icons.delete),
                      label: Text(t.receiveHistoryPage.deleteHistory),
                    ),
            ),
            const SizedBox(height: 8),
            if (receiveHistory.isEmpty)
              _EmptyState(icon: Icons.history, title: t.receiveHistoryPage.empty)
            else
              ...receiveHistory.map(
                (entry) => _HistoryDownloadTile(entry: entry, onOpen: () => _openHistoryEntry(context, entry, context.redux(receiveHistoryProvider))),
              ),
          ],
        ),
        if (checkPlatform([TargetPlatform.macOS])) Positioned(top: 0, left: 0, right: 0, height: 40, child: MoveWindow()),
      ],
    );
  }

  int _activeCount(ReceiveSessionState? session) {
    if (session == null) {
      return 0;
    }
    return session.files.values.where((file) => file.status == FileStatus.sending || file.status == FileStatus.queue).length;
  }
}

bool _isUsableIp(String? ip) {
  return ip != null && ip.isNotEmpty && ip != '-';
}

class _ActiveReceiveCard extends StatelessWidget {
  final ReceiveSessionState session;

  const _ActiveReceiveCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final progress = context.watch(progressProvider);
    final selectedFiles = session.files.values.where((file) => file.status != FileStatus.skipped).toList(growable: false);
    final totalBytes = selectedFiles.fold<int>(0, (sum, file) => sum + file.file.size);
    final currentBytes = selectedFiles.fold<int>(
      0,
      (sum, file) => sum + (progress.getProgress(sessionId: session.sessionId, fileId: file.file.id) * file.file.size).round(),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.senderAlias, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      if (checkPlatformWithFileSystem())
                        Text(
                          session.destinationDirectory,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                _StatusChip(label: _sessionStatusLabel(session.status)),
              ],
            ),
            const SizedBox(height: 12),
            CustomProgressBar(progress: totalBytes == 0 ? 0 : currentBytes / totalBytes),
            const SizedBox(height: 8),
            Text('${currentBytes.asReadableFileSize} / ${totalBytes.asReadableFileSize}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ...session.files.values.map((file) {
              final itemProgress = progress.getProgress(sessionId: session.sessionId, fileId: file.file.id);
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    FilePathThumbnail(path: file.path, fileType: file.file.fileType),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.desiredName ?? file.file.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: const TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          if (file.status == FileStatus.sending)
                            CustomProgressBar(progress: itemProgress)
                          else
                            Text(_fileStatusLabel(file.status), style: TextStyle(color: _fileStatusColor(context, file.status))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(file.file.size.asReadableFileSize, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _sessionStatusLabel(SessionStatus status) {
    return switch (status) {
      SessionStatus.sending => t.progressPage.total.title.sending(time: '-'),
      SessionStatus.finished => t.general.finished,
      SessionStatus.finishedWithErrors => t.progressPage.total.title.finishedError,
      SessionStatus.canceledBySender => t.progressPage.total.title.canceledSender,
      SessionStatus.canceledByReceiver => t.progressPage.total.title.canceledReceiver,
      _ => status.name,
    };
  }

  String _fileStatusLabel(FileStatus status) {
    return switch (status) {
      FileStatus.queue => t.general.queue,
      FileStatus.skipped => t.general.skipped,
      FileStatus.sending => '',
      FileStatus.failed => t.general.error,
      FileStatus.finished => t.general.done,
    };
  }

  Color _fileStatusColor(BuildContext context, FileStatus status) {
    return switch (status) {
      FileStatus.failed => Theme.of(context).colorScheme.warning,
      FileStatus.finished => Colors.green,
      _ => Colors.grey,
    };
  }
}

class _RemoteAttachmentTile extends StatelessWidget {
  final ChatAttachment attachment;
  final bool online;

  const _RemoteAttachmentTile({required this.attachment, required this.online});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          FilePathThumbnail(path: null, fileType: attachment.fileType),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attachment.fileName, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: const TextStyle(fontSize: 16)),
                Text(
                  online ? attachment.size.asReadableFileSize : '${attachment.size.asReadableFileSize} - Source offline',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
            onPressed: online ? () => context.ref.notifier(chatProvider).requestAttachmentDownload(context, attachment) : null,
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
        ],
      ),
    );
  }
}

class _HistoryDownloadTile extends StatelessWidget {
  final ReceiveHistoryEntry entry;
  final Future<void> Function() onOpen;

  const _HistoryDownloadTile({required this.entry, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: entry.path != null ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilePathThumbnail(path: entry.path, fileType: entry.fileType),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(entry.fileName, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.timestampString} - ${entry.fileSize.asReadableFileSize} - ${entry.senderAlias}',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_HistoryOption>(
                onSelected: (item) async {
                  switch (item) {
                    case _HistoryOption.open:
                      await onOpen();
                      break;
                    case _HistoryOption.showInFolder:
                      if (entry.path != null) {
                        await openFolder(folderPath: File(entry.path!).parent.path, fileName: path.basename(entry.path!));
                      }
                      break;
                    case _HistoryOption.info:
                      if (context.mounted) {
                        await showDialog(
                          context: context,
                          builder: (_) => FileInfoDialog(entry: entry),
                        );
                      }
                      break;
                    case _HistoryOption.delete:
                      if (context.mounted) {
                        await context.redux(receiveHistoryProvider).dispatchAsync(RemoveHistoryEntryAction(entry.id));
                      }
                      break;
                  }
                },
                itemBuilder: (context) {
                  return (entry.path != null ? _historyOptionsAll : _historyOptionsWithoutOpen).map((option) {
                    return PopupMenuItem<_HistoryOption>(value: option, child: Text(option.label));
                  }).toList();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeader({required this.title, required this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (action != null) action!,
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainerIfDark, borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;

  const _EmptyState({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: Colors.grey),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
