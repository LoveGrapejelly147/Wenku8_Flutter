import 'content_text.dart';
import 'explore.dart';
import 'http.dart';
import 'js_runtime.dart';
import 'model.dart';
import 'rule_engine.dart';
import 'url_template.dart';

/// Runs search, detail, directory and chapter rules for one text source.
class BookSourceEngine {
  BookSourceEngine({RuleEngine? rules, BookSourceFetcher? fetch, this.scripts})
    : rules = rules ?? const RuleEngine(),
      fetch = fetch ?? BookSourceHttp.shared.send;

  final RuleEngine rules;
  final BookSourceFetcher fetch;
  final BookSourceScripts? scripts;
  static const maxSearchResults = 80;
  static const maxChapters = 5000;
  static const maxTocPages = 20;
  static const maxContentPages = 8;

  Future<List<CustomBookRecord>> search(
    BookSource source,
    String keyword, {
    int page = 1,
    int Function(String sourceUrl, String bookUrl)? identify,
  }) async {
    _ensureText(source);
    if (keyword.trim().isEmpty) return const [];
    if (page > 1 && !searchUrlUsesPage(source.searchUrl)) return const [];
    final requests = parseSearchRequests(
      searchUrl: _scriptedUrl(source, source.searchUrl, keyword.trim(), page),
      sourceUrl: source.url,
      sourceHeaders: source.headers,
      key: keyword.trim(),
      page: page,
      script: (expression) =>
          _script(source, expression, key: keyword, page: page),
    );
    return _collect(
      source,
      source.search,
      requests,
      key: keyword.trim(),
      page: page,
      identify: identify,
      limit: maxSearchResults,
    );
  }

  Future<List<CustomBookRecord>> explore(
    BookSource source,
    String url, {
    int page = 1,
    int Function(String sourceUrl, String bookUrl)? identify,
  }) async {
    _ensureText(source);
    if (url.trim().isEmpty) return const [];
    if (page > 1 && !searchUrlUsesPage(url) && !ruleHasScript(url)) {
      return const [];
    }
    final requests = parseSearchRequests(
      searchUrl: _scriptedUrl(source, url, '', page),
      sourceUrl: source.url,
      sourceHeaders: source.headers,
      key: '',
      page: page,
      script: (expression) => _script(source, expression, page: page),
    );
    return _collect(
      source,
      exploreRules(source),
      requests,
      page: page,
      identify: identify,
      limit: maxSearchResults,
    );
  }

  Future<List<CustomBookRecord>> _collect(
    BookSource source,
    BookSourceRules fields,
    List<BookSourceRequestSpec> requests, {
    required int page,
    required int limit,
    String key = '',
    int Function(String sourceUrl, String bookUrl)? identify,
  }) async {
    final books = <CustomBookRecord>[];
    final seen = <String>{};
    for (final request in requests) {
      final response = await fetch(request);
      final node = RuleNode.parse(response.body, baseUrl: response.url);
      final items = _items(
        source,
        fields['bookList'],
        node,
        key: key,
        page: page,
      );
      for (final item in items) {
        final name = _field(source, fields['name'], item, key: key, page: page);
        final link = _field(
          source,
          fields['bookUrl'],
          item,
          key: key,
          page: page,
        );
        if (name.isEmpty || link.isEmpty) continue;
        final bookUrl = canonicalBookSourceUrl(
          resolveBookSourceUrl(response.url, link),
        );
        if (!seen.add(bookUrl)) continue;
        final cover = _field(
          source,
          fields['coverUrl'],
          item,
          key: key,
          page: page,
        );
        final intro = _plain(
          _field(source, fields['intro'], item, key: key, page: page),
          response.url,
        );
        books.add(
          CustomBookRecord(
            id: identify?.call(source.url, bookUrl) ?? 0,
            sourceUrl: source.url,
            bookUrl: bookUrl,
            name: name,
            author: _field(
              source,
              fields['author'],
              item,
              key: key,
              page: page,
            ),
            kind: _field(source, fields['kind'], item, key: key, page: page),
            intro: intro,
            coverUrl: cover.isEmpty
                ? ''
                : resolveBookSourceUrl(response.url, cover),
            lastChapter: _field(
              source,
              fields['lastChapter'],
              item,
              key: key,
              page: page,
            ),
            wordCount: _field(
              source,
              fields['wordCount'],
              item,
              key: key,
              page: page,
            ),
          ),
        );
        if (books.length >= limit) return books;
      }
    }
    return books;
  }

  Future<CustomBookRecord> detail(
    BookSource source,
    CustomBookRecord book,
  ) async {
    _ensureText(source);
    final response = await _get(source, book.bookUrl);
    var node = RuleNode.parse(response.body, baseUrl: response.url);
    var pageUrl = response.url;
    final init = source.info['init'].trim();
    if (init.isNotEmpty) {
      final value = _field(source, init, node, key: '', page: 1);
      final first = value.split('\n').first.trim();
      if (first.startsWith('http') || first.startsWith('/')) {
        final next = await _get(source, resolveBookSourceUrl(pageUrl, first));
        pageUrl = next.url;
        node = RuleNode.parse(next.body, baseUrl: next.url);
      } else if (value.contains('<')) {
        node = RuleNode.parse(value, baseUrl: pageUrl);
      } else {
        final selected = rules.nodes(init, node);
        if (selected.isNotEmpty) node = selected.first;
      }
    }
    String field(String rule, String fallback) {
      if (rule.trim().isEmpty) return fallback;
      final value = _field(source, rule, node, key: '', page: 1);
      return value.isEmpty ? fallback : value;
    }

    final tocRaw = field(source.info['tocUrl'], '');
    final cover = field(source.info['coverUrl'], '');
    return book.copyWith(
      name: _one([field(source.info['name'], book.name)]),
      author: field(source.info['author'], book.author),
      kind: field(source.info['kind'], book.kind),
      intro: _plain(field(source.info['intro'], book.intro), pageUrl),
      coverUrl: cover.isEmpty
          ? book.coverUrl
          : resolveBookSourceUrl(pageUrl, cover),
      lastChapter: field(source.info['lastChapter'], book.lastChapter),
      wordCount: field(source.info['wordCount'], book.wordCount),
      tocUrl: tocRaw.isEmpty
          ? (book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl)
          : canonicalBookSourceUrl(
              resolveBookSourceUrl(pageUrl, tocRaw.split('\n').first.trim()),
            ),
    );
  }

  Future<CustomBookRecord> toc(BookSource source, CustomBookRecord book) async {
    _ensureText(source);
    final listRule = source.toc['chapterList'].trim();
    if (listRule.isEmpty) {
      throw const BookSourceRuleException('目录规则 chapterList 为空');
    }
    var url = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl;
    final chapters = <CustomChapterRef>[];
    final seenPages = <String>{};
    var volumeTitle = '';
    var volumeId = 0;
    for (var hop = 0; hop < maxTocPages && url.isNotEmpty; hop++) {
      final canonical = canonicalBookSourceUrl(url);
      if (!seenPages.add(canonical)) break;
      final response = await _get(source, canonical);
      final node = RuleNode.parse(response.body, baseUrl: response.url);
      final items = rules.nodes(listRule, node);
      for (final item in items) {
        final title = _field(
          source,
          source.toc['chapterName'],
          item,
          key: '',
          page: 1,
        );
        final link = _field(
          source,
          source.toc['chapterUrl'],
          item,
          key: '',
          page: 1,
        );
        if (_isVolume(source, item)) {
          if (title.isNotEmpty) {
            volumeTitle = title;
            volumeId++;
          }
          continue;
        }
        if (title.isEmpty || link.isEmpty) continue;
        chapters.add(
          CustomChapterRef(
            id: chapters.length + 1,
            title: title,
            url: canonicalBookSourceUrl(
              resolveBookSourceUrl(response.url, link),
            ),
            volumeId: volumeId,
            volumeTitle: volumeTitle,
          ),
        );
        if (chapters.length >= maxChapters) break;
      }
      final nextRule = source.toc['nextTocUrl'].trim();
      if (nextRule.isEmpty || chapters.length >= maxChapters) break;
      final next = _one(rules.strings(nextRule, node));
      if (next.isEmpty) break;
      url = resolveBookSourceUrl(response.url, next);
    }
    if (chapters.isEmpty) {
      throw const BookSourceRuleException('目录规则没有匹配到章节');
    }
    return book.copyWith(chapters: chapters);
  }

  Future<String> content(
    BookSource source,
    CustomBookRecord book,
    CustomChapterRef chapter,
  ) async {
    _ensureText(source);
    if (chapter.url.isEmpty) {
      throw const BookSourceRuleException('章节缺少链接');
    }
    final contentRule = source.content['content'].trim();
    if (contentRule.isEmpty && source.content['sourceRegex'].trim().isEmpty) {
      throw const BookSourceRuleException('正文规则 content 为空');
    }
    var url = chapter.url;
    final pages = <String>[];
    final seen = <String>{};
    var base = url;
    for (var hop = 0; hop < maxContentPages && url.isNotEmpty; hop++) {
      final canonical = canonicalBookSourceUrl(url);
      if (!seen.add(canonical)) break;
      final response = await _get(source, canonical);
      base = response.url;
      var html = response.body;
      final sourceRegex = source.content['sourceRegex'].trim();
      if (sourceRegex.isNotEmpty) {
        html = rules
            .strings(sourceRegex, RuleNode.text(html, baseUrl: base))
            .join('\n');
      }
      final node = RuleNode.parse(html, baseUrl: base);
      final text = contentRule.isEmpty
          ? html
          : rules.strings(contentRule, node).join('\n');
      final replaced = source.content['replaceRegex'].trim().isEmpty
          ? text
          : rules
                .strings(
                  source.content['replaceRegex'],
                  RuleNode.text(text, baseUrl: base),
                )
                .join('\n');
      if (replaced.trim().isNotEmpty) pages.add(replaced);
      final nextRule = source.content['nextContentUrl'].trim();
      if (nextRule.isEmpty) break;
      final next = _one(rules.strings(nextRule, node));
      if (next.isEmpty) break;
      url = resolveBookSourceUrl(base, next);
    }
    final body = bookSourceContentText(pages.join('\n'), base);
    if (body.trim().isEmpty) {
      throw const FormatException('章节正文为空');
    }
    return body;
  }

  bool _isVolume(BookSource source, RuleNode item) {
    final rule = source.toc['isVolume'].trim();
    if (rule.isEmpty) return false;
    final value = _one(rules.strings(rule, item)).toLowerCase();
    return value == 'true' || value == '1' || value == '是';
  }

  Future<BookSourceResponse> _get(BookSource source, String url) {
    final resolved = resolveBookSourceUrl(source.url, url);
    return fetch(
      BookSourceRequestSpec(
        url: resolved,
        headers: {'User-Agent': bookSourceUserAgent, ...source.headers},
      ),
    );
  }

  JsContext _context(RuleNode node, {required String key, required int page}) =>
      JsContext(result: node.raw, baseUrl: node.baseUrl, key: key, page: page);

  PreparedRule _prepare(
    BookSource source,
    String rule,
    RuleNode node, {
    required String key,
    required int page,
  }) =>
      scripts?.prepare(source, rule, _context(node, key: key, page: page)) ??
      PreparedRule(rule, done: false);

  String _field(
    BookSource source,
    String rule,
    RuleNode node, {
    required String key,
    required int page,
  }) {
    final prepared = _prepare(source, rule, node, key: key, page: page);
    if (prepared.done) return prepared.text.trim();
    if (prepared.text.trim().isEmpty) return '';
    return _one(rules.strings(prepared.text, node));
  }

  List<RuleNode> _items(
    BookSource source,
    String rule,
    RuleNode node, {
    required String key,
    required int page,
  }) {
    final trimmed = rule.trim();
    final scripts = this.scripts;
    if (scripts != null &&
        (trimmed.startsWith('<js>') || trimmed.startsWith('@js:'))) {
      final code = trimmed.startsWith('@js:')
          ? trimmed.substring(4)
          : RegExp(r'^<js>([\s\S]*)</js>$').firstMatch(trimmed)?.group(1) ??
                trimmed;
      final raw = scripts.evalRaw(
        source,
        code,
        _context(node, key: key, page: page),
      );
      if (raw is List) {
        return [
          for (final item in raw)
            RuleNode.parse('$item', baseUrl: node.baseUrl),
        ];
      }
      final text = raw == null ? '' : '$raw'.trim();
      if (text.isEmpty) return [node];
      return rules.nodes(text, node);
    }
    final prepared = _prepare(source, rule, node, key: key, page: page);
    if (prepared.text.trim().isEmpty) return [node];
    return rules.nodes(prepared.text, node);
  }

  String _script(
    BookSource source,
    String expression, {
    String key = '',
    int page = 1,
  }) {
    final scripts = this.scripts;
    if (scripts == null) {
      throw BookSourceRuleException('不支持 URL 中的 JavaScript 模板 {{$expression}}');
    }
    return scripts.eval(
      source,
      expression,
      JsContext(key: key, page: page, baseUrl: source.url),
    );
  }

  String _scriptedUrl(BookSource source, String url, String key, int page) {
    final trimmed = url.trim();
    if (scripts == null || !ruleHasScript(trimmed)) return url;
    if (trimmed.startsWith('<js>') || trimmed.startsWith('@js:')) {
      return scripts!
          .prepare(
            source,
            trimmed,
            JsContext(key: key, page: page, baseUrl: source.url),
          )
          .text;
    }
    return url;
  }

  void _ensureText(BookSource source) {
    if (!source.isText) {
      throw const BookSourceRuleException('仅支持文本书源');
    }
  }

  String _one(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _plain(String value, String baseUrl) {
    if (!value.contains('<')) return value.trim();
    return bookSourceContentText(value, baseUrl).replaceAll('\n\n', '\n');
  }
}
