import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'charset.dart';
import 'rule_engine.dart';
import 'url_template.dart';
import '../legacy_transport.dart';
import '../online_component.dart';

class BookSourceResponse {
  const BookSourceResponse({
    required this.url,
    required this.body,
    required this.status,
  });

  final String url;
  final String body;
  final int status;
}

typedef BookSourceFetcher =
    Future<BookSourceResponse> Function(BookSourceRequestSpec request);

/// Bounded HTTP used by custom sources. Cookies stay in memory for this
/// process and are only sent back to the same host.
class BookSourceHttp {
  BookSourceHttp({HttpClient Function()? clientFactory})
    : _factory = clientFactory ?? HttpClient.new;

  static final shared = BookSourceHttp();
  final HttpClient Function() _factory;
  HttpClient? _client;
  final _cookies = <String, Map<String, String>>{};
  static const maxBytes = 2 * 1024 * 1024;

  /// Book-source collections are often several MiB; the 2 MiB default is
  /// for chapter pages, not for importing a whole collection by URL.
  static const importMaxBytes = 16 * 1024 * 1024;

  Future<BookSourceResponse> send(
    BookSourceRequestSpec spec, {
    int limitBytes = maxBytes,
  }) async {
    final bytes = await _request(
      spec.url,
      method: spec.method,
      body: spec.body == null
          ? null
          : encodeBookSourceText(spec.body!, spec.charset),
      headers: spec.headers,
      contentType: _contentType(spec),
      limitBytes: limitBytes,
    );
    final detected = bytes.charset;
    final charset = _explicitCharset(spec.charset)
        ? spec.charset
        : (detected == null || detected.isEmpty ? spec.charset : detected);
    return BookSourceResponse(
      url: bytes.url,
      body: decodeBookSourceText(bytes.bytes, charset),
      status: bytes.status,
    );
  }

  Future<Uint8List> getBytes(String url, {Map<String, String>? headers}) async {
    final response = await _request(
      url,
      method: 'GET',
      headers: {'User-Agent': bookSourceUserAgent, ...?headers},
    );
    return Uint8List.fromList(response.bytes);
  }

  /// Wenku8 keeps its own image loader. A missing online component falls back
  /// to a direct request so custom-source pictures can still be cached.
  static Future<Uint8List> directIllustration(String url) async {
    try {
      return await LegacyTransport.illustration(url, cacheForViewing: false);
    } on OnlineComponentUnavailable {
      return shared.getBytes(url);
    }
  }

  Future<({String url, List<int> bytes, int status, String? charset})> _request(
    String url, {
    required String method,
    List<int>? body,
    required Map<String, String> headers,
    String? contentType,
    int limitBytes = maxBytes,
  }) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      throw const BookSourceRuleException('书源链接必须是 http 或 https');
    }
    var uri = parsed;
    final client = _client ??= _factory()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 15);
    var currentMethod = method;
    List<int>? currentBody = body;
    for (var hop = 0; hop < 5; hop++) {
      final request = await client
          .openUrl(currentMethod, uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      final sent = Map<String, String>.from(headers);
      sent.putIfAbsent('User-Agent', () => bookSourceUserAgent);
      sent.forEach(request.headers.set);
      final cookie = _cookieHeader(uri);
      if (cookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      if (contentType != null && currentBody != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (currentBody != null &&
          currentMethod != 'GET' &&
          currentMethod != 'HEAD') {
        request.contentLength = currentBody.length;
        request.add(currentBody);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      _storeCookies(uri, response.headers[HttpHeaders.setCookieHeader]);
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.isEmpty) {
          throw BookSourceRuleException(
            '书源重定向缺少地址（HTTP ${response.statusCode}）',
          );
        }
        uri = uri.resolve(location);
        if (uri.userInfo.isNotEmpty ||
            (uri.scheme != 'http' && uri.scheme != 'https')) {
          throw const BookSourceRuleException('书源重定向到了不支持的地址');
        }
        if (response.statusCode != 307 && response.statusCode != 308) {
          currentMethod = 'GET';
          currentBody = null;
        }
        continue;
      }
      final collected = await _read(response, limitBytes);
      if (response.statusCode >= 400) {
        throw BookSourceRuleException('书源请求失败（HTTP ${response.statusCode}）');
      }
      return (
        url: uri.toString(),
        bytes: collected,
        status: response.statusCode,
        charset:
            response.headers.contentType?.charset ?? _metaCharset(collected),
      );
    }
    throw const BookSourceRuleException('书源重定向次数过多');
  }

  Future<List<int>> _read(HttpClientResponse response, int limitBytes) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > limitBytes) {
        throw const BookSourceRuleException('书源响应过大');
      }
    }
    return builder.takeBytes();
  }

  void _storeCookies(Uri uri, List<String>? values) {
    if (values == null || values.isEmpty) return;
    final jar = _cookies.putIfAbsent(uri.host, () => {});
    for (final value in values) {
      final pair = value.split(';').first.trim();
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      jar[pair.substring(0, index).trim()] = pair.substring(index + 1).trim();
    }
  }

  String _cookieHeader(Uri uri) {
    final jar = _cookies[uri.host];
    if (jar == null || jar.isEmpty) return '';
    return jar.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  bool _isRedirect(int status) =>
      const {301, 302, 303, 307, 308}.contains(status);

  bool _explicitCharset(String charset) {
    final name = charset.trim().toLowerCase();
    return name.isNotEmpty && name != 'utf-8' && name != 'utf8';
  }

  String? _contentType(BookSourceRequestSpec spec) {
    final existing = spec.headers.keys.any(
      (key) => key.toLowerCase() == 'content-type',
    );
    if (existing || spec.body == null) return null;
    final trimmed = spec.body!.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return 'application/json; charset=${spec.charset}';
    }
    return 'application/x-www-form-urlencoded; charset=${spec.charset}';
  }

  String? _metaCharset(List<int> bytes) {
    final preview = latin1.decode(
      bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes,
    );
    final match = RegExp(
      r'charset\s*=\s*["\x27]?([\w-]+)',
      caseSensitive: false,
    ).firstMatch(preview);
    return match?.group(1);
  }
}
