import 'dart:convert';

import '../book_source/rule_engine.dart';
import '../book_source/url_template.dart';
import '../local_import_options.dart';

const readingRulesUnavailable = '此版本不可用';

class TxtTocRule {
  const TxtTocRule({
    required this.id,
    required this.name,
    required this.rule,
    this.replacement = '',
    this.example = '',
    this.serialNumber = 0,
    this.enabled = true,
    this.volume = false,
  });

  final int id;
  final String name;
  final String rule;
  final String replacement;
  final String example;
  final int serialNumber;
  final bool enabled;
  final bool volume;

  TxtTocRule copyWith({
    String? name,
    String? rule,
    String? replacement,
    String? example,
    int? serialNumber,
    bool? enabled,
    bool? volume,
  }) => TxtTocRule(
    id: id,
    name: name ?? this.name,
    rule: rule ?? this.rule,
    replacement: replacement ?? this.replacement,
    example: example ?? this.example,
    serialNumber: serialNumber ?? this.serialNumber,
    enabled: enabled ?? this.enabled,
    volume: volume ?? this.volume,
  );

  Map<String, Object?> toLegado() => {
    'id': id,
    'name': name,
    'rule': rule,
    'replacement': replacement,
    'example': example,
    'serialNumber': serialNumber,
    'enable': enabled,
    if (volume) 'volume': true,
  };

  factory TxtTocRule.fromLegado(Map<String, dynamic> json) {
    final name = '${json['name'] ?? ''}'.trim();
    final rule = '${json['rule'] ?? ''}'.trim();
    if (name.isEmpty || rule.isEmpty) {
      throw const FormatException('TXT 目录规则缺少 name 或 rule');
    }
    RegExp(rule);
    final id = json['id'];
    return TxtTocRule(
      id: id is int ? id : DateTime.now().microsecondsSinceEpoch,
      name: name,
      rule: rule,
      replacement: '${json['replacement'] ?? ''}',
      example: '${json['example'] ?? ''}',
      serialNumber: json['serialNumber'] is int
          ? json['serialNumber'] as int
          : 0,
      enabled: json['enable'] != false && json['enabled'] != false,
      volume: json['volume'] == true || _looksLikeVolume(rule, name),
    );
  }
}

bool _looksLikeVolume(String rule, String name) {
  final text = '$name $rule';
  final volume = text.contains('卷') || text.contains('volume');
  final chapter = text.contains('章') || text.contains('chapter');
  return volume && !chapter;
}

const builtInTxtTocRules = <TxtTocRule>[
  TxtTocRule(
    id: 1,
    name: '第X章 / 回 / 节',
    rule: r'^(第[零〇一二三四五六七八九十百千万萬两兩0-9０-９]+[章节節回幕话話]|序章|序言|楔子|尾声|尾聲|后记|後記|番外)',
    serialNumber: 0,
  ),
  TxtTocRule(
    id: 2,
    name: 'Chapter',
    rule: r'^(chapter|chap\.?)\s+[0-9]+',
    serialNumber: 1,
  ),
  TxtTocRule(
    id: 3,
    name: '第X卷',
    rule: r'^(第[零〇一二三四五六七八九十百千万萬两兩0-9０-９]+[卷部]|volume\s+\d+)',
    serialNumber: 2,
    volume: true,
  ),
  TxtTocRule(
    id: 4,
    name: '综合（章、卷、Chapter）',
    rule:
        r'^(第[零〇一二三四五六七八九十百千万萬两兩0-9０-９]+[章节節回卷部幕话話]|chapter\s+\d+|volume\s+\d+|序章|楔子|尾声|番外)',
    serialNumber: 3,
  ),
];

class TxtTocMatch {
  const TxtTocMatch(this.rule, this.count);
  final TxtTocRule rule;
  final int count;
}

TxtTocMatch? bestTxtTocRule(String sample, List<TxtTocRule> rules) {
  final lines = [
    for (final line in sample.split(RegExp(r'\r\n?|\n')))
      if (line.trim().isNotEmpty && line.trim().length <= 90) line.trim(),
  ];
  if (lines.isEmpty) return null;
  TxtTocMatch? best;
  for (final rule in rules.where((rule) => rule.enabled && !rule.volume)) {
    final RegExp pattern;
    try {
      pattern = RegExp(rule.rule, caseSensitive: false);
    } on FormatException {
      continue;
    }
    final count = lines.where(pattern.hasMatch).length;
    if (count < 2 || count > lines.length * 0.6) continue;
    if (best == null || count > best.count) best = TxtTocMatch(rule, count);
  }
  return best;
}

LocalImportOptions optionsForTxtRule(TxtTocRule rule) => LocalImportOptions(
  customToc: true,
  chapterRule: rule.volume ? defaultLocalChapterRule : rule.rule,
  volumeRule: rule.volume ? rule.rule : '',
);

String cleanTxtTitle(String line, TxtTocRule rule) {
  if (rule.replacement.isEmpty) return line.trim();
  try {
    return line.replaceAll(RegExp(rule.rule), rule.replacement).trim();
  } on FormatException {
    return line.trim();
  }
}

class ReplaceRule {
  const ReplaceRule({
    required this.id,
    required this.name,
    required this.pattern,
    this.group = '',
    this.replacement = '',
    this.scope = '',
    this.scopeTitle = false,
    this.scopeContent = true,
    this.excludeScope = '',
    this.isRegex = true,
    this.enabled = true,
    this.order = 0,
  });

  final int id;
  final String name;
  final String group;
  final String pattern;
  final String replacement;
  final String scope;
  final bool scopeTitle;
  final bool scopeContent;
  final String excludeScope;
  final bool isRegex;
  final bool enabled;
  final int order;

  ReplaceRule copyWith({
    String? name,
    String? group,
    String? pattern,
    String? replacement,
    String? scope,
    bool? scopeTitle,
    bool? scopeContent,
    String? excludeScope,
    bool? isRegex,
    bool? enabled,
    int? order,
  }) => ReplaceRule(
    id: id,
    name: name ?? this.name,
    group: group ?? this.group,
    pattern: pattern ?? this.pattern,
    replacement: replacement ?? this.replacement,
    scope: scope ?? this.scope,
    scopeTitle: scopeTitle ?? this.scopeTitle,
    scopeContent: scopeContent ?? this.scopeContent,
    excludeScope: excludeScope ?? this.excludeScope,
    isRegex: isRegex ?? this.isRegex,
    enabled: enabled ?? this.enabled,
    order: order ?? this.order,
  );

  bool appliesTo({String? bookTitle, String? sourceUrl, String? sourceName}) {
    if (_listed(excludeScope, bookTitle, sourceUrl, sourceName)) return false;
    if (scope.trim().isEmpty) return true;
    return _listed(scope, bookTitle, sourceUrl, sourceName);
  }

  String apply(String input) {
    if (pattern.isEmpty) return input;
    try {
      if (!isRegex) return input.replaceAll(pattern, replacement);
      return input.replaceAll(RegExp(pattern), replacement);
    } on FormatException {
      return input;
    }
  }

  Map<String, Object?> toLegado() => {
    'id': id,
    'name': name,
    'group': group,
    'pattern': pattern,
    'replacement': replacement,
    'scope': scope,
    'scopeTitle': scopeTitle,
    'scopeContent': scopeContent,
    'excludeScope': excludeScope,
    'isRegex': isRegex,
    'isEnabled': enabled,
    'order': order,
  };

  factory ReplaceRule.fromLegado(Map<String, dynamic> json) {
    final name = '${json['name'] ?? ''}'.trim();
    final pattern = '${json['pattern'] ?? ''}'.trim();
    if (name.isEmpty || pattern.isEmpty) {
      throw const FormatException('替换规则缺少 name 或 pattern');
    }
    final id = json['id'];
    return ReplaceRule(
      id: id is int ? id : DateTime.now().microsecondsSinceEpoch,
      name: name,
      group: '${json['group'] ?? ''}',
      pattern: pattern,
      replacement: '${json['replacement'] ?? ''}',
      scope: '${json['scope'] ?? ''}',
      scopeTitle: json['scopeTitle'] == true,
      scopeContent: json['scopeContent'] != false,
      excludeScope: '${json['excludeScope'] ?? ''}',
      isRegex: json['isRegex'] != false,
      enabled: json['isEnabled'] != false && json['enable'] != false,
      order: json['order'] is int ? json['order'] as int : 0,
    );
  }
}

bool _listed(
  String scope,
  String? bookTitle,
  String? sourceUrl,
  String? sourceName,
) {
  final tokens = scope
      .split(RegExp(r'[\n,，;；]+'))
      .map((token) => token.trim().toLowerCase())
      .where((token) => token.isNotEmpty);
  final title = bookTitle?.trim().toLowerCase() ?? '';
  final url = sourceUrl?.trim().toLowerCase() ?? '';
  final source = sourceName?.trim().toLowerCase() ?? '';
  for (final token in tokens) {
    if (token == title ||
        token == url ||
        token == source ||
        title.isNotEmpty && title.contains(token) ||
        url.isNotEmpty && url.contains(token)) {
      return true;
    }
  }
  return false;
}

enum ReplaceTarget { content, title }

String applyReplaceRules(
  String input,
  List<ReplaceRule> rules, {
  required bool enabled,
  required ReplaceTarget target,
  String? bookTitle,
  String? sourceUrl,
  String? sourceName,
}) {
  if (!enabled || input.isEmpty) return input;
  var text = input;
  final ordered = [...rules]..sort((a, b) => a.order.compareTo(b.order));
  for (final rule in ordered) {
    if (!rule.enabled ||
        !rule.appliesTo(
          bookTitle: bookTitle,
          sourceUrl: sourceUrl,
          sourceName: sourceName,
        )) {
      continue;
    }
    if (target == ReplaceTarget.content && !rule.scopeContent) continue;
    if (target == ReplaceTarget.title && !rule.scopeTitle) continue;
    text = rule.apply(text);
  }
  return text;
}

class DictRule {
  const DictRule({
    required this.name,
    required this.urlRule,
    required this.showRule,
    this.enabled = true,
    this.order = 0,
  });

  final String name;
  final String urlRule;
  final String showRule;
  final bool enabled;
  final int order;

  DictRule copyWith({
    String? name,
    String? urlRule,
    String? showRule,
    bool? enabled,
    int? order,
  }) => DictRule(
    name: name ?? this.name,
    urlRule: urlRule ?? this.urlRule,
    showRule: showRule ?? this.showRule,
    enabled: enabled ?? this.enabled,
    order: order ?? this.order,
  );

  Map<String, Object?> toLegado() => {
    'name': name,
    'urlRule': urlRule,
    'showRule': showRule,
    'enabled': enabled,
    'order': order,
  };

  factory DictRule.fromLegado(Map<String, dynamic> json) {
    final name = '${json['name'] ?? ''}'.trim();
    final urlRule = '${json['urlRule'] ?? ''}'.trim();
    if (name.isEmpty || urlRule.isEmpty) {
      throw const FormatException('字典规则缺少 name 或 urlRule');
    }
    return DictRule(
      name: name,
      urlRule: urlRule,
      showRule: '${json['showRule'] ?? ''}'.trim(),
      enabled: json['enabled'] != false,
      order: json['order'] is int ? json['order'] as int : 0,
    );
  }

  String urlFor(String word) =>
      fillBookSourceTemplate(urlRule, key: word, page: 1);

  String read(String body, String pageUrl) {
    if (showRule.isEmpty) {
      return body
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    final node = RuleNode.parse(body, baseUrl: pageUrl);
    return const RuleEngine().strings(showRule, node).join('\n').trim();
  }
}

List<T> parseRuleList<T>(
  String text,
  T Function(Map<String, dynamic> json) decode,
) {
  final decoded = jsonDecode(text);
  final items = decoded is List ? decoded : [decoded];
  final rules = <T>[];
  for (final item in items) {
    if (item is Map) rules.add(decode(item.cast<String, dynamic>()));
  }
  if (rules.isEmpty) throw const FormatException('没有可导入的规则');
  return rules;
}

String encodeRuleList(List<Map<String, Object?>> rules) =>
    const JsonEncoder.withIndent('  ').convert(rules);
