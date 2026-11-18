import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_js/flutter_js.dart';

import 'explore.dart';
import 'js_http.dart';
import 'model.dart';
import 'rule_engine.dart';
import 'url_template.dart';

class JsContext {
  const JsContext({
    this.result = '',
    this.baseUrl = '',
    this.key = '',
    this.page = 1,
    this.book = const {},
    this.chapter = const {},
  });

  final String result;
  final String baseUrl;
  final String key;
  final int page;
  final Map<String, Object?> book;
  final Map<String, Object?> chapter;
}

class PreparedRule {
  const PreparedRule(this.text, {required this.done});

  final String text;
  final bool done;
}

class BookSourceScripts {
  BookSourceScripts({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;
  final _sessions = <String, _JsSession>{};

  _JsSession _session(BookSource source) =>
      _sessions.putIfAbsent(source.url, () => _JsSession(source, timeout));

  PreparedRule prepare(BookSource source, String rule, JsContext context) {
    if (!ruleHasScript(rule)) return PreparedRule(rule, done: false);
    final session = _session(source);
    final trimmed = rule.trim();
    final block = RegExp(r'^<js>([\s\S]*)</js>$').firstMatch(trimmed);
    if (block != null) {
      return PreparedRule(session.eval(block.group(1)!, context), done: true);
    }
    if (trimmed.startsWith('@js:')) {
      return PreparedRule(
        session.eval(trimmed.substring(4), context),
        done: true,
      );
    }
    final only = RegExp(r'^\{\{([\s\S]*)\}\}$').firstMatch(trimmed);
    if (only != null) {
      return PreparedRule(session.eval(only.group(1)!, context), done: true);
    }
    final expanded = trimmed
        .replaceAllMapped(RegExp(r'<js>([\s\S]*?)</js>'), (match) {
          return session.eval(match.group(1)!, context);
        })
        .replaceAllMapped(RegExp(r'\{\{([\s\S]*?)\}\}'), (match) {
          return session.eval(match.group(1)!, context);
        });
    return PreparedRule(expanded, done: false);
  }

  String eval(BookSource source, String code, JsContext context) =>
      _session(source).eval(code, context);

  Object? evalRaw(BookSource source, String code, JsContext context) =>
      _session(source).evalRaw(code, context);

  List<ExploreKind> kinds(BookSource source) {
    final raw = source.exploreUrl.trim();
    if (raw.isEmpty) return const [];
    final text = ruleHasScript(raw)
        ? prepare(source, raw, JsContext(baseUrl: source.url)).text
        : raw;
    return parseExploreKinds(text);
  }
}

bool ruleHasScript(String rule) =>
    rule.contains('<js>') || rule.contains('@js:') || rule.contains('{{');

class _JsSession {
  _JsSession(this.source, this.timeout) {
    _runtime = QuickJsRuntime2(timeout: timeout.inMilliseconds);
    _runtime.onMessage('legado', _message);
    _runtime.evaluate(_bridge);
    final library = source.jsLib.trim();
    if (library.isNotEmpty) {
      final loaded = _runtime.evaluate(library);
      if (loaded.isError) {
        throw BookSourceRuleException('书源 jsLib 无法执行：${loaded.stringResult}');
      }
    }
  }

  final BookSource source;
  final Duration timeout;
  late final JavascriptRuntime _runtime;
  final _variables = <String, String>{};
  final _cookies = <String, String>{};

  String eval(String code, JsContext context) {
    final raw = evalRaw(code, context);
    if (raw == null || raw == 'null') return '';
    if (raw is String) return raw;
    return '$raw';
  }

  Object? evalRaw(String code, JsContext context) {
    final body = code.trim();
    final script =
        '''
var result = ${jsonEncode(context.result)};
var baseUrl = ${jsonEncode(context.baseUrl)};
var key = ${jsonEncode(context.key)};
var page = ${context.page};
var book = ${jsonEncode(context.book)};
var chapter = ${jsonEncode(context.chapter)};
source.bookSourceUrl = ${jsonEncode(source.url)};
source.bookSourceName = ${jsonEncode(source.name)};
${RegExp(r'\breturn\b').hasMatch(body) ? '(function(){\n$body\n})()' : body}
''';
    final value = _runtime.evaluate(script);
    if (value.isError) {
      throw BookSourceRuleException(_clean(value.stringResult));
    }
    return value.rawResult;
  }

  dynamic _message(dynamic args) {
    try {
      return _dispatch(args);
    } catch (error) {
      final message = error is FormatException ? error.message : '$error';
      return {'__error': message};
    }
  }

  dynamic _dispatch(dynamic args) {
    final map = args is Map ? args : const {};
    final op = '${map['op']}';
    final payload = map['payload'];
    final data = payload is Map ? payload : const {};
    switch (op) {
      case 'get':
        return _variables['${data['key']}'] ?? '';
      case 'put':
        _variables['${data['key']}'] = '${data['value']}';
        return '';
      case 'base64Encode':
        return base64.encode(utf8.encode('${data['text']}'));
      case 'base64Decode':
        try {
          return utf8.decode(base64.decode('${data['text']}'));
        } on FormatException {
          throw const BookSourceRuleException('java.base64Decode 无法解码');
        }
      case 'md5':
        return md5.convert(utf8.encode('${data['text']}')).toString();
      case 'time':
        return _time(data['a'], data['b']);
      case 'getString':
        return _strings('${data['html']}', '${data['rule']}').join('\n');
      case 'getElements':
        return _nodes(
          '${data['html']}',
          '${data['rule']}',
        ).map((node) => node.raw).toList();
      case 'sourceKey':
        return source.url;
      case 'getCookie':
        return _cookies['${data['key']}'] ?? '';
      case 'setCookie':
        _cookies['${data['key']}'] = '${data['value']}';
        return '';
      case 'cookieHeader':
        return jsCookieHeader(_cookies);
      case 'ajax':
        return _ajax(data);
      case 'log':
        return '';
      default:
        throw BookSourceRuleException('不支持的 Java 方法 java.$op');
    }
  }

  String _ajax(Map<dynamic, dynamic> data) {
    final nested = data['url'];
    var url = '';
    var method = 'GET';
    String? body;
    final headers = <String, String>{};
    if (nested is Map) {
      url = '${nested['url'] ?? ''}';
      method = '${nested['method'] ?? method}';
      body = nested['body']?.toString();
      headers.addAll(_headers(nested['headers']));
    } else {
      url = '$nested';
      headers.addAll(_headers(data['headers']));
    }
    if (url.startsWith('/')) {
      url = resolveBookSourceUrl(source.url, url);
    }
    return JsBlockingHttp.request(
      url: url,
      method: method,
      body: body,
      headers: headers,
      cookie: jsCookieHeader(_cookies),
      timeout: timeout,
    );
  }

  Map<String, String> _headers(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries) '${entry.key}': '${entry.value}',
    };
  }

  List<String> _strings(String html, String rule) => const RuleEngine().strings(
    rule,
    RuleNode.parse(html, baseUrl: source.url),
  );

  List<RuleNode> _nodes(String html, String rule) =>
      const RuleEngine().nodes(rule, RuleNode.parse(html, baseUrl: source.url));

  String _time(Object? first, Object? second) {
    var clock = DateTime.now();
    var pattern = 'yyyy-MM-dd HH:mm:ss';
    if (first is num) {
      clock = DateTime.fromMillisecondsSinceEpoch(first.toInt());
      if (second != null) pattern = '$second';
    } else if (first is String && first.isNotEmpty) {
      pattern = first;
    }
    final y = clock.year.toString().padLeft(4, '0');
    final m = clock.month.toString().padLeft(2, '0');
    final d = clock.day.toString().padLeft(2, '0');
    final h = clock.hour.toString().padLeft(2, '0');
    final min = clock.minute.toString().padLeft(2, '0');
    final s = clock.second.toString().padLeft(2, '0');
    return pattern
        .replaceAll('yyyy', y)
        .replaceAll('MM', m)
        .replaceAll('dd', d)
        .replaceAll('HH', h)
        .replaceAll('mm', min)
        .replaceAll('ss', s);
  }

  String _clean(String message) {
    final text = message.trim();
    if (text.isEmpty) return 'JS 规则执行失败';
    if (text.contains('interrupted') || text.contains('timeout')) {
      return 'JS 执行超时';
    }
    return text;
  }
}

const _bridge = r'''
function __legado(op, payload) {
  var value = sendMessage('legado', JSON.stringify({op: op, payload: payload}));
  if (value && value.__error) throw new Error(String(value.__error));
  return value;
}
var java = {
  ajax: function(url, second) {
    if (url && typeof url === 'object') return __legado('ajax', {url: url});
    return __legado('ajax', {url: url, headers: second || null});
  },
  get: function(key) { return __legado('get', {key: String(key)}); },
  put: function(key, value) { return __legado('put', {key: String(key), value: String(value)}); },
  base64Encode: function(text) { return __legado('base64Encode', {text: String(text)}); },
  base64Decode: function(text) { return __legado('base64Decode', {text: String(text)}); },
  md5Encode: function(text) { return __legado('md5', {text: String(text)}); },
  timeFormat: function(a, b) { return __legado('time', {a: a == null ? null : a, b: b == null ? null : String(b)}); },
  getString: function(html, rule) {
    if (arguments.length < 2) { rule = html; html = typeof result === 'undefined' ? '' : result; }
    return __legado('getString', {html: String(html), rule: String(rule)});
  },
  getElements: function(html, rule) {
    if (arguments.length < 2) { rule = html; html = typeof result === 'undefined' ? '' : result; }
    return __legado('getElements', {html: String(html), rule: String(rule)});
  },
  getCookie: function(key) { return __legado('getCookie', {key: String(key)}); },
  setCookie: function(key, value) { return __legado('setCookie', {key: String(key), value: String(value)}); },
  log: function(message) { return __legado('log', {message: String(message)}); }
};
if (typeof Proxy === 'function') {
  java = new Proxy(java, {
    get: function(target, prop) {
      if (prop in target) return target[prop];
      return function() {
        throw new Error('不支持的 Java 方法 java.' + String(prop));
      };
    }
  });
}
var cookie = {
  getKey: function(url, key) { return java.getCookie(key); },
  get: function(url) { return __legado('cookieHeader', {}); },
  put: function(url, key, value) { java.setCookie(key, String(value)); }
};
var source = {
  getKey: function() { return __legado('sourceKey', {}); },
  getVariable: function(key) { return java.get(key); },
  setVariable: function(key, value) { java.put(key, value); },
  bookSourceUrl: '',
  bookSourceName: ''
};
''';
