import 'package:common/api_route_builder.dart';
import 'package:common/model/device.dart';
import 'package:common/src/isolate/child/http_provider.dart';
import 'package:logging/logging.dart';
import 'package:refena/refena.dart';

final _logger = Logger('HttpUploadService');

final httpUploadProvider = ViewProvider((ref) {
  final client = ref.watch(httpProvider).longLiving;
  return HttpUploadService(client);
});

class HttpUploadService {
  final CustomHttpClient _client;

  HttpUploadService(this._client);

  Future<void> upload({
    required Stream<List<int>> stream,
    required int contentLength,
    required String contentType,
    required Device target,
    required String? remoteSessionId,
    required String fileId,
    required String token,
    required void Function(double) onSendProgress,
    required CustomCancelToken cancelToken,
  }) async {
    final uri = ApiRoute.upload.target(target);
    final query = {
      if (remoteSessionId != null) 'sessionId': remoteSessionId,
      'fileId': fileId,
      'token': token,
    };
    _logger.info(
      'POST stream upload uri=$uri query=${_redactQuery(query)} target=${_debugDevice(target)} '
      'contentLength=$contentLength contentType=$contentType',
    );
    await _client.postStream(
      uri: uri,
      query: query,
      headers: {
        'Content-Length': contentLength.toString(),
        'Content-Type': contentType,
      },
      stream: stream,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    _logger.info('POST stream upload completed uri=$uri fileId=$fileId');
  }
}

String _debugDevice(Device device) {
  return 'alias=${device.alias}, ip=${device.ip}, port=${device.port}, https=${device.https}, '
      'version=${device.version}, fingerprint=${device.fingerprint}, '
      'methods=${device.discoveryMethods.map((e) => e.runtimeType).join('|')}';
}

Map<String, String> _redactQuery(Map<String, String> query) {
  return {
    for (final entry in query.entries)
      entry.key: entry.key == 'token'
          ? '<${entry.value.length} chars>'
          : entry.value,
  };
}
