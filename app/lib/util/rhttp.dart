import 'package:common/isolate.dart';
import 'package:common/model/stored_security_context.dart';
import 'package:logging/logging.dart';
import 'package:rhttp/rhttp.dart';

final _logger = Logger('RhttpWrapper');

class RhttpWrapper implements CustomHttpClient {
  final RhttpClient _client;

  RhttpWrapper._(this._client);

  factory RhttpWrapper.create(Duration timeout, StoredSecurityContext securityContext) {
    final client = createRhttpClient(timeout, securityContext);
    return RhttpWrapper._(client);
  }

  @override
  Future<String> get({
    required String uri,
    required Map<String, String> query,
  }) async {
    final response = await _client.get(
      uri,
      query: query,
    );
    return response.body;
  }

  @override
  Future<String> post({
    required String uri,
    Map<String, String> query = const {},
    required Map<String, dynamic> json,
  }) async {
    final response = await _client.post(
      uri,
      query: query,
      body: HttpBody.json(json),
    );
    return response.body;
  }

  @override
  Future<void> postStream({
    required String uri,
    required Map<String, String> query,
    required Map<String, String> headers,
    required Stream<List<int>> stream,
    required void Function(double progress) onSendProgress,
    required CustomCancelToken cancelToken,
  }) async {
    final token = CancelToken();
    cancelToken.setCancel(token.cancel);
    final length = int.parse(headers['Content-Length']!);
    _logger.info(
      'postStream start uri=$uri query=${_redactQuery(query)} length=$length headers=$headers',
    );
    try {
      await _client.request(
        method: HttpMethod.post,
        expectBody: HttpExpectBody.bytes,
        url: uri,
        query: query,
        headers: HttpHeaders.rawMap(headers),
        body: HttpBody.stream(
          stream,
          length: length,
        ),
        onSendProgress: (curr, total) {
          _logger.fine('postStream progress uri=$uri curr=$curr total=$total');
          onSendProgress(curr / total);
        },
        cancelToken: token,
      );
      _logger.info('postStream completed uri=$uri');
    } catch (e, st) {
      _logger.warning('postStream failed uri=$uri query=${_redactQuery(query)}', e, st);
      rethrow;
    }
  }
}

RhttpClient createRhttpClient(Duration timeout, StoredSecurityContext securityContext, {Interceptor? interceptor}) {
  return RhttpClient.createSync(
    settings: ClientSettings(
      proxySettings: const ProxySettings.noProxy(),
      timeoutSettings: TimeoutSettings(
        timeout: timeout,
      ),
      tlsSettings: TlsSettings(
        verifyCertificates: false,
        clientCertificate: ClientCertificate(
          certificate: securityContext.certificate,
          privateKey: securityContext.privateKey,
        ),
      ),
    ),
    interceptors: interceptor != null ? [interceptor] : [],
  );
}

Map<String, String> _redactQuery(Map<String, String> query) {
  return {
    for (final entry in query.entries) entry.key: entry.key == 'token' ? '<${entry.value.length} chars>' : entry.value,
  };
}
