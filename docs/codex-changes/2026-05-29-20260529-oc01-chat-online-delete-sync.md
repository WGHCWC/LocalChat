# Change Record: 20260529-oc01

## Date
2026-05-29

## Summary
Updated chat room status and sync behavior: the app bar now shows online members over total chat members using the same online predicate as User management, message deletion records a persistent deletion watermark used as the lower bound for future sync snapshots, and pure HTTP/HTTPS text messages can be opened in the system browser.

## Task Type
fix

## Base Branch
feature/20260526-chatroom-lan-chatroom

## Worktree Branch
fix/20260529-oc01-chat-online-delete-sync

## Worktree Path
/Users/chenwei/Documents/project2/localsend-20260526-chatroom/.worktree/20260529-oc01-chat-online-delete-sync

## Files Changed
- app/lib/pages/tabs/chat_tab.dart
- app/lib/provider/chat/chat_database.dart
- app/lib/provider/chat/chat_provider.dart
- app/test/unit/provider/chat_database_test.dart

## Checks Run
- `dart format lib/pages/tabs/chat_tab.dart lib/provider/chat/chat_database.dart lib/provider/chat/chat_provider.dart test/unit/provider/chat_database_test.dart` - passed
- `flutter test test/unit/provider/chat_database_test.dart` - passed
- `flutter analyze lib/pages/tabs/chat_tab.dart lib/provider/chat/chat_database.dart lib/provider/chat/chat_provider.dart test/unit/provider/chat_database_test.dart` - passed
- `git diff --check` - passed

## Related Commits
- ce9d1cf7 `fix(20260529-oc01): improve chat online and sync behavior`
- <this change record commit> `docs(20260529-oc01): record chat online sync fix`

## Risks / Follow-ups
- The deletion watermark intentionally prevents older messages from being re-fetched after local deletion; devices with clock skew can still affect ordering for newly created messages.
- Link opening is limited to full-message HTTP/HTTPS URLs to avoid treating arbitrary text fragments or non-web schemes as browser links.

## Merge Action
Run `git merge --ff-only fix/20260529-oc01-chat-online-delete-sync` from `feature/20260526-chatroom-lan-chatroom`, advancing the target branch from `2cf25c1c` to the fix branch head that includes this change record.
