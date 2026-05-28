import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:common/api_route_builder.dart';
import 'package:common/model/device.dart';
import 'package:common/model/file_type.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/provider/chat/chat_database.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/security_provider.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/rhttp.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:rhttp/rhttp.dart';
import 'package:uuid/uuid.dart';

final _logger = Logger('Chat');
const _uuid = Uuid();

final chatProvider = NotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});

class ChatNotifier extends Notifier<ChatState> {
  ChatDatabase? _database;
  RhttpClient? _client;

  @override
  ChatState init() {
    return ChatState.initial;
  }

  Future<void> initialize() async {
    if (state.initialized) {
      return;
    }

    _database ??= await ChatDatabase.open();
    _client ??= createRhttpClient(const Duration(seconds: 10), ref.read(securityProvider));
    _refreshFromDb();
    state = state.copyWith(initialized: true);
  }

  Future<void> addMember(Device device) async {
    await initialize();
    _database!.upsertMember(ChatMember.fromDevice(device));
    _refreshFromDb();
  }

  Future<void> removeMember(String fingerprint) async {
    await initialize();
    _database!.deleteMember(fingerprint);
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
      Uint8List? thumbnail = file.thumbnail;
      if (thumbnail == null && file.fileType == FileType.image && file.bytes != null) {
        thumbnail = await _buildThumbnail(file.bytes!);
      }
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
          localPath: file.path,
          thumbnail: thumbnail,
          downloadPending: false,
          downloadError: null,
          createdAt: now,
        ),
      );
      _database!.upsertMessage(message);
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
      await refreshOnlineMembers();
      final sinceSentAt = _database!.getMaxSentAt();
      final onlineByFingerprint = {
        for (final device in ref.read(nearbyDevicesProvider).allDevices.values)
          if (device.ip != null) device.fingerprint: device,
      };

      for (final member in _database!.getMembers()) {
        final device = onlineByFingerprint[member.fingerprint];
        if (device == null || device.ip == null) {
          continue;
        }
        try {
          await _syncAndRecord(device, sinceSentAt);
        } catch (e, st) {
          _logger.info('Could not sync chat with ${device.alias}', e, st);
        }
      }
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
    final attachment = message.attachment;
    if (attachment != null && attachment.fileType == FileType.image) {
      final localPath = attachment.localPath;
      if (attachment.thumbnail == null && localPath != null) {
        final thumbnail = await _buildThumbnailBytesFromFile(localPath);
        if (thumbnail != null) {
          _database!.upsertMessage(
            message.copyWith(
              attachment: attachment.copyWith(
                thumbnail: thumbnail,
              ),
            ),
          );
          _refreshFromDb();
          return;
        }
      }
    }
    _database!.upsertMessage(message);
    _refreshFromDb();
  }

  Future<void> handleIncomingNotification(Device sender) async {
    await initialize();
    if (!_isChatMember(sender.fingerprint)) {
      _logger.fine('Ignoring chat notification from non-member ${sender.alias}');
      return;
    }

    _database!.upsertMember(ChatMember.fromDevice(sender));
    try {
      await _syncAndRecord(sender, _database!.getMaxSentAt());
      _refreshFromDb();
    } catch (e, st) {
      _logger.info('Could not sync chat after notification from ${sender.alias}', e, st);
    }
  }

  Future<List<ChatMessage>> messagesNewerThan(int sentAt) async {
    await initialize();
    return _database!.getMessagesNewerThan(sentAt);
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

    final source = _findOnlineDevice(attachment.sourceFingerprint);
    if (source == null || source.ip == null) {
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
    try {
      await _client!.post(
        url,
        body: HttpBody.json({
          'attachmentId': attachment.id,
          'requester': _deviceToJson(requester),
        }),
      );
      state = state.copyWith(errorMessage: null);
    } catch (e, st) {
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
    if (localPath != null && attachment.fileType == FileType.image && attachment.thumbnail == null && !localPath.startsWith('content://')) {
      final thumbnail = await _buildThumbnailBytesFromFile(localPath);
      if (thumbnail != null) {
        _database!.updateAttachmentThumbnail(
          attachmentId: attachment.id,
          thumbnail: thumbnail,
        );
      }
    }
    _refreshFromDb();
  }

  Future<Uint8List?> _buildThumbnailBytesFromFile(String path) async {
    if (!path.startsWith('content://')) {
      final file = File(path);
      if (!file.existsSync()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return _buildThumbnail(bytes);
    }
    return null;
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

  Future<bool> serveAttachmentDownload(String attachmentId, Device requester) async {
    await initialize();
    final attachment = _database!.getAttachment(attachmentId);
    if (attachment == null || attachment.localPath == null) {
      return false;
    }

    final file = File(attachment.localPath!);
    if (!file.existsSync()) {
      return false;
    }

    await ref
        .notifier(sendProvider)
        .startSession(
          target: requester,
          files: [
            CrossFile(
              name: attachment.fileName,
              fileType: attachment.fileType,
              size: await file.length(),
              thumbnail: null,
              asset: null,
              path: attachment.localPath,
              bytes: null,
              lastModified: file.lastModifiedSync().toUtc(),
              lastAccessed: file.lastAccessedSync().toUtc(),
            ),
          ],
          background: true,
        );
    return true;
  }

  Future<bool> hasLocalAttachmentFile(ChatAttachment attachment) async {
    await initialize();
    final localPath = attachment.localPath;
    if (localPath == null) {
      return false;
    }
    if (localPath.startsWith('content://')) {
      return true;
    }
    final exists = File(localPath).existsSync();
    if (!exists) {
      _database!.updateAttachmentLocalPath(
        attachmentId: attachment.id,
        localPath: null,
        downloadError: 'Local file is missing.',
      );
      _refreshFromDb();
    }
    return exists;
  }

  Future<void> openLocalAttachment(BuildContext context, ChatAttachment attachment) async {
    final localPath = attachment.localPath;
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
        _database!.upsertMessage(ChatMessage.fromJson(Map<String, dynamic>.from(raw)));
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
          body: HttpBody.json({
            'sender': _deviceToJson(sender),
          }),
        );
      } catch (e, st) {
        _logger.info('Could not notify ${device.alias} about chat updates', e, st);
      }
    }
  }

  Future<void> _syncAndRecord(Device device, int sinceSentAt) async {
    await _syncDevice(device, sinceSentAt);
    _database!.updateMemberLastSync(device.fingerprint, DateTime.now().toUtc().millisecondsSinceEpoch);
  }

  bool _isChatMember(String fingerprint) {
    return _database!.getMembers().any((member) => member.fingerprint == fingerprint);
  }

  Device? _findOnlineDevice(String fingerprint) {
    final devices = ref.read(nearbyDevicesProvider).allDevices.values;
    for (final device in devices) {
      if (device.fingerprint == fingerprint && device.ip != null) {
        return device;
      }
    }
    return null;
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

Device deviceFromChatJson(Map<String, dynamic> json, {String? fallbackIp}) {
  return Device(
    signalingId: null,
    ip: json['ip'] as String? ?? fallbackIp,
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
