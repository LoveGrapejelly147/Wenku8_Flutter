import 'dart:convert';

import 'package:enough_convert/enough_convert.dart';

import 'rule_engine.dart';

/// Decodes a book-source response. GBK/Big5 are pure Dart so the Android
/// client does not need a platform channel for chapter text.
String decodeBookSourceText(List<int> bytes, String charset) {
  final name = _canonical(charset);
  try {
    return switch (name) {
      '' ||
      'utf-8' ||
      'utf8' ||
      'us-ascii' ||
      'ascii' => utf8.decode(bytes, allowMalformed: true),
      'gbk' ||
      'gb2312' ||
      'gb18030' ||
      'gb-18030' => const GbkCodec(allowInvalid: true).decode(bytes),
      'big5' ||
      'big5-hkscs' ||
      'cp950' => const Big5Codec(allowInvalid: true).decode(bytes),
      'latin1' || 'iso-8859-1' || 'iso8859-1' => latin1.decode(bytes),
      _ => throw BookSourceRuleException('不支持的字符集 $charset'),
    };
  } on BookSourceRuleException {
    rethrow;
  } catch (error) {
    throw BookSourceRuleException('无法用 $charset 解码书源响应');
  }
}

List<int> encodeBookSourceText(String text, String charset) {
  final name = _canonical(charset);
  return switch (name) {
    '' || 'utf-8' || 'utf8' || 'us-ascii' || 'ascii' => utf8.encode(text),
    'gbk' || 'gb2312' || 'gb18030' || 'gb-18030' => gbk.encode(text),
    'big5' || 'big5-hkscs' || 'cp950' => big5.encode(text),
    'latin1' || 'iso-8859-1' || 'iso8859-1' => latin1.encode(text),
    _ => throw BookSourceRuleException('不支持的字符集 $charset'),
  };
}

String _canonical(String charset) =>
    charset.trim().toLowerCase().replaceAll('_', '-');
