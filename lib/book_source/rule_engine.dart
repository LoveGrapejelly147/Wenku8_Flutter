import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// A Legado rule this client cannot run. Callers show [message] and continue.
class BookSourceRuleException extends FormatException {
  const BookSourceRuleException(super.message);
}

/// One HTML element or JSON value, plus the original text it was parsed from.
class RuleNode {
  const RuleNode({
    required this.raw,
    required this.baseUrl,
    this.element,
    this.root,
    this.json,
  });

  final String raw;
  final String baseUrl;
  final Element? element;
  final Element? root;
  final Object? json;

  factory RuleNode.parse(String body, {required String baseUrl}) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return RuleNode(raw: body, baseUrl: baseUrl, json: jsonDecode(body));
      } on FormatException {
        // HTML pages occasionally start with a brace in a script comment.
      }
    }
    final document = html_parser.parse(body);
    final root = document.documentElement;
    return RuleNode(raw: body, baseUrl: baseUrl, element: root, root: root);
  }

  factory RuleNode.text(String text, {String baseUrl = ''}) =>
      RuleNode(raw: text, baseUrl: baseUrl);

  RuleNode elementChild(Element child) => RuleNode(
    raw: child.outerHtml,
    baseUrl: baseUrl,
    element: child,
    root: root ?? child,
  );

  RuleNode jsonChild(Object? value) => RuleNode(
    raw: value is String ? value : jsonEncode(value),
    baseUrl: baseUrl,
    root: root,
    json: value,
  );

  bool get isJson => json != null && element == null;
}

/// Legado rule subsets used by text book sources: CSS / default JSoup, XPath,
/// JSONPath, and `##regex##replacement`. JavaScript is rejected, not executed.
class RuleEngine {
  const RuleEngine();

  List<String> strings(String? rule, RuleNode node) {
    final source = rule?.trim() ?? '';
    if (source.isEmpty) return [_nodeText(node)];
    _rejectUnsupported(source);
    return _combine(source, (part) => _stringsOne(part, node));
  }

  List<RuleNode> nodes(String? rule, RuleNode node) {
    final source = rule?.trim() ?? '';
    if (source.isEmpty) return [node];
    _rejectUnsupported(source);
    return _combine(source, (part) => _nodesOne(part, node));
  }
}

void _rejectUnsupported(String rule) {
  final lower = rule.toLowerCase();
  if (lower.contains('@js:') ||
      lower.contains('<js>') ||
      lower.contains('</js>') ||
      RegExp(r'<js\b').hasMatch(lower)) {
    throw const BookSourceRuleException('不支持 JavaScript 规则（<js> / @js:）');
  }
  if (rule.contains('{{')) {
    throw const BookSourceRuleException('不支持规则中的 {{ }} 变量或脚本');
  }
  if (RegExp(r'\bjava\.').hasMatch(rule)) {
    throw const BookSourceRuleException('不支持 Java / JavaScript 规则');
  }
}

List<T> _combine<T>(String rule, List<T> Function(String part) eval) {
  final split = _splitCombinator(rule);
  if (split.op == null) return eval(rule);
  if (split.op == '||') {
    for (final part in split.parts) {
      final values = eval(part);
      if (values.isNotEmpty) return values;
    }
    return const [];
  }
  if (split.op == '%%') {
    final groups = [for (final part in split.parts) eval(part)];
    final longest = groups.fold<int>(0, (max, group) {
      return group.length > max ? group.length : max;
    });
    final merged = <T>[];
    for (var index = 0; index < longest; index++) {
      for (final group in groups) {
        if (index < group.length) merged.add(group[index]);
      }
    }
    return merged;
  }
  return [for (final part in split.parts) ...eval(part)];
}

({String? op, List<String> parts}) _splitCombinator(String rule) {
  String? found;
  var at = rule.length;
  for (final op in const ['||', '&&', '%%']) {
    final index = _indexOutsideQuotes(rule, op);
    if (index >= 0 && index < at) {
      at = index;
      found = op;
    }
  }
  if (found == null) return (op: null, parts: [rule]);
  final parts = _splitOutsideQuotes(
    rule,
    found,
  ).map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  return (op: found, parts: parts);
}

int _indexOutsideQuotes(String rule, String needle) {
  final parts = _splitOutsideQuotes(rule, needle);
  if (parts.length < 2) return -1;
  return parts.first.length;
}

List<String> _splitOutsideQuotes(String rule, String needle) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var quote = '';
  for (var i = 0; i < rule.length; i++) {
    final char = rule[i];
    if (quote.isNotEmpty) {
      buffer.write(char);
      if (char == r'\' && i + 1 < rule.length) {
        buffer.write(rule[++i]);
        continue;
      }
      if (char == quote) quote = '';
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      continue;
    }
    if (rule.startsWith(needle, i)) {
      parts.add(buffer.toString());
      buffer.clear();
      i += needle.length - 1;
      continue;
    }
    buffer.write(char);
  }
  parts.add(buffer.toString());
  return parts;
}

({String selector, List<(String, String)> replaces}) _splitRegex(String rule) {
  final end = rule.indexOf('###');
  if (end >= 0) {
    final bits = rule.substring(0, end).split('##');
    if (bits.length >= 3) {
      return (
        selector: bits.first,
        replaces: [(bits[1], bits.sublist(2).join('##'))],
      );
    }
  }
  if (!rule.contains('##')) return (selector: rule, replaces: const []);
  final bits = rule.split('##');
  final replaces = <(String, String)>[];
  for (var i = 1; i < bits.length; i += 2) {
    replaces.add((bits[i], i + 1 < bits.length ? bits[i + 1] : ''));
  }
  return (selector: bits.first, replaces: replaces);
}

List<String> _stringsOne(String rule, RuleNode node) {
  final split = _splitRegex(rule);
  final selector = split.selector.trim();
  final values = selector.isEmpty
      ? <String>[node.raw]
      : _extractStrings(selector, node);
  if (split.replaces.isEmpty) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }
  return [
    for (final value in values) _applyReplaces(value, split.replaces).trim(),
  ].where((value) => value.isNotEmpty).toList();
}

List<RuleNode> _nodesOne(String rule, RuleNode node) {
  final selector = _splitRegex(rule).selector.trim();
  if (selector.isEmpty) return [node];
  return _extractNodes(selector, node);
}

String _applyReplaces(String input, List<(String, String)> replaces) {
  var value = input;
  for (final (pattern, replacement) in replaces) {
    value = _applyReplace(value, pattern, replacement);
  }
  return value;
}

String _applyReplace(String input, String pattern, String replacement) {
  if (pattern.isEmpty) return input;
  var source = pattern;
  var dotAll = false;
  var caseSensitive = true;
  var multiLine = false;
  final flags = RegExp(r'^\(\?([ims]+)\)').firstMatch(source);
  if (flags != null) {
    final text = flags.group(1)!;
    dotAll = text.contains('s');
    caseSensitive = !text.contains('i');
    multiLine = text.contains('m');
    source = source.substring(flags.end);
  }
  final RegExp regex;
  try {
    regex = RegExp(
      source,
      dotAll: dotAll,
      caseSensitive: caseSensitive,
      multiLine: multiLine,
    );
  } on FormatException {
    throw BookSourceRuleException('正则无效：$pattern');
  }
  return input.replaceAllMapped(regex, (match) {
    return replacement.replaceAllMapped(RegExp(r'\$(\d)|\$\{(\d+)\}'), (group) {
      final index = int.parse(group.group(1) ?? group.group(2)!);
      return match.group(index) ?? '';
    });
  });
}

enum _Mode { css, custom, xpath, json }

({_Mode mode, String body}) _modeOf(String rule, RuleNode node) {
  final lower = rule.toLowerCase();
  if (lower.startsWith('@css:')) {
    return (mode: _Mode.css, body: rule.substring(5).trim());
  }
  if (lower.startsWith('@xpath:')) {
    return (mode: _Mode.xpath, body: rule.substring(7).trim());
  }
  if (lower.startsWith('@json:')) {
    return (mode: _Mode.json, body: rule.substring(6).trim());
  }
  if (rule.startsWith('//') || rule.startsWith('/')) {
    return (mode: _Mode.xpath, body: rule);
  }
  if (rule.startsWith(r'$.') || rule.startsWith(r'$[')) {
    return (mode: _Mode.json, body: rule);
  }
  if (node.isJson && _looksLikeJsonPath(rule)) {
    return (mode: _Mode.json, body: rule.startsWith(r'$') ? rule : r'$.$rule');
  }
  final selector = _stripAttr(rule).selector;
  if (_isCustom(selector)) return (mode: _Mode.custom, body: rule);
  return (mode: _Mode.css, body: rule);
}

bool _looksLikeJsonPath(String rule) => RegExp(
  r'^[A-Za-z_][\w-]*(\.[A-Za-z_][\w-]*|\[\d+\]|\[\*\]|\[["\x27][^"\x27]+["\x27]\])*$',
).hasMatch(rule);

bool _isCustom(String selector) {
  if (selector.isEmpty) return false;
  final head = selector.split(RegExp(r'[.@]')).first;
  return const {'class', 'tag', 'id', 'text', 'children'}.contains(head);
}

List<String> _extractStrings(String rule, RuleNode node) {
  final mode = _modeOf(rule, node);
  return switch (mode.mode) {
    _Mode.css => _cssStrings(mode.body, node),
    _Mode.custom => _customStrings(mode.body, node),
    _Mode.xpath => _asStrings(_xpath(mode.body, node)),
    _Mode.json => _jsonStrings(mode.body, node),
  };
}

List<String> _asStrings(List<Object?> values) => [
  for (final value in values)
    if (value is Element)
      _elementText(value)
    else if (value != null && '$value'.trim().isNotEmpty)
      '$value'.trim(),
];

List<RuleNode> _extractNodes(String rule, RuleNode node) {
  final mode = _modeOf(rule, node);
  return switch (mode.mode) {
    _Mode.css => [
      for (final element in _cssElements(_stripAttr(mode.body).selector, node))
        node.elementChild(element),
    ],
    _Mode.custom => [
      for (final element in _customElements(
        _stripAttr(mode.body).selector,
        node,
      ))
        node.elementChild(element),
    ],
    _Mode.xpath => [
      for (final value in _xpath(mode.body, node))
        if (value is Element) node.elementChild(value),
    ],
    _Mode.json => [
      for (final value in _jsonValues(mode.body, node))
        if (value != null) node.jsonChild(value),
    ],
  };
}

({String selector, String? attr}) _stripAttr(String rule) {
  final index = rule.lastIndexOf('@');
  if (index <= 0) return (selector: rule.trim(), attr: null);
  final suffix = rule.substring(index + 1).trim();
  if (!RegExp(r'^[A-Za-z_:][\w:-]*$').hasMatch(suffix)) {
    return (selector: rule.trim(), attr: null);
  }
  return (selector: rule.substring(0, index).trim(), attr: suffix);
}

List<String> _cssStrings(String rule, RuleNode node) {
  final parsed = _stripAttr(rule);
  final elements = _cssElements(parsed.selector, node);
  if (parsed.attr == null) return elements.map(_elementText).toList();
  return elements.map((element) => _readAttr(element, parsed.attr!)).toList();
}

List<Element> _cssElements(String selector, RuleNode node) {
  final root = node.element;
  if (root == null) {
    throw const BookSourceRuleException('当前结果不是 HTML，不能使用 CSS 规则');
  }
  final query = _parseCss(selector);
  if (query.selector.isEmpty) return _filterIndexed([root], query.filters);
  try {
    final found = root.querySelectorAll(query.selector);
    return _filterIndexed(found, query.filters);
  } on FormatException catch (error) {
    throw BookSourceRuleException('CSS 选择器无效：$selector（${error.message}）');
  }
}

class _CssQuery {
  const _CssQuery(this.selector, this.filters);
  final String selector;
  final List<_CssFilter> filters;
}

class _CssFilter {
  const _CssFilter(this.kind, this.index);
  final String kind;
  final int index;
}

_CssQuery _parseCss(String selector) {
  final filters = <_CssFilter>[];
  final cleaned = selector.replaceAllMapped(_cssPseudo, (match) {
    final named = match.group(1)?.toLowerCase();
    if (named == null) {
      final word = match.group(0)!.substring(1).toLowerCase();
      filters.add(_CssFilter(word, 0));
    } else {
      filters.add(_CssFilter(named, int.parse(match.group(2)!)));
    }
    return '';
  }).trim();
  return _CssQuery(cleaned, filters);
}

final _cssPseudo = RegExp(
  r':(eq|gt|lt)\((-?\d+)\)|:first\b|:last\b',
  caseSensitive: false,
);

List<Element> _filterIndexed(List<Element> items, List<_CssFilter> filters) {
  var current = items;
  for (final filter in filters) {
    current = switch (filter.kind) {
      'eq' || 'first' => _indexElements(current, '${filter.index}'),
      'last' => _indexElements(current, '-1'),
      'gt' => [
        for (var i = 0; i < current.length; i++)
          if (i > _normalize(filter.index, current.length)) current[i],
      ],
      'lt' => [
        for (var i = 0; i < current.length; i++)
          if (i < _normalize(filter.index, current.length)) current[i],
      ],
      _ => current,
    };
  }
  return current;
}

List<String> _customStrings(String rule, RuleNode node) {
  final parsed = _stripAttr(rule);
  final elements = _customElements(parsed.selector, node);
  if (parsed.attr == null) return elements.map(_elementText).toList();
  return elements.map((element) => _readAttr(element, parsed.attr!)).toList();
}

List<Element> _customElements(String rule, RuleNode node) {
  final root = node.element;
  if (root == null) {
    throw const BookSourceRuleException('当前结果不是 HTML，不能使用默认规则');
  }
  final tokens = _tokens(rule);
  var current = <Element>[root];
  var started = false;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (_isIndexToken(token)) {
      current = _indexElements(current, token);
      continue;
    }
    if (_isTerminalAttr(token) && i == tokens.length - 1) break;
    if (token == 'children') {
      current = [for (final element in current) ...element.children];
      started = true;
      continue;
    }
    if (const {'class', 'tag', 'id', 'text'}.contains(token)) {
      if (i + 1 >= tokens.length || _isTerminalAttr(tokens[i + 1])) break;
      final argument = tokens[++i];
      current = _selectKeyword(current, token, argument, includeSelf: !started);
      started = true;
      continue;
    }
    current = _selectKeyword(current, 'tag', token, includeSelf: !started);
    started = true;
  }
  if (!started) return [root];
  return current;
}

List<String> _tokens(String rule) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  for (final char in rule.split('')) {
    if (char == '.' || char == '@') {
      if (buffer.isNotEmpty) tokens.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  if (buffer.isNotEmpty) tokens.add(buffer.toString());
  return tokens;
}

bool _isIndexToken(String token) =>
    RegExp(r'^!?\-?\d+(?::\-?\d+)?$').hasMatch(token);

bool _isTerminalAttr(String token) => const {
  'text',
  'owntext',
  'textnodes',
  'html',
}.contains(token.toLowerCase());

List<Element> _selectKeyword(
  List<Element> current,
  String keyword,
  String argument, {
  required bool includeSelf,
}) {
  final next = <Element>[];
  for (final element in current) {
    if (includeSelf && _keywordMatch(element, keyword, argument)) {
      next.add(element);
    }
    void walk(Element parent) {
      for (final child in parent.children) {
        if (_keywordMatch(child, keyword, argument)) next.add(child);
        walk(child);
      }
    }

    walk(element);
  }
  return next;
}

bool _keywordMatch(Element element, String keyword, String argument) {
  return switch (keyword) {
    'class' => element.classes.contains(argument),
    'tag' => element.localName?.toLowerCase() == argument.toLowerCase(),
    'id' => element.id == argument,
    'text' => element.text.contains(argument),
    _ => false,
  };
}

List<T> _indexElements<T>(List<T> items, String token) {
  if (items.isEmpty) return items;
  if (token.startsWith('!')) {
    final body = token.substring(1);
    final excluded = <int>{};
    if (body.contains(':')) {
      final parts = body.split(':');
      final start = _normalize(int.parse(parts[0]), items.length);
      final end = _normalize(int.parse(parts[1]), items.length);
      for (var i = start; i <= end && i < items.length; i++) {
        if (i >= 0) excluded.add(i);
      }
    } else {
      final index = _normalize(int.parse(body), items.length);
      if (index >= 0 && index < items.length) excluded.add(index);
    }
    return [
      for (var i = 0; i < items.length; i++)
        if (!excluded.contains(i)) items[i],
    ];
  }
  if (token.contains(':')) {
    final parts = token.split(':');
    var start = _normalize(int.parse(parts[0]), items.length);
    var end = _normalize(int.parse(parts[1]), items.length);
    if (start < 0) start = 0;
    if (end >= items.length) end = items.length - 1;
    if (start > end || start >= items.length) return [];
    return items.sublist(start, end + 1);
  }
  final index = _normalize(int.parse(token), items.length);
  if (index < 0 || index >= items.length) return [];
  return [items[index]];
}

int _normalize(int index, int length) => index < 0 ? index + length : index;

String _readAttr(Element element, String attr) {
  return switch (attr.toLowerCase()) {
    'text' => _elementText(element),
    'owntext' =>
      element.nodes.whereType<Text>().map((node) => node.data).join().trim(),
    'textnodes' => _textNodes(element),
    'html' => element.innerHtml,
    _ =>
      element.attributes[attr] ?? element.attributes[attr.toLowerCase()] ?? '',
  };
}

String _elementText(Element element) =>
    element.text.replaceAll(RegExp(r'[ \t\r\f]+'), ' ').trim();

String _textNodes(Element element) {
  final parts = <String>[];
  void walk(Node node) {
    if (node is Text) {
      final text = node.data.trim();
      if (text.isNotEmpty) parts.add(text);
    } else if (node is Element) {
      if (node.localName == 'br') {
        parts.add('');
      } else if (node.localName != 'script' && node.localName != 'style') {
        for (final child in node.nodes) {
          walk(child);
        }
      }
    }
  }

  walk(element);
  return parts.join('\n');
}

String _nodeText(RuleNode node) {
  if (node.element != null) return _elementText(node.element!);
  if (node.json is String) return node.json as String;
  if (node.json != null) return jsonEncode(node.json);
  return node.raw.trim();
}

List<Object?> _xpath(String rule, RuleNode node) {
  final root = node.root ?? node.element;
  final context = node.element ?? root;
  if (root == null || context == null) {
    throw const BookSourceRuleException('当前结果不是 HTML，不能使用 XPath');
  }
  try {
    return _XPath(rule).eval(context, root);
  } on BookSourceRuleException {
    rethrow;
  } catch (error) {
    throw BookSourceRuleException('XPath 无法解析：$rule');
  }
}

class _XPath {
  _XPath(this.input);
  final String input;
  int i = 0;

  List<Object?> eval(Element context, Element root) {
    _skip();
    var current = <Object?>[context];
    var descendant = false;
    var absolute = false;
    if (_startsWith('.//')) {
      i += 3;
      descendant = true;
    } else if (_startsWith('./')) {
      i += 2;
    } else if (_startsWith('//')) {
      i += 2;
      current = [root];
      descendant = true;
      absolute = true;
    } else if (_peek() == '/') {
      i++;
      current = [root];
      absolute = true;
    } else {
      descendant = true;
    }
    if (absolute) {
      // Absolute paths start at the document element, then take a step.
    }
    var first = true;
    while (i < input.length) {
      _skip();
      if (i >= input.length) break;
      if (_startsWith('//')) {
        i += 2;
        descendant = true;
      } else if (_peek() == '/') {
        i++;
        descendant = false;
      } else if (!first) {
        break;
      }
      _skip();
      if (i >= input.length) break;
      final step = _readStep();
      current = _apply(current.whereType<Element>().toList(), step, descendant);
      descendant = false;
      first = false;
      _skip();
    }
    return current;
  }

  void _skip() {
    while (i < input.length && (input[i] == ' ' || input[i] == '\n')) {
      i++;
    }
  }

  String _peek() => i < input.length ? input[i] : '';

  bool _startsWith(String text) => input.startsWith(text, i);

  _Step _readStep() {
    if (_startsWith('..')) {
      i += 2;
      return _Step('..', const []);
    }
    if (_peek() == '.' && !_startsWith('..')) {
      i++;
      return _Step('.', _predicates());
    }
    if (_peek() == '@') {
      i++;
      return _Step('@${_readName()}', _predicates());
    }
    if (_startsWith('text()')) {
      i += 6;
      return _Step('text()', _predicates());
    }
    if (_peek() == '*') {
      i++;
      return _Step('*', _predicates());
    }
    final name = _readName();
    if (name.isEmpty) {
      throw BookSourceRuleException('XPath 无法解析：$input');
    }
    return _Step(name, _predicates());
  }

  List<_Pred> _predicates() {
    final preds = <_Pred>[];
    while (true) {
      _skip();
      if (_peek() != '[') break;
      i++;
      final start = i;
      var quote = '';
      var depth = 1;
      while (i < input.length && depth > 0) {
        final char = input[i];
        if (quote.isNotEmpty) {
          if (char == quote) quote = '';
        } else if (char == '"' || char == "'") {
          quote = char;
        } else if (char == '[') {
          depth++;
        } else if (char == ']') {
          depth--;
          if (depth == 0) break;
        }
        i++;
      }
      final inside = input.substring(start, i).trim();
      if (_peek() == ']') i++;
      preds.add(_parsePred(inside));
    }
    return preds;
  }

  String _readName() {
    final start = i;
    while (i < input.length && RegExp(r'[\w:-]').hasMatch(input[i])) {
      i++;
    }
    return input.substring(start, i);
  }

  List<Object?> _apply(List<Element> current, _Step step, bool descendant) {
    final matched = <Object?>[];
    for (final element in current) {
      if (step.test == '..') {
        final parent = element.parent;
        if (parent != null) matched.add(parent);
        continue;
      }
      if (step.test == '.') {
        matched.add(element);
        continue;
      }
      if (step.test.startsWith('@')) {
        final name = step.test.substring(1);
        final elements = descendant
            ? _descendants(element)
            : <Element>[element];
        for (final candidate in elements) {
          final value = candidate.attributes[name];
          if (value != null) matched.add(value);
        }
        continue;
      }
      if (step.test == 'text()') {
        final elements = descendant
            ? _descendants(element)
            : <Element>[element];
        for (final candidate in elements) {
          for (final node in candidate.nodes.whereType<Text>()) {
            final text = node.data.trim();
            if (text.isNotEmpty) matched.add(text);
          }
        }
        continue;
      }
      final pool = descendant
          ? _descendants(element)
          : element.children.toList();
      for (final candidate in pool) {
        if (step.test == '*' ||
            candidate.localName?.toLowerCase() == step.test.toLowerCase()) {
          matched.add(candidate);
        }
      }
    }
    final unique = <Object?>[];
    final seen = <Element>{};
    for (final value in matched) {
      if (value is Element) {
        if (seen.add(value)) unique.add(value);
      } else {
        unique.add(value);
      }
    }
    return _filterPreds(unique, step.preds);
  }
}

class _Step {
  const _Step(this.test, this.preds);
  final String test;
  final List<_Pred> preds;
}

sealed class _Pred {
  bool match(Object? value, int position, int size);
}

class _PosPred extends _Pred {
  _PosPred(this.position, {this.last = false});
  final int position;
  final bool last;
  @override
  bool match(Object? value, int index, int size) =>
      last ? index == size : position == index;
}

class _AttrPred extends _Pred {
  _AttrPred(this.name, this.equals, this.expected, {this.exists = false});
  final String name;
  final bool equals;
  final String expected;
  final bool exists;
  @override
  bool match(Object? value, int index, int size) {
    if (value is! Element) return false;
    final actual = value.attributes[name];
    if (exists) return actual != null;
    if (actual == null) return false;
    return equals ? actual == expected : actual != expected;
  }
}

class _ContainsPred extends _Pred {
  _ContainsPred(this.name, this.expected, {required this.text});
  final String? name;
  final String expected;
  final bool text;
  @override
  bool match(Object? value, int index, int size) {
    if (value is! Element) return false;
    if (text) return value.text.contains(expected);
    return (value.attributes[name] ?? '').contains(expected);
  }
}

class _AndPred extends _Pred {
  _AndPred(this.items);
  final List<_Pred> items;
  @override
  bool match(Object? value, int index, int size) =>
      items.every((item) => item.match(value, index, size));
}

_Pred _parsePred(String inside) {
  final parts = _splitOutsideQuotes(
    inside,
    ' and ',
  ).map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  final preds = parts.map(_parsePredOne).toList();
  return preds.length == 1 ? preds.single : _AndPred(preds);
}

_Pred _parsePredOne(String inside) {
  if (inside == 'last()') return _PosPred(0, last: true);
  final number = int.tryParse(inside);
  if (number != null) return _PosPred(number);
  final contains = RegExp(
    r'''^contains\(\s*@([\w:-]+)\s*,\s*(['"])(.*?)\2\s*\)$''',
  ).firstMatch(inside);
  if (contains != null) {
    return _ContainsPred(contains.group(1), contains.group(3)!, text: false);
  }
  final containsText = RegExp(
    r'''^contains\(\s*text\(\)\s*,\s*(['"])(.*?)\1\s*\)$''',
  ).firstMatch(inside);
  if (containsText != null) {
    return _ContainsPred(null, containsText.group(2)!, text: true);
  }
  final attr = RegExp(
    r'''^@([\w:-]+)\s*(=|!=)\s*(['"])(.*?)\3$''',
  ).firstMatch(inside);
  if (attr != null) {
    return _AttrPred(attr.group(1)!, attr.group(2) == '=', attr.group(4)!);
  }
  final exists = RegExp(r'^@([\w:-]+)$').firstMatch(inside);
  if (exists != null) {
    return _AttrPred(exists.group(1)!, true, '', exists: true);
  }
  throw BookSourceRuleException('不支持的 XPath 条件：$inside');
}

List<Object?> _filterPreds(List<Object?> values, List<_Pred> preds) {
  var current = values;
  for (final pred in preds) {
    final next = <Object?>[];
    for (var index = 0; index < current.length; index++) {
      if (pred.match(current[index], index + 1, current.length)) {
        next.add(current[index]);
      }
    }
    current = next;
  }
  return current;
}

Iterable<Element> _descendants(Element element) sync* {
  for (final child in element.children) {
    yield child;
    yield* _descendants(child);
  }
}

List<String> _jsonStrings(String rule, RuleNode node) => [
  for (final value in _jsonValues(rule, node))
    if (value != null) _jsonScalar(value),
].where((value) => value.isNotEmpty).toList();

String _jsonScalar(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return '$value';
  return jsonEncode(value);
}

List<Object?> _jsonValues(String rule, RuleNode node) {
  if (!node.isJson && node.json == null) {
    throw const BookSourceRuleException('当前结果不是 JSON，不能使用 JSONPath');
  }
  var path = rule.trim();
  if (path.toLowerCase().startsWith('@json:')) path = path.substring(6).trim();
  if (!path.startsWith(r'$')) path = r'$.$path';
  try {
    final values = _JsonPath(path).read(node.json);
    if (values.length == 1 && values.single is List) {
      return (values.single as List).cast<Object?>();
    }
    return values;
  } on BookSourceRuleException {
    rethrow;
  } catch (_) {
    throw BookSourceRuleException('JSONPath 无法解析：$rule');
  }
}

class _JsonPath {
  _JsonPath(this.path);
  final String path;
  int i = 0;

  List<Object?> read(Object? root) {
    if (!path.startsWith(r'$')) {
      throw BookSourceRuleException('JSONPath 需要以 \$ 开头：$path');
    }
    i = 1;
    var current = <Object?>[root];
    while (i < path.length) {
      if (path.startsWith('..', i)) {
        i += 2;
        final key = _readKey();
        current = _descend(current, key);
      } else if (path.startsWith('.', i)) {
        i++;
        final key = _readKey();
        current = [for (final value in current) ..._child(value, key)];
      } else if (path.startsWith('[', i)) {
        final end = _bracketEnd();
        final inside = path.substring(i + 1, end);
        i = end + 1;
        current = _bracket(current, inside.trim());
      } else {
        throw BookSourceRuleException('JSONPath 无法解析：$path');
      }
    }
    return current.where((value) => value != null).toList();
  }

  String _readKey() {
    if (i >= path.length) throw BookSourceRuleException('JSONPath 无法解析：$path');
    if (path[i] == '[') return '';
    final start = i;
    while (i < path.length && path[i] != '.' && path[i] != '[') {
      i++;
    }
    final key = path.substring(start, i);
    if (key.isEmpty) throw BookSourceRuleException('JSONPath 无法解析：$path');
    return key;
  }

  int _bracketEnd() {
    final end = path.indexOf(']', i);
    if (end < 0) throw BookSourceRuleException('JSONPath 无法解析：$path');
    return end;
  }

  List<Object?> _child(Object? value, String key) {
    if (key.isEmpty) return const [];
    if (value is Map && value.containsKey(key)) return [value[key]];
    if (value is List) {
      return [for (final item in value) ..._child(item, key)];
    }
    return const [];
  }

  List<Object?> _descend(List<Object?> current, String key) {
    final found = <Object?>[];
    void walk(Object? value) {
      if (value is Map) {
        value.forEach((name, child) {
          if (name == key) found.add(child);
          walk(child);
        });
      } else if (value is List) {
        for (final child in value) {
          walk(child);
        }
      }
    }

    for (final value in current) {
      walk(value);
    }
    return found;
  }

  List<Object?> _bracket(List<Object?> current, String inside) {
    if (inside == '*') {
      return [for (final value in current) ..._star(value)];
    }
    if (inside.startsWith('?')) return _filter(current, inside);
    final quoted = RegExp(r'''^['"](.+)['"]$''').firstMatch(inside);
    if (quoted != null) return _childAll(current, quoted.group(1)!);
    if (inside.contains(':')) {
      final parts = inside.split(':');
      final start = parts[0].isEmpty ? 0 : int.parse(parts[0]);
      final end = parts.length < 2 || parts[1].isEmpty
          ? null
          : int.parse(parts[1]);
      return [
        for (final value in current)
          if (value is List)
            ...value.sublist(
              start.clamp(0, value.length),
              (end ?? value.length).clamp(0, value.length),
            ),
      ];
    }
    final index = int.tryParse(inside);
    if (index == null) {
      throw BookSourceRuleException('不支持的 JSONPath 下标：$inside');
    }
    return [
      for (final value in current)
        if (value is List && index >= 0 && index < value.length) value[index],
    ];
  }

  List<Object?> _star(Object? value) {
    if (value is List) return value.cast<Object?>();
    if (value is Map) return value.values.toList();
    return const [];
  }

  List<Object?> _childAll(List<Object?> current, String key) => [
    for (final value in current) ..._child(value, key),
  ];

  List<Object?> _filter(List<Object?> current, String inside) {
    final match = RegExp(
      r'''^\?\(\s*@\.([\w-]+)\s*(==|!=)\s*(['"]?)([^'")]+)\3\s*\)$''',
    ).firstMatch(inside);
    if (match == null) {
      throw BookSourceRuleException('不支持的 JSONPath 过滤：$inside');
    }
    final key = match.group(1)!;
    final equals = match.group(2) == '==';
    final expected = match.group(4)!;
    return [
      for (final value in current) ..._filterOne(value, key, equals, expected),
    ];
  }

  List<Object?> _filterOne(
    Object? value,
    String key,
    bool equals,
    String expected,
  ) {
    final items = value is List ? value : [value];
    return [
      for (final item in items)
        if (item is Map && ((_stringify(item[key]) == expected) == equals))
          item,
    ];
  }

  String _stringify(Object? value) => value == null ? '' : '$value';
}
