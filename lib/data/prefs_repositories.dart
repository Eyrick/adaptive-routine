import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/fixed_rule.dart';
import '../domain/holiday.dart';
import '../domain/models.dart';
import 'block_repository.dart';
import 'holiday_repository.dart';
import 'rule_repository.dart';

/// Armazenamento para o navegador (localStorage, via SharedPreferences), onde
/// não existem arquivos em disco. Usa exatamente o mesmo formato JSON dos
/// arquivos do Windows e do Android.
class _PrefsJson {
  _PrefsJson(this._prefs, this.key);
  final SharedPreferences _prefs;
  final String key;

  String? read() => _prefs.getString(key);

  Future<void> write(String text) async {
    try {
      await _prefs.setString(key, text);
    } catch (e) {
      debugPrint('Falha ao salvar $key: $e');
    }
  }

  /// Dado ilegível: guarda uma cópia e libera a chave, em vez de sobrescrever.
  Future<void> quarantine(String text) async {
    await _prefs.setString('$key.corrupt', text);
    await _prefs.remove(key);
  }
}

class PrefsBlockRepository implements BlockRepository {
  PrefsBlockRepository(SharedPreferences prefs) : _store = _PrefsJson(prefs, 'schedule.json');
  final _PrefsJson _store;

  @override
  Future<List<TimeBlock>?> load() async {
    final text = _store.read();
    if (text == null) return null;
    try {
      return decodeBlocks(text);
    } catch (e) {
      debugPrint('schedule.json ilegível no navegador, guardando cópia: $e');
      await _store.quarantine(text);
      return null;
    }
  }

  @override
  Future<void> save(List<TimeBlock> blocks) => _store.write(encodeBlocks(blocks));
}

class PrefsRuleRepository implements RuleRepository {
  PrefsRuleRepository(SharedPreferences prefs) : _store = _PrefsJson(prefs, 'routine.json');
  final _PrefsJson _store;

  @override
  Future<List<FixedRule>?> load() async {
    final text = _store.read();
    if (text == null) return null;
    try {
      return decodeRules(text);
    } catch (e) {
      debugPrint('routine.json ilegível no navegador, guardando cópia: $e');
      await _store.quarantine(text);
      return null;
    }
  }

  @override
  Future<void> save(List<FixedRule> rules) => _store.write(encodeRules(rules));
}

class PrefsHolidayRepository implements HolidayRepository {
  PrefsHolidayRepository(SharedPreferences prefs) : _store = _PrefsJson(prefs, 'holidays.json');
  final _PrefsJson _store;

  @override
  Future<Map<String, Holiday>?> load() async {
    final text = _store.read();
    if (text == null) return null;
    try {
      return decodeHolidays(text);
    } catch (e) {
      debugPrint('holidays.json ilegível no navegador, guardando cópia: $e');
      await _store.quarantine(text);
      return null;
    }
  }

  @override
  Future<void> save(Map<String, Holiday> holidays) => _store.write(encodeHolidays(holidays));
}
