import 'package:common/model/device.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/provider/chat/chat_database.dart';
import 'package:localsend_app/provider/chat/chat_sync.dart';
import 'package:test/test.dart';

void main() {
  group('ChatDatabase', () {
    late ChatDatabase database;

    setUp(() {
      database = ChatDatabase.openInMemoryForTest();
    });

    tearDown(() {
      database.close();
    });

    test('returns messages sent at or after the sync timestamp', () {
      database.upsertMessage(_message(id: 'before', sentAt: 999));
      database.upsertMessage(_message(id: 'edge', sentAt: 1000));
      database.upsertMessage(_message(id: 'after', sentAt: 1001));

      final messages = database.getMessagesAtOrAfter(1000);

      expect(messages.map((message) => message.id), ['edge', 'after']);
    });

    test('deduplicates inclusive sync results by message id', () {
      final message = _message(id: 'same-id', sentAt: 1000);

      database.upsertMessage(message);
      database.upsertMessage(message);

      final messages = database.getMessagesAtOrAfter(1000);

      expect(messages.map((message) => message.id), ['same-id']);
    });

    test('uses the deletion watermark when it is newer than messages', () {
      database.upsertMessage(_message(id: 'before-delete', sentAt: 1000));

      database.recordMessageDeleteAt(1500);
      database.recordMessageDeleteAt(1200);

      expect(database.getLastMessageDeleteAt(), 1500);
      expect(database.getSyncSnapshotSentAt(), 1500);
    });

    test('records the deletion watermark with message deletion', () {
      database.upsertMessage(_message(id: 'deleted', sentAt: 1000));

      database.deleteMessagesByIds(['deleted'], deletedAt: 1500);

      expect(database.getMessages(), isEmpty);
      expect(database.getLastMessageDeleteAt(), 1500);
      expect(database.getSyncSnapshotSentAt(), 1500);
    });

    test('uses the latest message time when it is newer than deletions', () {
      database.recordMessageDeleteAt(1500);
      database.upsertMessage(_message(id: 'after-delete', sentAt: 1800));

      expect(database.getSyncSnapshotSentAt(), 1800);
    });
  });

  group('chat sync', () {
    test(
      'uses the same snapshot timestamp for every device in a sync round',
      () async {
        var maxSentAt = 1000;
        var maxSentAtReads = 0;
        final callOrder = <String>[];
        final first = _device('first');
        final second = _device('second');
        final syncSinceByFingerprint = <String, int>{};

        await syncOnlineChatMembersWithSnapshot(
          refreshOnlineMembers: () async {
            callOrder.add('refresh');
          },
          getSnapshotSentAt: () {
            callOrder.add('snapshot');
            maxSentAtReads++;
            return maxSentAt;
          },
          getMembers: () => [
            ChatMember.fromDevice(first),
            ChatMember.fromDevice(second),
          ],
          getOnlineDevices: () => [first, second],
          syncDevice: (device, sinceSentAt) async {
            syncSinceByFingerprint[device.fingerprint] = sinceSentAt;
            if (device.fingerprint == first.fingerprint) {
              maxSentAt = 2000;
            }
          },
          onDeviceError: (device, error, stackTrace) {
            fail('Unexpected sync error for ${device.fingerprint}: $error');
          },
        );

        expect(callOrder, ['snapshot', 'refresh']);
        expect(maxSentAtReads, 1);
        expect(syncSinceByFingerprint, {
          first.fingerprint: 1000,
          second.fingerprint: 1000,
        });
      },
    );
  });
}

ChatMessage _message({required String id, required int sentAt}) {
  return ChatMessage(
    id: id,
    roomId: defaultChatRoomId,
    senderFingerprint: 'sender',
    senderAlias: 'Sender',
    kind: ChatMessageKind.text,
    text: id,
    sentAt: sentAt,
    receivedAt: sentAt,
    attachment: null,
  );
}

Device _device(String fingerprint) {
  return Device(
    signalingId: null,
    ip: '192.168.1.${fingerprint == 'first' ? '10' : '11'}',
    version: '1.0.0',
    port: 53317,
    https: false,
    fingerprint: fingerprint,
    alias: fingerprint,
    deviceModel: null,
    deviceType: DeviceType.desktop,
    download: false,
    discoveryMethods: const {},
  );
}
