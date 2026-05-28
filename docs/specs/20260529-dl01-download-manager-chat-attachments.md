# Spec: Download Manager and Chat Attachment Downloads

Change ID: 20260529-dl01

## Objective

Add a download management page and fix chat attachment downloads so tapping a remote attachment either starts a real transfer or reports a clear reason why it cannot start.

## Assumptions

- "Download" in the app means files received by this device, plus remote chat attachments that can be requested from their source device.
- Existing receive history remains the durable source for completed received files.
- Canceled/failed persistent download records need a new transfer-history model; this change may show current failed/canceled session state, but must not invent fake persisted records.
- Pause, resume, true breakpoint transfer, and reliable mobile background download require protocol/native service work and must not be represented as working UI controls until implemented.

## Tech Stack

- Flutter/Dart UI.
- Refena providers.
- Existing `serverProvider`, `sendProvider`, `progressProvider`, `receiveHistoryProvider`, and `chatProvider`.
- Existing LocalSend HTTP upload protocol for the actual file transfer.

## Commands

- Dependencies: `cd app && flutter pub get`
- Analyze: `cd app && flutter analyze lib/pages/download_manager_page.dart lib/pages/home_page.dart lib/provider/chat/chat_provider.dart lib/provider/network/server/controller/chat_controller.dart lib/provider/network/send_provider.dart lib/provider/network/server/controller/receive_controller.dart`
- Common tests: `cd common && dart test`

## Project Structure

- `app/lib/pages/download_manager_page.dart`: new UI.
- `app/lib/pages/home_page.dart`: navigation entry.
- `app/lib/provider/chat/chat_provider.dart`: attachment request fixes.
- `docs/plans/20260529-dl01-download-manager-chat-attachments.md`: implementation plan.

## Boundaries

- Always: only enable actions when there is enough state to execute them.
- Always: preserve existing send, receive, chat sync, and user-management behavior.
- Ask first: protocol changes, native foreground/background services, new dependencies, or generated localization rebuilds.
- Never: fake pause/resume/breakpoint support by changing UI state only.

## Success Criteria

- Downloads tab opens a real page.
- Current receive session appears with per-file progress and cancel action.
- Completed receive history appears with open/reveal/delete actions.
- Remote chat attachments without a local path appear with a request-download action.
- Tapping a remote chat attachment refreshes online members and sends a real request to the source if reachable.
- If the source is offline or unavailable, the chat page shows a clear error.
- Pause/resume/breakpoint controls are not shown unless backed by real protocol support.
