# Implementation Plan: Download Manager and Chat Attachment Downloads

Change ID: 20260529-dl01

## Phase 1: Chat Attachment Download Fix

- Use the attachment's `remoteFileId` when requesting a source device to serve an attachment.
- Refresh online members before resolving the source device.
- Treat missing, empty, or placeholder requester IP values as invalid and fall back to the HTTP request IP on the source side.
- Keep errors visible through existing `ChatState.errorMessage`.

## Phase 2: Download Manager UI

- Add a `downloads` home tab.
- Add `DownloadManagerPage`.
- Active section reads `serverProvider.session` and `progressProvider`.
- Completed section reads `receiveHistoryProvider`.
- Chat attachments section reads `chatProvider.messages` and offers re-request only for remote attachments.

## Phase 3: Verification and Documentation

- Run targeted `flutter analyze`.
- Run `common` tests.
- Attempt app tests where practical; record native asset blockers.
- Update docs with remaining protocol/platform risks.

## Deferred Work

- Durable failed/canceled transfer records need a new persistence model.
- Redownloading arbitrary receive-history entries needs source/session metadata that history does not currently store.
- Pause/resume/breakpoint transfer needs protocol capability negotiation, offsets, partial-file validation, and storage changes.
- Reliable Android/iOS background receiving needs platform-specific foreground/background services.
