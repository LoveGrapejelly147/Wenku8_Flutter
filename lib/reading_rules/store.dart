import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../local_import_options.dart';
import 'models.dart';

class ReadingRuleStore extends ChangeNotifier {
  ReadingRuleStore({List<TxtTocRule>? initialTxt})
    : txtRules = [...initialTxt ?? builtInTxtTocRules];

  static final shared = ReadingRuleStore();
  Directory? _root;
  final List<TxtTocRule> txtRules;
  final List<ReplaceRule> replaceRules = [];
  final List<DictRule> dictRules = [];
  bool purifyEnabled = true;
  Future<void> _writes = Future<void>.value();

  static Future<void> openShared() async {
    final support = await getApplicationSupportDirectory();
    shared._root = Directory('${support.path}/reading_rules');
    await shared.load();
  }

  List<TxtTocRule> get enabledTxtRules =>
      txtRules.where((rule) => rule.enabled).toList();

  Future<void> load() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      purifyEnabled = decoded['purifyEnabled'] != false;
      txtRules
        ..clear()
        ..addAll(_readList(decoded['txtToc'], TxtTocRule.fromLegado));
      if (txtRules.isEmpty) txtRules.addAll(builtInTxtTocRules);
      replaceRules
        ..clear()
        ..addAll(_readList(decoded['replace'], ReplaceRule.fromLegado));
      dictRules
        ..clear()
        ..addAll(_readList(decoded['dict'], DictRule.fromLegado));
      _sort();
      notifyListeners();
    } on FormatException {
      return;
    }
  }

  Future<LocalImportOptions> optionsForText(String sample) async {
    final match = bestTxtTocRule(sample, enabledTxtRules);
    if (match == null) return const LocalImportOptions();
    return optionsForTxtRule(match.rule);
  }

  Future<void> saveTxt(TxtTocRule rule) => _update(() {
    final index = txtRules.indexWhere((item) => item.id == rule.id);
    if (index >= 0) {
      txtRules[index] = rule;
    } else {
      txtRules.add(rule);
    }
  });

  Future<void> moveTxt(int id, int delta) => _move(
    txtRules,
    (rule) => rule.id == id,
    delta,
    (rule, order) => rule.copyWith(serialNumber: order),
  );

  Future<void> removeTxt(int id) =>
      _update(() => txtRules.removeWhere((rule) => rule.id == id));

  Future<int> importTxt(List<TxtTocRule> incoming) => _update(() {
    var added = 0;
    for (final rule in incoming) {
      final index = txtRules.indexWhere((item) => item.name == rule.name);
      if (index >= 0) {
        txtRules[index] = rule;
      } else {
        txtRules.add(rule);
        added++;
      }
    }
    return added;
  });

  Future<void> saveReplace(ReplaceRule rule) => _update(() {
    final index = replaceRules.indexWhere((item) => item.id == rule.id);
    if (index >= 0) {
      replaceRules[index] = rule;
    } else {
      replaceRules.add(rule);
    }
  });

  Future<void> moveReplace(int id, int delta) => _move(
    replaceRules,
    (rule) => rule.id == id,
    delta,
    (rule, order) => rule.copyWith(order: order),
  );

  Future<void> removeReplace(int id) =>
      _update(() => replaceRules.removeWhere((rule) => rule.id == id));

  Future<int> importReplace(List<ReplaceRule> incoming) => _update(() {
    var added = 0;
    for (final rule in incoming) {
      final index = replaceRules.indexWhere((item) => item.id == rule.id);
      if (index >= 0) {
        replaceRules[index] = rule;
      } else {
        replaceRules.add(rule);
        added++;
      }
    }
    return added;
  });

  Future<void> setPurifyEnabled(bool value) =>
      _update(() => purifyEnabled = value);

  Future<void> saveDict(DictRule rule) => _update(() {
    final index = dictRules.indexWhere((item) => item.name == rule.name);
    if (index >= 0) {
      dictRules[index] = rule;
    } else {
      dictRules.add(rule);
    }
  });

  Future<void> moveDict(String name, int delta) => _move(
    dictRules,
    (rule) => rule.name == name,
    delta,
    (rule, order) => rule.copyWith(order: order),
  );

  Future<void> removeDict(String name) =>
      _update(() => dictRules.removeWhere((rule) => rule.name == name));

  Future<int> importDict(List<DictRule> incoming) => _update(() {
    var added = 0;
    for (final rule in incoming) {
      final index = dictRules.indexWhere((item) => item.name == rule.name);
      if (index >= 0) {
        dictRules[index] = rule;
      } else {
        dictRules.add(rule);
        added++;
      }
    }
    return added;
  });

  String purify(
    String input, {
    required ReplaceTarget target,
    String? bookTitle,
    String? sourceUrl,
    String? sourceName,
  }) => applyReplaceRules(
    input,
    replaceRules,
    enabled: purifyEnabled,
    target: target,
    bookTitle: bookTitle,
    sourceUrl: sourceUrl,
    sourceName: sourceName,
  );

  File? get _file {
    final root = _root;
    return root == null ? null : File('${root.path}/rules.json');
  }

  List<T> _readList<T>(Object? value, T Function(Map<String, dynamic>) decode) {
    if (value is! List) return [];
    final rules = <T>[];
    for (final item in value) {
      if (item is Map) {
        try {
          rules.add(decode(item.cast<String, dynamic>()));
        } on FormatException {
          continue;
        }
      }
    }
    return rules;
  }

  void _sort() {
    txtRules.sort((a, b) => a.serialNumber.compareTo(b.serialNumber));
    replaceRules.sort((a, b) => a.order.compareTo(b.order));
    dictRules.sort((a, b) => a.order.compareTo(b.order));
  }

  Future<T> _update<T>(T Function() change) {
    final result = _writes.then((_) async {
      final value = change();
      _sort();
      await _persist();
      notifyListeners();
      return value;
    });
    _writes = result.then((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> _move<T>(
    List<T> rules,
    bool Function(T rule) same,
    int delta,
    T Function(T rule, int order) reorder,
  ) => _update(() {
    final index = rules.indexWhere(same);
    final next = index + delta;
    if (index < 0 || next < 0 || next >= rules.length) return;
    final item = rules.removeAt(index);
    rules.insert(next, item);
    for (var i = 0; i < rules.length; i++) {
      rules[i] = reorder(rules[i], i);
    }
  });

  Future<void> _persist() async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'purifyEnabled': purifyEnabled,
        'txtToc': [for (final rule in txtRules) rule.toLegado()],
        'replace': [for (final rule in replaceRules) rule.toLegado()],
        'dict': [for (final rule in dictRules) rule.toLegado()],
      }),
    );
  }
}
