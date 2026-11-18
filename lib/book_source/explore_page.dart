import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_interactions.dart';
import '../app_ui.dart';
import '../catalog.dart';
import '../feature_pages.dart';
import 'explore.dart';
import 'model.dart';
import 'repository.dart';

class BookSourceDiscoverSection extends StatelessWidget {
  const BookSourceDiscoverSection({
    super.key,
    required this.repository,
    required this.reduceMotion,
    required this.onOpen,
  });

  final BookSourceRepository repository;
  final bool reduceMotion;
  final ValueChanged<Novel> onOpen;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository.store,
    builder: (context, _) {
      final sources = discoverableSources(repository.store.sources);
      if (sources.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              '书源发现',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final source in sources) ...[
              AppText(source.name, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final kind in _kinds(source))
                    GlassTextButton(
                      onPressed: () => pushNovelPage<void>(
                        context,
                        BookSourceExplorePage(
                          repository: repository,
                          source: source,
                          kind: kind,
                          reduceMotion: reduceMotion,
                          onOpen: onOpen,
                        ),
                        reduceMotion: reduceMotion,
                        slot: ('explore', source.url, kind.url),
                      ),
                      child: AppText(kind.title),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    },
  );

  List<ExploreKind> _kinds(BookSource source) {
    try {
      final scripts = repository.engine.scripts;
      if (scripts != null) return scripts.kinds(source);
      return parseExploreKinds(source.exploreUrl);
    } catch (error) {
      final message = error is FormatException ? error.message : '发现规则无法解析';
      return [ExploreKind(title: message, url: source.url)];
    }
  }
}

class BookSourceExplorePage extends StatefulWidget {
  const BookSourceExplorePage({
    super.key,
    required this.repository,
    required this.source,
    required this.kind,
    required this.reduceMotion,
    required this.onOpen,
  });

  final BookSourceRepository repository;
  final BookSource source;
  final ExploreKind kind;
  final bool reduceMotion;
  final ValueChanged<Novel> onOpen;

  @override
  State<BookSourceExplorePage> createState() => _BookSourceExplorePageState();
}

class _BookSourceExplorePageState extends State<BookSourceExplorePage> {
  final _books = <Novel>[];
  var _page = 1;
  var _loading = false;
  var _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_more) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await widget.repository.engine.explore(
        widget.source,
        widget.kind.url,
        page: _page,
        identify: widget.repository.store.idFor,
      );
      final novels = <Novel>[];
      for (final record in found) {
        final id = record.id == 0
            ? widget.repository.store.idFor(record.sourceUrl, record.bookUrl)
            : record.id;
        final stored = await widget.repository.store.remember(
          record.copyWith(id: id),
        );
        novels.add(widget.repository.novelFrom(stored));
      }
      if (!mounted) return;
      setState(() {
        _books.addAll(novels);
        _more = novels.isNotEmpty && widget.kind.url.contains('{{page');
        _page++;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FormatException ? error.message : '发现列表加载失败';
        _more = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: widget.kind.title,
    code: widget.source.name,
    child: ListView(
      padding: featurePadding(context),
      children: [
        if (_books.isEmpty && _loading) const AppText('正在加载发现列表…'),
        if (_error != null) AppText(_error!),
        for (final book in _books)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ContentPanel(
              onTap: () => widget.onOpen(book),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    book.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (book.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    AppText(book.author, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        if (_more)
          GlassTextButton(
            onPressed: _loading ? null : _load,
            child: AppText(_loading ? '正在加载…' : '下一页'),
          ),
        if (!_more && _books.isEmpty && _error == null && !_loading)
          const AppText('这个分类没有书'),
      ],
    ),
  );
}
