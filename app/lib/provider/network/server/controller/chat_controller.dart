import 'dart:convert';
import 'dart:io';

import 'package:common/api_route_builder.dart';
import 'package:localsend_app/model/chat/chat_models.dart';
import 'package:localsend_app/provider/chat/chat_provider.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/util/simple_server.dart';

class ChatController {
  final ServerUtils server;

  ChatController(this.server);

  void installRoutes({
    required SimpleServerRouteBuilder router,
  }) {
    router.post(ApiRoute.chatSync.v2, (HttpRequest request) async {
      final payload = await _readJson(request);
      if (payload == null) {
        return await request.respondJson(400, message: 'Invalid JSON.');
      }
      final sinceSentAt = payload['sinceSentAt'];
      if (sinceSentAt is! num) {
        return await request.respondJson(400, message: 'Missing sinceSentAt.');
      }

      final messages = await server.ref.notifier(chatProvider).messagesNewerThan(sinceSentAt.toInt());
      return await request.respondJson(
        200,
        body: {
          'messages': messages.map((message) => message.toJson()).toList(growable: false),
        },
      );
    });

    router.post(ApiRoute.chatNotify.v2, (HttpRequest request) async {
      final payload = await _readJson(request);
      if (payload == null) {
        return await request.respondJson(400, message: 'Invalid JSON.');
      }
      final senderRaw = payload['sender'];
      if (senderRaw is! Map) {
        return await request.respondJson(400, message: 'Missing sender.');
      }

      final sender = deviceFromChatJson(Map<String, dynamic>.from(senderRaw), fallbackIp: request.ip);
      await server.ref.notifier(chatProvider).handleIncomingNotification(sender);
      return await request.respondJson(202);
    });

    router.post(ApiRoute.chatMessage.v2, (HttpRequest request) async {
      final payload = await _readJson(request);
      if (payload == null) {
        return await request.respondJson(400, message: 'Invalid JSON.');
      }
      final messageRaw = payload['message'];
      if (messageRaw is! Map) {
        return await request.respondJson(400, message: 'Missing message.');
      }

      await server.ref.notifier(chatProvider).receiveMessage(ChatMessage.fromJson(Map<String, dynamic>.from(messageRaw)));
      return await request.respondJson(204);
    });

    router.post(ApiRoute.chatAttachment.v2, (HttpRequest request) async {
      final payload = await _readJson(request);
      if (payload == null) {
        return await request.respondJson(400, message: 'Invalid JSON.');
      }
      final attachmentId = payload['attachmentId'];
      final requesterRaw = payload['requester'];
      if (attachmentId is! String || requesterRaw is! Map) {
        return await request.respondJson(400, message: 'Missing attachment request data.');
      }

      final requester = deviceFromChatJson(Map<String, dynamic>.from(requesterRaw), fallbackIp: request.ip);
      final accepted = await server.ref.notifier(chatProvider).serveAttachmentDownload(attachmentId, requester);
      if (!accepted) {
        return await request.respondJson(404, message: 'Attachment is not available on this device.');
      }

      return await request.respondJson(202);
    });
  }

  Future<Map<String, dynamic>?> _readJson(HttpRequest request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
