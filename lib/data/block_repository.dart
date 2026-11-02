import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';

/// Armazenamento local-first da camada dinâmica.
abstract class BlockRepository {
  /// null = nada salvo ainda (primeira execução ou arquivo inutilizável).
  Future<List<TimeBlock>?> load();
  Future<void> save(List<TimeBlock> blocks);
}

class MemoryBlockRepository implements BlockRepository {
  List<TimeBlock>? _data;

  @override
  Future<List<TimeBlock>?> load() async => _data;

  @override
  Future<void> save(List<TimeBlock> blocks) async {
    _data = List.of(blocks);
  }
}

class FileBlockRepository implements BlockRepository {
  FileBlockRepository(this._file);
  final File _file;
  Future<void> _queue = Future.value();

  static Future<FileBlockRepository> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return FileBlockRepository(File('${dir.path}${Platform.pathSeparator}schedule.json'));
  }

  String get path => _file.path;

  @override
  Future<List<TimeBlock>?> load() async {
    if (!await _file.exists()) return null;
    try {
      final data = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      return [
        for (final j in data['blocks'] as List) TimeBlock.fromJson(j as Map<String, dynamic>),
      ];
    } catch (e) {
      debugPrint('schedule.json ilegível, criando backup: $e');
      try {
        await _file.rename('${_file.path}.corrupt');
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> save(List<TimeBlock> blocks) {
    final snapshot = jsonEncode({
      'version': 1,
      'blocks': [for (final b in blocks) b.toJson()],
    });
    _queue = _queue.then((_) => _write(snapshot));
    return _queue;
  }

  Future<void> _write(String content) async {
    try {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Falha ao salvar a agenda: $e');
    }
  }
}

/// Em produção o main() sobrescreve estes dois; nos testes valem os padrões.
final blockRepositoryProvider =
    Provider<BlockRepository>((ref) => MemoryBlockRepository());

/// Blocos dinâmicos carregados do disco antes do runApp (null = primeira vez).
final initialBlocksProvider = Provider<List<TimeBlock>?>((ref) => null);
