import '../book_source/http.dart';
import '../book_source/url_template.dart';
import '../dictionary_models.dart';
import 'store.dart';

Future<List<DictionaryLookupGroup>> lookupOnlineDictionaries(
  String word,
) async {
  final query = word.trim();
  if (query.isEmpty) return const [];
  final groups = <DictionaryLookupGroup>[];
  final rules = [...ReadingRuleStore.shared.dictRules]
    ..sort((a, b) => a.order.compareTo(b.order));
  for (final rule in rules.where((rule) => rule.enabled)) {
    final dictionary = UserDictionary(
      id: 'dict-online',
      name: rule.name,
      format: 'online',
      source: DictionaryAsset(
        file: 'online.mdx',
        sourceName: rule.name,
        entries: 0,
        bytes: 1,
      ),
    );
    try {
      final response = await BookSourceHttp.shared.send(
        BookSourceRequestSpec(url: rule.urlFor(query)),
      );
      final text = rule.read(response.body, response.url);
      groups.add(
        DictionaryLookupGroup(
          dictionary,
          definitions: text.isEmpty
              ? const []
              : [DictionaryDefinition(query, text)],
          error: text.isEmpty ? '没有查到释义' : null,
        ),
      );
    } catch (error) {
      groups.add(
        DictionaryLookupGroup(
          dictionary,
          error: error is FormatException ? error.message : '在线查词失败',
        ),
      );
    }
  }
  return groups;
}
