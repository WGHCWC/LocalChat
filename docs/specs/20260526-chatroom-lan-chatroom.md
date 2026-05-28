# LAN Chatroom Spec: 20260526-chatroom

## Scope
Add a local-network chatroom to the Flutter app. The chatroom lets a user add or remove discovered LAN devices, exchange text messages, announce image/file attachments, and synchronize history directly with online peers.

## Functional Requirements
- Add a Chat tab in the main home UI.
- The chat UI should behave like an IM conversation page: entering the chat shows the message timeline first, not a management surface.
- Add a top-right menu button for chat actions and member management.
- Member add/remove flows should live behind the top-right menu instead of occupying the main timeline area.
- Persist chatroom members, messages, and attachment metadata in SQLite.
- On app start and when entering the Chat tab, reuse LocalSend discovery to check which chat members are online, then synchronize messages with online members by P2P HTTP requests.
- Synchronization is incremental: the local device sends its known maximum message send time, and the peer returns only messages whose send time is newer than that value.
- Real-time delivery should avoid polling: when device A sends a new message, it actively notifies online chat members, and each notified peer then pulls only messages newer than its local maximum `sentAt`.
- Store messages idempotently by stable message ID so repeated syncs do not create duplicates.
- Render messages ordered by `sentAt`, then by local receive time as a deterministic fallback.
- Text messages store text content in SQLite.
- Image/file messages store metadata only in SQLite: file name, size, type, source device, remote file ID, optional local path.
- Image/file bytes are not downloaded during sync.
- The composer should support IM-style message sending and file sending from the same conversation page.
- When the user clicks an attachment, trigger the existing LocalSend transfer/download flow instead of implementing an eager background downloader.
- While the chat page is open and devices are online, new messages from other online devices should appear on the chat page automatically without requiring a manual sync action.

## Non-Goals
- No public relay service, account system, or cloud sync.
- No changes to generated Rust bridge files.
- No replacement of existing send/receive file-transfer behavior.
- No full multi-room UX beyond one default LAN chatroom in this change.

## Acceptance Criteria
- A user can open the Chat tab, add/remove online LAN devices, send text, and see persisted history after restart.
- Opening the Chat tab lands directly on the conversation timeline.
- Member management is reachable from the top-right menu.
- A sync request only asks peers for messages newer than the local maximum send time.
- Message insertion is deduplicated by ID.
- Attachment records appear in the chat without downloading their bytes.
- Attachment download uses the existing send-provider session path when the source file is local and online.
- Existing receive/send tabs continue to build.
