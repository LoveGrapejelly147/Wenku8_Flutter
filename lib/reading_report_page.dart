import 'package:flutter/material.dart';

import 'catalog.dart';
import 'library_state.dart';
import 'reading_report_range.dart';

class ReadingReportPage extends StatelessWidget {
  const ReadingReportPage({
    super.key,
    required this.state,
    required this.repository,
    this.now,
    this.initialRange,
  });

  final LibraryState state;
  final NovelRepository repository;
  final DateTime? now;
  final ReadingReportRange? initialRange;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('阅读报告')),
    body: const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        '图文阅读报告在此版本不可用。统计页里的记录、书签和进度仍然可以查看。',
        style: TextStyle(height: 1.6),
      ),
    ),
  );
}
