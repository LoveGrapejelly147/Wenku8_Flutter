import 'book_documents.dart';
import 'catalog.dart';
import 'local_books.dart';

typedef LocalImportNotice = ({String name, String message});

class LocalImportReport {
  const LocalImportReport({
    required this.bookIds,
    required this.added,
    required this.existing,
    this.failures = const [],
    this.notices = const [],
  });

  final List<int> bookIds;
  final int added;
  final int existing;
  final List<LocalImportNotice> failures;
  final List<LocalImportNotice> notices;

  String get summary {
    if (failures.isEmpty && added == 0 && existing == 0) return '没有导入新的书籍';
    final parts = <String>[
      if (added > 0) '新导入 $added 本',
      if (existing > 0) '已有 $existing 本',
      if (failures.isNotEmpty) '${failures.length} 本未导入',
    ];
    return parts.join('，');
  }
}

class LocalImportGroup {
  const LocalImportGroup({
    required this.seed,
    required this.title,
    required this.volumes,
    this.targetId,
    this.needsTarget = false,
  });

  final int seed;
  final int? targetId;
  final String title;
  final List<({int bookId, String title})> volumes;
  final bool needsTarget;
}

/// Series grouping stays out of this build. Imported books remain separate.
List<LocalImportGroup> localImportGroups(
  LocalBookStore books,
  List<int> bookIds,
) => const [];

/// Walks the files the picker already staged and records each result.
Future<LocalImportReport> importLocalDocuments({
  required List<BookDocumentSelection> selections,
  required BookDocuments documents,
  required LocalBookStore books,
  required Future<Novel> Function(String name, String path) importFile,
  required Future<Novel> Function(BookDocumentSelection selected)
  importSelection,
  bool releaseSources = false,
  void Function(Iterable<BookDocumentSelection> books)? onCleanupFailed,
  void Function(int done, int total)? onProgress,
}) async {
  final ids = <int>[];
  final failures = <LocalImportNotice>[];
  var done = 0;
  for (final selected in selections) {
    try {
      if (selected.error != null) {
        failures.add((name: selected.name, message: selected.error!));
        continue;
      }
      final book = selected.path == null
          ? await importSelection(selected)
          : await importFile(selected.name, selected.path!);
      ids.add(book.id);
    } catch (error) {
      failures.add((
        name: selected.name,
        message: error is FormatException ? error.message : '导入未完成',
      ));
    }
    done++;
    onProgress?.call(done, selections.length);
  }
  if (releaseSources) {
    try {
      await documents.releaseBooks(selections);
    } catch (_) {
      onCleanupFailed?.call(selections);
    }
  }
  return LocalImportReport(
    bookIds: ids,
    added: ids.length,
    existing: 0,
    failures: failures,
  );
}
