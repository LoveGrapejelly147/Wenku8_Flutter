import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/book_source/model.dart';
import 'package:wenku8_flutter/book_source/rule_engine.dart';
import 'package:wenku8_flutter/book_source/url_template.dart';

void main() {
  const engine = RuleEngine();
  final page = RuleNode.parse('''
    <html><body>
      <div class="book">
        <a href="/b/1">诡秘之主</a>
        <span class="author">爱潜水的乌贼</span>
      </div>
      <ul class="list">
        <li class="odd">第一章</li>
        <li class="even">第二章</li>
      </ul>
      <div id="content">第一段<br>第二段</div>
    </body></html>
  ''', baseUrl: 'https://example.com/search');

  test('css and default jsoup selectors read text, href and index', () {
    expect(engine.strings('@css:div.book a@text', page), ['诡秘之主']);
    expect(engine.strings('div.book a@href', page), ['/b/1']);
    expect(engine.strings('span.author@text', page), ['爱潜水的乌贼']);
    expect(engine.strings('class.odd@text', page), ['第一章']);
    expect(engine.strings('tag.li.-1@text', page), ['第二章']);
    expect(engine.strings('li:eq(0)@text', page), ['第一章']);
    expect(engine.strings('ul.list li:gt(0)@text', page), ['第二章']);
    expect(engine.strings('#content@textNodes', page), ['第一段\n\n第二段']);
  });

  test('xpath reads attributes, text and contains()', () {
    expect(engine.strings('//div[@class="book"]/a/@href', page), ['/b/1']);
    expect(engine.strings('@XPath://ul[@class="list"]/li[2]/text()', page), [
      '第二章',
    ]);
    expect(engine.strings('//span[contains(@class,"author")]/text()', page), [
      '爱潜水的乌贼',
    ]);
  });

  test('jsonpath reads lists, indexes and filters', () {
    final node = RuleNode.parse(
      '{"data":{"list":[{"name":"甲","author":"乙"},{"name":"丙","author":"丁"}]}}',
      baseUrl: 'https://example.com/api',
    );
    expect(engine.strings(r'$.data.list[*].name', node), ['甲', '丙']);
    expect(engine.strings('@json:\$.data.list[0].author', node), ['乙']);
    expect(engine.strings(r'$.data.list[?(@.author=="丁")].name', node), ['丙']);
    expect(engine.strings(r'$..author', node), ['乙', '丁']);
  });

  test('regex replacement and combinators', () {
    expect(engine.strings(r'##章节(\d+)##第$1章', RuleNode.text('章节12')), ['第12章']);
    expect(engine.strings(r'.author@text##\s+##', page), ['爱潜水的乌贼']);
    expect(engine.strings('missing@text||.author@text', page), ['爱潜水的乌贼']);
    expect(engine.strings('.odd@text&&.even@text', page), ['第一章', '第二章']);
  });

  test('javascript rules fail with a readable error', () {
    expect(
      () => engine.strings('<js>java.ajax(result)</js>', page),
      throwsA(
        isA<BookSourceRuleException>().having(
          (error) => error.message,
          'message',
          contains('JavaScript'),
        ),
      ),
    );
    expect(
      () => engine.strings('@js:java.put("a",1)', page),
      throwsA(isA<BookSourceRuleException>()),
    );
    expect(
      () => engine.strings('{{book.name}}', page),
      throwsA(isA<BookSourceRuleException>()),
    );
  });

  test('url templates fill key, page math, post, charset and headers', () {
    final specs = parseSearchRequests(
      searchUrl:
          'https://ex.com/search.php,{"method":"POST","body":"searchkey={{key}}&page={{page-1}}","charset":"gbk","headers":{"X-Test":"1"}}',
      sourceUrl: 'https://ex.com',
      sourceHeaders: const {'User-Agent': 'ua'},
      key: '诡秘',
      page: 2,
    );
    expect(specs, hasLength(1));
    expect(specs.single.method, 'POST');
    expect(specs.single.charset, 'gbk');
    expect(
      specs.single.body,
      'searchkey=${Uri.encodeQueryComponent('诡秘')}&page=1',
    );
    expect(specs.single.headers['X-Test'], '1');
    expect(specs.single.headers['User-Agent'], 'ua');
    expect(specs.single.url, 'https://ex.com/search.php');

    final plain = parseSearchRequests(
      searchUrl: '/s?key={{key}}&page={{page}}',
      sourceUrl: 'https://ex.com/book/',
      sourceHeaders: const {},
      key: 'a b',
      page: 3,
    );
    expect(plain.single.url, 'https://ex.com/s?key=a+b&page=3');
    expect(
      () => parseSearchRequests(
        searchUrl: '{"url":"/s","webView":true}',
        sourceUrl: 'https://ex.com',
        sourceHeaders: const {},
        key: 'a',
        page: 1,
      ),
      throwsA(isA<BookSourceRuleException>()),
    );
  });

  test('legado json round-trips the common fields', () {
    const raw = '''
    [{
      "bookSourceUrl": "https://example.com/",
      "bookSourceName": "示例源",
      "bookSourceGroup": "网络",
      "searchUrl": "https://example.com/s?q={{key}}",
      "header": "{\\"User-Agent\\":\\"test\\"}",
      "exploreUrl": "https://example.com/explore",
      "enabled": false,
      "ruleSearch": {"bookList": ".book", "name": "a@text", "bookUrl": "a@href"},
      "ruleBookInfo": {"tocUrl": "a@href"},
      "ruleToc": {"chapterList": "#list a", "chapterName": "a@text"},
      "ruleContent": {"content": "#content@html", "replaceRegex": "##<br>##\\\\n"}
    }]
    ''';
    final source = parseBookSourceDocument(raw).single;
    expect(source.name, '示例源');
    expect(source.url, 'https://example.com');
    expect(source.enabled, isFalse);
    expect(source.group, '网络');
    expect(source.search['bookList'], '.book');
    expect(source.content['replaceRegex'], r'##<br>##\n');
    final again = BookSource.fromLegado(source.toLegado());
    expect(again.name, source.name);
    expect(again.searchUrl, source.searchUrl);
    expect(again.exploreUrl, source.exploreUrl);
    expect(again.toc['chapterList'], '#list a');
    expect(again.headers['User-Agent'], 'test');
  });

  test('batch import skips bad entries instead of failing them all', () {
    const raw = '''
    [
      {"bookSourceUrl": "https://a.example/", "bookSourceName": "好源A"},
      {"bookSourceName": "缺地址的源"},
      {"bookSourceUrl": "not a url", "bookSourceName": "坏地址的源"},
      {"bookSourceUrl": "https://b.example/", "bookSourceName": "好源B"},
      "not an object"
    ]
    ''';
    final report = parseBookSourceDocumentReport(raw);
    expect(
      report.sources.map((source) => source.name),
      ['好源A', '好源B'],
    );
    expect(report.skipped, 3);
    expect(parseBookSourceDocument(raw).length, 2);
  });

  test('batch import tolerates a leading BOM', () {
    const raw =
        '\uFEFF[{"bookSourceUrl": "https://a.example/", "bookSourceName": "好源A"}]';
    expect(parseBookSourceDocument(raw).single.name, '好源A');
  });

  test('batch import still fails when nothing is usable', () {
    expect(
      () => parseBookSourceDocument('[{"bookSourceName": "缺地址"}]'),
      throwsA(isA<FormatException>()),
    );
  });
}
