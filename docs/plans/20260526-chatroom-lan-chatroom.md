# LAN Chatroom Plan: 20260526-chatroom

## Implementation Plan
1. Add SQLite dependencies and a chat data layer with schema, models, and repository APIs.
2. Add P2P chat HTTP routes for incremental sync and incoming message ingestion.
3. Add a Refena chat provider that manages members, history, sending, sync, and attachment download dispatch.
4. Replace the prototype chat tab with an IM-style conversation UI, with a top-right menu for member management and sync actions.
5. Initialize chat sync on app start and on Chat tab entry, reusing existing online discovery before message sync.
6. Add sender-triggered foreground auto-sync for the active chat page: online peers receive a lightweight notification and then perform incremental pull sync without polling.
7. Run dependency resolution, formatting, analyzer or targeted tests where feasible.

## Risk Notes
- Attachment download can only reuse the original transfer flow when the source device still has a local path for the attachment and is online.
- Device clocks may differ. The requested sync rule uses send time as the high-water mark; message ID dedupe remains necessary.
- SQLite support is added for app platforms supported by the chosen Flutter SQLite plugin. Web is not targeted by this feature.
