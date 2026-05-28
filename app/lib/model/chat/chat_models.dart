import 'package:common/model/device.dart';
import 'package:common/model/file_type.dart';

const defaultChatRoomId = 'default';

enum ChatMessageKind {
  text,
  attachment,
}

extension ChatMessageKindWire on ChatMessageKind {
  String get wireName => name;

  static ChatMessageKind fromWire(String value) {
    return ChatMessageKind.values.firstWhere(
      (kind) => kind.wireName == value,
      orElse: () => ChatMessageKind.text,
    );
  }
}

extension FileTypeWire on FileType {
  String get wireName => name;

  static FileType fromWire(String value) {
    return FileType.values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => FileType.other,
    );
  }
}

class ChatMember {
  final String fingerprint;
  final String alias;
  final String? ip;
  final int port;
  final bool https;
  final String version;
  final String? deviceModel;
  final DeviceType deviceType;
  final int addedAt;
  final int? lastSyncAt;

  const ChatMember({
    required this.fingerprint,
    required this.alias,
    required this.ip,
    required this.port,
    required this.https,
    required this.version,
    required this.deviceModel,
    required this.deviceType,
    required this.addedAt,
    required this.lastSyncAt,
  });

  factory ChatMember.fromDevice(Device device) {
    return ChatMember(
      fingerprint: device.fingerprint,
      alias: device.alias,
      ip: device.ip,
      port: device.port,
      https: device.https,
      version: device.version,
      deviceModel: device.deviceModel,
      deviceType: device.deviceType,
      addedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      lastSyncAt: null,
    );
  }

  Device toDevice() {
    return Device(
      signalingId: null,
      ip: ip,
      version: version,
      port: port,
      https: https,
      fingerprint: fingerprint,
      alias: alias,
      deviceModel: deviceModel,
      deviceType: deviceType,
      download: false,
      discoveryMethods: const {},
    );
  }

  ChatMember copyWith({
    String? alias,
    String? ip,
    int? port,
    bool? https,
    String? version,
    String? deviceModel,
    DeviceType? deviceType,
    int? addedAt,
    int? lastSyncAt,
  }) {
    return ChatMember(
      fingerprint: fingerprint,
      alias: alias ?? this.alias,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      https: https ?? this.https,
      version: version ?? this.version,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceType: deviceType ?? this.deviceType,
      addedAt: addedAt ?? this.addedAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }
}

class ChatAttachment {
  final String id;
  final String messageId;
  final String fileName;
  final int size;
  final FileType fileType;
  final String sourceFingerprint;
  final String remoteFileId;
  final String? localPath;
  final String? thumbnailPath;
  final bool downloadPending;
  final String? downloadError;
  final int createdAt;

  const ChatAttachment({
    required this.id,
    required this.messageId,
    required this.fileName,
    required this.size,
    required this.fileType,
    required this.sourceFingerprint,
    required this.remoteFileId,
    required this.localPath,
    required this.thumbnailPath,
    required this.downloadPending,
    required this.downloadError,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'messageId': messageId,
      'fileName': fileName,
      'size': size,
      'fileType': fileType.wireName,
      'sourceFingerprint': sourceFingerprint,
      'remoteFileId': remoteFileId,
      'createdAt': createdAt,
    };
  }

  static ChatAttachment fromJson(Map<String, dynamic> json, {String? localPath}) {
    return ChatAttachment(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      fileName: json['fileName'] as String,
      size: _asInt(json['size']),
      fileType: FileTypeWire.fromWire(json['fileType'] as String? ?? ''),
      sourceFingerprint: json['sourceFingerprint'] as String,
      remoteFileId: json['remoteFileId'] as String,
      localPath: localPath,
      thumbnailPath: null,
      downloadPending: false,
      downloadError: null,
      createdAt: _asInt(json['createdAt']),
    );
  }

  ChatAttachment copyWith({
    String? messageId,
    String? sourceFingerprint,
    String? localPath,
    String? thumbnailPath,
    bool? downloadPending,
    String? downloadError,
  }) {
    return ChatAttachment(
      id: id,
      messageId: messageId ?? this.messageId,
      fileName: fileName,
      size: size,
      fileType: fileType,
      sourceFingerprint: sourceFingerprint ?? this.sourceFingerprint,
      remoteFileId: remoteFileId,
      localPath: localPath ?? this.localPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      downloadPending: downloadPending ?? this.downloadPending,
      downloadError: downloadError ?? this.downloadError,
      createdAt: createdAt,
    );
  }
}

class ChatMessage {
  final String id;
  final String roomId;
  final String senderFingerprint;
  final String senderAlias;
  final ChatMessageKind kind;
  final String? text;
  final int sentAt;
  final int receivedAt;
  final ChatAttachment? attachment;

  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderFingerprint,
    required this.senderAlias,
    required this.kind,
    required this.text,
    required this.sentAt,
    required this.receivedAt,
    required this.attachment,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roomId': roomId,
      'senderFingerprint': senderFingerprint,
      'senderAlias': senderAlias,
      'kind': kind.wireName,
      'text': text,
      'sentAt': sentAt,
      'attachment': attachment?.toJson(),
    };
  }

  static ChatMessage fromJson(Map<String, dynamic> json) {
    final attachmentJson = json['attachment'];
    return ChatMessage(
      id: json['id'] as String,
      roomId: json['roomId'] as String? ?? defaultChatRoomId,
      senderFingerprint: json['senderFingerprint'] as String,
      senderAlias: json['senderAlias'] as String,
      kind: ChatMessageKindWire.fromWire(json['kind'] as String? ?? ''),
      text: json['text'] as String?,
      sentAt: _asInt(json['sentAt']),
      receivedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      attachment: attachmentJson is Map<String, dynamic> ? ChatAttachment.fromJson(attachmentJson) : null,
    );
  }

  ChatMessage copyWith({
    int? receivedAt,
    ChatAttachment? attachment,
  }) {
    return ChatMessage(
      id: id,
      roomId: roomId,
      senderFingerprint: senderFingerprint,
      senderAlias: senderAlias,
      kind: kind,
      text: text,
      sentAt: sentAt,
      receivedAt: receivedAt ?? this.receivedAt,
      attachment: attachment ?? this.attachment,
    );
  }

  bool get hasImageAttachment => attachment?.fileType == FileType.image;
}

int _asInt(Object? value) {
  return (value as num).toInt();
}

class ChatState {
  final bool initialized;
  final bool syncing;
  final List<ChatMember> members;
  final List<ChatMessage> messages;
  final String? errorMessage;

  const ChatState({
    required this.initialized,
    required this.syncing,
    required this.members,
    required this.messages,
    required this.errorMessage,
  });

  static const initial = ChatState(
    initialized: false,
    syncing: false,
    members: [],
    messages: [],
    errorMessage: null,
  );

  ChatState copyWith({
    bool? initialized,
    bool? syncing,
    List<ChatMember>? members,
    List<ChatMessage>? messages,
    String? errorMessage,
  }) {
    return ChatState(
      initialized: initialized ?? this.initialized,
      syncing: syncing ?? this.syncing,
      members: members ?? this.members,
      messages: messages ?? this.messages,
      errorMessage: errorMessage,
    );
  }
}
