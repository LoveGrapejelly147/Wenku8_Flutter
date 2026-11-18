import 'package:flutter/material.dart';

import '../book_identity.dart';
import '../book_search.dart';
import '../catalog.dart';
import '../offline_repository.dart';
import '../online_component.dart';
import '../publication_catalog.dart';
import '../tag_catalogue.dart';
import 'engine.dart';
import 'model.dart';
import 'store.dart';
import 'url_template.dart';

/// Wenku8 stays the primary catalogue. Enabled text sources are searched beside
/// it and then use the same detail, directory, chapter, shelf and cache ids.
class BookSourceRepository extends NovelRepository
    implements PublicationCatalog, ProgressiveTagCatalogue {
  BookSourceRepository({
    required this.primary,
    required this.store,
    BookSourceEngine? engine,
  }) : engine = engine ?? BookSourceEngine();

  final NovelRepository primary;
  final BookSourceStore store;
  final BookSourceEngine engine;

  static const builtInName = '轻小说文库';

  @override
  Future<List<Novel>> list() => primary.list();

  @override
  Future<NovelPage> browse({
    NovelSort sort = NovelSort.lastUpdate,
    int page = 1,
    bool refresh = false,
  }) => primary.browse(sort: sort, page: page, refresh: refresh);

  @override
  Future<List<PublicationLibrary>> publicationLibraries({
    bool refresh = false,
  }) => _publications.publicationLibraries(refresh: refresh);

  @override
  Future<NovelPage> browsePublication(
    int libraryId, {
    int page = 1,
    bool refresh = false,
  }) =>
      _publications.browsePublication(libraryId, page: page, refresh: refresh);

  @override
  Future<NovelPage> tagPage(
    String tag, {
    int page = 1,
    bool refresh = false,
    bool Function()? current,
    TagProgressCallback? onProgress,
  }) {
    final catalogue = primary;
    if (catalogue is ProgressiveTagCatalogue) {
      return (catalogue as ProgressiveTagCatalogue).tagPage(
        tag,
        page: page,
        refresh: refresh,
        current: current,
        onProgress: onProgress,
      );
    }
    return searchFilteredPage(tag, field: BookSearchField.tags, page: page);
  }

  @override
  Future<List<Novel>> search(String query) async =>
      (await searchFilteredPage(query)).items;

  @override
  Future<NovelPage> searchPage(
    String query, {
    int page = 1,
    bool refresh = false,
  }) => searchFilteredPage(query, page: page, refresh: refresh);

  @override
  Future<NovelPage> searchFilteredPage(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
  }) async {
    final enabled = store.enabledSources;
    if (enabled.isEmpty || field == BookSearchField.id) {
      return primary.searchFilteredPage(
        query,
        field: field,
        page: page,
        refresh: refresh,
      );
    }
    NovelPage? primaryPage;
    Object? primaryError;
    try {
      primaryPage = await primary.searchFilteredPage(
        query,
        field: field,
        page: page,
        refresh: refresh,
      );
    } catch (error) {
      primaryError = error;
    }
    final custom = await _searchSources(
      enabled,
      query,
      field: field,
      page: page,
    );
    if (primaryPage == null && custom.books.isEmpty) {
      if (custom.errors.isNotEmpty) throw custom.errors.first;
      if (primaryError != null) throw primaryError;
    }
    final merged = <int, Novel>{
      for (final book in primaryPage?.items ?? const <Novel>[]) book.id: book,
      for (final book in custom.books) book.id: book,
    };
    final mayHaveMore = custom.mayHaveMore;
    return NovelPage(
      items: List.unmodifiable(merged.values),
      page: page,
      totalPages: mayHaveMore ? null : (primaryPage?.totalPages ?? page),
      totalItems:
          (primaryPage?.totalItems ?? merged.length) +
          (primaryPage == null ? 0 : custom.books.length),
      searchFailures: {
        ...?primaryPage?.searchFailures,
        if (primaryError != null &&
            !_quietPrimary(primaryError) &&
            custom.books.isNotEmpty)
          field: primaryError,
      },
    );
  }

  @override
  Future<NovelPage> authorPage(
    String author, {
    int page = 1,
    bool refresh = false,
  }) async {
    NovelPage? primaryPage;
    Object? primaryError;
    try {
      primaryPage = await primary.authorPage(
        author,
        page: page,
        refresh: refresh,
      );
    } catch (error) {
      primaryError = error;
    }
    final custom = await _searchSources(
      store.enabledSources,
      author,
      field: BookSearchField.author,
      page: page,
    );
    if (primaryPage == null && custom.books.isEmpty && primaryError != null) {
      if (custom.errors.isNotEmpty) throw custom.errors.first;
      throw primaryError;
    }
    final merged = <int, Novel>{
      for (final book in primaryPage?.items ?? const <Novel>[]) book.id: book,
      for (final book in custom.books) book.id: book,
    };
    return NovelPage(
      items: List.unmodifiable(merged.values),
      page: page,
      totalPages: custom.mayHaveMore ? null : (primaryPage?.totalPages ?? page),
      totalItems: merged.length,
    );
  }

  @override
  Future<Novel?> find(int id) async {
    if (!isCustomSourceBook(id)) return primary.find(id);
    final record = store.book(id);
    return record == null ? null : _novel(record);
  }

  @override
  Future<Novel> detail(Novel novel) async {
    if (!isCustomSourceBook(novel.id)) return primary.detail(novel);
    final record = store.book(novel.id);
    if (record == null) {
      throw const FormatException('找不到这本书的书源记录');
    }
    final source = store.sourceByUrl(record.sourceUrl);
    if (source == null) return _novel(record);
    try {
      final detailed = await engine.detail(source, record);
      return _novel(await store.remember(detailed));
    } catch (error) {
      if (record.name.isNotEmpty) return _novel(record);
      rethrow;
    }
  }

  @override
  Future<List<NovelChapter>> chapters(int id) async {
    if (!isCustomSourceBook(id)) return primary.chapters(id);
    final record = store.book(id);
    if (record == null) throw const FormatException('找不到这本书的书源记录');
    final source = store.sourceByUrl(record.sourceUrl);
    if (source == null) {
      if (record.chapters.isNotEmpty) return _chapters(record);
      throw const FormatException('这本书的书源已删除');
    }
    try {
      final listed = await engine.toc(source, record);
      return _chapters(await store.remember(listed));
    } catch (error) {
      if (record.chapters.isNotEmpty) return _chapters(record);
      rethrow;
    }
  }

  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) async {
    if (!isCustomSourceBook(novelId)) {
      return primary.chapterContent(novelId, chapter);
    }
    final record = store.book(novelId);
    if (record == null) throw const FormatException('找不到这本书的书源记录');
    final source = store.sourceByUrl(record.sourceUrl);
    if (source == null) throw const FormatException('这本书的书源已删除');
    final ref = record.chapter(chapter.id);
    if (ref == null) {
      final refreshed = await engine.toc(source, record);
      await store.remember(refreshed);
      final found = refreshed.chapter(chapter.id);
      if (found == null) throw const FormatException('章节已不在目录中');
      return engine.content(source, refreshed, found);
    }
    return engine.content(source, record, ref);
  }

  Future<({List<Novel> books, List<Object> errors, bool mayHaveMore})>
  _searchSources(
    List<BookSource> sources,
    String query, {
    required BookSearchField field,
    required int page,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty || sources.isEmpty) {
      return (
        books: const <Novel>[],
        errors: const <Object>[],
        mayHaveMore: false,
      );
    }
    final results = await _pool(sources, (source) async {
      try {
        final found = await engine.search(
          source,
          keyword,
          page: page,
          identify: store.idFor,
        );
        final novels = <Novel>[];
        var usesPage = false;
        for (final record in found) {
          if (!_matchesField(record, field, keyword)) continue;
          final id = record.id == 0
              ? store.idFor(record.sourceUrl, record.bookUrl)
              : record.id;
          final stored = await store.remember(record.copyWith(id: id));
          novels.add(_novel(stored));
        }
        usesPage = searchUrlUsesPage(source.searchUrl) && novels.isNotEmpty;
        return (books: novels, error: null, mayHaveMore: usesPage);
      } catch (error) {
        return (books: const <Novel>[], error: error, mayHaveMore: false);
      }
    });
    return (
      books: [for (final result in results) ...result.books],
      errors: [
        for (final result in results)
          if (result.error != null) result.error!,
      ],
      mayHaveMore: results.any((result) => result.mayHaveMore),
    );
  }

  bool _matchesField(
    CustomBookRecord book,
    BookSearchField field,
    String query,
  ) {
    final needle = query.trim().toLowerCase();
    return switch (field) {
      BookSearchField.author => book.author.toLowerCase().contains(needle),
      BookSearchField.tags =>
        book.kind.toLowerCase().contains(needle) ||
            book.name.toLowerCase().contains(needle),
      BookSearchField.id => false,
      _ => true,
    };
  }

  Novel novelFrom(CustomBookRecord record) => _novel(record);

  Novel _novel(CustomBookRecord record) => Novel(
    id: record.id,
    title: record.name,
    author: record.author,
    genre: record.kind,
    summary: record.intro,
    colors: _colors(record.name),
    chapters: _chapters(record),
    coverUrl: record.coverUrl.isEmpty ? null : record.coverUrl,
    lastUpdate: record.lastChapter.isEmpty ? null : record.lastChapter,
    chapterCount: record.chapters.length,
  );

  List<NovelChapter> _chapters(CustomBookRecord record) => [
    for (final chapter in record.chapters)
      NovelChapter(
        chapter.title,
        '',
        id: chapter.id,
        volumeId: chapter.volumeId,
        volumeTitle: chapter.volumeTitle,
      ),
  ];

  PublicationCatalog get _publications {
    final source = primary;
    if (source is PublicationCatalog) {
      return source as PublicationCatalog;
    }
    throw const FormatException('当前书库没有出版目录');
  }

  bool _quietPrimary(Object error) => error is OnlineComponentUnavailable;
}

List<Color> _colors(String seed) {
  final hue = (seed.hashCode.abs() % 360).toDouble();
  return [
    HSLColor.fromAHSL(1, hue, .28, .20).toColor(),
    HSLColor.fromAHSL(1, (hue + 28) % 360, .22, .30).toColor(),
  ];
}

Future<List<T>> _pool<S, T>(
  List<S> items,
  Future<T> Function(S item) action,
) async {
  final results = List<T?>.filled(items.length, null);
  var cursor = 0;
  Future<void> worker() async {
    while (cursor < items.length) {
      final index = cursor++;
      results[index] = await action(items[index]);
    }
  }

  final width = items.length < 3 ? items.length : 3;
  await Future.wait([for (var i = 0; i < width; i++) worker()]);
  return results.cast<T>();
}

/// Used by settings to find the Android book-source catalogue.
BookSourceRepository? bookSourceRepositoryOf(NovelRepository? repository) {
  if (repository is BookSourceRepository) return repository;
  if (repository is OfflineNovelRepository &&
      repository.remote is BookSourceRepository) {
    return repository.remote as BookSourceRepository;
  }
  return null;
}
