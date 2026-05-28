import 'package:common/model/device.dart';
import 'package:localsend_app/model/chat/chat_models.dart';

typedef RefreshOnlineMembers = Future<void> Function();
typedef GetChatSyncSnapshotSentAt = int Function();
typedef GetChatMembers = Iterable<ChatMember> Function();
typedef GetOnlineDevices = Iterable<Device> Function();
typedef SyncChatDevice = Future<void> Function(Device device, int sinceSentAt);
typedef OnChatSyncDeviceError =
    void Function(
      Device device,
      Object error,
      StackTrace stackTrace,
    );

Future<void> syncOnlineChatMembersWithSnapshot({
  required RefreshOnlineMembers refreshOnlineMembers,
  required GetChatSyncSnapshotSentAt getSnapshotSentAt,
  required GetChatMembers getMembers,
  required GetOnlineDevices getOnlineDevices,
  required SyncChatDevice syncDevice,
  required OnChatSyncDeviceError onDeviceError,
}) async {
  final sinceSentAt = getSnapshotSentAt();
  await refreshOnlineMembers();
  final onlineByFingerprint = {
    for (final device in getOnlineDevices())
      if (device.ip != null) device.fingerprint: device,
  };

  for (final member in getMembers()) {
    final device = onlineByFingerprint[member.fingerprint];
    if (device == null || device.ip == null) {
      continue;
    }

    try {
      await syncDevice(device, sinceSentAt);
    } catch (e, st) {
      onDeviceError(device, e, st);
    }
  }
}
