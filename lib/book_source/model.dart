import 'dart:convert';

import 'url_template.dart';

/// A Legado text book source. Unknown rule keys are kept so export stays
/// compatible with fields this editor does not show.
class BookSource {
  const BookSource({
    required this.url,
    required this.name,
    this.group = '',
    this.comment = '',
    this.enabled = true,
    this.enabledExplore = true,
    this.type = 0,
    this.order = 0,
    this.weight = 0,
    this.updatedAt = 0,
    this.searchUrl = '',
    this.exploreUrl = '',
    this.header = '',
    this.loginUrl = '',
    this.bookUrlPattern = '',
    this.search = const BookSourceRules({}),
    this.explore = const BookSourceRules({}),
    this.info = const BookSourceRules({}),
    this.toc = const BookSourceRules({}),
    this.content = const BookSourceRules({}),
  });

  final String url;
  final String name;
  final String group;
  final String comment;
  final bool enabled;
  final bool enabledExplore;
  final int type;
  final int order;
  final int weight;
  final int updatedAt;
  final String searchUrl;
  final String exploreUrl;
  final String header;
  final String loginUrl;
  final String bookUrlPattern;
  final BookSourceRules search;
  final BookSourceRules explore;
  final BookSourceRules info;
  final BookSourceRules toc;
  final BookSourceRules content;

  bool get isText => type == 0;

  Map<String, String> get headers => parseHeaderMap(header);

  BookSource copyWith({
    String? url,
    String? name,
    String? group,
    String? comment,
    bool? enabled,
    bool? enabledExplore,
    int? type,
    int? order,
    int? weight,
    int? updatedAt,
    String? searchUrl,
    String? exploreUrl,
    String? header,
    String? loginUrl,
    String? bookUrlPattern,
    BookSourceRules? search,
    BookSourceRules? explore,
    BookSourceRules? info,
    BookSourceRules? toc,
    BookSourceRules? content,
  }) => BookSource(
    url: url ?? this.url,
    name: name ?? this.name,
    group: group ?? this.group,
    comment: comment ?? this.comment,
    enabled: enabled ?? this.enabled,
    enabledExplore: enabledExplore ?? this.enabledExplore,
    type: type ?? this.type,
    order: order ?? this.order,
    weight: weight ?? this.weight,
    updatedAt: updatedAt ?? this.updatedAt,
    searchUrl: searchUrl ?? this.searchUrl,
    exploreUrl: exploreUrl ?? this.exploreUrl,
    header: header ?? this.header,
    loginUrl: loginUrl ?? this.loginUrl,
    bookUrlPattern: bookUrlPattern ?? this.bookUrlPattern,
    search: search ?? this.search,
    explore: explore ?? this.explore,
    info: info ?? this.info,
    toc: toc ?? this.toc,
    content: content ?? this.content,
  );

  factory BookSource.fromLegado(Map<String, dynamic> json) {
    final url = _text(json['bookSourceUrl']);
    final name = _text(json['bookSourceName']);
    if (url.isEmpty || name.isEmpty) {
      throw const FormatException('书源缺少 bookSourceUrl 或 bookSourceName');
    }
    final canonical = canonicalBookSourceUrl(url);
    if (Uri.tryParse(canonical)?.host.isEmpty != false) {
      throw const FormatException('书源地址无效');
    }
    return BookSource(
      url: canonical,
      name: name,
      group: _text(json['bookSourceGroup']),
      comment: _text(json['bookSourceComment']),
      enabled: json['enabled'] != false,
      enabledExplore: json['enabledExplore'] != false,
      type: _int(json['bookSourceType']),
      order: _int(json['customOrder']),
      weight: _int(json['weight']),
      updatedAt: _int(json['lastUpdateTime']),
      searchUrl: _text(json['searchUrl']),
      exploreUrl: _text(json['exploreUrl']),
      header: _headerText(json['header']),
      loginUrl: _text(json['loginUrl']),
      bookUrlPattern: _text(json['bookUrlPattern']),
      search: BookSourceRules.from(json['ruleSearch']),
      explore: BookSourceRules.from(json['ruleExplore']),
      info: BookSourceRules.from(json['ruleBookInfo']),
      toc: BookSourceRules.from(json['ruleToc']),
      content: BookSourceRules.from(json['ruleContent']),
    );
  }

  Map<String, Object?> toLegado() => {
    'bookSourceUrl': url,
    'bookSourceName': name,
    'bookSourceGroup': group,
    'bookSourceComment': comment,
    'bookSourceType': type,
    'bookUrlPattern': bookUrlPattern,
    'customOrder': order,
    'enabled': enabled,
    'enabledExplore': enabledExplore,
    'header': header,
    'loginUrl': loginUrl,
    'lastUpdateTime': updatedAt,
    'weight': weight,
    'searchUrl': searchUrl,
    'exploreUrl': exploreUrl,
    'ruleSearch': search.toJson(),
    'ruleExplore': explore.toJson(),
    'ruleBookInfo': info.toJson(),
    'ruleToc': toc.toJson(),
    'ruleContent': content.toJson(),
  };
}

class BookSourceRules {
  const BookSourceRules(this.values);
  final Map<String, String> values;

  String operator [](String key) => values[key] ?? '';

  factory BookSourceRules.from(Object? json) {
    final map = _asMap(json);
    return BookSourceRules({
      for (final entry in map.entries)
        if (_text(entry.value).isNotEmpty) entry.key: _text(entry.value),
    });
  }

  BookSourceRules merge(Map<String, String> updates) =>
      BookSourceRules({...values, ...updates});

  Map<String, String> toJson() => Map<String, String>.from(values);
}

class CustomChapterRef {
  const CustomChapterRef({
    required this.id,
    required this.title,
    required this.url,
    this.volumeId = 0,
    this.volumeTitle = '',
  });

  final int id;
  final String title;
  final String url;
  final int volumeId;
  final String volumeTitle;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    if (volumeId != 0) 'volumeId': volumeId,
    if (volumeTitle.isNotEmpty) 'volumeTitle': volumeTitle,
  };

  factory CustomChapterRef.fromJson(Map<String, dynamic> json) =>
      CustomChapterRef(
        id: _int(json['id']),
        title: _text(json['title']),
        url: _text(json['url']),
        volumeId: _int(json['volumeId']),
        volumeTitle: _text(json['volumeTitle']),
      );
}

class CustomBookRecord {
  const CustomBookRecord({
    required this.id,
    required this.sourceUrl,
    required this.bookUrl,
    required this.name,
    this.author = '',
    this.kind = '',
    this.intro = '',
    this.coverUrl = '',
    this.lastChapter = '',
    this.tocUrl = '',
    this.wordCount = '',
    this.chapters = const [],
  });

  final int id;
  final String sourceUrl;
  final String bookUrl;
  final String name;
  final String author;
  final String kind;
  final String intro;
  final String coverUrl;
  final String lastChapter;
  final String tocUrl;
  final String wordCount;
  final List<CustomChapterRef> chapters;

  CustomChapterRef? chapter(int id) {
    for (final item in chapters) {
      if (item.id == id) return item;
    }
    return null;
  }

  CustomBookRecord copyWith({
    int? id,
    String? sourceUrl,
    String? bookUrl,
    String? name,
    String? author,
    String? kind,
    String? intro,
    String? coverUrl,
    String? lastChapter,
    String? tocUrl,
    String? wordCount,
    List<CustomChapterRef>? chapters,
  }) => CustomBookRecord(
    id: id ?? this.id,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    bookUrl: bookUrl ?? this.bookUrl,
    name: name ?? this.name,
    author: author ?? this.author,
    kind: kind ?? this.kind,
    intro: intro ?? this.intro,
    coverUrl: coverUrl ?? this.coverUrl,
    lastChapter: lastChapter ?? this.lastChapter,
    tocUrl: tocUrl ?? this.tocUrl,
    wordCount: wordCount ?? this.wordCount,
    chapters: chapters ?? this.chapters,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceUrl': sourceUrl,
    'bookUrl': bookUrl,
    'name': name,
    'author': author,
    'kind': kind,
    'intro': intro,
    'coverUrl': coverUrl,
    'lastChapter': lastChapter,
    'tocUrl': tocUrl,
    'wordCount': wordCount,
    'chapters': [for (final chapter in chapters) chapter.toJson()],
  };

  factory CustomBookRecord.fromJson(Map<String, dynamic> json) {
    final chapters = json['chapters'];
    return CustomBookRecord(
      id: _int(json['id']),
      sourceUrl: _text(json['sourceUrl']),
      bookUrl: _text(json['bookUrl']),
      name: _text(json['name']),
      author: _text(json['author']),
      kind: _text(json['kind']),
      intro: _text(json['intro']),
      coverUrl: _text(json['coverUrl']),
      lastChapter: _text(json['lastChapter']),
      tocUrl: _text(json['tocUrl']),
      wordCount: _text(json['wordCount']),
      chapters: chapters is List
          ? [
              for (final item in chapters)
                if (item is Map)
                  CustomChapterRef.fromJson(item.cast<String, dynamic>()),
            ]
          : const [],
    );
  }
}

List<BookSource> parseBookSourceDocument(String text) {
  final decoded = jsonDecode(text);
  final items = decoded is List ? decoded : [decoded];
  final sources = <BookSource>[];
  for (final item in items) {
    if (item is! Map) continue;
    sources.add(BookSource.fromLegado(item.cast<String, dynamic>()));
  }
  if (sources.isEmpty) throw const FormatException('没有可导入的书源');
  return sources;
}

String encodeBookSources(List<BookSource> sources) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert([for (final source in sources) source.toLegado()]);

String _text(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _headerText(Object? value) {
  if (value is Map) return jsonEncode(value);
  return _text(value);
}

Map<String, dynamic> _asMap(Object? json) {
  if (json is Map) return json.map((key, value) => MapEntry('$key', value));
  if (json is String && json.trim().startsWith('{')) {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
  }
  return const {};
}
