import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'rule_engine.dart';
import 'url_template.dart';

/// Synchronous HTTP for `java.ajax`. QuickJS calls back into Dart without an
/// event loop, so the request cannot be a Future.
class JsBlockingHttp {
  const JsBlockingHttp._();

  static String request({
    required String url,
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
    String? cookie,
    Duration timeout = const Duration(seconds: 8),
  }) {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      throw const BookSourceRuleException('java.ajax 只接受 http 或 https');
    }
    if (Platform.isAndroid) {
      return _android(url: url, method: method, body: body, cookie: cookie);
    }
    return _curl(
      url: url,
      method: method,
      body: body,
      headers: headers,
      cookie: cookie,
      timeout: timeout,
    );
  }
}

String _curl({
  required String url,
  required String method,
  required String? body,
  required Map<String, String> headers,
  required String? cookie,
  required Duration timeout,
}) {
  final marker = '\x1e';
  final args = <String>[
    '-sS',
    '-L',
    '--max-redirs',
    '5',
    '--max-time',
    '${timeout.inSeconds.clamp(1, 60)}',
    '-A',
    bookSourceUserAgent,
    '-X',
    method.trim().isEmpty ? 'GET' : method.trim().toUpperCase(),
    '-w',
    '$marker%{http_code}',
  ];
  headers.forEach((name, value) {
    args.addAll(['-H', '$name: $value']);
  });
  if (cookie != null && cookie.isNotEmpty) {
    args.addAll(['-H', 'Cookie: $cookie']);
  }
  if (body != null && body.isNotEmpty) {
    args.addAll(['--data-binary', body]);
  }
  args.add(url);
  final result = Process.runSync('curl', args);
  if (result.exitCode != 0 && '${result.stdout}'.isEmpty) {
    final error = '${result.stderr}'.trim();
    throw BookSourceRuleException(
      error.isEmpty ? 'java.ajax 失败' : 'java.ajax 失败：$error',
    );
  }
  final text = '${result.stdout}';
  final split = text.lastIndexOf(marker);
  if (split < 0) return text;
  final status = int.tryParse(text.substring(split + marker.length).trim());
  final payload = text.substring(0, split);
  if (status != null && status >= 400 && payload.isEmpty) {
    throw BookSourceRuleException('java.ajax HTTP $status');
  }
  return payload;
}

String _android({
  required String url,
  required String method,
  required String? body,
  required String? cookie,
}) {
  final lib = DynamicLibrary.open('libwenku_mobi.so');
  final ajax = lib.lookupFunction<_AjaxNative, _AjaxDart>('legado_ajax');
  final free = lib.lookupFunction<_FreeNative, _FreeDart>('legado_free');
  final urlNative = url.toNativeUtf8();
  final methodNative = method.toNativeUtf8();
  final bodyNative = (body ?? '').toNativeUtf8();
  final cookieNative = (cookie ?? '').toNativeUtf8();
  final pointer = ajax(
    urlNative.cast(),
    methodNative.cast(),
    bodyNative.cast(),
    cookieNative.cast(),
  );
  calloc.free(urlNative);
  calloc.free(methodNative);
  calloc.free(bodyNative);
  calloc.free(cookieNative);
  if (pointer == nullptr) {
    throw const BookSourceRuleException('java.ajax 没有返回');
  }
  final text = pointer.cast<Utf8>().toDartString();
  free(pointer);
  const marker = '\x1e';
  if (!text.startsWith(marker)) return text;
  final second = text.indexOf(marker, 1);
  if (second < 0) return text;
  final status = text.substring(1, second);
  final payload = text.substring(second + 1);
  if (status == 'ERR') {
    throw BookSourceRuleException(payload.isEmpty ? 'java.ajax 失败' : payload);
  }
  return payload;
}

typedef _AjaxNative =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _AjaxDart =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

String jsCookieHeader(Map<String, String> jar) => jar.entries
    .where((entry) => entry.value.isNotEmpty)
    .map((entry) => '${entry.key}=${entry.value}')
    .join('; ');
