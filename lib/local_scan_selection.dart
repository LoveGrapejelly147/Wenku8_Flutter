import 'package:flutter/material.dart';

import 'book_documents.dart';

class LocalScanSelection extends StatefulWidget {
  const LocalScanSelection({super.key, required this.snapshot});
  final BookScanSnapshot snapshot;

  @override
  State<LocalScanSelection> createState() => _LocalScanSelectionState();
}

class _LocalScanSelectionState extends State<LocalScanSelection> {
  late final _selected = {for (final book in widget.snapshot.books) book.token};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('选择书籍')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('此版本不能扫描文件夹。已选择的项目不会被导入。'),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final book in widget.snapshot.books)
                CheckboxListTile(
                  value: _selected.contains(book.token),
                  title: Text(book.name),
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _selected.add(book.token);
                    } else {
                      _selected.remove(book.token);
                    }
                  }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('完成'),
          ),
        ),
      ],
    ),
  );
}
