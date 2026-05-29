import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:common/api_route_builder.dart';
import 'package:common/model/device.dart';
import 'package:common/model/dto/file_dto.dart';
import 'package:common/model/file_type.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/provider/chat/chat_attachment_file.dart';
import 'package:localsend_app/provider/chat/chat_database.dart';
import 'package:localsend_app/provider/chat/chat_sync.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/rhttp.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:rhttp/rhttp.dart';
import 'package:uri_content/uri_content.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('Chat');
const _uuid = Uuid();
const _pendingAttachmentDownloadTimeout = Duration(minutes: 2);

final chatProvider = NotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});

class ChatNotifier extends Notifier<ChatState> {
  ChatDatabase? _database;
  RhttpClient? _client;
  final Map<String, _PendingAttachmentDownload> _pendingAttachmentDownloads = {};

  @override
  ChatState init() {
    return ChatState.initial;
  }

  Future<void> initialize() async {
    if (state.initialized) {
      return;
    }

    _database ??= await ChatDatabase.open();
    _client ??= createRhttpClient(
      const Duration(seconds: 10),
      ref.read(securityProvider),
    );
    _refreshFromDb();
    await _backfillAttachmentLocalPathsFromHistory();
    state = state.copyWith(initialized: true);
  }

  Future<void> addMember(Device device) async {
    await initialize();
    if (device.ip == null || device.fingerprint == ref.read(deviceFullInfoProvider).fingerprint || _isChatMember(device.fingerprint)) {
      _refreshFromDb();
      return;
    }
    _database!.upsertMember(ChatMember.fromDevice(device));
    _refreshFromDb();
    await refreshOnlineMembers();
  }

  Future<void> removeMember(String fingerprint) async {
    await initialize();
    if (fingerprint == ref.read(deviceFullInfoProvider).fingerprint || !_isChatMember(fingerprint)) {
      _refreshFromDb();
      return;
    }
    _database!.deleteMember(fingerprint);
    _refreshFromDb();
    await refreshOnlineMembers();
  }

  Future<void> deleteMessages(Iterable<String> messageIds) async {
    final ids = messageIds.toSet();
    if (ids.isEmpty) {
      return;
    }

    await initialize();
    final deletedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    _database!.deleteMessagesByIds(ids, deletedAt: deletedAt);
    _refreshFromDb();
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await initialize();
    final device = ref.read(deviceFullInfoProvider);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final message = ChatMessage(
      id: _uuid.v4(),
      roomId: defaultChatRoomId,
      senderFingerprint: device.fingerprint,
      senderAlias: device.alias,
      kind: ChatMessageKind.text,
      text: trimmed,
      sentAt: now,
      receivedAt: now,
      attachment: null,
    );
    _database!.upsertMessage(message);
    _refreshFromDb();
    await refreshOnlineMembers();
    await _notifyOnlineMembers();
  }

  Future<void> sendAttachments(List<CrossFile> files) async {
    if (files.isEmpty) {
      return;
    }

    await initialize();
    final device = ref.read(deviceFullInfoProvider);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await refreshOnlineMembers();
    for (final file in files) {
      final messageId = _uuid.v4();
      final attachmentId = _uuid.v4();
      final localPath = file.path;
      final message = ChatMessage(
        id: messageId,
        roomId: defaultChatRoomId,
        senderFingerprint: device.fingerprint,
        senderAlias: device.alias,
        kind: ChatMessageKind.attachment,
        text: null,
        sentAt: now,
        receivedAt: now,
        attachment: ChatAttachment(
          id: attachmentId,
          messageId: messageId,
          fileName: file.name,
          size: file.size,
          fileType: file.fileType,
          sourceFingerprint: device.fingerprint,
          remoteFileId: attachmentId,
          localPath: localPath,
          thumbnailPath: null,
          downloadPending: false,
          downloadError: null,
          createdAt: now,
        ),
      );
      _database!.upsertMessage(message);
      if (file.fileType == FileType.image && localPath != null) {
        await _ensureThumbnailPath(localPath, attachmentId);
      }
    }
    _refreshFromDb();
    await _notifyOnlineMembers();
  }

  Future<void> syncOnlineMembers() async {
    await initialize();
    if (state.syncing) {
      return;
    }

    state = state.copyWith(syncing: true, errorMessage: null);
    try {
      await syncOnlineChatMembersWithSnapshot(
        refreshOnlineMembers: refreshOnlineMembers,
        getSnapshotSentAt: () => _database!.getSyncSnapshotSentAt(),
        getMembers: () => _database!.getMembers(),
        getOnlineDevices: () => ref.read(nearbyDevicesProvider).allDevices.values,
        syncDevice: _syncAndRecord,
        onDeviceError: (device, e, st) {
          _logger.info('Could not sync chat with ${device.alias}', e, st);
        },
      );
      _refreshFromDb();
    } catch (e, st) {
      _logger.warning('Chat sync failed', e, st);
      state = state.copyWith(errorMessage: e.toString());
    } finally {
      state = state.copyWith(syncing: false);
    }
  }

  Future<void> refreshOnlineMembers() async {
    await initialize();
    ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());

    final membersByIp = {
      for (final member in _database!.getMembers())
        if (member.ip != null) member.ip!: member,
    };
    if (membersByIp.isEmpty) {
      return;
    }

    for (final https in [false, true]) {
      final devices = membersByIp.values
          .where((member) => member.https == https)
          .map((member) {
            return FavoriteDevice(
              id: member.fingerprint,
              fingerprint: member.fingerprint,
              ip: member.ip!,
              port: member.port,
              alias: member.alias,
            );
          })
          .toList(growable: false);
      if (devices.isNotEmpty) {
        await ref.redux(nearbyDevicesProvider).dispatchAsync(StartFavoriteScan(devices: devices, https: https));
      }
    }
  }

  Future<void> receiveMessage(ChatMessage message) async {
    await initialize();
    _database!.upsertMessage(message);
    _refreshFromDb();
  }

  Future<void> _backfillAttachmentLocalPathsFromHistory() async {
    final history = ref.read(persistenceProvider).getReceiveHistory().where((entry) => entry.path != null).toList(growable: false);
    if (history.isEmpty) {
      return;
    }

    var updated = false;
    for (final message in _database!.getMessages()) {
      final attachment = message.attachment;
      if (attachment == null) {
        continue;
      }
      if (hasUsableLocalAttachmentPath(attachment.localPath)) {
        continue;
      }

      final resolvedPath = _resolveAttachmentPathFromHistory(
        attachment,
        history,
      );
      if (resolvedPath == null) {
        continue;
      }

      _database!.updateAttachmentLocalPath(
        attachmentId: attachment.id,
        localPath: resolvedPath,
        downloadPending: false,
        downloadError: null,
      );
      if (attachment.fileType == FileType.image) {
        await _ensureThumbnailPath(resolvedPath, attachment.id);
      }
      updated = true;
    }

    if (updated) {
      _refreshFromDb();
    }
  }

  String? _resolveAttachmentPathFromHistory(
    ChatAttachment attachment,
    List<ReceiveHistoryEntry> historyEntries,
  ) {
    for (final entry in historyEntries) {
      if (entry.fileName != attachment.fileName || entry.fileSize != attachment.size) {
        continue;
      }
      final path = entry.path;
      if (hasUsableLocalAttachmentPath(path)) {
        return path;
      }
    }
    return null;
  }

  Future<void> handleIncomingNotification(Device sender) async {
    await initialize();
    if (!_isChatMember(sender.fingerprint)) {
      _logger.fine(
        'Ignoring chat notification from non-member ${sender.alias}',
      );
      return;
    }

    _database!.upsertMember(ChatMember.fromDevice(sender));
    try {
      await _syncAndRecord(sender, _database!.getSyncSnapshotSentAt());
      _refreshFromDb();
    } catch (e, st) {
      _logger.info(
        'Could not sync chat after notification from ${sender.alias}',
        e,
        st,
      );
    }
  }

  Future<List<ChatMessage>> messagesAtOrAfter(int sentAt) async {
    await initialize();
    return _database!.getMessagesAtOrAfter(sentAt);
  }

  Future<void> requestAttachmentDownload(ChatAttachment attachment) async {
    if (await hasLocalAttachmentFile(attachment)) {
      return;
    }

    await initialize();
    _database!.updateAttachmentLocalPath(
      attachmentId: attachment.id,
      localPath: null,
      downloadPending: true,
      downloadError: null,
    );
    _refreshFromDb();
    await refreshOnlineMembers();

    final source = _findOnlineDevice(attachment.sourceFingerprint);
    if (source == null || !_isUsableIp(source.ip)) {
      _database!.updateAttachmentLocalPath(
        attachmentId: attachment.id,
        localPath: null,
        downloadError: 'Source device is offline.',
      );
      _refreshFromDb();
      return;
    }

    final requester = ref.read(deviceFullInfoProvider);
    final url = ApiRoute.chatAttachment.target(source);
    _rememberPendingAttachmentDownload(attachment);
    try {
      final response = await _client!.post(
        url,
        body: HttpBody.json({
          'attachmentId': attachment.remoteFileId,
          'requester': _deviceToJson(requester),
        }),
      );
      if (response.statusCode >= 400) {
        _database!.updateAttachmentLocalPath(
          attachmentId: attachment.id,
          localPath: null,
          downloadError: response.body.isEmpty ? 'Attachment request failed.' : response.body,
        );
        _refreshFromDb();
        return;
      }
      state = state.copyWith(errorMessage: null);
    } catch (e, st) {
      _forgetPendingAttachmentDownload(attachment);
      _logger.warning('Attachment download request failed', e, st);
      _database!.updateAttachmentLocalPath(
        attachmentId: attachment.id,
        localPath: null,
        downloadError: 'Attachment request failed: $e',
      );
      _refreshFromDb();
    }
  }

  Future<void> recordReceivedAttachment({
    required String sourceFingerprint,
    required String fileName,
    required int size,
    required String? localPath,
    required String? errorMessage,
  }) async {
    await initialize();
    final attachment = _database!.findAttachmentForReceivedFile(
      sourceFingerprint: sourceFingerprint,
      fileName: fileName,
      size: size,
    );
    if (attachment == null) {
      return;
    }
    _database!.updateAttachmentLocalPath(
      attachmentId: attachment.id,
      localPath: localPath,
      downloadPending: false,
      downloadError: errorMessage,
    );
    if (localPath != null && attachment.fileType == FileType.image) {
      await _ensureThumbnailPath(localPath, attachment.id);
    }
    _refreshFromDb();
  }

  Future<String?> _ensureThumbnailPath(
    String sourcePath,
    String attachmentId,
  ) async {
    final existingPath = _database!.getAttachment(attachmentId)?.thumbnailPath;
    if (hasUsableLocalAttachmentPath(existingPath)) {
      return existingPath;
    }
    final thumbnailDir = Directory(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'localsend',
        '.chat-thumbnails',
      ),
    );
    if (!thumbnailDir.existsSync()) {
      thumbnailDir.createSync(recursive: true);
    }
    final thumbnailPath = p.join(thumbnailDir.path, '$attachmentId.thumbcache');
    final file = File(thumbnailPath);
    if (file.existsSync()) {
      _database!.updateAttachmentThumbnailPath(
        attachmentId: attachmentId,
        thumbnailPath: thumbnailPath,
      );
      return thumbnailPath;
    }
    final bytes = await _readImageBytes(sourcePath);
    if (bytes == null) {
      return null;
    }
    final thumbnail = await _buildThumbnail(bytes);
    if (thumbnail == null) {
      return null;
    }
    await file.writeAsBytes(thumbnail);
    _database!.updateAttachmentThumbnailPath(
      attachmentId: attachmentId,
      thumbnailPath: thumbnailPath,
    );
    return thumbnailPath;
  }

  Future<Uint8List?> _readImageBytes(String path) async {
    if (path.startsWith('content://')) {
      try {
        return await UriContent().from(Uri.parse(path));
      } catch (_) {
        return null;
      }
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<Uint8List?> _buildThumbnail(List<int> bytes) async {
    try {
      return await _buildImageThumbnail(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _buildImageThumbnail(List<int> bytes) async {
    final image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) {
      throw Exception('Failed to decode image');
    }
    final width = image.width > 240 ? 240 : image.width;
    final thumbnail = img.copyResize(image, width: width);
    final png = img.encodePng(thumbnail);
    return Uint8List.fromList(png);
  }

  Future<bool> serveAttachmentDownload(
    String attachmentId,
    Device requester,
  ) async {
    await initialize();
    final attachment = _database!.getAttachment(attachmentId);
    if (attachment == null || attachment.localPath == null) {
      return false;
    }

    final localPath = attachment.localPath!;
    DateTime? lastModified;
    DateTime? lastAccessed;
    var size = attachment.size;
    if (!localPath.startsWith('content://')) {
      final file = File(localPath);
      if (!file.existsSync()) {
        return false;
      }
      size = await file.length();
      lastModified = file.lastModifiedSync().toUtc();
      lastAccessed = file.lastAccessedSync().toUtc();
    }

    final status = await ref
        .notifier(sendProvider)
        .startSession(
          target: requester,
          files: [
            CrossFile(
              name: attachment.fileName,
              fileType: attachment.fileType,
              size: size,
              thumbnail: null,
              asset: null,
              path: localPath,
              bytes: null,
              lastModified: lastModified,
              lastAccessed: lastAccessed,
            ),
          ],
          background: true,
        );
    return status == SessionStatus.finished;
  }

  Future<bool> hasLocalAttachmentFile(ChatAttachment attachment) async {
    await initialize();
    final current = _database!.getAttachment(attachment.id) ?? attachment;
    if (hasUsableLocalAttachmentPath(current.localPath)) {
      return true;
    }
    if (current.localPath != null && current.localPath!.isNotEmpty) {
      _database!.updateAttachmentLocalPath(
        attachmentId: current.id,
        localPath: null,
        downloadError: 'Local file is missing.',
      );
      _refreshFromDb();
    }
    return false;
  }

  Future<ChatAttachment?> resolveAttachmentForPreview(
    ChatAttachment attachment,
  ) async {
    await initialize();
    final current = _database!.getAttachment(attachment.id) ?? attachment;
    final localPath =
        current.localPath ??
        _resolveAttachmentPathFromHistory(
          current,
          ref.read(persistenceProvider).getReceiveHistory().where((entry) => entry.path != null).toList(growable: false),
        );
    if (!hasUsableLocalAttachmentPath(localPath)) {
      if (current.localPath != null && current.localPath!.isNotEmpty) {
        _database!.updateAttachmentLocalPath(
          attachmentId: current.id,
          localPath: null,
          downloadError: 'Local file is missing.',
        );
        _refreshFromDb();
      }
      return null;
    }

    if (current.downloadPending || current.downloadError != null) {
      _database!.updateAttachmentLocalPath(
        attachmentId: current.id,
        localPath: localPath,
        downloadPending: false,
        downloadError: null,
      );
    }
    if (current.fileType == FileType.image) {
      await _ensureThumbnailPath(localPath!, current.id);
    }
    _refreshFromDb();

    return _database!.getAttachment(current.id);
  }

  bool consumePendingAttachmentDownload({
    required String senderFingerprint,
    required Iterable<FileDto> files,
  }) {
    _prunePendingAttachmentDownloads();
    final fileList = files.toList(growable: false);
    if (fileList.length != 1) {
      return false;
    }

    final file = fileList.single;
    for (final entry in _pendingAttachmentDownloads.entries) {
      final attachment = entry.value.attachment;
      if (attachment.sourceFingerprint == senderFingerprint &&
          attachment.fileName == file.fileName &&
          attachment.size == file.size &&
          attachment.fileType == file.fileType) {
        _pendingAttachmentDownloads.remove(entry.key);
        return true;
      }
    }

    return false;
  }

  Future<void> openLocalAttachment(
    BuildContext context,
    ChatAttachment attachment,
  ) async {
    final resolvedAttachment = await resolveAttachmentForPreview(attachment);
    final localPath = resolvedAttachment?.localPath;
    if (localPath == null) {
      state = state.copyWith(errorMessage: 'Local file path is unavailable.');
      return;
    }

    final file = File(localPath);

    if (checkPlatformIsDesktop() && !localPath.startsWith('content://') && file.existsSync()) {
      await openFolder(
        folderPath: file.parent.path,
        fileName: localPath.fileName,
      );
    } else {
      if (!context.mounted) {
        return;
      }
      await openFile(context, attachment.fileType, localPath);
    }
    state = state.copyWith(errorMessage: null);
  }

  Future<void> _syncDevice(Device device, int sinceSentAt) async {
    final response = await _client!.post(
      ApiRoute.chatSync.target(device),
      body: HttpBody.json({
        'roomId': defaultChatRoomId,
        'sinceSentAt': sinceSentAt,
        'sender': _deviceToJson(ref.read(deviceFullInfoProvider)),
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawMessages = body['messages'];
    if (rawMessages is! List) {
      return;
    }
    for (final raw in rawMessages) {
      if (raw is Map<String, dynamic>) {
        _database!.upsertMessage(ChatMessage.fromJson(raw));
      } else if (raw is Map) {
        _database!.upsertMessage(
          ChatMessage.fromJson(Map<String, dynamic>.from(raw)),
        );
      }
    }
  }

  Future<void> _notifyOnlineMembers() async {
    final members = _database!.getMembers().map((member) => member.fingerprint).toSet();
    final sender = ref.read(deviceFullInfoProvider);
    for (final device in ref.read(nearbyDevicesProvider).allDevices.values) {
      if (device.ip == null || !members.contains(device.fingerprint)) {
        continue;
      }

      try {
        await _client!.post(
          ApiRoute.chatNotify.target(device),
          body: HttpBody.json({'sender': _deviceToJson(sender)}),
        );
      } catch (e, st) {
        _logger.info(
          'Could not notify ${device.alias} about chat updates',
          e,
          st,
        );
      }
    }
  }

  Future<void> _syncAndRecord(Device device, int sinceSentAt) async {
    await _syncDevice(device, sinceSentAt);
    _database!.updateMemberLastSync(
      device.fingerprint,
      DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  bool _isChatMember(String fingerprint) {
    return _database!.getMembers().any(
      (member) => member.fingerprint == fingerprint,
    );
  }

  Device? _findOnlineDevice(String fingerprint) {
    final devices = ref.read(nearbyDevicesProvider).allDevices.values;
    for (final device in devices) {
      if (device.fingerprint == fingerprint && _isUsableIp(device.ip)) {
        return device;
      }
    }
    return null;
  }

  void _rememberPendingAttachmentDownload(ChatAttachment attachment) {
    _pendingAttachmentDownloads[_pendingAttachmentKey(
      attachment,
    )] = _PendingAttachmentDownload(
      attachment: attachment,
      requestedAt: DateTime.now(),
    );
  }

  void _forgetPendingAttachmentDownload(ChatAttachment attachment) {
    _pendingAttachmentDownloads.remove(_pendingAttachmentKey(attachment));
  }

  void _prunePendingAttachmentDownloads() {
    final now = DateTime.now();
    _pendingAttachmentDownloads.removeWhere(
      (_, pending) => now.difference(pending.requestedAt) > _pendingAttachmentDownloadTimeout,
    );
  }

  String _pendingAttachmentKey(ChatAttachment attachment) {
    return '${attachment.sourceFingerprint}:${attachment.remoteFileId}';
  }

  void _refreshFromDb() {
    final db = _database;
    if (db == null) {
      return;
    }
    state = state.copyWith(
      members: db.getMembers(),
      messages: db.getMessages(),
      errorMessage: null,
    );
  }

  bool isMemberOnline(String fingerprint) {
    final device = _findOnlineDevice(fingerprint);
    return device?.ip != null;
  }

  List<Device> onlineNonMemberDevices() {
    final memberFingerprints = _database?.getMembers().map((member) => member.fingerprint).toSet() ?? {};
    final seenFingerprints = <String>{};
    final devices = <Device>[];
    for (final device in ref.read(nearbyDevicesProvider).allDevices.values) {
      if (device.ip == null || device.fingerprint == ref.read(deviceFullInfoProvider).fingerprint) {
        continue;
      }
      if (memberFingerprints.contains(device.fingerprint) || !seenFingerprints.add(device.fingerprint)) {
        continue;
      }
      devices.add(device);
    }
    devices.sort(
      (a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()),
    );
    return devices;
  }
}

class _PendingAttachmentDownload {
  final ChatAttachment attachment;
  final DateTime requestedAt;

  const _PendingAttachmentDownload({
    required this.attachment,
    required this.requestedAt,
  });
}

Map<String, dynamic> _deviceToJson(Device device) {
  return {
    'ip': device.ip,
    'version': device.version,
    'port': device.port,
    'https': device.https,
    'fingerprint': device.fingerprint,
    'alias': device.alias,
    'deviceModel': device.deviceModel,
    'deviceType': device.deviceType.name,
  };
}

Device deviceFromChatJson(
  Map<String, dynamic> json, {
  String? fallbackIp,
  bool preferFallbackIp = false,
}) {
  final jsonIp = json['ip'] as String?;
  return Device(
    signalingId: null,
    ip: preferFallbackIp && _isUsableIp(fallbackIp)
        ? fallbackIp
        : _isUsableIp(jsonIp)
        ? jsonIp
        : fallbackIp,
    version: json['version'] as String? ?? '2.0',
    port: (json['port'] as num).toInt(),
    https: json['https'] as bool? ?? false,
    fingerprint: json['fingerprint'] as String,
    alias: json['alias'] as String,
    deviceModel: json['deviceModel'] as String?,
    deviceType: DeviceType.values.firstWhere(
      (type) => type.name == json['deviceType'],
      orElse: () => DeviceType.desktop,
    ),
    download: false,
    discoveryMethods: const {},
  );
}

bool _isUsableIp(String? ip) {
  return ip != null && ip.isNotEmpty && ip != '-';
}
