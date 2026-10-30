import 'package:flutter/material.dart';

/// Gráfico de linha mínimo e funcional: uma série de pontos (x, y) com eixo y
/// explicado numeralmente. Sem animações longas nem eixo truncado (R3 §7).
class GraficoLinha extends StatelessWidget {
  final List<double> valores;
  final List<String> rotulos;
  final String rotuloValor;
  final double altura;

  const GraficoLinha({
    super.key,
    required this.valores,
    required this.rotulos,
    this.rotuloValor = '',
    this.altura = 160,
  });

  @override
  Widget build(BuildContext context) {
    if (valores.isEmpty) {
      return SizedBox(height: altura, child: const Center(child: Text('Sem dados suficientes.')));
    }
    final min = valores.reduce((a, b) => a < b ? a : b);
    final max = valores.reduce((a, b) => a > b ? a : b);
    final range = ((max - min).abs() < 1 ? 1.0 : (max - min)).toDouble();
    return Column(
      children: [
        SizedBox(
          height: altura - 24,
          child: CustomPaint(
            size: Size(double.infinity, altura - 24),
            painter: _LinhaPainter(valores: valores, min: min, max: max, range: range),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(rotulos.first, style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
            Text(rotulos.last, style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$rotuloValor ${min.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
            Text('$rotuloValor ${max.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
          ],
        ),
      ],
    );
  }
}

class _LinhaPainter extends CustomPainter {
  final List<double> valores;
  final double min;
  final double max;
  final double range;
  _LinhaPainter({required List<double> valores, required this.min, required this.max, required this.range})
      : valores = List<double>.from(valores);

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFF0F766E)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final ponto = Paint()
      ..color = const Color(0xFF0F766E)
      ..style = PaintingStyle.fill;
    final dx = size.width / (valores.length - 1);
    for (var i = 0; i < valores.length - 1; i++) {
      final x1 = i * dx;
      final y1 = size.height - ((valores[i] - min) / range) * size.height;
      final x2 = (i + 1) * dx;
      final y2 = size.height - ((valores[i + 1] - min) / range) * size.height;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
    for (var i = 0; i < valores.length; i++) {
      final x = i * dx;
      final y = size.height - ((valores[i] - min) / range) * size.height;
      canvas.drawCircle(Offset(x, y), 3, ponto);
    }
  }

  @override
  bool shouldRepaint(covariant _LinhaPainter old) =>
      old.valores != valores || old.min != min || old.max != max;
}
