import 'package:flutter/material.dart';

import '../../domain/holiday.dart';
import '../../domain/models.dart';

class BlockStyle {
  const BlockStyle({required this.bg, required this.fg, required this.accent});
  final Color bg; // fundo do bloco
  final Color fg; // texto
  final Color accent; // faixa lateral e ícone
}

/// Cores por camada e situação.
///
/// * Pendente: cinza (base fixa) e roxo (dinâmico), como sempre foi.
/// * Realizada / não realizada: verde e vermelho. A base fixa usa tons
///   **suaves e dessaturados**; o dinâmico usa tons **vivos**, para os dois
///   grupos continuarem distinguíveis mesmo com a mesma situação.
BlockStyle blockStyle(ColorScheme cs, Layer layer, BlockStatus status) {
  final dark = cs.brightness == Brightness.dark;
  final fixed = layer == Layer.fixed;

  switch (status) {
    case BlockStatus.planned:
      return fixed
          ? BlockStyle(bg: cs.surfaceContainerHighest, fg: cs.onSurfaceVariant, accent: cs.outline)
          : BlockStyle(bg: cs.primaryContainer, fg: cs.onPrimaryContainer, accent: cs.primary);

    case BlockStatus.done:
      if (fixed) {
        return dark
            ? const BlockStyle(bg: Color(0xFF2A3B2E), fg: Color(0xFFC5D8C8), accent: Color(0xFF7FA886))
            : const BlockStyle(bg: Color(0xFFDDE9DF), fg: Color(0xFF3B5240), accent: Color(0xFF6B8F71));
      }
      return dark
          ? const BlockStyle(bg: Color(0xFF14532D), fg: Color(0xFFDCFCE7), accent: Color(0xFF22C55E))
          : const BlockStyle(bg: Color(0xFFBBF7D0), fg: Color(0xFF14532D), accent: Color(0xFF16A34A));

    case BlockStatus.missed:
      if (fixed) {
        return dark
            ? const BlockStyle(bg: Color(0xFF3F2B2B), fg: Color(0xFFE2CACA), accent: Color(0xFFB07A7A))
            : const BlockStyle(bg: Color(0xFFEFDCDC), fg: Color(0xFF5A3A3A), accent: Color(0xFFA56A6A));
      }
      return dark
          ? const BlockStyle(bg: Color(0xFF7F1D1D), fg: Color(0xFFFEE2E2), accent: Color(0xFFEF4444))
          : const BlockStyle(bg: Color(0xFFFECACA), fg: Color(0xFF7F1D1D), accent: Color(0xFFDC2626));
  }
}

/// Dia especial: a coluna inteira ganha um tom próprio, diferente do cinza,
/// roxo, verde e vermelho dos blocos. Feriado = âmbar; evento = azul-céu.
Color dayKindTint(ColorScheme cs, DayKind kind) {
  final dark = cs.brightness == Brightness.dark;
  return switch (kind) {
    DayKind.holiday => dark ? const Color(0x26F59E0B) : const Color(0x33F59E0B),
    DayKind.event => dark ? const Color(0x260EA5E9) : const Color(0x330EA5E9),
  };
}

Color dayKindAccent(ColorScheme cs, DayKind kind) {
  final dark = cs.brightness == Brightness.dark;
  return switch (kind) {
    DayKind.holiday => dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
    DayKind.event => dark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1),
  };
}
