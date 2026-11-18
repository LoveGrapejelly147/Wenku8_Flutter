import 'package:flutter/material.dart';

import 'lan_reading_sync.dart';

class LanReadingPage extends StatelessWidget {
  const LanReadingPage({
    super.key,
    required this.sync,
    required this.reduceMotion,
  });

  final LanReadingSync sync;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('局域网续读')),
    body: const Padding(
      padding: EdgeInsets.all(24),
      child: Text('局域网续读在此版本不可用。阅读进度仍保存在本机。', style: TextStyle(height: 1.6)),
    ),
  );
}
