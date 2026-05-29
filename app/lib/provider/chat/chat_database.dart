import 'dart:io';

import 'package:common/model/device.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class ChatDatabase {
  final Database _db;

  ChatDatabase._(this._db);

  static String _lastMessageDeleteAtKey(String roomId) => 'last_message_delete_at:$roomId';

  static ChatDatabase openInMemoryForTest() {
    final database = ChatDatabase._(sqlite3.openInMemory());
    database._migrate();
    return database;
  }

  static Future<ChatDatabase> open() async {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'localsend'));
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    final db = sqlite3.open(p.join(dbDir.path, 'chat.sqlite'));
    final database = ChatDatabase._(db);
    database._migrate();
    return database;
  }

  void close() {
    _db.close();
  }

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS chat_members (
        fingerprint TEXT PRIMARY KEY,
        alias TEXT NOT NULL,
        ip TEXT,
        port INTEGER NOT NULL,
        https INTEGER NOT NULL,
        version TEXT NOT NULL,
        device_model TEXT,
        device_type TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        last_sync_at INTEGER
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        sender_fingerprint TEXT NOT NULL,
        sender_alias TEXT NOT NULL,
        kind TEXT NOT NULL,
        text TEXT,
        sent_at INTEGER NOT NULL,
        received_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS chat_attachments (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        size INTEGER NOT NULL,
        file_type TEXT NOT NULL,
        source_fingerprint TEXT NOT NULL,
        remote_file_id TEXT NOT NULL,
        local_path TEXT,
        thumbnail_path TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(message_id) REFERENCES chat_messages(id) ON DELETE CASCADE
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS chat_metadata (
        key TEXT PRIMARY KEY,
        int_value INTEGER NOT NULL
      );
    ''');
    _addColumnIfMissing('chat_attachments', 'thumbnail_path', 'TEXT');
    _addColumnIfMissing(
      'chat_attachments',
      'download_pending',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _addColumnIfMissing('chat_attachments', 'download_error', 'TEXT');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_messages_sent_at ON chat_messages(sent_at);',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_attachments_message_id ON chat_attachments(message_id);',
    );
  }

  void _addColumnIfMissing(String table, String column, String definition) {
    final columns = _db.select('PRAGMA table_info($table);').map((row) => row['name']).toSet();
    if (!columns.contains(column)) {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $definition;');
    }
  }

  void updateAttachmentLocalPath({
    required String attachmentId,
    required String? localPath,
    String? thumbnailPath,
    bool downloadPending = false,
    String? downloadError,
  }) {
    _db.execute(
      '''
      UPDATE chat_attachments
      SET local_path = ?, thumbnail_path = COALESCE(?, thumbnail_path), download_pending = ?, download_error = ?
      WHERE id = ?;
      ''',
      [
        localPath,
        thumbnailPath,
        downloadPending ? 1 : 0,
        downloadError,
        attachmentId,
      ],
    );
  }

  void updateAttachmentThumbnailPath({
    required String attachmentId,
    required String thumbnailPath,
  }) {
    _db.execute(
      '''
      UPDATE chat_attachments
      SET thumbnail_path = ?
      WHERE id = ?;
      ''',
      [thumbnailPath, attachmentId],
    );
  }

  ChatAttachment? findAttachmentForReceivedFile({
    required String sourceFingerprint,
    required String fileName,
    required int size,
  }) {
    final rows = _db.select(
      '''
      SELECT
        id AS attachment_id,
        message_id,
        file_name,
        size,
        file_type,
        source_fingerprint,
        remote_file_id,
        local_path,
        thumbnail_path,
        download_pending,
        download_error,
        created_at
      FROM chat_attachments
      WHERE source_fingerprint = ?
        AND file_name = ?
        AND size = ?
      ORDER BY created_at DESC
      LIMIT 1;
      ''',
      [sourceFingerprint, fileName, size],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _attachmentFromRow(rows.first);
  }

  List<ChatMember> getMembers() {
    final rows = _db.select(
      'SELECT * FROM chat_members ORDER BY alias COLLATE NOCASE;',
    );
    return rows.map(_memberFromRow).toList(growable: false);
  }

  void upsertMember(ChatMember member) {
    _db.execute(
      '''
      INSERT INTO chat_members (
        fingerprint, alias, ip, port, https, version, device_model, device_type, added_at, last_sync_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(fingerprint) DO UPDATE SET
        alias = excluded.alias,
        ip = excluded.ip,
        port = excluded.port,
        https = excluded.https,
        version = excluded.version,
        device_model = excluded.device_model,
        device_type = excluded.device_type,
        last_sync_at = COALESCE(excluded.last_sync_at, chat_members.last_sync_at);
      ''',
      [
        member.fingerprint,
        member.alias,
        member.ip,
        member.port,
        member.https ? 1 : 0,
        member.version,
        member.deviceModel,
        member.deviceType.name,
        member.addedAt,
        member.lastSyncAt,
      ],
    );
  }

  void deleteMember(String fingerprint) {
    _db.execute('DELETE FROM chat_members WHERE fingerprint = ?;', [
      fingerprint,
    ]);
  }

  void deleteMessagesByIds(
    Iterable<String> messageIds, {
    int? deletedAt,
  }) {
    final ids = messageIds.toSet();
    if (ids.isEmpty) {
      return;
    }

    _db.execute('BEGIN TRANSACTION;');
    try {
      for (final args in _chunks(ids.toList(growable: false), 900)) {
        final placeholders = List.filled(args.length, '?').join(', ');
        _db.execute(
          'DELETE FROM chat_attachments WHERE message_id IN ($placeholders);',
          args,
        );
        _db.execute(
          'DELETE FROM chat_messages WHERE id IN ($placeholders);',
          args,
        );
      }
      if (deletedAt != null) {
        _recordMessageDeleteAt(deletedAt);
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void recordMessageDeleteAt(
    int deletedAt, {
    String roomId = defaultChatRoomId,
  }) {
    _recordMessageDeleteAt(deletedAt, roomId: roomId);
  }

  void _recordMessageDeleteAt(
    int deletedAt, {
    String roomId = defaultChatRoomId,
  }) {
    _db.execute(
      '''
      INSERT INTO chat_metadata (key, int_value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET
        int_value = MAX(chat_metadata.int_value, excluded.int_value);
      ''',
      [_lastMessageDeleteAtKey(roomId), deletedAt],
    );
  }

  Iterable<List<T>> _chunks<T>(List<T> values, int size) sync* {
    for (var start = 0; start < values.length; start += size) {
      final end = start + size > values.length ? values.length : start + size;
      yield values.sublist(start, end);
    }
  }

  void updateMemberLastSync(String fingerprint, int lastSyncAt) {
    _db.execute(
      'UPDATE chat_members SET last_sync_at = ? WHERE fingerprint = ?;',
      [lastSyncAt, fingerprint],
    );
  }

  List<ChatMessage> getMessages({String roomId = defaultChatRoomId}) {
    final rows = _db.select(
      '''
      SELECT
        m.id AS message_id,
        m.room_id,
        m.sender_fingerprint,
        m.sender_alias,
        m.kind,
        m.text,
        m.sent_at,
        m.received_at,
        a.id AS attachment_id,
        a.file_name,
        a.size,
        a.file_type,
        a.source_fingerprint,
        a.remote_file_id,
        a.local_path,
        a.thumbnail_path,
        a.download_pending,
        a.download_error,
        a.created_at
      FROM chat_messages m
      LEFT JOIN chat_attachments a ON a.message_id = m.id
      WHERE m.room_id = ?
      ORDER BY m.sent_at ASC, m.received_at ASC;
      ''',
      [roomId],
    );
    return rows.map(_messageFromRow).toList(growable: false);
  }

  List<ChatMessage> getMessagesAtOrAfter(
    int sentAt, {
    String roomId = defaultChatRoomId,
  }) {
    final rows = _db.select(
      '''
      SELECT
        m.id AS message_id,
        m.room_id,
        m.sender_fingerprint,
        m.sender_alias,
        m.kind,
        m.text,
        m.sent_at,
        m.received_at,
        a.id AS attachment_id,
        a.file_name,
        a.size,
        a.file_type,
        a.source_fingerprint,
        a.remote_file_id,
        a.local_path,
        a.thumbnail_path,
        a.download_pending,
        a.download_error,
        a.created_at
      FROM chat_messages m
      LEFT JOIN chat_attachments a ON a.message_id = m.id
      WHERE m.room_id = ? AND m.sent_at >= ?
      ORDER BY m.sent_at ASC, m.received_at ASC;
      ''',
      [roomId, sentAt],
    );
    return rows.map(_messageFromRow).toList(growable: false);
  }

  int getMaxSentAt({String roomId = defaultChatRoomId}) {
    final rows = _db.select(
      'SELECT COALESCE(MAX(sent_at), 0) AS max_sent_at FROM chat_messages WHERE room_id = ?;',
      [roomId],
    );
    return _asInt(rows.first['max_sent_at']);
  }

  int getLastMessageDeleteAt({String roomId = defaultChatRoomId}) {
    final rows = _db.select(
      'SELECT int_value FROM chat_metadata WHERE key = ?;',
      [_lastMessageDeleteAtKey(roomId)],
    );
    if (rows.isEmpty) {
      return 0;
    }
    return _asInt(rows.first['int_value']);
  }

  int getSyncSnapshotSentAt({String roomId = defaultChatRoomId}) {
    final maxSentAt = getMaxSentAt(roomId: roomId);
    final lastDeleteAt = getLastMessageDeleteAt(roomId: roomId);
    return maxSentAt > lastDeleteAt ? maxSentAt : lastDeleteAt;
  }

  ChatAttachment? getAttachment(String attachmentId) {
    final rows = _db.select(
      '''
      SELECT
        id AS attachment_id,
        message_id,
        file_name,
        size,
        file_type,
        source_fingerprint,
        remote_file_id,
        local_path,
        thumbnail_path,
        download_pending,
        download_error,
        created_at
      FROM chat_attachments
      WHERE id = ?;
      ''',
      [attachmentId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _attachmentFromRow(rows.first);
  }

  void upsertMessage(ChatMessage message) {
    _db.execute(
      '''
      INSERT OR IGNORE INTO chat_messages (
        id, room_id, sender_fingerprint, sender_alias, kind, text, sent_at, received_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        message.id,
        message.roomId,
        message.senderFingerprint,
        message.senderAlias,
        message.kind.wireName,
        message.text,
        message.sentAt,
        message.receivedAt,
      ],
    );

    final attachment = message.attachment;
    if (attachment != null) {
      _db.execute(
        '''
        INSERT INTO chat_attachments (
          id, message_id, file_name, size, file_type, source_fingerprint, remote_file_id, local_path, thumbnail_path, download_pending, download_error, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          file_name = excluded.file_name,
          size = excluded.size,
          file_type = excluded.file_type,
          source_fingerprint = excluded.source_fingerprint,
          remote_file_id = excluded.remote_file_id,
          local_path = COALESCE(excluded.local_path, chat_attachments.local_path),
          thumbnail_path = COALESCE(excluded.thumbnail_path, chat_attachments.thumbnail_path),
          download_pending = excluded.download_pending,
          download_error = excluded.download_error,
          created_at = excluded.created_at;
        ''',
        [
          attachment.id,
          message.id,
          attachment.fileName,
          attachment.size,
          attachment.fileType.wireName,
          attachment.sourceFingerprint,
          attachment.remoteFileId,
          attachment.localPath,
          attachment.thumbnailPath,
          attachment.downloadPending ? 1 : 0,
          attachment.downloadError,
          attachment.createdAt,
        ],
      );
    }
  }

  ChatMember _memberFromRow(Row row) {
    return ChatMember(
      fingerprint: row['fingerprint'] as String,
      alias: row['alias'] as String,
      ip: row['ip'] as String?,
      port: _asInt(row['port']),
      https: _asInt(row['https']) == 1,
      version: row['version'] as String,
      deviceModel: row['device_model'] as String?,
      deviceType: DeviceType.values.firstWhere(
        (type) => type.name == row['device_type'],
        orElse: () => DeviceType.desktop,
      ),
      addedAt: _asInt(row['added_at']),
      lastSyncAt: _asNullableInt(row['last_sync_at']),
    );
  }

  ChatMessage _messageFromRow(Row row) {
    final attachment = row['attachment_id'] == null ? null : _attachmentFromRow(row);
    return ChatMessage(
      id: row['message_id'] as String,
      roomId: row['room_id'] as String,
      senderFingerprint: row['sender_fingerprint'] as String,
      senderAlias: row['sender_alias'] as String,
      kind: ChatMessageKindWire.fromWire(row['kind'] as String),
      text: row['text'] as String?,
      sentAt: _asInt(row['sent_at']),
      receivedAt: _asInt(row['received_at']),
      attachment: attachment,
    );
  }

  ChatAttachment _attachmentFromRow(Row row) {
    return ChatAttachment(
      id: row['attachment_id'] as String,
      messageId: row['message_id'] as String,
      fileName: row['file_name'] as String,
      size: _asInt(row['size']),
      fileType: FileTypeWire.fromWire(row['file_type'] as String),
      sourceFingerprint: row['source_fingerprint'] as String,
      remoteFileId: row['remote_file_id'] as String,
      localPath: row['local_path'] as String?,
      thumbnailPath: row['thumbnail_path'] as String?,
      downloadPending: _asInt(row['download_pending'] ?? 0) == 1,
      downloadError: row['download_error'] as String?,
      createdAt: _asInt(row['created_at']),
    );
  }

  int _asInt(Object? value) {
    return (value as num).toInt();
  }

  int? _asNullableInt(Object? value) {
    return value == null ? null : _asInt(value);
  }
}
