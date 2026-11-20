import 'dart:convert';

import 'model.dart';

class ExploreKind {
  const ExploreKind({required this.title, required this.url});

  final String title;
  final String url;
}

/// Legado `exploreUrl`: one `名称::URL` per line or `&&`, or a JSON array of
/// `{title, url, style}`.
List<ExploreKind> parseExploreKinds(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  if (text.startsWith('[')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return [
          for (final item in decoded)
            if (item is Map)
              ExploreKind(
                title: '${item['title'] ?? item['name'] ?? ''}'.trim(),
                url: '${item['url'] ?? ''}'.trim(),
              ),
        ].where((kind) => kind.url.isNotEmpty).toList();
      }
    } on FormatException {
      return const [];
    }
  }
  final kinds = <ExploreKind>[];
  for (final part in text.split(RegExp(r'(?:&&|\r?\n)+'))) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final split = trimmed.indexOf('::');
    if (split < 0) {
      kinds.add(ExploreKind(title: trimmed, url: trimmed));
    } else {
      final title = trimmed.substring(0, split).trim();
      final url = trimmed.substring(split + 2).trim();
      if (url.isEmpty) continue;
      kinds.add(ExploreKind(title: title.isEmpty ? url : title, url: url));
    }
  }
  return kinds;
}

bool sourceShowsExplore(BookSource source) =>
    source.enabled &&
    source.enabledExplore &&
    source.isText &&
    source.exploreUrl.trim().isNotEmpty;

List<BookSource> discoverableSources(Iterable<BookSource> sources) => [
  for (final source in sources)
    if (sourceShowsExplore(source)) source,
];

BookSourceRules exploreRules(BookSource source) =>
    source.explore.values.isEmpty ? source.search : source.explore;
