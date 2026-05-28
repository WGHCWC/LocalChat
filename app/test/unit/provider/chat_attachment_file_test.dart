import 'dart:io';

import 'package:localsend_app/provider/chat/chat_attachment_file.dart';
import 'package:test/test.dart';

void main() {
  group('hasUsableLocalAttachmentPath', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('localsend-chat-attachment-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('is false when no local path is recorded', () {
      expect(hasUsableLocalAttachmentPath(null), isFalse);
    });

    test('is false when the recorded local file no longer exists', () {
      final missingPath = '${tempDir.path}/missing.pdf';

      expect(hasUsableLocalAttachmentPath(missingPath), isFalse);
    });

    test('is true when the recorded local file exists', () {
      final file = File('${tempDir.path}/document.pdf')..writeAsStringSync('pdf');

      expect(hasUsableLocalAttachmentPath(file.path), isTrue);
    });

    test('keeps content uri paths usable', () {
      expect(hasUsableLocalAttachmentPath('content://attachment/1'), isTrue);
    });
  });
}
