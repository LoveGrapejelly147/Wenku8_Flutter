import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_interactions.dart';
import '../app_ui.dart';
import '../feature_pages.dart';
import '../local_platform.dart';
import 'engine.dart';
import 'js_runtime.dart';
import 'http.dart';
import 'manage_page.dart';
import 'model.dart';
import 'repository.dart';
import 'store.dart';
import 'url_template.dart';

class BookSourceListPage extends StatelessWidget {
  const BookSourceListPage({
    super.key,
    required this.repository,
    required this.reduceMotion,
  });

  final BookSourceRepository repository;
  final bool reduceMotion;
  BookSourceStore get store => repository.store;

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '书源',
    code: 'SOURCE / LEGADO',
    actions: [
      GlassIconButton(
        icon: CupertinoIcons.square_arrow_up,
        label: '导出',
        onPressed: () => _export(context),
      ),
      GlassIconButton(
        icon: CupertinoIcons.add,
        label: '导入或新建',
        onPressed: () => _add(context),
      ),
    ],
    child: BookSourceManager(
      store: store,
      reduceMotion: reduceMotion,
      onEdit: (source) => _edit(context, source),
    ),
  );

  Future<void> _edit(BuildContext context, BookSource source) {
    return pushNovelPage<void>(
      context,
      BookSourceEditPage(
        store: store,
        source: source,
        reduceMotion: reduceMotion,
      ),
      reduceMotion: reduceMotion,
    );
  }

  Future<void> _add(BuildContext context) async {
    final choice = await showJellySheet<String>(
      context: context,
      reduceMotion: reduceMotion,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppText(
              '添加书源',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const AppText('支持开源阅读（Legado）书源 JSON。可以一次导入多个。'),
            const SizedBox(height: 18),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, 'text'),
              child: const AppText('从 JSON 文本导入'),
            ),
            const SizedBox(height: 8),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, 'file'),
              child: const AppText('从文件导入'),
            ),
            const SizedBox(height: 8),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, 'url'),
              child: const AppText('从 URL 导入'),
            ),
            const SizedBox(height: 8),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, 'new'),
              child: const AppText('新建空白书源'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    try {
      switch (choice) {
        case 'text':
          final text = await _askText(
            context,
            title: '粘贴书源 JSON',
            confirm: '导入',
          );
          if (text == null || !context.mounted) return;
          await _importText(context, text);
        case 'file':
          final text = await LocalPlatform.importBackup();
          if (text == null || !context.mounted) return;
          await _importText(context, text);
        case 'url':
          final url = await _askText(
            context,
            title: '书源 JSON 地址',
            confirm: '获取',
            hint: 'https://',
          );
          if (url == null || url.trim().isEmpty) return;
          final response = await BookSourceHttp.shared.send(
            BookSourceRequestSpec(url: url.trim()),
          );
          if (!context.mounted) return;
          await _importText(context, response.body);
        case 'new':
          await _edit(context, const BookSource(url: 'https://', name: ''));
      }
    } on FormatException catch (error) {
      if (context.mounted) _showError(context, error.message);
    } catch (error) {
      if (context.mounted) _showError(context, '$error');
    }
  }

  Future<void> _importText(BuildContext context, String text) async {
    final sources = parseBookSourceDocument(text);
    final added = await store.importAll(sources);
    if (!context.mounted) return;
    final updated = sources.length - added;
    showNovelFeedback(
      context,
      updated == 0 ? '已导入 ${sources.length} 个书源' : '已导入 $added 个，更新 $updated 个',
    );
  }

  Future<void> _export(BuildContext context) async {
    if (store.sources.isEmpty) {
      showNovelFeedback(context, '没有可导出的自定义书源');
      return;
    }
    final choice = await showJellySheet<String>(
      context: context,
      reduceMotion: reduceMotion,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppText(
              '导出书源',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, 'file'),
              child: const AppText('保存为 JSON 文件'),
            ),
            const SizedBox(height: 8),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, 'copy'),
              child: const AppText('复制 JSON'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    final text = encodeBookSources(store.sources);
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) showNovelFeedback(context, '书源 JSON 已复制');
      return;
    }
    final saved = await LocalPlatform.exportBackup(text, 'book-sources.json');
    if (context.mounted && saved) showNovelFeedback(context, '书源文件已保存');
  }

  Future<String?> _askText(
    BuildContext context, {
    required String title,
    required String confirm,
    String hint = '',
  }) async {
    final controller = TextEditingController();
    final result = await showJellySheet<String>(
      context: context,
      reduceMotion: reduceMotion,
      maxHeight: 520,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: hint.isEmpty ? 6 : 1,
              maxLines: hint.isEmpty ? 10 : 1,
              decoration: InputDecoration(hintText: hint.isEmpty ? null : hint),
            ),
            const SizedBox(height: 14),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, controller.text),
              child: AppText(confirm),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  void _showError(BuildContext context, String message) {
    showNovelFeedback(context, message.isEmpty ? '书源导入失败' : message);
  }
}

class BookSourceEditPage extends StatefulWidget {
  const BookSourceEditPage({
    super.key,
    required this.store,
    required this.source,
    required this.reduceMotion,
  });

  final BookSourceStore store;
  final BookSource source;
  final bool reduceMotion;

  @override
  State<BookSourceEditPage> createState() => _BookSourceEditPageState();
}

class _BookSourceEditPageState extends State<BookSourceEditPage> {
  late final _fields = <String, TextEditingController>{
    'name': TextEditingController(text: widget.source.name),
    'url': TextEditingController(text: widget.source.url),
    'group': TextEditingController(text: widget.source.group),
    'comment': TextEditingController(text: widget.source.comment),
    'searchUrl': TextEditingController(text: widget.source.searchUrl),
    'exploreUrl': TextEditingController(text: widget.source.exploreUrl),
    'header': TextEditingController(text: widget.source.header),
    for (final entry in _ruleFields.entries)
      for (final field in entry.value)
        '${entry.key.$1}.${field.$1}': TextEditingController(
          text: _rulesOf(widget.source, entry.key.$1)[field.$1],
        ),
  };
  late bool _enabled = widget.source.enabled;
  late bool _explore = widget.source.enabledExplore;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: widget.source.name.isEmpty ? '新建书源' : '编辑书源',
    code: 'SOURCE / EDIT',
    actions: [
      GlassIconButton(
        icon: CupertinoIcons.play,
        label: '调试',
        onPressed: _debug,
      ),
      GlassIconButton(
        icon: CupertinoIcons.check_mark,
        label: '保存',
        onPressed: _save,
      ),
    ],
    child: ListView(
      padding: featurePadding(context),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        _switch('启用', _enabled, (value) => setState(() => _enabled = value)),
        const SizedBox(height: 8),
        _switch('发现', _explore, (value) => setState(() => _explore = value)),
        const SizedBox(height: 12),
        _field('名称', 'name'),
        _field('地址', 'url', hint: 'https://example.com'),
        _field('分组', 'group'),
        _field('备注', 'comment', maxLines: 2),
        _field(
          '搜索地址',
          'searchUrl',
          maxLines: 4,
          hint:
              '可用 {{key}}、{{page}}，POST 写成 地址,{"method":"POST","body":"q={{key}}","charset":"gbk"}',
        ),
        _field('请求头', 'header', maxLines: 3, hint: '{"User-Agent":"..."}'),
        _field('发现地址', 'exploreUrl', maxLines: 2),
        const SizedBox(height: 8),
        const AppText(
          'Android 上会执行 <js>、@js: 和 {{ }}。不支持的 Java 方法会在调试页提示，不会让应用退出。',
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
        for (final entry in _ruleFields.entries) ...[
          const SizedBox(height: 22),
          sectionHeader(context, entry.key.$2, ''),
          const SizedBox(height: 10),
          for (final field in entry.value)
            _field(field.$2, '${entry.key.$1}.${field.$1}', maxLines: 2),
        ],
        if (widget.source.url != 'https://' &&
            widget.source.name.isNotEmpty) ...[
          const SizedBox(height: 18),
          GlassTextButton(onPressed: _delete, child: const AppText('删除书源')),
        ],
      ],
    ),
  );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      ContentPanel(
        child: Row(
          children: [
            Expanded(
              child: AppText(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      );

  Widget _field(String label, String key, {int maxLines = 1, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _fields[key],
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  BookSource _edited() {
    BookSourceRules merge(String group, BookSourceRules original) =>
        original.merge({
          for (final field in _ruleFields[(group, _titleOf(group))]!)
            field.$1: _fields['$group.${field.$1}']!.text.trim(),
        });
    return widget.source.copyWith(
      name: _fields['name']!.text.trim(),
      url: _fields['url']!.text.trim(),
      group: _fields['group']!.text.trim(),
      comment: _fields['comment']!.text.trim(),
      enabled: _enabled,
      enabledExplore: _explore,
      searchUrl: _fields['searchUrl']!.text.trim(),
      exploreUrl: _fields['exploreUrl']!.text.trim(),
      header: _fields['header']!.text.trim(),
      search: merge('search', widget.source.search),
      explore: widget.source.explore,
      info: merge('info', widget.source.info),
      toc: merge('toc', widget.source.toc),
      content: merge('content', widget.source.content),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final source = _edited();
    final uri = Uri.tryParse(source.url);
    if (source.name.isEmpty ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() => _error = '请填写书源名称，以及 http 或 https 地址');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(source);
      if (mounted) {
        showNovelFeedback(context, '书源已保存');
        Navigator.pop(context);
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _debug() {
    return pushNovelPage<void>(
      context,
      BookSourceDebugPage(source: _edited(), reduceMotion: widget.reduceMotion),
      reduceMotion: widget.reduceMotion,
    );
  }

  Future<void> _delete() async {
    final confirmed = await confirmNovelAction(
      context,
      title: '删除书源',
      message: '已加入书架的书会保留缓存和进度，但无法再从该源更新。',
      confirmLabel: '删除',
      reduceMotion: widget.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    await widget.store.remove(widget.source.url);
    if (mounted) Navigator.pop(context);
  }
}

class BookSourceDebugPage extends StatefulWidget {
  const BookSourceDebugPage({
    super.key,
    required this.source,
    required this.reduceMotion,
    this.engine,
  });

  final BookSource source;
  final bool reduceMotion;
  final BookSourceEngine? engine;

  @override
  State<BookSourceDebugPage> createState() => _BookSourceDebugPageState();
}

class _BookSourceDebugPageState extends State<BookSourceDebugPage> {
  final _keyword = TextEditingController();
  late final BookSourceEngine _engine =
      widget.engine ??
      BookSourceEngine(
        scripts: LocalPlatform.android ? BookSourceScripts() : null,
      );
  List<CustomBookRecord> _results = const [];
  CustomBookRecord? _book;
  String? _content;
  String? _error;
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '调试书源',
    code: 'SOURCE / DEBUG',
    child: ListView(
      padding: featurePadding(context),
      children: [
        TextField(
          controller: _keyword,
          decoration: const InputDecoration(labelText: '搜索关键字'),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),
        GlassTextButton(
          onPressed: _busy ? null : _search,
          child: AppText(_busy ? '正在请求…' : '搜索'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          AppText(_status!, style: const TextStyle(fontSize: 12, height: 1.5)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          AppText(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (final book in _results)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ContentPanel(
              onTap: () => _detail(book),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    book.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    [
                      if (book.author.isNotEmpty) book.author,
                      book.bookUrl,
                    ].join('\n'),
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        if (_book != null) ...[
          const SizedBox(height: 8),
          sectionHeader(context, '详情', _book!.bookUrl),
          const SizedBox(height: 8),
          ContentPanel(child: AppText(_detailText(_book!))),
          const SizedBox(height: 12),
          GlassTextButton(
            onPressed: _busy ? null : () => _toc(_book!),
            child: const AppText('获取目录'),
          ),
          const SizedBox(height: 12),
          for (final chapter in _book!.chapters.take(80))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ContentPanel(
                onTap: () => _readChapter(chapter),
                child: AppText(
                  chapter.volumeTitle.isEmpty
                      ? chapter.title
                      : '${chapter.volumeTitle} · ${chapter.title}',
                ),
              ),
            ),
          if (_book!.chapters.length > 80) const AppText('目录较长，这里只列出前 80 章。'),
        ],
        if (_content != null) ...[
          const SizedBox(height: 12),
          sectionHeader(context, '正文', ''),
          const SizedBox(height: 8),
          ContentPanel(
            child: AppText(
              _content!.length > 4000
                  ? '${_content!.substring(0, 4000)}\n\n…共 ${_content!.length} 字'
                  : _content!,
              style: const TextStyle(height: 1.6),
            ),
          ),
        ],
      ],
    ),
  );

  String _detailText(CustomBookRecord book) => [
    book.name,
    if (book.author.isNotEmpty) '作者 ${book.author}',
    if (book.kind.isNotEmpty) '分类 ${book.kind}',
    if (book.lastChapter.isNotEmpty) '最新 ${book.lastChapter}',
    if (book.coverUrl.isNotEmpty) '封面 ${book.coverUrl}',
    if (book.tocUrl.isNotEmpty) '目录 ${book.tocUrl}',
    if (book.intro.isNotEmpty) book.intro,
  ].join('\n');

  Future<void> _search() => _run('搜索', () async {
    final books = await _engine.search(
      widget.source,
      _keyword.text,
      identify: (_, _) => 0,
    );
    setState(() {
      _results = books;
      _book = null;
      _content = null;
      _status = books.isEmpty ? '搜索完成，没有匹配的书' : '搜索完成 · ${books.length} 本';
    });
  });

  Future<void> _detail(CustomBookRecord book) => _run('详情', () async {
    final detailed = await _engine.detail(widget.source, book);
    setState(() {
      _book = detailed;
      _content = null;
      _status = '详情完成 · ${detailed.name}';
    });
  });

  Future<void> _toc(CustomBookRecord book) => _run('目录', () async {
    final listed = await _engine.toc(widget.source, book);
    setState(() {
      _book = listed;
      _content = null;
      _status = '目录完成 · ${listed.chapters.length} 章';
    });
  });

  Future<void> _readChapter(CustomChapterRef chapter) => _run('正文', () async {
    final book = _book;
    if (book == null) return;
    final text = await _engine.content(widget.source, book, chapter);
    setState(() {
      _content = text;
      _status = '正文完成 · ${chapter.title}';
    });
  });

  Future<void> _run(String step, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在$step…';
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException ? error.message : '$error';
      setState(() => _error = '$step失败：$message');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

const _ruleFields = <(String, String), List<(String, String)>>{
  ('search', '搜索规则'): [
    ('bookList', '书目列表'),
    ('name', '书名'),
    ('author', '作者'),
    ('kind', '分类'),
    ('intro', '简介'),
    ('coverUrl', '封面'),
    ('bookUrl', '书籍链接'),
    ('lastChapter', '最新章节'),
    ('wordCount', '字数'),
  ],
  ('info', '详情规则'): [
    ('init', '预处理'),
    ('name', '书名'),
    ('author', '作者'),
    ('kind', '分类'),
    ('intro', '简介'),
    ('coverUrl', '封面'),
    ('tocUrl', '目录链接'),
    ('lastChapter', '最新章节'),
    ('wordCount', '字数'),
  ],
  ('toc', '目录规则'): [
    ('chapterList', '章节列表'),
    ('chapterName', '章节名'),
    ('chapterUrl', '章节链接'),
    ('isVolume', '是否分卷'),
    ('nextTocUrl', '下一页目录'),
  ],
  ('content', '正文规则'): [
    ('content', '正文'),
    ('title', '标题'),
    ('nextContentUrl', '下一页正文'),
    ('sourceRegex', '正文提取'),
    ('replaceRegex', '替换'),
  ],
};

String _titleOf(String group) =>
    _ruleFields.keys.firstWhere((entry) => entry.$1 == group).$2;

BookSourceRules _rulesOf(BookSource source, String group) => switch (group) {
  'search' => source.search,
  'info' => source.info,
  'toc' => source.toc,
  'content' => source.content,
  _ => const BookSourceRules({}),
};
