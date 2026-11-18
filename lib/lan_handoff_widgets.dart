import 'package:flutter/material.dart';

import 'catalog.dart';
import 'lan_reading_sync.dart';
import 'library_state.dart';

class LanHandoffMonitor extends StatelessWidget {
  const LanHandoffMonitor({
    super.key,
    required this.handoff,
    required this.onContinue,
    required this.reduceMotion,
    required this.noticeWrapper,
    required this.child,
  });

  final LanBookHandoff? handoff;
  final Future<void> Function(LanHandoffReceipt receipt) onContinue;
  final bool reduceMotion;
  final Widget Function(Widget notice) noticeWrapper;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class LanSendBookSheet extends StatelessWidget {
  const LanSendBookSheet({
    super.key,
    required this.sync,
    required this.book,
    required this.position,
    required this.reduceMotion,
  });

  final LanReadingSync sync;
  final Novel book;
  final ReadingPosition position;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Text(
      '局域网续读在此版本不可用。本书的本地进度仍然保存在这台设备上。',
      style: TextStyle(height: 1.6),
    ),
  );
}
