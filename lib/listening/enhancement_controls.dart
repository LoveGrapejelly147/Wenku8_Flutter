import 'package:flutter/widgets.dart';

import 'enhancement.dart';

class ListeningEnhancementSettings extends StatelessWidget {
  const ListeningEnhancementSettings({
    super.key,
    required this.enhancement,
    required this.onChanged,
  });

  final ListeningEnhancement enhancement;
  final ValueChanged<ListeningEnhancementPreference> onChanged;

  @override
  Widget build(BuildContext context) => const Text(
    '声音增强在此版本不可用。语速、音色和段落跟随仍然可用。',
    style: TextStyle(fontSize: 12, height: 1.5),
  );
}
