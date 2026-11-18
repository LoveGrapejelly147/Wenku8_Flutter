import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../book_identity.dart';
import 'manage.dart';
import 'model.dart';
import 'url_template.dart';

int hashCustomBookId(String sourceUrl, String bookUrl) {
  final digest = sha1.convert(utf8.encode('$sourceUrl\n$bookUrl')).bytes;
  final mixed =
      (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3];
  const span = localBookIdStart - customSourceBookIdStart;
  return customSourceBookIdStart + mixed % span;
}

/// Persists imported sources and the stable ids of books found through them.
class BookSourceStore extends ChangeNotifier {
  BookSourceStore(this.root);
  final Directory? root;
  final List<BookSource> sources = [];
  final Map<int, CustomBookRecord> books = {};
  final Map<String, BookSourceCheck> checks = {};
  Future<void> _writes = Future<void>.value();

  static Future<BookSourceStore> open() async {
    final support = await getApplicationSupportDirectory();
    final store = BookSourceStore(Directory('${support.path}/book_sources'));
    await store.load();
    return store;
  }

  List<BookSource> get enabledSources =>
      sources.where((source) => source.enabled && source.isText).toList();

  BookSource? sourceByUrl(String url) {
    final canonical = canonicalBookSourceUrl(url);
    for (final source in sources) {
      if (source.url == canonical) return source;
    }
    return null;
  }

  CustomBookRecord? book(int id) => books[id];

  Future<void> load() async {
    final directory = root;
    if (directory == null) return;
    sources
      ..clear()
      ..addAll(await _readSources(File('${directory.path}/sources.json')));
    books
      ..clear()
      ..addAll(await _readBooks(File('${directory.path}/books.json')));
    checks
      ..clear()
      ..addAll(await _readChecks(File('${directory.path}/checks.json')));
    notifyListeners();
  }

  Future<int> importAll(List<BookSource> incoming) {
    return _serialized(() async {
      var added = 0;
      for (final source in incoming) {
        final index = sources.indexWhere((item) => item.url == source.url);
        if (index >= 0) {
          sources[index] = source;
        } else {
          sources.add(source);
          added++;
        }
      }
      sources.sort((a, b) {
        final order = a.order.compareTo(b.order);
        return order != 0 ? order : a.name.compareTo(b.name);
      });
      await _writeSources();
      notifyListeners();
      return added;
    });
  }

  Future<void> save(BookSource source) {
    return _serialized(() async {
      final canonical = canonicalBookSourceUrl(source.url);
      final next = source.url == canonical
          ? source
          : source.copyWith(url: canonical);
      final index = sources.indexWhere((item) => item.url == next.url);
      if (index >= 0) {
        sources[index] = next;
      } else {
        sources.add(next);
      }
      await _writeSources();
      notifyListeners();
    });
  }

  Future<void> setEnabled(String url, bool enabled) {
    final source = sourceByUrl(url);
    if (source == null || source.enabled == enabled) {
      return Future<void>.value();
    }
    return save(source.copyWith(enabled: enabled));
  }

  Future<void> setEnabledMany(Iterable<String> urls, bool enabled) {
    return _serialized(() async {
      final selected = urls.map(canonicalBookSourceUrl).toSet();
      for (var index = 0; index < sources.length; index++) {
        if (selected.contains(sources[index].url)) {
          sources[index] = sources[index].copyWith(enabled: enabled);
        }
      }
      await _writeSources();
      notifyListeners();
    });
  }

  Future<void> setGroupMany(Iterable<String> urls, String group) {
    return _serialized(() async {
      final selected = urls.map(canonicalBookSourceUrl).toSet();
      for (var index = 0; index < sources.length; index++) {
        if (selected.contains(sources[index].url)) {
          sources[index] = sources[index].copyWith(group: group.trim());
        }
      }
      await _writeSources();
      notifyListeners();
    });
  }

  Future<void> renameGroup(String from, String to) {
    return _serialized(() async {
      for (var index = 0; index < sources.length; index++) {
        sources[index] = sources[index].copyWith(
          group: replaceBookSourceGroup(sources[index].group, from, to),
        );
      }
      await _writeSources();
      notifyListeners();
    });
  }

  Future<void> removeGroup(String group) => renameGroup(group, '');

  Future<void> reorderSources(int from, int to) {
    return _serialized(() async {
      final next = moveBookSource([...sources], from, to);
      sources
        ..clear()
        ..addAll(next);
      await _writeSources();
      notifyListeners();
    });
  }

  Future<void> pinSource(String url, {required bool top}) {
    return _serialized(() async {
      final next = pinBookSource(
        [...sources],
        canonicalBookSourceUrl(url),
        top: top,
      );
      sources
        ..clear()
        ..addAll(next);
      await _writeSources();
      notifyListeners();
    });
  }

  Future<void> recordChecks(Iterable<BookSourceCheck> results) {
    return _serialized(() async {
      for (final check in results) {
        checks[check.url] = check;
      }
      await _writeChecks();
      notifyListeners();
    });
  }

  Future<void> removeMany(Iterable<String> urls) {
    return _serialized(() async {
      final selected = urls.map(canonicalBookSourceUrl).toSet();
      sources.removeWhere((source) => selected.contains(source.url));
      checks.removeWhere((url, _) => selected.contains(url));
      _reindex();
      await _writeSources();
      await _writeChecks();
      notifyListeners();
    });
  }

  void _reindex() {
    for (var index = 0; index < sources.length; index++) {
      sources[index] = sources[index].copyWith(order: index);
    }
  }

  Future<void> remove(String url) {
    return _serialized(() async {
      final canonical = canonicalBookSourceUrl(url);
      sources.removeWhere((source) => source.url == canonical);
      checks.remove(canonical);
      _reindex();
      await _writeSources();
      await _writeChecks();
      notifyListeners();
    });
  }

  int idFor(String sourceUrl, String bookUrl) {
    final source = canonicalBookSourceUrl(sourceUrl);
    final book = canonicalBookSourceUrl(bookUrl);
    var id = hashCustomBookId(source, book);
    const span = localBookIdStart - customSourceBookIdStart;
    for (var attempt = 0; attempt < 32; attempt++) {
      final existing = books[id];
      if (existing == null ||
          (existing.sourceUrl == source && existing.bookUrl == book)) {
        return id;
      }
      id =
          customSourceBookIdStart + ((id - customSourceBookIdStart + 1) % span);
    }
    throw const FormatException('书源书籍标识冲突');
  }

  Future<CustomBookRecord> remember(CustomBookRecord record) {
    return _serialized(() async {
      final previous = books[record.id];
      final stored = previous == null
          ? record
          : record.copyWith(
              chapters: record.chapters.isEmpty
                  ? previous.chapters
                  : record.chapters,
              tocUrl: record.tocUrl.isEmpty ? previous.tocUrl : record.tocUrl,
              coverUrl: record.coverUrl.isEmpty
                  ? previous.coverUrl
                  : record.coverUrl,
              intro: record.intro.isEmpty ? previous.intro : record.intro,
            );
      books[stored.id] = stored;
      await _writeBooks();
      return stored;
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> _writeSources() async {
    final directory = root;
    if (directory == null) return;
    await _atomic(
      File('${directory.path}/sources.json'),
      encodeBookSources(sources),
    );
  }

  Future<void> _writeBooks() async {
    final directory = root;
    if (directory == null) return;
    await _atomic(
      File('${directory.path}/books.json'),
      jsonEncode({
        for (final book in books.values) '${book.id}': book.toJson(),
      }),
    );
  }

  Future<void> _writeChecks() async {
    final directory = root;
    if (directory == null) return;
    await _atomic(
      File('${directory.path}/checks.json'),
      jsonEncode({
        for (final check in checks.values) check.url: check.toJson(),
      }),
    );
  }

  Future<Map<String, BookSourceCheck>> _readChecks(File file) async {
    final text = await _readText(file);
    if (text == null || text.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const {};
      return {
        for (final value in decoded.values)
          if (value is Map)
            BookSourceCheck.fromJson(value.cast<String, dynamic>()).url:
                BookSourceCheck.fromJson(value.cast<String, dynamic>()),
      };
    } on FormatException {
      return const {};
    }
  }

  Future<List<BookSource>> _readSources(File file) async {
    final text = await _readText(file);
    if (text == null || text.trim().isEmpty) return const [];
    try {
      return parseBookSourceDocument(text);
    } on FormatException {
      await _quarantine(file);
      return const [];
    }
  }

  Future<Map<int, CustomBookRecord>> _readBooks(File file) async {
    final text = await _readText(file);
    if (text == null || text.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const {};
      final records = <int, CustomBookRecord>{};
      for (final value in decoded.values) {
        if (value is! Map) continue;
        final record = CustomBookRecord.fromJson(value.cast<String, dynamic>());
        if (isCustomSourceBook(record.id) && record.bookUrl.isNotEmpty) {
          records[record.id] = record;
        }
      }
      return records;
    } on FormatException {
      await _quarantine(file);
      return const {};
    }
  }

  Future<String?> _readText(File file) async {
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> _atomic(File file, String text) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> _quarantine(File file) async {
    final broken = File('${file.path}.bad');
    if (await file.exists()) await file.rename(broken.path);
  }
}
