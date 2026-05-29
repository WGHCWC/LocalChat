# Change Record: 20260529-ip01

## Date
2026-05-29

## Summary
Changed chat image attachments to open through the existing platform file opener instead of the custom chat image preview route. This makes mobile and desktop use the same behavior as the preview page's Open button and avoids the custom zoom boundary issue.

## Task Type
fix

## Base Branch
feature/20260526-chatroom-lan-chatroom

## Worktree Branch
fix/20260529-ip01-mobile-image-preview-zoom

## Worktree Path
/Users/chenwei/Documents/project2/localsend-20260526-chatroom/.worktree/20260529-ip01-mobile-image-preview-zoom

## Files Changed
- app/lib/pages/tabs/chat_tab.dart

## Checks Run
- `dart format app/lib/pages/tabs/chat_tab.dart` - passed
- `flutter analyze app/lib/pages/tabs/chat_tab.dart` - passed, no issues found
- `git diff --check` - passed

## Related Commits
- d0a6508e `fix(20260529-ip01): open chat images with system viewer`

## Risks / Follow-ups
- The change delegates image viewing to the OS/default file opener, so the visual preview experience depends on the platform's configured image viewer.
- Manual device smoke testing should verify tapping a downloaded image message on Android and macOS opens the system preview/viewer.

## Merge Action
After this record is committed, run `git merge --ff-only fix/20260529-ip01-mobile-image-preview-zoom` from `/Users/chenwei/Documents/project2/localsend-20260526-chatroom`, advancing `feature/20260526-chatroom-lan-chatroom` from `2a601c08605f0eeafe29346ec65052eadbd4345d` to the final tip of `fix/20260529-ip01-mobile-image-preview-zoom`.
