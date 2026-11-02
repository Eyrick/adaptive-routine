import 'dart:io';

import 'package:adaptive_routine/data/block_repository.dart';
import 'package:adaptive_routine/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final block = TimeBlock(
    id: 'dy-1',
    title: 'Estudo de Física',
    layer: Layer.dynamic,
    start: DateTime(2026, 11, 2, 19),
    end: DateTime(2026, 11, 2, 20, 30),
  );

  test('JSON ida e volta', () {
    final b = TimeBlock.fromJson(block.toJson());
    expect(b.id, block.id);
    expect(b.layer, Layer.dynamic);
    expect(b.start, block.start);
    expect(b.end, block.end);
  });

  test('salva e recarrega do arquivo', () async {
    final dir = await Directory.systemTemp.createTemp('ar_test');
    final repo = FileBlockRepository(File('${dir.path}/schedule.json'));
    expect(await repo.load(), isNull);
    await repo.save([block]);
    final loaded = await repo.load();
    expect(loaded!.single.title, 'Estudo de Física');
    expect(loaded.single.start, block.start);
    await dir.delete(recursive: true);
  });

  test('arquivo corrompido vira backup e não derruba o app', () async {
    final dir = await Directory.systemTemp.createTemp('ar_test');
    final f = File('${dir.path}/schedule.json');
    await f.writeAsString('{ isso não é json');
    final repo = FileBlockRepository(f);
    expect(await repo.load(), isNull);
    expect(await File('${f.path}.corrupt').exists(), isTrue);
    await dir.delete(recursive: true);
  });
}
