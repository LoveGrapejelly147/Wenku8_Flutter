import 'package:flutter/material.dart';

import 'reading_widget_reference.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

class ReadingWidgetSkinPicker extends StatelessWidget {
  const ReadingWidgetSkinPicker({
    super.key,
    required this.previewBuilder,
    required this.value,
    required this.size,
    required this.snapshot,
    required this.onChanged,
  });

  final Widget Function(ReadingWidgetSkin skin) previewBuilder;
  final ReadingWidgetSkin value;
  final ReadingDesktopSize size;
  final ReadingWidgetSnapshot snapshot;
  final ValueChanged<ReadingWidgetSkin>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('桌面小组件插画在此版本使用简化预览。', style: TextStyle(height: 1.5)),
      const SizedBox(height: 12),
      SizedBox(height: 120, child: previewBuilder(value)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final skin in ReadingWidgetSkin.values)
            ChoiceChip(
              label: Text(skin.name),
              selected: skin == value,
              onSelected: onChanged == null ? null : (_) => onChanged!(skin),
            ),
        ],
      ),
    ],
  );
}
