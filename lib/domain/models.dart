import 'package:flutter/foundation.dart' show immutable;

/// Camada 1 = fixed (base imutável), Camada 2 = dynamic (extras negociáveis).
enum Layer { fixed, dynamic }

@immutable
class TimeBlock {
  const TimeBlock({
    required this.id,
    required this.title,
    required this.layer,
    required this.start,
    required this.end,
  });

  final String id;
  final String title;
  final Layer layer;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  bool overlaps(TimeBlock o) => start.isBefore(o.end) && o.start.isBefore(end);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'layer': layer.name,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      };

  factory TimeBlock.fromJson(Map<String, dynamic> j) => TimeBlock(
        id: j['id'] as String,
        title: j['title'] as String,
        layer: Layer.values.byName(j['layer'] as String),
        start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
      );

  TimeBlock copyWith({DateTime? start, DateTime? end}) => TimeBlock(
        id: id,
        title: title,
        layer: layer,
        start: start ?? this.start,
        end: end ?? this.end,
      );
}

@immutable
class SlotSuggestion {
  const SlotSuggestion(this.start, this.end);
  final DateTime start;
  final DateTime end;
}
