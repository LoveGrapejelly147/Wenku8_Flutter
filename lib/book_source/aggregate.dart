import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../catalog.dart';
import '../library_state.dart';
import 'manage.dart';
import 'model.dart';

const builtInAggregateUrl = 'builtin:wenku';

class AggregateSearchPreferences {
  const AggregateSearchPreferences({
    this.concurrency = 4,
    this.timeoutSeconds = 15,
  });

  final int concurrency;
  final int timeoutSeconds;

  Duration get timeout => Duration(seconds: timeoutSeconds);

  AggregateSearchPreferences clamped() => AggregateSearchPreferences(
    concurrency: concurrency.clamp(1, 8),
    timeoutSeconds: timeoutSeconds.clamp(5, 60),
  );

  Map<String, Object> toJson() => {
    'concurrency': concurrency,
    'timeoutSeconds': timeoutSeconds,
  };

  factory AggregateSearchPreferences.fromJson(Map<String, dynamic> json) =>
      AggregateSearchPreferences(
        concurrency: json['concurrency'] is int
            ? json['concurrency'] as int
            : 4,
        timeoutSeconds: json['timeoutSeconds'] is int
            ? json['timeoutSeconds'] as int
            : 15,
      ).clamped();

  static Future<AggregateSearchPreferences> load(Directory? root) async {
    if (root == null) return const AggregateSearchPreferences();
    final file = File('${root.path}/aggregate.json');
    if (!await file.exists()) return const AggregateSearchPreferences();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const AggregateSearchPreferences();
      return AggregateSearchPreferences.fromJson(
        decoded.cast<String, dynamic>(),
      );
    } catch (_) {
      return const AggregateSearchPreferences();
    }
  }

  Future<void> save(Directory? root) async {
    if (root == null) return;
    final next = clamped();
    final file = File('${root.path}/aggregate.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(next.toJson()));
  }
}

String aggregateNormalize(String value) {
  final width = String.fromCharCodes([
    for (final rune in value.runes)
      if (rune >= 0xff01 && rune <= 0xff5e)
        rune - 0xfee0
      else if (rune == 0x3000)
        0x20
      else
        rune,
  ]);
  return width.toLowerCase().replaceAll(
    RegExp(r'[\s·・_\-—–，,。.:：()（）\[\]【】「」『』《》]'),
    '',
  );
}

String aggregateIdentity(String title, String author) =>
    '${aggregateNormalize(title)}\u0000${aggregateNormalize(author)}';

bool sameAggregateBook(
  String title,
  String author,
  String otherTitle,
  String otherAuthor,
) {
  if (aggregateNormalize(title) != aggregateNormalize(otherTitle)) return false;
  final left = aggregateNormalize(author);
  final right = aggregateNormalize(otherAuthor);
  if (left.isEmpty || right.isEmpty) return true;
  return left == right;
}

class AggregateBook {
  const AggregateBook({
    required this.id,
    required this.title,
    required this.author,
    required this.sourceName,
    required this.sourceUrl,
  });

  final int id;
  final String title;
  final String author;
  final String sourceName;
  final String sourceUrl;
}

class AggregateHit {
  const AggregateHit({
    required this.title,
    required this.author,
    required this.books,
  });

  final String title;
  final String author;
  final List<AggregateBook> books;

  int get sourceCount => books.map((book) => book.sourceUrl).toSet().length;

  AggregateHit copyWith({List<AggregateBook>? books}) =>
      AggregateHit(title: title, author: author, books: books ?? this.books);
}

class AggregateTarget {
  const AggregateTarget({required this.name, required this.search});

  final String name;
  final Future<List<AggregateBook>> Function() search;
}

class AggregateProgress {
  const AggregateProgress({
    required this.hits,
    required this.done,
    required this.total,
    required this.failures,
    required this.failedNames,
    required this.stopped,
  });

  final List<AggregateHit> hits;
  final int done;
  final int total;
  final int failures;
  final List<String> failedNames;
  final bool stopped;
}

List<BookSource> sourcesForAggregateScope(
  List<BookSource> enabled, {
  String? group,
  String? sourceUrl,
}) {
  if (sourceUrl == builtInAggregateUrl) return const [];
  if (sourceUrl != null && sourceUrl.isNotEmpty) {
    return [
      for (final source in enabled)
        if (source.url == sourceUrl) source,
    ];
  }
  if (group != null && group.isNotEmpty) {
    return [
      for (final source in enabled)
        if (bookSourceGroups(source).contains(group)) source,
    ];
  }
  return enabled;
}

bool aggregateIncludesBuiltIn({String? group, String? sourceUrl}) {
  if (sourceUrl == builtInAggregateUrl) return true;
  if (sourceUrl != null && sourceUrl.isNotEmpty) return false;
  if (group != null && group.isNotEmpty) return false;
  return true;
}

void addAggregateBook(
  List<AggregateHit> hits,
  Map<String, int> index,
  AggregateBook book,
) {
  final key = aggregateIdentity(book.title, book.author);
  final at = index[key];
  if (at == null) {
    index[key] = hits.length;
    hits.add(
      AggregateHit(title: book.title, author: book.author, books: [book]),
    );
    return;
  }
  final hit = hits[at];
  if (hit.books.any(
    (item) => item.sourceUrl == book.sourceUrl && item.id == book.id,
  )) {
    return;
  }
  hits[at] = hit.copyWith(books: [...hit.books, book]);
}

Future<AggregateProgress> runAggregateSearch({
  required List<AggregateTarget> targets,
  int concurrency = 4,
  Duration timeout = const Duration(seconds: 15),
  bool Function()? cancelled,
  void Function(AggregateProgress progress)? onProgress,
}) async {
  final hits = <AggregateHit>[];
  final index = <String, int>{};
  final failed = <String>[];
  var done = 0;
  var cursor = 0;
  final stop = cancelled ?? () => false;

  AggregateProgress snapshot({required bool stopped}) => AggregateProgress(
    hits: List<AggregateHit>.unmodifiable(hits.toList()),
    done: done,
    total: targets.length,
    failures: failed.length,
    failedNames: List<String>.unmodifiable(failed.toList()),
    stopped: stopped,
  );

  Future<void> worker() async {
    while (!stop()) {
      final at = cursor++;
      if (at >= targets.length) return;
      final target = targets[at];
      try {
        final books = await target.search().timeout(timeout);
        if (stop()) return;
        for (final book in books) {
          addAggregateBook(hits, index, book);
        }
      } catch (_) {
        if (stop()) return;
        failed.add(target.name);
      }
      done++;
      onProgress?.call(snapshot(stopped: false));
    }
  }

  final width = targets.isEmpty
      ? 0
      : (targets.length < concurrency ? targets.length : concurrency);
  await Future.wait([for (var i = 0; i < width; i++) worker()]);
  return snapshot(stopped: stop());
}

String chapterMatchKey(String title) {
  final normalized = aggregateNormalize(title);
  return normalized.replaceFirst(RegExp(r'^第[0-9零一二三四五六七八九十百千两]+[章节回节部卷]'), '');
}

/// Returns the chapter index whose title best matches [current].
int? matchChapterByTitle(List<String> titles, String current) {
  final key = chapterMatchKey(current);
  if (key.isEmpty) return null;
  final exact = <int>[];
  for (var i = 0; i < titles.length; i++) {
    if (chapterMatchKey(titles[i]) == key) exact.add(i);
  }
  if (exact.isNotEmpty) return exact.first;
  int? best;
  var score = 1 << 30;
  for (var i = 0; i < titles.length; i++) {
    final other = chapterMatchKey(titles[i]);
    if (other.isEmpty) continue;
    if (!other.contains(key) && !key.contains(other)) continue;
    final delta = (other.length - key.length).abs();
    if (delta < score) {
      best = i;
      score = delta;
    }
  }
  return best;
}

class SourceSwitchPlan {
  const SourceSwitchPlan({
    required this.chapterIndex,
    required this.matchedTitle,
  });

  final int chapterIndex;
  final bool matchedTitle;
}

SourceSwitchPlan planSourceSwitch({
  required String? currentTitle,
  required List<NovelChapter> chapters,
}) {
  if (chapters.isEmpty) {
    return const SourceSwitchPlan(chapterIndex: 0, matchedTitle: false);
  }
  final index = currentTitle == null
      ? null
      : matchChapterByTitle([
          for (final chapter in chapters) chapter.title,
        ], currentTitle);
  if (index == null) {
    return const SourceSwitchPlan(chapterIndex: 0, matchedTitle: false);
  }
  return SourceSwitchPlan(chapterIndex: index, matchedTitle: true);
}

Future<void> applySourceSwitch({
  required LibraryState state,
  required Novel current,
  required Novel target,
  required SourceSwitchPlan plan,
  ReadingPosition? position,
}) async {
  if (target.chapters.isEmpty) {
    throw const FormatException('新书源没有可读章节');
  }
  final chapter = plan.chapterIndex.clamp(0, target.chapters.length - 1);
  if (plan.matchedTitle && position != null) {
    final maximum = position.fraction > 0
        ? position.offset / position.fraction
        : position.offset;
    await state.savePosition(
      novel: target,
      chapter: chapter,
      offset: position.offset,
      maximum: maximum,
      width: position.width,
      paragraphIndex: position.paragraphIndex,
      paragraphFraction: position.paragraphFraction,
      textOffset: position.textOffset,
      textScale: position.textScale,
      typeface: position.typeface,
    );
  } else {
    await state.setChapter(target.id, chapter);
  }
  if (current.id != target.id && state.contains(current.id)) {
    await state.setShelfMembership(current.id, false, novel: current);
    await state.setShelfMembership(target.id, true, novel: target);
  }
}
