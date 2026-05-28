import 'dart:io';

bool hasUsableLocalAttachmentPath(String? localPath) {
  if (localPath == null) {
    return false;
  }
  if (localPath.startsWith('content://')) {
    return true;
  }
  return File(localPath).existsSync();
}
