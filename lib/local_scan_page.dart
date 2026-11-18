import 'package:flutter/material.dart';

import 'book_documents.dart';
import 'local_book_scanner.dart';

class LocalScanPage extends StatelessWidget {
  const LocalScanPage({
    super.key,
    required this.documents,
    required this.changes,
    required this.isBusy,
    required this.progress,
    required this.result,
    required this.failure,
    required this.onScan,
  });

  final BookDocuments documents;
  final Listenable changes;
  final bool Function() isBusy;
  final (int, int)? Function() progress;
  final LocalScanResult? Function() result;
  final String? Function() failure;
  final Future<void> Function(BuildContext context) onScan;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描书籍')),
    body: AnimatedBuilder(
      animation: changes,
      builder: (context, _) {
        final current = result();
        final busy = isBusy();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '此版本不能扫描文件夹。选择文件导入、本地阅读、书架和进度仍然可用。',
              style: TextStyle(height: 1.6),
            ),
            if (failure() case final message?) ...[
              const SizedBox(height: 16),
              Text(message),
            ],
            if (current != null) ...[
              const SizedBox(height: 16),
              Text(current.summary),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : () => onScan(context),
              child: Text(busy ? '正在处理…' : '知道了'),
            ),
          ],
        );
      },
    ),
  );
}
