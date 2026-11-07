/// Primeiro dia da semana exibida no calendário: [DateTime.sunday] ou
/// [DateTime.monday]. Nos calendários usados no Brasil a semana costuma
/// começar no domingo (Dom ... Sáb). Para voltar a Seg ... Dom, troque para
/// `DateTime.monday`.
const int kWeekStart = DateTime.sunday;

/// Início (meia-noite) da semana que contém [d].
DateTime startOfWeek(DateTime d, {int firstDay = kWeekStart}) =>
    DateTime(d.year, d.month, d.day - (d.weekday - firstDay) % 7);

/// Ordem dos dias da semana na tela (1 = segunda ... 7 = domingo).
/// Domingo primeiro: [7, 1, 2, 3, 4, 5, 6].
List<int> weekdayOrder({int firstDay = kWeekStart}) =>
    [for (var i = 0; i < 7; i++) (firstDay - 1 + i) % 7 + 1];
