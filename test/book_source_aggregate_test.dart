import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/book_source/aggregate.dart';
import 'package:wenku8_flutter/book_source/model.dart';
import 'package:wenku8_flutter/catalog.dart';

AggregateBook book({
  required int id,
  required String title,
  required String author,
  required String source,
}) => AggregateBook(
  id: id,
  title: title,
  author: author,
  sourceName: source,
  sourceUrl: 'https://$source.example',
);

void main() {
  test('merges the same title and author and keeps other authors apart', () {
    final hits = <AggregateHit>[];
    final index = <String, int>{};
    addAggregateBook(
      hits,
      index,
      book(id: 1, title: '诡秘之主', author: '爱潜水的乌贼', source: '甲'),
    );
    addAggregateBook(
      hits,
      index,
      book(id: 2, title: '诡秘之主', author: '爱潜水的乌贼', source: '乙'),
    );
    addAggregateBook(
      hits,
      index,
      book(id: 3, title: '诡秘之主', author: '另一位', source: '丙'),
    );
    addAggregateBook(
      hits,
      index,
      book(id: 2, title: '诡秘之主', author: '爱潜水的乌贼', source: '乙'),
    );
    expect(hits, hasLength(2));
    expect(hits.first.sourceCount, 2);
    expect(hits.first.books, hasLength(2));
    expect(hits.last.books.single.author, '另一位');
  });

  test('a failed source does not drop results from the others', () async {
    final result = await runAggregateSearch(
      targets: [
        AggregateTarget(
          name: '甲',
          search: () async => [
            book(id: 1, title: '书', author: '作者', source: '甲'),
          ],
        ),
        AggregateTarget(name: '乙', search: () async => throw Exception('超时')),
        AggregateTarget(
          name: '丙',
          search: () async => [
            book(id: 3, title: '书', author: '作者', source: '丙'),
          ],
        ),
      ],
    );
    expect(result.hits.single.sourceCount, 2);
    expect(result.failures, 1);
    expect(result.failedNames, ['乙']);
    expect(result.done, 3);
  });

  test('stopping leaves finished results and skips the rest', () async {
    var stop = false;
    final result = await runAggregateSearch(
      concurrency: 1,
      cancelled: () => stop,
      onProgress: (_) => stop = true,
      targets: [
        AggregateTarget(
          name: '甲',
          search: () async => [
            book(id: 1, title: '书', author: '作者', source: '甲'),
          ],
        ),
        AggregateTarget(
          name: '乙',
          search: () async => [
            book(id: 2, title: '另一本', author: '作者', source: '乙'),
          ],
        ),
      ],
    );
    expect(result.stopped, isTrue);
    expect(result.hits.single.books.single.sourceName, '甲');
    expect(result.done, 1);
  });

  test('a source that exceeds the timeout is a failure', () async {
    final result = await runAggregateSearch(
      timeout: const Duration(milliseconds: 10),
      targets: [
        AggregateTarget(
          name: '慢',
          search: () => Completer<List<AggregateBook>>().future,
        ),
        AggregateTarget(
          name: '快',
          search: () async => [
            book(id: 4, title: '书', author: '作者', source: '快'),
          ],
        ),
      ],
    );
    expect(result.failures, 1);
    expect(result.failedNames, ['慢']);
    expect(result.hits.single.books.single.sourceName, '快');
  });

  test('scope can select one group or one source', () {
    final sources = [
      const BookSource(url: 'https://a.example', name: '甲', group: '网络'),
      const BookSource(url: 'https://b.example', name: '乙', group: '完结'),
    ];
    expect(sourcesForAggregateScope(sources, group: '完结').single.name, '乙');
    expect(aggregateIncludesBuiltIn(group: '完结'), isFalse);
    expect(
      sourcesForAggregateScope(sources, sourceUrl: builtInAggregateUrl),
      isEmpty,
    );
    expect(aggregateIncludesBuiltIn(sourceUrl: builtInAggregateUrl), isTrue);
    expect(
      sourcesForAggregateScope(
        sources,
        sourceUrl: 'https://a.example',
      ).single.name,
      '甲',
    );
  });

  test('chapter titles match after ordinals and punctuation', () {
    expect(matchChapterByTitle(const ['序章', '第1章 启程', '终章'], '第一章：启程'), 1);
    expect(matchChapterByTitle(const ['序章', '终章'], '不存在的章节'), isNull);
    final plan = planSourceSwitch(
      currentTitle: '第一章：启程',
      chapters: const [
        NovelChapter('序章', ''),
        NovelChapter('第1章 启程', '', id: 8),
      ],
    );
    expect(plan.matchedTitle, isTrue);
    expect(plan.chapterIndex, 1);
    expect(
      planSourceSwitch(
        currentTitle: '没有这一章',
        chapters: const [NovelChapter('序章', '')],
      ).matchedTitle,
      isFalse,
    );
  });

  test(
    'search preferences round-trip and stay inside the allowed range',
    () async {
      final root = await Directory.systemTemp.createTemp('aggregate-search');
      addTearDown(() => root.delete(recursive: true));
      await const AggregateSearchPreferences(
        concurrency: 20,
        timeoutSeconds: 1,
      ).clamped().save(root);
      final loaded = await AggregateSearchPreferences.load(root);
      expect(loaded.concurrency, 8);
      expect(loaded.timeoutSeconds, 5);
    },
  );
}
