import 'package:flutter/material.dart';

/// Sistema visual do Metric, conforme o Relatório 3 (Design e UX).
/// Cores são propostas a validar em teste de contraste (WCAG AA: 4,5:1).

const Color kFundo = Color(0xFFF7F8F7);
const Color kSuperficie = Color(0xFFFFFFFF);
const Color kTextoPrincipal = Color(0xFF1A1D1B);
const Color kTextoSecundario = Color(0xFF4B5563);
const Color kDestaque = Color(0xFF0F766E);
const Color kPositivo = Color(0xFF067647);
const Color kAtencao = Color(0xFFB54708);
const Color kNegativo = Color(0xFFB42318);

/// Cor de cada caixinha (R3 §3.2). Nunca é o único identificador: ícone e
/// nome acompanham (daltonismo).
Color boxColor(String id) {
  switch (id) {
    case 'essenciais':
      return const Color(0xFF1D4ED8); // Azul
    case 'livre':
      return const Color(0xFF15803D); // Verde
    case 'reserva':
      return const Color(0xFFB45309); // Âmbar
    case 'investido':
      return const Color(0xFF6D28D9); // Roxo
    case 'metas':
      return const Color(0xFFBE185D); // Magenta
    default:
      return kTextoSecundario;
  }
}

IconData boxIcon(String id) {
  switch (id) {
    case 'essenciais':
      return Icons.home_outlined;
    case 'livre':
      return Icons.account_balance_wallet_outlined;
    case 'reserva':
      return Icons.shield_outlined;
    case 'investido':
      return Icons.trending_up;
    case 'metas':
      return Icons.flag_outlined;
    default:
      return Icons.label_outlined;
  }
}

TextStyle temaTextStyle(BuildContext context, {Color? color, double? size, FontWeight? weight}) {
  return TextStyle(
    color: color ?? kTextoPrincipal,
    fontSize: size,
    fontWeight: weight,
  );
}
