import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/book_identity.dart';
import 'package:wenku8_flutter/book_source/engine.dart';
import 'package:wenku8_flutter/book_source/http.dart';
import 'package:wenku8_flutter/book_source/model.dart';
import 'package:wenku8_flutter/book_source/repository.dart';
import 'package:wenku8_flutter/book_source/store.dart';
import 'package:wenku8_flutter/book_source/url_template.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/online_component.dart';

void main() {
  test('custom search survives a missing built-in catalogue', () async {
    final store = BookSourceStore(null);
    await store.importAll([
      BookSource.fromLegado({
        'bookSourceUrl': 'https://source.example',
        'bookSourceName': '示例',
        'searchUrl': 'https://source.example/search?q={{key}}&page={{page}}',
        'ruleSearch': {
          'bookList': '.book',
          'name': 'a@text',
          'author': '.author@text',
          'bookUrl': 'a@href',
          'coverUrl': 'img@src',
          'intro': '.intro@text',
        },
        'ruleBookInfo': {
          'name': 'h1@text',
          'tocUrl': 'a.toc@href',
          'intro': '.summary@html',
        },
        'ruleToc': {
          'chapterList': '#list dd',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
          'isVolume': '.volume@text',
        },
        'ruleContent': {'content': '#content@html##<br>##\n'},
      }),
    ]);
    final repository = BookSourceRepository(
      primary: const _UnavailableCatalogue(),
      store: store,
      engine: BookSourceEngine(fetch: _fakeFetch),
    );

    final found = await repository.search('诡秘');
    expect(found, hasLength(1));
    expect(found.single.title, '诡秘之主');
    expect(found.single.author, '乌贼');
    expect(isCustomSourceBook(found.single.id), isTrue);
    expect(isLocalBook(found.single.id), isFalse);

    final detail = await repository.detail(found.single);
    expect(detail.summary, contains('雾'));
    final chapters = await repository.chapters(detail.id);
    expect(chapters.map((chapter) => chapter.title), ['序章', '第一章']);
    expect(chapters.last.volumeTitle, '第一卷');
    final text = await repository.chapterContent(detail.id, chapters.last);
    expect(text, contains('正文第一段'));
    expect(text, contains('正文第二段'));
    expect(
      text,
      contains('<!--image-->https://source.example/a.jpg<!--image-->'),
    );

    expect(await repository.find(7), isNotNull);
    expect((await repository.find(7))!.title, '文库书');
  });

  test(
    'a disabled source is skipped and a wenku id stays on the primary',
    () async {
      final store = BookSourceStore(null);
      await store.importAll([
        const BookSource(
          url: 'https://off.example',
          name: '关闭',
          enabled: false,
          searchUrl: 'https://off.example/s?q={{key}}',
        ),
      ]);
      final repository = BookSourceRepository(
        primary: const _UnavailableCatalogue(),
        store: store,
        engine: BookSourceEngine(
          fetch: (_) async => throw StateError('disabled source was called'),
        ),
      );
      expect(
        repository.search('anything'),
        throwsA(isA<OnlineComponentUnavailable>()),
      );
    },
  );
}

Future<BookSourceResponse> _fakeFetch(BookSourceRequestSpec request) async {
  final url = request.url;
  if (url.contains('/search')) {
    return BookSourceResponse(
      url: url,
      status: 200,
      body: '''
        <div class="book">
          <a href="/book/1">诡秘之主</a>
          <span class="author">乌贼</span>
          <img src="/cover.jpg">
          <p class="intro">雾与蒸汽</p>
        </div>
      ''',
    );
  }
  if (url.endsWith('/book/1')) {
    return const BookSourceResponse(
      url: 'https://source.example/book/1',
      status: 200,
      body: '''
        <h1>诡秘之主</h1>
        <div class="summary"><p>雾</p><p>蒸汽</p></div>
        <a class="toc" href="/book/1/toc">目录</a>
      ''',
    );
  }
  if (url.endsWith('/toc')) {
    return const BookSourceResponse(
      url: 'https://source.example/book/1/toc',
      status: 200,
      body: '''
        <div id="list">
          <dd><span class="volume">true</span><a href="/v">第一卷</a></dd>
          <dd><a href="/c0">序章</a></dd>
          <dd><a href="/c1">第一章</a></dd>
        </div>
      ''',
    );
  }
  return const BookSourceResponse(
    url: 'https://source.example/c1',
    status: 200,
    body: '<div id="content">正文第一段<br>正文第二段<img src="/a.jpg"></div>',
  );
}

class _UnavailableCatalogue extends NovelRepository {
  const _UnavailableCatalogue();

  @override
  Future<List<Novel>> list() => unavailableOnline();

  @override
  Future<Novel?> find(int id) async => id == 7 ? _wenku : null;

  @override
  Future<List<Novel>> search(String query) => unavailableOnline();

  @override
  Future<Novel> detail(Novel novel) async => novel;

  @override
  Future<List<NovelChapter>> chapters(int id) async => const [];

  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) =>
      unavailableOnline();
}

const _wenku = Novel(
  id: 7,
  title: '文库书',
  author: '甲',
  genre: '轻小说',
  summary: '',
  colors: [Color(0xFF111111), Color(0xFF222222)],
);
