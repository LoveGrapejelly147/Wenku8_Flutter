import 'book_documents.dart';
import 'local_import_batch.dart';

class LocalScanResult {
  const LocalScanResult({
    required this.report,
    required this.total,
    required this.unchanged,
    this.warnings = const [],
    this.pending = 0,
  });

  final LocalImportReport report;
  final int total;
  final int unchanged;
  final int pending;
  final List<String> warnings;

  String get summary => warnings.isEmpty ? report.summary : warnings.join('\n');
}

/// Folder scanning is omitted from this build. File-picker import still works.
Future<LocalScanResult> scanLocalBooks({
  required BookDocuments documents,
  required BookScanSnapshot snapshot,
  required Set<String> selectedTokens,
  required bool linkText,
  required Future<LocalImportReport> Function(BookDocumentSelection source)
  importSource,
  bool Function()? current,
  void Function(int done, int total)? onProgress,
}) async => LocalScanResult(
  report: const LocalImportReport(bookIds: [], added: 0, existing: 0),
  total: snapshot.total,
  unchanged: snapshot.unchanged,
  warnings: [...snapshot.warnings, '此版本不能扫描文件夹，请改用选择文件导入'],
);
