import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'library_state.dart';
import 'local_books.dart';

Future<void> openLocalBookBatch(
  BuildContext context, {
  required LocalBookStore books,
  required LibraryState library,
  Set<int>? selected,
}) => pushNovelPage<void>(
  context,
  const _LocalBookBatchPage(),
  reduceMotion: library.reduceMotion,
);

class _LocalBookBatchPage extends StatelessWidget {
  const _LocalBookBatchPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('批量整理')),
    body: const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        '此版本的批量整理不可用。单本本地书的导入、阅读、分类和进度仍然保留。',
        style: TextStyle(height: 1.6),
      ),
    ),
  );
}
