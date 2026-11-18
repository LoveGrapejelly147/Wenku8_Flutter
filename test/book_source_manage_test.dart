import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/book_source/store.dart';
import 'package:wenku8_flutter/book_source/engine.dart';
import 'package:wenku8_flutter/book_source/http.dart';
import 'package:wenku8_flutter/book_source/manage.dart';
import 'package:wenku8_flutter/book_source/model.dart';
import 'package:wenku8_flutter/book_source/url_template.dart';

void main() {
  final sources = [
    const BookSource(
      url: 'https://a.example',
      name: '甲',
      group: '网络,完结',
      order: 0,
    ),
    const BookSource(
      url: 'https://b.example',
      name: '乙',
      group: '完结',
      order: 1,
    ),
    const BookSource(
      url: 'https://c.example/search',
      name: '丙源',
      group: '',
      order: 2,
    ),
  ];

  test('filters sources by group, name and url', () {
    expect(
      filterBookSources(
        sources,
        const BookSourceQuery(group: '完结'),
      ).map((s) => s.name),
      ['甲', '乙'],
    );
    expect(
      filterBookSources(
        sources,
        const BookSourceQuery(text: 'search'),
      ).single.name,
      '丙源',
    );
    final checks = {
      'https://b.example': BookSourceCheck(
        url: 'https://b.example',
        status: BookSourceCheckStatus.failed,
        message: '超时',
        elapsedMs: 20,
        checkedAt: 1,
      ),
    };
    expect(
      filterBookSources(
        sources,
        BookSourceQuery(onlyInvalid: true, checks: checks),
      ).single.name,
      '乙',
    );
  });

  test('reorders and pins sources by updating order', () {
    final moved = moveBookSource(sources, 0, 2);
    expect(moved.map((source) => source.name), ['乙', '丙源', '甲']);
    expect(moved.map((source) => source.order), [0, 1, 2]);
    final pinned = pinBookSource(
      sources,
      'https://c.example/search',
      top: true,
    );
    expect(pinned.first.name, '丙源');
    expect(
      pinBookSource(sources, 'https://a.example', top: false).last.name,
      '甲',
    );
  });

  test('renames and removes a group segment', () {
    expect(replaceBookSourceGroup('网络,完结', '网络', '精校'), '精校,完结');
    expect(removeBookSourceGroup('网络,完结', '完结'), '网络');
  });

  test(
    'checks sources concurrently and marks empty or failed results',
    () async {
      final engine = BookSourceEngine(
        fetch: (BookSourceRequestSpec request) async {
          if (request.url.contains('fail')) throw const FormatException('连接失败');
          final body = request.url.contains('empty')
              ? '<html></html>'
              : '<a href="/book">书</a>';
          return BookSourceResponse(url: request.url, body: body, status: 200);
        },
      );
      final checks = await checkBookSources(engine, [
        const BookSource(
          url: 'https://ok.example',
          name: '好',
          searchUrl: 'https://ok.example/s?q={{key}}',
          search: BookSourceRules({'name': 'a@text', 'bookUrl': 'a@href'}),
        ),
        const BookSource(
          url: 'https://empty.example',
          name: '空',
          searchUrl: 'https://empty.example/s?q={{key}}',
          search: BookSourceRules({
            'bookList': 'li',
            'name': 'a@text',
            'bookUrl': 'a@href',
          }),
        ),
        const BookSource(
          url: 'https://fail.example',
          name: '坏',
          searchUrl: 'https://fail.example/s?q={{key}}',
        ),
      ]);
      expect(checks.map((check) => check.status), [
        BookSourceCheckStatus.ok,
        BookSourceCheckStatus.empty,
        BookSourceCheckStatus.failed,
      ]);
      expect(checks[0].invalid, isFalse);
      expect(checks[1].label, contains('无结果'));
      expect(checks[2].message, '连接失败');
    },
  );

  test('store keeps order, groups and the latest check', () async {
    final root = await Directory.systemTemp.createTemp('book-source-manage');
    addTearDown(() => root.delete(recursive: true));
    final store = BookSourceStore(root);
    await store.importAll(sources);
    await store.reorderSources(2, 0);
    await store.setGroupMany(['https://c.example/search'], '精校');
    await store.recordChecks([
      BookSourceCheck(
        url: 'https://c.example/search',
        status: BookSourceCheckStatus.ok,
        message: '搜到 1 本',
        elapsedMs: 12,
        checkedAt: 9,
      ),
    ]);
    final loaded = BookSourceStore(root);
    await loaded.load();
    expect(loaded.sources.map((source) => source.name), ['丙源', '甲', '乙']);
    expect(loaded.sources.first.group, '精校');
    expect(loaded.checks['https://c.example/search']?.elapsedMs, 12);
  });
}
