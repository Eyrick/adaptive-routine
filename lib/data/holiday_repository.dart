import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/holiday.dart';

/// Armazenamento local dos feriados (arquivo holidays.json).
/// A chave é a data no formato "yyyy-MM-dd".
abstract class HolidayRepository {
  /// null = nada salvo ainda (primeira execução ou arquivo inutilizável).
  Future<Map<String, Holiday>?> load();
  Future<void> save(Map<String, Holiday> holidays);
}

class MemoryHolidayRepository implements HolidayRepository {
  Map<String, Holiday>? _data;

  @override
  Future<Map<String, Holiday>?> load() async => _data;

  @override
  Future<void> save(Map<String, Holiday> holidays) async {
    _data = Map.of(holidays);
  }
}

class FileHolidayRepository implements HolidayRepository {
  FileHolidayRepository(this._file);
  final File _file;
  Future<void> _queue = Future.value();

  static Future<FileHolidayRepository> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return FileHolidayRepository(File('${dir.path}${Platform.pathSeparator}holidays.json'));
  }

  String get path => _file.path;

  @override
  Future<Map<String, Holiday>?> load() async {
    if (!await _file.exists()) return null;
    try {
      return decodeHolidays(await _file.readAsString());
    } catch (e) {
      debugPrint('holidays.json ilegível, criando backup: $e');
      try {
        await _file.rename('${_file.path}.corrupt');
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> save(Map<String, Holiday> holidays) {
    final snapshot = encodeHolidays(holidays);
    _queue = _queue.then((_) => _write(snapshot));
    return _queue;
  }

  Future<void> _write(String content) async {
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Falha ao salvar os feriados: $e');
    }
  }
}

final holidayRepositoryProvider =
    Provider<HolidayRepository>((ref) => MemoryHolidayRepository());

/// Feriados carregados do disco antes do runApp (null = primeira vez).
final initialHolidaysProvider = Provider<Map<String, Holiday>?>((ref) => null);

/// Formato do holidays.json (também usado no armazenamento do navegador).
String encodeHolidays(Map<String, Holiday> holidays) => jsonEncode({
      'version': 1,
      'holidays': {for (final e in holidays.entries) e.key: e.value.toJson()},
    });

Map<String, Holiday> decodeHolidays(String text) {
  final data = jsonDecode(text) as Map<String, dynamic>;
  return {
    for (final e in (data['holidays'] as Map).entries)
      e.key as String: Holiday.fromJson((e.value as Map).cast<String, dynamic>()),
  };
}
