import 'dart:async';

import 'package:flutter/material.dart';

import '../app_ui.dart';
import '../book_search.dart';
import '../catalog.dart';
import '../feature_pages.dart';
import '../library_state.dart';
import 'aggregate.dart';
import 'manage.dart';
import 'repository.dart';

class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({
    super.key,
    required this.repository,
    required this.state,
    this.initialQuery = '',
    required this.reduceMotion,
    required this.onOpen,
  });

  final BookSourceRepository repository;
  final LibraryState state;
  final String initialQuery;
  final bool reduceMotion;
  final ValueChanged<Novel> onOpen;

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  AggregateSearchPreferences _preferences = const AggregateSearchPreferences();
  String? _group;
  String? _sourceUrl;
  var _running = false;
  var _generation = 0;
  AggregateProgress? _progress;
  final _novels = <int, Novel>{};
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  @override
  void dispose() {
    _generation++;
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final loaded = await AggregateSearchPreferences.load(
      widget.repository.store.root,
    );
    if (mounted) setState(() => _preferences = loaded);
  }

  Future<void> _savePreferences(AggregateSearchPreferences next) async {
    final clamped = next.clamped();
    setState(() => _preferences = clamped);
    await clamped.save(widget.repository.store.root);
  }

  String get _scopeLabel {
    if (_sourceUrl == builtInAggregateUrl) {
      return BookSourceRepository.builtInName;
    }
    if (_sourceUrl != null) {
      return widget.repository.store.sourceByUrl(_sourceUrl!)?.name ?? '单个书源';
    }
    if (_group != null && _group!.isNotEmpty) return _group!;
    return '全部已启用书源';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    return ArchiveFeaturePage(
      title: '聚合搜索',
      code: 'SEARCH / ALL',
      child: Column(
        children: [
          Padding(
            padding: featurePadding(context).copyWith(bottom: 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _query,
                  decoration: const InputDecoration(hintText: '书名或作者'),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _start(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    GlassTextButton(
                      onPressed: _running ? null : _chooseScope,
                      child: AppText(_scopeLabel),
                    ),
                    GlassTextButton(
                      onPressed: _running
                          ? null
                          : () => _savePreferences(
                              AggregateSearchPreferences(
                                concurrency: _preferences.concurrency - 1,
                                timeoutSeconds: _preferences.timeoutSeconds,
                              ),
                            ),
                      child: AppText('并发 ${_preferences.concurrency}'),
                    ),
                    GlassTextButton(
                      onPressed: _running
                          ? null
                          : () => _savePreferences(
                              AggregateSearchPreferences(
                                concurrency: _preferences.concurrency + 1,
                                timeoutSeconds: _preferences.timeoutSeconds,
                              ),
                            ),
                      child: const AppText('增加并发'),
                    ),
                    GlassTextButton(
                      onPressed: _running
                          ? null
                          : () => _savePreferences(
                              AggregateSearchPreferences(
                                concurrency: _preferences.concurrency,
                                timeoutSeconds: _preferences.timeoutSeconds - 5,
                              ),
                            ),
                      child: AppText('超时 ${_preferences.timeoutSeconds} 秒'),
                    ),
                    GlassTextButton(
                      onPressed: _running
                          ? null
                          : () => _savePreferences(
                              AggregateSearchPreferences(
                                concurrency: _preferences.concurrency,
                                timeoutSeconds: _preferences.timeoutSeconds + 5,
                              ),
                            ),
                      child: const AppText('延长超时'),
                    ),
                    GlassTextButton(
                      onPressed: _running ? _stop : _start,
                      child: AppText(_running ? '停止' : '搜索'),
                    ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  AppText(
                    progress.total == 0
                        ? '没有可搜索的书源'
                        : '已完成 ${progress.done}/${progress.total} · 失败 ${progress.failures}${progress.stopped ? ' · 已停止' : ''}',
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                  if (progress.failedNames.isNotEmpty)
                    AppText(
                      '失败：${progress.failedNames.join('、')}',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                ],
              ],
            ),
          ),
          Expanded(
            child: progress == null || progress.hits.isEmpty
                ? const Center(child: AppText('输入书名或作者后搜索'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    itemCount: progress.hits.length,
                    itemBuilder: (context, index) => _hit(progress.hits[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _hit(AggregateHit hit) {
    final key = aggregateIdentity(hit.title, hit.author);
    final open = _expanded.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ContentPanel(
        onTap: () => setState(() {
          if (!open) {
            _expanded.add(key);
          } else {
            _expanded.remove(key);
          }
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              hit.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            AppText(
              [
                if (hit.author.isNotEmpty) hit.author,
                '${hit.sourceCount} 个来源',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
            if (open)
              for (final book in hit.books)
                GlassTextButton(
                  onPressed: () {
                    final novel = _novels[book.id];
                    if (novel == null) return;
                    widget.onOpen(novel);
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppText('${book.sourceName} · ${book.title}'),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  void _stop() => setState(() {
    _generation++;
    _running = false;
    final progress = _progress;
    if (progress != null) {
      _progress = AggregateProgress(
        hits: progress.hits,
        done: progress.done,
        total: progress.total,
        failures: progress.failures,
        failedNames: progress.failedNames,
        stopped: true,
      );
    }
  });

  Future<void> _start() async {
    final query = _query.text.trim();
    if (query.isEmpty || _running) return;
    final generation = ++_generation;
    final enabled = sourcesForAggregateScope(
      widget.repository.store.enabledSources,
      group: _group,
      sourceUrl: _sourceUrl,
    );
    final includeBuiltIn = aggregateIncludesBuiltIn(
      group: _group,
      sourceUrl: _sourceUrl,
    );
    final targets = <AggregateTarget>[
      if (includeBuiltIn)
        AggregateTarget(
          name: BookSourceRepository.builtInName,
          search: () async {
            final page = await widget.repository.primary.searchFilteredPage(
              query,
              field: BookSearchField.all,
            );
            return [
              for (final novel in page.items)
                _remember(
                  novel,
                  BookSourceRepository.builtInName,
                  builtInAggregateUrl,
                ),
            ];
          },
        ),
      for (final source in enabled)
        AggregateTarget(
          name: source.name,
          search: () async {
            final found = await widget.repository.engine.search(
              source,
              query,
              identify: widget.repository.store.idFor,
            );
            final books = <AggregateBook>[];
            for (final record in found) {
              final id = record.id == 0
                  ? widget.repository.store.idFor(
                      record.sourceUrl,
                      record.bookUrl,
                    )
                  : record.id;
              final stored = await widget.repository.store.remember(
                record.copyWith(id: id),
              );
              books.add(
                _remember(
                  widget.repository.novelFrom(stored),
                  source.name,
                  source.url,
                ),
              );
            }
            return books;
          },
        ),
    ];
    setState(() {
      _running = true;
      _progress = AggregateProgress(
        hits: const [],
        done: 0,
        total: targets.length,
        failures: 0,
        failedNames: const [],
        stopped: false,
      );
      _expanded.clear();
    });
    final result = await runAggregateSearch(
      targets: targets,
      concurrency: _preferences.concurrency,
      timeout: _preferences.timeout,
      cancelled: () => generation != _generation,
      onProgress: (progress) {
        if (!mounted || generation != _generation) return;
        setState(() => _progress = progress);
      },
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _running = false;
      _progress = result;
    });
  }

  AggregateBook _remember(Novel novel, String sourceName, String sourceUrl) {
    _novels[novel.id] = novel;
    return AggregateBook(
      id: novel.id,
      title: novel.title,
      author: novel.author,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
    );
  }

  Future<void> _chooseScope() async {
    final sources = widget.repository.store.enabledSources;
    final groups = bookSourceGroupNames(sources);
    final choice = await showJellySheet<({String? group, String? source})>(
      context: context,
      reduceMotion: widget.reduceMotion,
      maxHeight: 520,
      builder: (sheet) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const AppText(
            '搜索范围',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          GlassTextButton(
            onPressed: () => Navigator.pop(sheet, (group: null, source: null)),
            child: const AppText('全部已启用书源'),
          ),
          GlassTextButton(
            onPressed: () => Navigator.pop(sheet, (
              group: null,
              source: builtInAggregateUrl,
            )),
            child: const AppText(BookSourceRepository.builtInName),
          ),
          for (final group in groups)
            GlassTextButton(
              onPressed: () =>
                  Navigator.pop(sheet, (group: group, source: null)),
              child: AppText('分组 · $group'),
            ),
          for (final source in sources)
            GlassTextButton(
              onPressed: () =>
                  Navigator.pop(sheet, (group: null, source: source.url)),
              child: AppText(source.name),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _group = choice.group;
      _sourceUrl = choice.source;
    });
  }
}

class SourceSwitchPage extends StatefulWidget {
  const SourceSwitchPage({
    super.key,
    required this.repository,
    required this.title,
    required this.author,
    required this.currentId,
    required this.reduceMotion,
  });

  final BookSourceRepository repository;
  final String title;
  final String author;
  final int currentId;
  final bool reduceMotion;

  @override
  State<SourceSwitchPage> createState() => _SourceSwitchPageState();
}

class _SourceSwitchPageState extends State<SourceSwitchPage> {
  var _running = true;
  var _failures = 0;
  final _candidates = <AggregateBook>[];
  final _novels = <int, Novel>{};

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    final preferences = await AggregateSearchPreferences.load(
      widget.repository.store.root,
    );
    final targets = <AggregateTarget>[
      AggregateTarget(
        name: BookSourceRepository.builtInName,
        search: () async {
          final page = await widget.repository.primary.searchFilteredPage(
            widget.title,
            field: BookSearchField.title,
          );
          return [
            for (final novel in page.items)
              if (sameAggregateBook(
                widget.title,
                widget.author,
                novel.title,
                novel.author,
              ))
                _book(
                  novel,
                  BookSourceRepository.builtInName,
                  builtInAggregateUrl,
                ),
          ];
        },
      ),
      for (final source in widget.repository.store.enabledSources)
        AggregateTarget(
          name: source.name,
          search: () async {
            final found = await widget.repository.engine.search(
              source,
              widget.title,
              identify: widget.repository.store.idFor,
            );
            final books = <AggregateBook>[];
            for (final record in found) {
              if (!sameAggregateBook(
                widget.title,
                widget.author,
                record.name,
                record.author,
              )) {
                continue;
              }
              final id = record.id == 0
                  ? widget.repository.store.idFor(
                      record.sourceUrl,
                      record.bookUrl,
                    )
                  : record.id;
              final stored = await widget.repository.store.remember(
                record.copyWith(id: id),
              );
              books.add(
                _book(
                  widget.repository.novelFrom(stored),
                  source.name,
                  source.url,
                ),
              );
            }
            return books;
          },
        ),
    ];
    await runAggregateSearch(
      targets: targets,
      concurrency: preferences.concurrency,
      timeout: preferences.timeout,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _failures = progress.failures;
          _candidates
            ..clear()
            ..addAll([
              for (final hit in progress.hits)
                for (final book in hit.books)
                  if (book.id != widget.currentId) book,
            ]);
        });
      },
    );
    if (mounted) setState(() => _running = false);
  }

  AggregateBook _book(Novel novel, String sourceName, String sourceUrl) {
    _novels[novel.id] = novel;
    return AggregateBook(
      id: novel.id,
      title: novel.title,
      author: novel.author,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
    );
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '换源',
    code: 'SOURCE / SWITCH',
    child: ListView(
      padding: featurePadding(context),
      children: [
        AppText(
          _running
              ? '正在其他书源查找《${widget.title}》 · 失败 $_failures'
              : _candidates.isEmpty
              ? '没有找到同名书。失败 $_failures'
              : '找到 ${_candidates.length} 个来源 · 失败 $_failures',
          style: const TextStyle(height: 1.5),
        ),
        const SizedBox(height: 12),
        for (final book in _candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ContentPanel(
              onTap: () {
                final novel = _novels[book.id];
                if (novel != null) Navigator.pop(context, novel);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    book.sourceName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  AppText(
                    [
                      book.title,
                      if (book.author.isNotEmpty) book.author,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
