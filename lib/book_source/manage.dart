import 'engine.dart';
import 'model.dart';

/// One source can belong to several comma-separated Legado groups.
List<String> bookSourceGroups(BookSource source) => source.group
    .split(RegExp(r'[,，]'))
    .map((group) => group.trim())
    .where((group) => group.isNotEmpty)
    .toList();

List<String> bookSourceGroupNames(Iterable<BookSource> sources) {
  final names = <String>{
    for (final source in sources) ...bookSourceGroups(source),
  };
  final sorted = names.toList()..sort();
  return sorted;
}

String replaceBookSourceGroup(String group, String from, String to) {
  final next = <String>[];
  for (final name in group.split(RegExp(r'[,，]'))) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == from) {
      if (trimmed == from &&
          to.trim().isNotEmpty &&
          !next.contains(to.trim())) {
        next.add(to.trim());
      }
      continue;
    }
    if (!next.contains(trimmed)) next.add(trimmed);
  }
  return next.join(',');
}

String removeBookSourceGroup(String group, String target) =>
    replaceBookSourceGroup(group, target, '');

class BookSourceQuery {
  const BookSourceQuery({
    this.text = '',
    this.group = '',
    this.onlyInvalid = false,
    this.checks = const {},
  });

  final String text;
  final String group;
  final bool onlyInvalid;
  final Map<String, BookSourceCheck> checks;

  bool get canReorder => text.trim().isEmpty && group.isEmpty && !onlyInvalid;
}

List<BookSource> filterBookSources(
  List<BookSource> sources,
  BookSourceQuery query,
) {
  final needle = query.text.trim().toLowerCase();
  return [
    for (final source in sources)
      if (_matches(source, needle, query)) source,
  ];
}

bool _matches(BookSource source, String needle, BookSourceQuery query) {
  if (query.group.isNotEmpty &&
      !bookSourceGroups(source).contains(query.group)) {
    return false;
  }
  if (query.onlyInvalid && query.checks[source.url]?.invalid != true) {
    return false;
  }
  if (needle.isEmpty) return true;
  return source.name.toLowerCase().contains(needle) ||
      source.url.toLowerCase().contains(needle) ||
      source.group.toLowerCase().contains(needle);
}

List<BookSource> moveBookSource(List<BookSource> sources, int from, int to) {
  if (from < 0 || from >= sources.length || to < 0 || to >= sources.length) {
    return sources;
  }
  final next = [...sources];
  final item = next.removeAt(from);
  next.insert(to, item);
  return [
    for (final (index, source) in next.indexed) source.copyWith(order: index),
  ];
}

List<BookSource> pinBookSource(
  List<BookSource> sources,
  String url, {
  required bool top,
}) {
  final index = sources.indexWhere((source) => source.url == url);
  if (index < 0) return sources;
  return moveBookSource(sources, index, top ? 0 : sources.length - 1);
}

enum BookSourceCheckStatus { ok, empty, failed }

class BookSourceCheck {
  const BookSourceCheck({
    required this.url,
    required this.status,
    required this.message,
    required this.elapsedMs,
    required this.checkedAt,
  });

  final String url;
  final BookSourceCheckStatus status;
  final String message;
  final int elapsedMs;
  final int checkedAt;

  bool get invalid => status != BookSourceCheckStatus.ok;
  String get label => switch (status) {
    BookSourceCheckStatus.ok => '有效 · ${elapsedMs}ms',
    BookSourceCheckStatus.empty => '无结果 · ${elapsedMs}ms',
    BookSourceCheckStatus.failed => '失效 · $message',
  };

  Map<String, Object?> toJson() => {
    'url': url,
    'status': status.name,
    'message': message,
    'elapsedMs': elapsedMs,
    'checkedAt': checkedAt,
  };

  factory BookSourceCheck.fromJson(Map<String, dynamic> json) {
    final status = BookSourceCheckStatus.values.where(
      (value) => value.name == json['status'],
    );
    return BookSourceCheck(
      url: '${json['url'] ?? ''}',
      status: status.isEmpty ? BookSourceCheckStatus.failed : status.first,
      message: '${json['message'] ?? ''}',
      elapsedMs: json['elapsedMs'] is int ? json['elapsedMs'] as int : 0,
      checkedAt: json['checkedAt'] is int ? json['checkedAt'] as int : 0,
    );
  }
}

Future<BookSourceCheck> checkBookSource(
  BookSourceEngine engine,
  BookSource source, {
  String keyword = '的',
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  final started = clock();
  BookSourceCheck result(BookSourceCheckStatus status, String message) {
    final finished = clock();
    return BookSourceCheck(
      url: source.url,
      status: status,
      message: message,
      elapsedMs: finished.difference(started).inMilliseconds,
      checkedAt: finished.millisecondsSinceEpoch,
    );
  }

  if (!source.isText || source.searchUrl.trim().isEmpty) {
    return result(BookSourceCheckStatus.failed, '没有可用的搜索规则');
  }
  try {
    final books = await engine.search(source, keyword, identify: (_, _) => 0);
    if (books.isEmpty) return result(BookSourceCheckStatus.empty, '搜索没有结果');
    return result(BookSourceCheckStatus.ok, '搜到 ${books.length} 本');
  } catch (error) {
    final message = error is FormatException ? error.message : '校验失败';
    return result(BookSourceCheckStatus.failed, message);
  }
}

Future<List<BookSourceCheck>> checkBookSources(
  BookSourceEngine engine,
  List<BookSource> sources, {
  String keyword = '的',
  int concurrency = 3,
  DateTime Function()? now,
}) async {
  final results = List<BookSourceCheck?>.filled(sources.length, null);
  var cursor = 0;
  Future<void> worker() async {
    while (cursor < sources.length) {
      final index = cursor++;
      results[index] = await checkBookSource(
        engine,
        sources[index],
        keyword: keyword,
        now: now,
      );
    }
  }

  final width = sources.length < concurrency ? sources.length : concurrency;
  await Future.wait([for (var i = 0; i < width; i++) worker()]);
  return results.cast<BookSourceCheck>();
}
