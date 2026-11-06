import 'package:flutter/foundation.dart' show immutable;

/// Camada 1 = fixed (base imutável), Camada 2 = dynamic (extras negociáveis).
enum Layer { fixed, dynamic }

/// Situação de um bloco: pendente (padrão), realizada ou não realizada.
enum BlockStatus { planned, done, missed }

@immutable
class TimeBlock {
  const TimeBlock({
    required this.id,
    required this.title,
    required this.layer,
    required this.start,
    required this.end,
    this.status = BlockStatus.planned,
  });

  final String id;
  final String title;
  final Layer layer;
  final DateTime start;
  final DateTime end;
  final BlockStatus status;

  Duration get duration => end.difference(start);

  bool overlaps(TimeBlock o) => start.isBefore(o.end) && o.start.isBefore(end);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'layer': layer.name,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'status': status.name,
      };

  factory TimeBlock.fromJson(Map<String, dynamic> j) => TimeBlock(
        id: j['id'] as String,
        title: j['title'] as String,
        layer: Layer.values.byName(j['layer'] as String),
        start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        status: BlockStatus.values.byName((j['status'] as String?) ?? 'planned'),
      );

  TimeBlock copyWith({DateTime? start, DateTime? end, BlockStatus? status}) => TimeBlock(
        id: id,
        title: title,
        layer: layer,
        start: start ?? this.start,
        end: end ?? this.end,
        status: status ?? this.status,
      );
}

@immutable
class SlotSuggestion {
  const SlotSuggestion(this.start, this.end);
  final DateTime start;
  final DateTime end;
}


int _idSeq = 0;

/// Id único para blocos criados em tempo de execução. O contador evita
/// colisão quando dois blocos nascem no mesmo "tick" do relógio (no Windows
/// o relógio tem pouca resolução).
String newBlockId() => 'dy-${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';
