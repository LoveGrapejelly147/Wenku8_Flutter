import 'package:flutter/material.dart';

import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

enum ReadingDesktopSize { small, medium, large }

String readingGoalCaption(int minutes, int? verifiedTodaySeconds) {
  final done = (verifiedTodaySeconds ?? 0) ~/ 60;
  return '今日 $done / $minutes 分钟';
}

class ReadingDesktopCard extends StatelessWidget {
  const ReadingDesktopCard({
    super.key,
    required this.data,
    required this.size,
    required this.brightness,
    this.quoteText,
    this.quoteSource = '',
    this.quoteCount = 0,
  });

  final ReadingWidgetSnapshot data;
  final ReadingDesktopSize size;
  final Brightness brightness;
  final String? quoteText;
  final String quoteSource;
  final int quoteCount;

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? const Color(0xFF1C1C1C) : const Color(0xFFF7F3EA),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          quoteText ?? '桌面小组件画面在此版本使用简化预览',
          style: TextStyle(
            color: dark ? Colors.white : const Color(0xFF1C1C1C),
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
