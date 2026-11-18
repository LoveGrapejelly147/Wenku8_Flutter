import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_interactions.dart';
import '../app_ui.dart';
import '../feature_pages.dart';
import '../local_books.dart';
import '../local_platform.dart';
import 'models.dart';
import 'store.dart';

class ReadingRulesPage extends StatelessWidget {
  const ReadingRulesPage({super.key, required this.reduceMotion});
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '规则',
    code: 'SOURCE / RULES',
    child: ListView(
      padding: featurePadding(context),
      children: [
        _entry(
          context,
          title: 'TXT 目录规则',
          subtitle: '按正则切分本地 TXT 的章节',
          page: TxtTocRulesPage(reduceMotion: reduceMotion),
        ),
        const SizedBox(height: 12),
        _entry(
          context,
          title: '替换净化',
          subtitle: '阅读和朗读前替换正文',
          page: ReplaceRulesPage(reduceMotion: reduceMotion),
        ),
        const SizedBox(height: 12),
        _entry(
          context,
          title: '在线查词',
          subtitle: '长按选词时与离线词典一起查询',
          page: DictRulesPage(reduceMotion: reduceMotion),
        ),
      ],
    ),
  );

  Widget _entry(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget page,
  }) => FeatureEntry(
    title: title,
    subtitle: subtitle,
    icon: CupertinoIcons.square_list,
    onTap: () => pushNovelPage<void>(context, page, reduceMotion: reduceMotion),
  );
}

class TxtTocRulesPage extends StatelessWidget {
  const TxtTocRulesPage({super.key, required this.reduceMotion});
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => _RuleScaffold(
    title: 'TXT 目录规则',
    reduceMotion: reduceMotion,
    onImport: (text) => ReadingRuleStore.shared.importTxt(
      parseRuleList(text, TxtTocRule.fromLegado),
    ),
    onExport: () => encodeRuleList([
      for (final rule in ReadingRuleStore.shared.txtRules) rule.toLegado(),
    ]),
    onCreate: () => _editTxt(context, null),
    child: AnimatedBuilder(
      animation: ReadingRuleStore.shared,
      builder: (context, _) => Column(
        children: [
          for (final (index, rule) in ReadingRuleStore.shared.txtRules.indexed)
            _RuleTile(
              title: rule.name,
              subtitle: rule.rule,
              enabled: rule.enabled,
              onChanged: (value) => ReadingRuleStore.shared.saveTxt(
                rule.copyWith(enabled: value),
              ),
              onTap: () => _editTxt(context, rule),
              onUp: index == 0
                  ? null
                  : () => ReadingRuleStore.shared.moveTxt(rule.id, -1),
              onDown: index == ReadingRuleStore.shared.txtRules.length - 1
                  ? null
                  : () => ReadingRuleStore.shared.moveTxt(rule.id, 1),
              onDelete: () => ReadingRuleStore.shared.removeTxt(rule.id),
            ),
        ],
      ),
    ),
  );
}

Future<void> _editTxt(BuildContext context, TxtTocRule? rule) async {
  final name = TextEditingController(text: rule?.name ?? '');
  final pattern = TextEditingController(text: rule?.rule ?? '');
  final replacement = TextEditingController(text: rule?.replacement ?? '');
  var volume = rule?.volume ?? false;
  final saved = await showJellySheet<bool>(
    context: context,
    builder: (sheet) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            TextField(
              controller: pattern,
              decoration: const InputDecoration(labelText: '正则'),
            ),
            TextField(
              controller: replacement,
              decoration: const InputDecoration(labelText: '替换（可空）'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('作为分卷规则'),
              value: volume,
              onChanged: (value) => setState(() => volume = value),
            ),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, true),
              child: const AppText('保存'),
            ),
          ],
        ),
      ),
    ),
  );
  if (saved == true &&
      name.text.trim().isNotEmpty &&
      pattern.text.trim().isNotEmpty) {
    try {
      RegExp(pattern.text.trim());
      await ReadingRuleStore.shared.saveTxt(
        TxtTocRule(
          id: rule?.id ?? DateTime.now().microsecondsSinceEpoch,
          name: name.text.trim(),
          rule: pattern.text.trim(),
          replacement: replacement.text,
          serialNumber:
              rule?.serialNumber ?? ReadingRuleStore.shared.txtRules.length,
          enabled: rule?.enabled ?? true,
          volume: volume,
        ),
      );
    } on FormatException {
      if (context.mounted) showNovelFeedback(context, '正则无法编译');
    }
  }
  name.dispose();
  pattern.dispose();
  replacement.dispose();
}

class ReplaceRulesPage extends StatelessWidget {
  const ReplaceRulesPage({super.key, required this.reduceMotion});
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => _RuleScaffold(
    title: '替换净化',
    reduceMotion: reduceMotion,
    onImport: (text) => ReadingRuleStore.shared.importReplace(
      parseRuleList(text, ReplaceRule.fromLegado),
    ),
    onExport: () => encodeRuleList([
      for (final rule in ReadingRuleStore.shared.replaceRules) rule.toLegado(),
    ]),
    onCreate: () => _editReplace(context, null),
    child: AnimatedBuilder(
      animation: ReadingRuleStore.shared,
      builder: (context, _) => Column(
        children: [
          SwitchListTile(
            title: const Text('阅读时净化正文'),
            subtitle: const Text('关闭后，阅读和朗读都使用原文'),
            value: ReadingRuleStore.shared.purifyEnabled,
            onChanged: ReadingRuleStore.shared.setPurifyEnabled,
          ),
          for (final (index, rule)
              in ReadingRuleStore.shared.replaceRules.indexed)
            _RuleTile(
              title: rule.name,
              subtitle: [
                if (rule.scope.isEmpty) '全部书籍' else rule.scope,
                rule.pattern,
              ].join(' · '),
              enabled: rule.enabled,
              onChanged: (value) => ReadingRuleStore.shared.saveReplace(
                rule.copyWith(enabled: value),
              ),
              onTap: () => _editReplace(context, rule),
              onUp: index == 0
                  ? null
                  : () => ReadingRuleStore.shared.moveReplace(rule.id, -1),
              onDown: index == ReadingRuleStore.shared.replaceRules.length - 1
                  ? null
                  : () => ReadingRuleStore.shared.moveReplace(rule.id, 1),
              onDelete: () => ReadingRuleStore.shared.removeReplace(rule.id),
            ),
        ],
      ),
    ),
  );
}

Future<void> _editReplace(BuildContext context, ReplaceRule? rule) async {
  final name = TextEditingController(text: rule?.name ?? '');
  final pattern = TextEditingController(text: rule?.pattern ?? '');
  final replacement = TextEditingController(text: rule?.replacement ?? '');
  final scope = TextEditingController(text: rule?.scope ?? '');
  var regex = rule?.isRegex ?? true;
  var title = rule?.scopeTitle ?? false;
  var content = rule?.scopeContent ?? true;
  final saved = await showJellySheet<bool>(
    context: context,
    maxHeight: 560,
    builder: (sheet) => StatefulBuilder(
      builder: (context, setState) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          TextField(
            controller: pattern,
            decoration: const InputDecoration(labelText: '查找'),
          ),
          TextField(
            controller: replacement,
            decoration: const InputDecoration(labelText: '替换为'),
          ),
          TextField(
            controller: scope,
            decoration: const InputDecoration(
              labelText: '作用范围',
              hintText: '空为全部；可填书名或书源地址',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('使用正则'),
            value: regex,
            onChanged: (value) => setState(() => regex = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('作用于正文'),
            value: content,
            onChanged: (value) => setState(() => content = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('作用于标题'),
            value: title,
            onChanged: (value) => setState(() => title = value),
          ),
          GlassTextButton(
            onPressed: () => Navigator.pop(sheet, true),
            child: const AppText('保存'),
          ),
        ],
      ),
    ),
  );
  if (saved == true &&
      name.text.trim().isNotEmpty &&
      pattern.text.trim().isNotEmpty) {
    await ReadingRuleStore.shared.saveReplace(
      ReplaceRule(
        id: rule?.id ?? DateTime.now().microsecondsSinceEpoch,
        name: name.text.trim(),
        pattern: pattern.text,
        replacement: replacement.text,
        scope: scope.text.trim(),
        isRegex: regex,
        scopeTitle: title,
        scopeContent: content,
        enabled: rule?.enabled ?? true,
        order: rule?.order ?? ReadingRuleStore.shared.replaceRules.length,
      ),
    );
  }
  name.dispose();
  pattern.dispose();
  replacement.dispose();
  scope.dispose();
}

class DictRulesPage extends StatelessWidget {
  const DictRulesPage({super.key, required this.reduceMotion});
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => _RuleScaffold(
    title: '在线查词',
    reduceMotion: reduceMotion,
    onImport: (text) => ReadingRuleStore.shared.importDict(
      parseRuleList(text, DictRule.fromLegado),
    ),
    onExport: () => encodeRuleList([
      for (final rule in ReadingRuleStore.shared.dictRules) rule.toLegado(),
    ]),
    onCreate: () => _editDict(context, null),
    child: AnimatedBuilder(
      animation: ReadingRuleStore.shared,
      builder: (context, _) => Column(
        children: [
          for (final (index, rule) in ReadingRuleStore.shared.dictRules.indexed)
            _RuleTile(
              title: rule.name,
              subtitle: rule.urlRule,
              enabled: rule.enabled,
              onChanged: (value) => ReadingRuleStore.shared.saveDict(
                rule.copyWith(enabled: value),
              ),
              onTap: () => _editDict(context, rule),
              onUp: index == 0
                  ? null
                  : () => ReadingRuleStore.shared.moveDict(rule.name, -1),
              onDown: index == ReadingRuleStore.shared.dictRules.length - 1
                  ? null
                  : () => ReadingRuleStore.shared.moveDict(rule.name, 1),
              onDelete: () => ReadingRuleStore.shared.removeDict(rule.name),
            ),
        ],
      ),
    ),
  );
}

Future<void> _editDict(BuildContext context, DictRule? rule) async {
  final name = TextEditingController(text: rule?.name ?? '');
  final url = TextEditingController(text: rule?.urlRule ?? '');
  final show = TextEditingController(text: rule?.showRule ?? '');
  final saved = await showJellySheet<bool>(
    context: context,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          TextField(
            controller: url,
            decoration: const InputDecoration(
              labelText: 'urlRule，用 {{key}} 表示词',
            ),
          ),
          TextField(
            controller: show,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'showRule'),
          ),
          GlassTextButton(
            onPressed: () => Navigator.pop(sheet, true),
            child: const AppText('保存'),
          ),
        ],
      ),
    ),
  );
  if (saved == true &&
      name.text.trim().isNotEmpty &&
      url.text.trim().isNotEmpty) {
    await ReadingRuleStore.shared.saveDict(
      DictRule(
        name: name.text.trim(),
        urlRule: url.text.trim(),
        showRule: show.text.trim(),
        enabled: rule?.enabled ?? true,
        order: rule?.order ?? ReadingRuleStore.shared.dictRules.length,
      ),
    );
  }
  name.dispose();
  url.dispose();
  show.dispose();
}

Future<void> showTxtTocPicker({
  required BuildContext context,
  required LocalBookStore books,
  required int bookId,
  required bool reduceMotion,
}) async {
  final selected = await showJellySheet<TxtTocRule>(
    context: context,
    reduceMotion: reduceMotion,
    maxHeight: 520,
    builder: (sheet) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const AppText(
          '重新切分会按新规则生成目录。原来的章内进度可能对不上。',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 12),
        for (final rule in ReadingRuleStore.shared.enabledTxtRules)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassTextButton(
              onPressed: () => Navigator.pop(sheet, rule),
              child: AppText(rule.name),
            ),
          ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  try {
    await books.resplitTextBook(bookId, optionsForTxtRule(selected));
    if (context.mounted) showNovelFeedback(context, '已按「${selected.name}」重新切分');
  } on FormatException catch (error) {
    if (context.mounted) showNovelFeedback(context, error.message);
  }
}

class _RuleScaffold extends StatelessWidget {
  const _RuleScaffold({
    required this.title,
    required this.reduceMotion,
    required this.child,
    required this.onImport,
    required this.onExport,
    required this.onCreate,
  });
  final String title;
  final bool reduceMotion;
  final Widget child;
  final Future<int> Function(String text) onImport;
  final String Function() onExport;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: title,
    code: 'SOURCE / RULES',
    actions: [
      GlassIconButton(
        icon: CupertinoIcons.square_arrow_down,
        label: '导入',
        onPressed: () => _import(context),
      ),
      GlassIconButton(
        icon: CupertinoIcons.add,
        label: '新建',
        onPressed: onCreate,
      ),
    ],
    child: ListView(
      padding: featurePadding(context),
      children: [
        GlassTextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: onExport()));
            if (context.mounted) showNovelFeedback(context, '规则 JSON 已复制');
          },
          child: const AppText('复制 JSON'),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Future<void> _import(BuildContext context) async {
    final text = LocalPlatform.android
        ? await LocalPlatform.importBackup()
        : null;
    if (text == null || !context.mounted) return;
    try {
      final added = await onImport(text);
      if (context.mounted) showNovelFeedback(context, '已导入 $added 条规则');
    } on FormatException catch (error) {
      if (context.mounted) showNovelFeedback(context, error.message);
    }
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
    required this.onTap,
    required this.onDelete,
    this.onUp,
    this.onDown,
  });
  final String title, subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap, onDelete;
  final VoidCallback? onUp, onDown;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ContentPanel(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                AppText(
                  subtitle,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onUp,
            icon: const Icon(CupertinoIcons.chevron_up),
          ),
          IconButton(
            onPressed: onDown,
            icon: const Icon(CupertinoIcons.chevron_down),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(CupertinoIcons.trash),
          ),
          Switch.adaptive(value: enabled, onChanged: onChanged),
        ],
      ),
    ),
  );
}
