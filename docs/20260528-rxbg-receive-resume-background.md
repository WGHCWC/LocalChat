# Receive Resume and Background Assessment

Change ID: 20260528-rxbg

## Existing Receive Flow

The receiver installs v1/v2 routes in `ReceiveController.installRoutes`.

- `POST /prepare-upload` rejects concurrent receive sessions, validates the optional PIN, creates a `ReceiveSessionState`, and either waits for user selection or quick-saves accepted files.
- The accepted response contains a generated receiver `sessionId` and a map of accepted `fileId -> token`.
- `POST /upload` requires `fileId`, `token`, and v2 `sessionId`, then streams the request into `saveFile`.
- `saveFile` writes directly to the final destination or Android SAF/gallery cache path, emits progress, and deletes the destination on write failure.
- When every accepted file is finished or failed, the receive session moves to `finished` or `finishedWithErrors`.

## Fixed Receive Failure

The sender parsed the receiver response but accidentally shadowed the local `sessionId` variable with the receiver session id, then updated the send-session map using the receiver id as the local key. That left `remoteSessionId` unset, so later v2 upload requests omitted the required `sessionId` query parameter. The receiver rejected those uploads with `400 Missing parameters`.

The safe fix is to keep the local send-session key unchanged and store the receiver id in `remoteSessionId`.

## Resume Assessment

Current protocol support is not enough for safe resumable uploads.

- `PrepareUploadRequestDto` carries sender info and file metadata only.
- `PrepareUploadResponseDto` carries receiver `sessionId` and accepted `fileId -> token` only.
- `POST /upload` uses only `sessionId`, `fileId`, and `token`; there is no offset, range, chunk id, checksum window, upload id, or partial-file negotiation.
- Receive state tracks only file status/progress/path after completion, not durable partial-byte state.
- `saveFile` chooses a unique destination path and deletes the destination on failure, so an interrupted write leaves no resumable artifact by design.
- Android SAF and gallery writes are stream sessions; random access append/resume is not available through the current abstraction.

Minimum safe resume design:

1. Add a protocol capability flag so old peers continue using the current one-shot upload.
2. Extend prepare response with per-file resume metadata, at least `offset`, `uploadId`, and an integrity marker for the partial prefix.
3. Write incoming data to a durable temporary partial path, not the final target path.
4. Validate partial length and checksum before accepting a resumed suffix.
5. Finalize with atomic rename where possible; keep SAF/gallery as non-resumable until a platform-specific append strategy exists.
6. Persist receive-session partial metadata across app restarts only after the wire protocol and storage model are explicit.

This change intentionally does not implement resumable transfer because doing so without protocol and storage changes would create silent file corruption risks.

## Background Receive Assessment

Current background behavior is limited to the app process staying alive.

- Desktop platforms can keep the server alive while the process remains running; tray integration can reveal the app for incoming requests.
- Android/iOS may suspend or kill the Dart isolate after backgrounding; a reliable long receive requires platform services.
- macOS/Windows/Linux do not need the same mobile background service model, but sleep, app quit, and sandbox file access still interrupt transfers.

Minimum safe background receive plan:

1. Android: add a foreground service with a persistent transfer notification, bind the HTTP receive server lifetime to that service during active receive sessions, and request notification permission where required.
2. iOS: support only bounded background time for already-started transfers via `beginBackgroundTask`; document that indefinite LAN receiving in the background is not supported by iOS without a permitted background mode.
3. macOS/Windows/Linux: keep the current process/tray model, add user-visible transfer notification/state, and avoid closing active receive sessions when windows are hidden.
4. Add lifecycle logging around `paused`, `inactive`, `resumed`, and `detached` while a receive session is active.
5. Add platform tests/manual checks for app backgrounding during an active transfer before claiming background receive support.

This change does not claim full background receive support; it fixes the active v2 upload failure first.
