import 'dart:convert';

import 'rule_engine.dart';

/// One HTTP call described by a Legado `searchUrl` (or a chapter/detail URL).
class BookSourceRequestSpec {
  const BookSourceRequestSpec({
    required this.url,
    this.method = 'GET',
    this.body,
    this.charset = 'utf-8',
    this.headers = const {},
  });

  final String url;
  final String method;
  final String? body;
  final String charset;
  final Map<String, String> headers;
}

const bookSourceUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// Fills `{{key}}`, `{{page}}` and simple `{{page±n}}` / `{{page*n}}` templates.
///
/// [encode] chooses how `{{key}}` is escaped: query-component, JSON string
/// contents, or the raw keyword.
String fillBookSourceTemplate(
  String input, {
  required String key,
  required int page,
  TemplateEncode encode = TemplateEncode.query,
  String Function(String expression)? script,
}) {
  return input.replaceAllMapped(_template, (match) {
    final expr = match.group(1)!.trim();
    if (script != null &&
        expr != 'key' &&
        expr != 'searchKey' &&
        expr != 'keyword' &&
        expr != 'page' &&
        _pageMath.firstMatch(expr) == null) {
      return script(expr);
    }
    if (expr.contains(';') ||
        expr.contains('java.') ||
        expr.startsWith('@') ||
        expr.startsWith('<')) {
      throw BookSourceRuleException('不支持 URL 中的 JavaScript 模板 {{$expr}}');
    }
    if (expr == 'key' || expr == 'searchKey' || expr == 'keyword') {
      return switch (encode) {
        TemplateEncode.query => Uri.encodeQueryComponent(key),
        TemplateEncode.jsonString => _jsonStringContents(key),
        TemplateEncode.raw => key,
      };
    }
    if (expr == 'page') return '$page';
    final math = _pageMath.firstMatch(expr);
    if (math != null) {
      final n = int.parse(math.group(2)!);
      final value = switch (math.group(1)) {
        '+' => page + n,
        '-' => page - n,
        '*' => page * n,
        _ => page,
      };
      return value < 0 ? '0' : '$value';
    }
    throw BookSourceRuleException('不支持的 URL 模板 {{$expr}}');
  });
}

enum TemplateEncode { query, jsonString, raw }

String resolveBookSourceUrl(String base, String relative) {
  final value = relative.trim();
  if (value.isEmpty) return value;
  final lower = value.toLowerCase();
  if (lower.startsWith('javascript:') || lower.startsWith('data:')) {
    throw const BookSourceRuleException('不支持的链接');
  }
  if (value.startsWith('//')) {
    final scheme = Uri.tryParse(base)?.scheme ?? 'https';
    return _checked('$scheme:$value');
  }
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) return _checked(parsed.toString());
  final baseUri = Uri.tryParse(base);
  if (baseUri == null || !baseUri.hasScheme) {
    throw const BookSourceRuleException('无法解析相对链接');
  }
  return _checked(baseUri.resolve(value).toString());
}

String canonicalBookSourceUrl(String url) {
  final trimmed = url.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return trimmed;
  var path = uri.path;
  if (path == '/') {
    path = '';
  } else if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return uri.replace(path: path).removeFragment().toString();
}

Map<String, String> parseHeaderMap(Object? header) {
  if (header == null) return {};
  if (header is Map) {
    return {
      for (final entry in header.entries)
        if ('${entry.value}'.isNotEmpty) '${entry.key}': '${entry.value}',
    };
  }
  if (header is! String || header.trim().isEmpty) return {};
  final trimmed = header.trim();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return parseHeaderMap(decoded);
    } on FormatException {
      throw const BookSourceRuleException('书源 header 不是合法 JSON');
    }
  }
  final map = <String, String>{};
  for (final line in trimmed.split(RegExp(r'\r?\n'))) {
    final index = line.indexOf(':');
    if (index <= 0) continue;
    final name = line.substring(0, index).trim();
    final value = line.substring(index + 1).trim();
    if (name.isNotEmpty) map[name] = value;
  }
  return map;
}

/// Legado searchUrl is a URL, `url,{json}`, a JSON object, or several of those
/// separated by newlines or `&&`.
List<BookSourceRequestSpec> parseSearchRequests({
  required String searchUrl,
  required String sourceUrl,
  required Map<String, String> sourceHeaders,
  required String key,
  required int page,
  String Function(String expression)? script,
}) {
  final targets = _splitTargets(searchUrl);
  if (targets.isEmpty) {
    throw const BookSourceRuleException('书源没有搜索地址');
  }
  return [
    for (final target in targets)
      _oneRequest(
        target,
        sourceUrl: sourceUrl,
        sourceHeaders: sourceHeaders,
        key: key,
        page: page,
        script: script,
      ),
  ];
}

bool searchUrlUsesPage(String searchUrl) => searchUrl.contains('{{page');

List<String> _splitTargets(String searchUrl) {
  final normalized = searchUrl.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) return const [];
  if (normalized.startsWith('{')) return [normalized];
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  for (var i = 0; i < normalized.length; i++) {
    final char = normalized[i];
    if (char == '{') depth++;
    if (char == '}') depth = depth > 0 ? depth - 1 : 0;
    final split =
        depth == 0 && (char == '\n' || normalized.startsWith('&&', i));
    if (split) {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) parts.add(text);
      buffer.clear();
      if (char != '\n') i++;
      continue;
    }
    buffer.write(char);
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) parts.add(tail);
  return parts;
}

BookSourceRequestSpec _oneRequest(
  String target, {
  required String sourceUrl,
  required Map<String, String> sourceHeaders,
  required String key,
  required int page,
  String Function(String expression)? script,
}) {
  String url;
  var method = 'GET';
  String? body;
  var charset = 'utf-8';
  final headers = Map<String, String>.from(sourceHeaders);
  if (target.trimLeft().startsWith('{')) {
    final map = _decodeOptions(target);
    url = '${map['url'] ?? ''}';
    method = '${map['method'] ?? method}';
    body = map['body']?.toString();
    charset = '${map['charset'] ?? charset}';
    headers.addAll(parseHeaderMap(map['headers']));
    _rejectWebView(map);
  } else {
    final marker = target.indexOf(',{');
    if (marker > 0) {
      url = target.substring(0, marker);
      final map = _decodeOptions(target.substring(marker + 1));
      method = '${map['method'] ?? method}';
      body = map['body']?.toString();
      charset = '${map['charset'] ?? charset}';
      headers.addAll(parseHeaderMap(map['headers']));
      _rejectWebView(map);
    } else {
      url = target;
    }
  }
  final bodyEncode = body != null && _looksLikeJson(body)
      ? TemplateEncode.jsonString
      : TemplateEncode.query;
  final filledUrl = fillBookSourceTemplate(
    url,
    key: key,
    page: page,
    encode: TemplateEncode.query,
    script: script,
  );
  final filledBody = body == null
      ? null
      : fillBookSourceTemplate(
          body,
          key: key,
          page: page,
          encode: bodyEncode,
          script: script,
        );
  final resolved = resolveBookSourceUrl(
    sourceUrl,
    filledUrl.isEmpty ? sourceUrl : filledUrl,
  );
  method = method.trim().toUpperCase();
  if (method.isEmpty) method = 'GET';
  if (filledBody != null && filledBody.isNotEmpty && method == 'GET') {
    method = 'POST';
  }
  if (!{'GET', 'POST', 'PUT', 'HEAD'}.contains(method)) {
    throw BookSourceRuleException('不支持的请求方法 $method');
  }
  headers.putIfAbsent('User-Agent', () => bookSourceUserAgent);
  return BookSourceRequestSpec(
    url: resolved,
    method: method,
    body: filledBody,
    charset: charset.trim().isEmpty ? 'utf-8' : charset.trim(),
    headers: headers,
  );
}

Map<String, dynamic> _decodeOptions(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const BookSourceRuleException('搜索选项必须是 JSON 对象');
    }
    return decoded.map((key, value) => MapEntry('$key', value));
  } on BookSourceRuleException {
    rethrow;
  } on FormatException {
    throw const BookSourceRuleException('搜索地址中的 JSON 选项无法解析');
  }
}

void _rejectWebView(Map<String, dynamic> map) {
  final webView = map['webView'];
  if (webView == true || webView == 'true' || webView == 1) {
    throw const BookSourceRuleException('不支持 webView / JavaScript 书源请求');
  }
}

bool _looksLikeJson(String body) {
  final trimmed = body.trimLeft();
  return trimmed.startsWith('{') || trimmed.startsWith('[');
}

String _jsonStringContents(String value) {
  final encoded = jsonEncode(value);
  return encoded.substring(1, encoded.length - 1);
}

String _checked(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const BookSourceRuleException('书源链接必须是 http 或 https');
  }
  return uri.toString();
}

final _template = RegExp(r'\{\{\s*([^{}]+?)\s*\}\}');
final _pageMath = RegExp(r'^page\s*([+\-*])\s*(\d+)$');
