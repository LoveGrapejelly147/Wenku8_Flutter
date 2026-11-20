import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_interactions.dart';
import '../app_ui.dart';
import '../feature_pages.dart';
import 'engine.dart';
import 'manage.dart';
import 'model.dart';
import 'store.dart';

class BookSourceManager extends StatefulWidget {
  const BookSourceManager({
    super.key,
    required this.store,
    required this.reduceMotion,
    required this.onEdit,
  });

  final BookSourceStore store;
  final bool reduceMotion;
  final ValueChanged<BookSource> onEdit;

  @override
  State<BookSourceManager> createState() => _BookSourceManagerState();
}

class _BookSourceManagerState extends State<BookSourceManager> {
  final _query = TextEditingController();
  String _group = '';
  bool _onlyInvalid = false;
  bool _selecting = false;
  bool _checking = false;
  final _selected = <String>{};

  BookSourceQuery get _filter => BookSourceQuery(
    text: _query.text,
    group: _group,
    onlyInvalid: _onlyInvalid,
    checks: widget.store.checks,
  );

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final visible = filterBookSources(widget.store.sources, _filter);
      final groups = bookSourceGroupNames(widget.store.sources);
      return Column(
        children: [
          Padding(
            padding: featurePadding(context).copyWith(bottom: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ContentPanel(
                  child: AppText(
                    '轻小说文库是内置书源，不参与分组、排序和校验。',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _query,
                  decoration: const InputDecoration(
                    hintText: '搜索书源名称或地址',
                    prefixIcon: Icon(CupertinoIcons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip(
                        '全部分组',
                        _group.isEmpty,
                        () => setState(() => _group = ''),
                      ),
                      for (final group in groups)
                        _chip(
                          group,
                          _group == group,
                          () => setState(() => _group = group),
                        ),
                      _chip(
                        '只看失效',
                        _onlyInvalid,
                        () => setState(() => _onlyInvalid = !_onlyInvalid),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    GlassTextButton(
                      onPressed: _selecting
                          ? () => setState(() {
                              _selecting = false;
                              _selected.clear();
                            })
                          : () => setState(() => _selecting = true),
                      child: AppText(_selecting ? '完成' : '多选'),
                    ),
                    GlassTextButton(
                      onPressed: _checking ? null : _check,
                      child: AppText(_checking ? '正在校验…' : '校验'),
                    ),
                    GlassTextButton(
                      onPressed: _groups,
                      child: const AppText('分组'),
                    ),
                  ],
                ),
                if (_selecting) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      GlassTextButton(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => _enable(true),
                        child: const AppText('启用'),
                      ),
                      GlassTextButton(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => _enable(false),
                        child: const AppText('禁用'),
                      ),
                      GlassTextButton(
                        onPressed: _selected.isEmpty ? null : _assignGroup,
                        child: const AppText('设置分组'),
                      ),
                      GlassTextButton(
                        onPressed: _selected.isEmpty ? null : _exportSelected,
                        child: const AppText('导出'),
                      ),
                      GlassTextButton(
                        onPressed: _selected.isEmpty ? null : _deleteSelected,
                        child: const AppText('删除'),
                      ),
                    ],
                  ),
                ],
                if (_onlyInvalid)
                  GlassTextButton(
                    onPressed: _deleteInvalid,
                    child: const AppText('删除失效书源'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: AppText('没有符合条件的书源'))
                : _filter.canReorder
                ? ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    itemCount: visible.length,
                    onReorder: (from, to) {
                      if (to > from) to--;
                      widget.store.reorderSources(from, to);
                    },
                    itemBuilder: (context, index) =>
                        _tile(visible[index], index),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        _tile(visible[index], index),
                  ),
          ),
        ],
      );
    },
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GlassTextButton(
      selected: selected,
      onPressed: onTap,
      child: AppText(label),
    ),
  );

  Widget _tile(BookSource source, int index) {
    final check = widget.store.checks[source.url];
    final picked = _selected.contains(source.url);
    return Padding(
      key: ValueKey(source.url),
      padding: const EdgeInsets.only(bottom: 8),
      child: ContentPanel(
        onTap: () {
          if (_selecting) {
            setState(() {
              if (!picked) {
                _selected.add(source.url);
              } else {
                _selected.remove(source.url);
              }
            });
          } else {
            widget.onEdit(source);
          }
        },
        child: Row(
          children: [
            if (_selecting)
              Icon(
                picked
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                size: 20,
              ),
            if (_selecting) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    source.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    [
                      if (source.group.isNotEmpty) source.group,
                      if (!source.isText) '非文本',
                      source.url,
                      if (check != null) check.label,
                    ].join(' · '),
                    maxLines: 3,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
            if (!_selecting) ...[
              IconButton(
                tooltip: '置顶',
                onPressed: () => widget.store.pinSource(source.url, top: true),
                icon: const Icon(CupertinoIcons.arrow_up_to_line, size: 18),
              ),
              IconButton(
                tooltip: '置底',
                onPressed: () => widget.store.pinSource(source.url, top: false),
                icon: const Icon(CupertinoIcons.arrow_down_to_line, size: 18),
              ),
            ],
            Switch.adaptive(
              value: source.enabled,
              onChanged: (value) => widget.store.setEnabled(source.url, value),
            ),
            IconButton(
              tooltip: source.enabledExplore ? '关闭发现' : '打开发现',
              onPressed: () {
                widget.store.save(
                  source.copyWith(enabledExplore: !source.enabledExplore),
                );
              },
              icon: Icon(
                source.enabledExplore
                    ? CupertinoIcons.compass_fill
                    : CupertinoIcons.compass,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enable(bool enabled) async {
    await widget.store.setEnabledMany(_selected, enabled);
    if (mounted) showNovelFeedback(context, enabled ? '已启用所选书源' : '已禁用所选书源');
  }

  Future<void> _assignGroup() async {
    final controller = TextEditingController();
    final group = await showJellySheet<String>(
      context: context,
      reduceMotion: widget.reduceMotion,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '分组名称，多个用逗号分隔'),
            ),
            const SizedBox(height: 12),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, controller.text),
              child: const AppText('设置'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (group == null) return;
    await widget.store.setGroupMany(_selected, group);
  }

  Future<void> _exportSelected() async {
    final selected = widget.store.sources.where(
      (source) => _selected.contains(source.url),
    );
    final text = encodeBookSources(selected.toList());
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showNovelFeedback(context, '所选书源 JSON 已复制');
  }

  Future<void> _deleteSelected() async {
    final confirmed = await confirmNovelAction(
      context,
      title: '删除书源',
      message: '删除 ${_selected.length} 个书源。已在书架上的书仍保留缓存。',
      confirmLabel: '删除',
      reduceMotion: widget.reduceMotion,
    );
    if (!confirmed) return;
    await widget.store.removeMany(_selected);
    setState(_selected.clear);
  }

  Future<void> _deleteInvalid() async {
    final urls = [
      for (final source in widget.store.sources)
        if (widget.store.checks[source.url]?.invalid == true) source.url,
    ];
    if (urls.isEmpty) {
      showNovelFeedback(context, '没有已标记失效的书源');
      return;
    }
    await widget.store.removeMany(urls);
    if (mounted) showNovelFeedback(context, '已删除 ${urls.length} 个失效书源');
  }

  Future<void> _check() async {
    final visible = filterBookSources(widget.store.sources, _filter);
    if (visible.isEmpty) return;
    setState(() => _checking = true);
    try {
      final checks = await checkBookSources(
        BookSourceEngine(),
        visible,
        keyword: '的',
      );
      await widget.store.recordChecks(checks);
      final failed = checks.where((check) => check.invalid).length;
      if (mounted) {
        showNovelFeedback(
          context,
          '校验完成 · ${checks.length - failed} 个有效，$failed 个失效或无结果',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _groups() async {
    final groups = bookSourceGroupNames(widget.store.sources);
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.reduceMotion,
      maxHeight: 520,
      builder: (sheet) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const AppText(
            '分组',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty) const AppText('还没有分组。多选书源后可以设置分组。'),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: AppText(group)),
                  GlassTextButton(
                    onPressed: () async {
                      final next = await _ask(sheet, group);
                      if (next == null ||
                          next.trim().isEmpty ||
                          next == group) {
                        return;
                      }
                      await widget.store.renameGroup(group, next.trim());
                      if (sheet.mounted) Navigator.pop(sheet);
                    },
                    child: const AppText('改名'),
                  ),
                  GlassTextButton(
                    onPressed: () async {
                      await widget.store.removeGroup(group);
                      if (sheet.mounted) Navigator.pop(sheet);
                    },
                    child: const AppText('移除'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _ask(BuildContext context, String initial) {
    final controller = TextEditingController(text: initial);
    return showJellySheet<String>(
      context: context,
      reduceMotion: widget.reduceMotion,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '分组名称'),
            ),
            const SizedBox(height: 12),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, controller.text),
              child: const AppText('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
