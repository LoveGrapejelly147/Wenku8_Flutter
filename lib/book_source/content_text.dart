import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'url_template.dart';

/// Turns a chapter rule result into the reader's paragraph text.
///
/// Images become the same `<!--image-->` markers the cache and reader already
/// understand. JavaScript is never executed; tags are only read as text.
String bookSourceContentText(String raw, String baseUrl) {
  final source = raw.replaceAll('\r\n', '\n').trim();
  if (source.isEmpty) return '';
  final text = source.contains('<') && source.contains('>')
      ? _htmlText(source, baseUrl)
      : source;
  final paragraphs = <String>[];
  for (final block in text.split(RegExp(r'\n+'))) {
    final line = block
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    if (line.isEmpty) continue;
    paragraphs.add(line);
  }
  return paragraphs.join('\n\n');
}

String _htmlText(String source, String baseUrl) {
  final fragment = html_parser.parseFragment(source);
  final buffer = StringBuffer();
  void walk(Node node) {
    if (node is Text) {
      buffer.write(node.data);
      return;
    }
    if (node is! Element) return;
    final name = node.localName;
    if (name == 'script' || name == 'style') return;
    if (name == 'img') {
      final src =
          node.attributes['src'] ??
          node.attributes['data-src'] ??
          node.attributes['data-original'] ??
          '';
      if (src.trim().isNotEmpty) {
        try {
          final url = resolveBookSourceUrl(baseUrl, src.trim());
          buffer.write('\n<!--image-->$url<!--image-->\n');
        } on FormatException {
          // Skip an image whose address is not http(s).
        }
      }
      return;
    }
    if (name == 'br') {
      buffer.write('\n');
      return;
    }
    const blocks = {
      'p',
      'div',
      'h1',
      'h2',
      'h3',
      'h4',
      'li',
      'tr',
      'section',
      'article',
      'blockquote',
    };
    final block = blocks.contains(name);
    if (block) buffer.write('\n');
    for (final child in node.nodes) {
      walk(child);
    }
    if (block) buffer.write('\n');
  }

  for (final node in fragment.nodes) {
    walk(node);
  }
  return buffer.toString();
}
