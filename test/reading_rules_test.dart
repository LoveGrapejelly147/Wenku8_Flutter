import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reading_rules/models.dart';

void main() {
  const sample = '''
正文
第一章 出发
仍然是正文
第二章 归来
Chapter 3 Extra
''';

  test('txt rules prefer the pattern that finds real chapters', () {
    final match = bestTxtTocRule(sample, builtInTxtTocRules);
    expect(match, isNotNull);
    expect(match!.rule.name, '综合（章、卷、Chapter）');
    expect(match.count, 3);
    expect(optionsForTxtRule(match.rule).customToc, isTrue);
    expect(cleanTxtTitle('第一章 出发', match.rule), '第一章 出发');
  });

  test('chapter pattern does not treat every line as a heading', () {
    final noisy = List.filled(10, '普通句子').join('\n');
    expect(bestTxtTocRule(noisy, builtInTxtTocRules), isNull);
  });

  test('replace rules honor scope, order and the global switch', () {
    const rules = [
      ReplaceRule(
        id: 2,
        name: '后',
        pattern: '乙',
        replacement: '2',
        order: 2,
        isRegex: false,
      ),
      ReplaceRule(
        id: 1,
        name: '先',
        pattern: '甲',
        replacement: '1',
        order: 1,
        isRegex: false,
        scope: '诡秘',
      ),
      ReplaceRule(
        id: 3,
        name: '标题',
        pattern: '标题',
        replacement: '题',
        scopeTitle: true,
        scopeContent: false,
      ),
    ];
    expect(
      applyReplaceRules(
        '甲乙',
        rules,
        enabled: true,
        target: ReplaceTarget.content,
        bookTitle: '诡秘之主',
      ),
      '12',
    );
    expect(
      applyReplaceRules(
        '甲乙',
        rules,
        enabled: true,
        target: ReplaceTarget.content,
        bookTitle: '别的书',
      ),
      '甲2',
    );
    expect(
      applyReplaceRules(
        '标题',
        rules,
        enabled: false,
        target: ReplaceTarget.title,
      ),
      '标题',
    );
    expect(
      applyReplaceRules(
        '标题',
        rules,
        enabled: true,
        target: ReplaceTarget.title,
      ),
      '题',
    );
  });

  test('legado txt, replace and dict json round-trip', () {
    final txt = TxtTocRule.fromLegado({
      'id': 9,
      'name': '自定义',
      'rule': r'^第\d+章',
      'replacement': '',
      'enable': false,
      'serialNumber': 4,
    });
    expect(TxtTocRule.fromLegado(txt.toLegado()).enabled, isFalse);
    final replace = ReplaceRule.fromLegado({
      'id': 3,
      'name': '广告',
      'pattern': '广告',
      'replacement': '',
      'scope': 'https://source.example',
      'isRegex': false,
      'scopeContent': true,
      'isEnabled': true,
    });
    expect(replace.appliesTo(sourceUrl: 'https://source.example/book'), isTrue);
    expect(replace.appliesTo(bookTitle: '别的书'), isFalse);
    final dict = DictRule.fromLegado({
      'name': '示例词典',
      'urlRule': 'https://dict.example/s?q={{key}}',
      'showRule': r'##<b>(.*?)</b>##$1',
    });
    expect(dict.urlFor('雾'), 'https://dict.example/s?q=%E9%9B%BE');
    expect(dict.read('<b>雾</b>', 'https://dict.example/s'), '雾');
  });
}
