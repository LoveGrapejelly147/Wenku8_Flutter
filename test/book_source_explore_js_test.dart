import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/book_source/engine.dart';
import 'package:wenku8_flutter/book_source/explore.dart';
import 'package:wenku8_flutter/book_source/http.dart';
import 'package:wenku8_flutter/book_source/js_runtime.dart';
import 'package:wenku8_flutter/book_source/model.dart';

void main() {
  test('explore urls accept lines, && and json', () {
    expect(
      parseExploreKinds(
        '玄幻::https://a.example/x\n都市::https://a.example/d',
      ).map((kind) => kind.title),
      ['玄幻', '都市'],
    );
    expect(
      parseExploreKinds(
        '玄幻::https://a.example/x&&都市::https://a.example/d',
      ).last.url,
      'https://a.example/d',
    );
    final json = parseExploreKinds(
      '[{"title":"排行","url":"https://a.example/top","style":{"layout_flexGrow":1}}]',
    );
    expect(json.single.title, '排行');
    expect(
      discoverableSources(const [
        BookSource(
          url: 'https://a.example',
          name: '甲',
          exploreUrl: '玄幻::https://a.example/x',
        ),
        BookSource(
          url: 'https://b.example',
          name: '乙',
          enabledExplore: false,
          exploreUrl: '都市::https://b.example/d',
        ),
        BookSource(url: 'https://c.example', name: '丙'),
      ]).single.name,
      '甲',
    );
  });

  test(
    'explore list uses ruleExplore and falls back to search rules',
    () async {
      final engine = BookSourceEngine(
        fetch: (request) async => BookSourceResponse(
          url: request.url,
          status: 200,
          body: request.url.contains('page=2')
              ? '<a href="/b">第二本</a>'
              : '<a href="/a">第一本</a>',
        ),
      );
      const source = BookSource(
        url: 'https://a.example',
        name: '甲',
        exploreUrl: '玄幻::https://a.example/explore?page={{page}}',
        explore: BookSourceRules({'name': 'a@text', 'bookUrl': 'a@href'}),
      );
      final first = await engine.explore(
        source,
        parseExploreKinds(source.exploreUrl).single.url,
      );
      expect(first.single.name, '第一本');
      final second = await engine.explore(
        source,
        parseExploreKinds(source.exploreUrl).single.url,
        page: 2,
      );
      expect(second.single.name, '第二本');
      const fallback = BookSource(
        url: 'https://a.example',
        name: '甲',
        exploreUrl: 'https://a.example/list',
        search: BookSourceRules({'name': 'a@text', 'bookUrl': 'a@href'}),
      );
      expect(
        (await engine.explore(fallback, fallback.exploreUrl)).single.name,
        '第一本',
      );
    },
  );

  test('legado javascript rules read variables, html and ajax', () async {
    final root = await Directory.systemTemp.createTemp('js-source');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/item').writeAsString('<h1>书名</h1>');
    final server = await Process.start('python3', [
      '-m',
      'http.server',
      '8766',
      '--bind',
      '127.0.0.1',
    ], workingDirectory: root.path);
    addTearDown(server.kill);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final scripts = BookSourceScripts(timeout: const Duration(seconds: 3));
    const source = BookSource(
      url: 'https://a.example',
      name: '甲',
      jsLib: 'function prefix(value) { return "源-" + value; }',
    );
    final context = JsContext(
      result: '<h1>书名</h1>',
      baseUrl: 'https://a.example',
      key: '诡秘',
      page: 2,
    );
    expect(
      scripts.prepare(source, '<js>return prefix(key)</js>', context).text,
      '源-诡秘',
    );
    expect(scripts.prepare(source, '@js: page + 1', context).text, '3');
    expect(scripts.prepare(source, '{{key + "!"}}', context).text, '诡秘!');
    expect(
      scripts.prepare(source, '<js>java.md5Encode("a")</js>', context).text,
      '0cc175b9c0f1b6a831c399e269772661',
    );
    expect(
      scripts.prepare(source, '<js>java.base64Encode("hi")</js>', context).text,
      'aGk=',
    );
    scripts.prepare(source, '<js>java.put("token", "yes")</js>', context);
    expect(
      scripts.prepare(source, '<js>java.get("token")</js>', context).text,
      'yes',
    );
    expect(
      scripts.prepare(source, '<js>source.getKey()</js>', context).text,
      source.url,
    );
    expect(
      scripts
          .prepare(
            source,
            '<js>java.getString(result, "h1@text")</js>',
            context,
          )
          .text,
      '书名',
    );
    expect(
      scripts
          .prepare(
            source,
            '<js>java.ajax("http://127.0.0.1:8766/item")</js>',
            context,
          )
          .text
          .trim(),
      '<h1>书名</h1>',
    );
    expect(
      () => scripts.prepare(source, '<js>java.toast("x")</js>', context),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('不支持的 Java 方法 java.toast'),
        ),
      ),
    );
  });
}
