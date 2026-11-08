import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/fixed_rule.dart';

/// Armazenamento local da rotina fixa (arquivo routine.json).
abstract class RuleRepository {
  /// null = nada salvo ainda (primeira execução ou arquivo inutilizável).
  Future<List<FixedRule>?> load();
  Future<void> save(List<FixedRule> rules);
}

class MemoryRuleRepository implements RuleRepository {
  List<FixedRule>? _data;

  @override
  Future<List<FixedRule>?> load() async => _data;

  @override
  Future<void> save(List<FixedRule> rules) async {
    _data = List.of(rules);
  }
}

class FileRuleRepository implements RuleRepository {
  FileRuleRepository(this._file);
  final File _file;
  Future<void> _queue = Future.value();

  static Future<FileRuleRepository> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return FileRuleRepository(File('${dir.path}${Platform.pathSeparator}routine.json'));
  }

  String get path => _file.path;

  @override
  Future<List<FixedRule>?> load() async {
    if (!await _file.exists()) return null;
    try {
      return decodeRules(await _file.readAsString());
    } catch (e) {
      debugPrint('routine.json ilegível, criando backup: $e');
      try {
        await _file.rename('${_file.path}.corrupt');
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> save(List<FixedRule> rules) {
    final snapshot = encodeRules(rules);
    _queue = _queue.then((_) => _write(snapshot));
    return _queue;
  }

  Future<void> _write(String content) async {
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Falha ao salvar a rotina fixa: $e');
    }
  }
}

final ruleRepositoryProvider =
    Provider<RuleRepository>((ref) => MemoryRuleRepository());

/// Regras carregadas do disco antes do runApp (null = primeira vez).
final initialRulesProvider = Provider<List<FixedRule>?>((ref) => null);

/// Formato do routine.json (também usado no armazenamento do navegador).
String encodeRules(List<FixedRule> rules) => jsonEncode({
      'version': 1,
      'rules': [for (final r in rules) r.toJson()],
    });

List<FixedRule> decodeRules(String text) {
  final data = jsonDecode(text) as Map<String, dynamic>;
  return [
    for (final j in data['rules'] as List) FixedRule.fromJson(j as Map<String, dynamic>),
  ];
}
