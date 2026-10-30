import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'finance.dart';
import 'store.dart';
import 'theme.dart';
import 'grafico_linha.dart';

/// Relatório mensal (R3 §6.10).
/// Todos os totais derivam dos mesmos lançamentos da aplicação; transferências
/// entre caixinhas não entram como receita nem despesa (R1 §8.8).
class RelatorioMensalScreen extends StatefulWidget {
  final FinanceStore store;
  const RelatorioMensalScreen({super.key, required this.store});

  @override
  State<RelatorioMensalScreen> createState() => _RelatorioMensalScreenState();
}

class _RelatorioMensalScreenState extends State<RelatorioMensalScreen> {
  DateTime _mes = DateTime.now();
  Map<String, Object?>? resumo;
  bool busy = false;

  String get _de => '${_mes.year}-${_mes.month.toString().padLeft(2, '0')}-01';
  String get _ate {
    final ultimoDia = DateTime(_mes.year, _mes.month + 1, 0).day;
    return '${_mes.year}-${_mes.month.toString().padLeft(2, '0')}-${ultimoDia.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => busy = true);
    resumo = await widget.store.resumoPeriodo(_de, _ate);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _exportarCsv() async {
    final csv = await widget.store.exportarCsvLancamentos(de: _de, ate: _ate);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/metric-relatorio-${_mes.year}${_mes.month.toString().padLeft(2, '0')}.csv',
    );
    await file.writeAsString(csv);
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Exportar do Metric - ${_mes.month}/${_mes.year}',
      ),
    );
  }

  Map<String, int> _mapa(Object? valor) {
    final mapa =
        (valor as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return mapa.map((key, value) => MapEntry(key, (value as num).toInt()));
  }

  Iterable<MapEntry<String, int>> get _categoriasOrdenadas {
    final r = resumo;
    if (r == null) return const <MapEntry<String, int>>[];
    final essenciais = _mapa(r['essenciais']);
    final naoEssenciais = _mapa(r['naoEssenciais']);
    final todas = <String, int>{...essenciais, ...naoEssenciais};
    final entries = todas.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  int get _maiorCategoria {
    final maior = _categoriasOrdenadas.isEmpty
        ? 0
        : _categoriasOrdenadas.first.value;
    return maior == 0 ? 1 : maior;
  }

  int get _receitas => resumo == null ? 0 : (resumo!['receitas'] as int);
  int get _gastos => resumo == null ? 0 : (resumo!['gastos'] as int);

  @override
  Widget build(BuildContext context) {
    final essenciais = _mapa(resumo?['essenciais']);
    final naoEssenciais = _mapa(resumo?['naoEssenciais']);
    final totalEssenciais = essenciais.values.fold<int>(0, (a, b) => a + b);
    final totalNaoEssenciais = naoEssenciais.values.fold<int>(
      0,
      (a, b) => a + b,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Relatório mensal')),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.calendar_month),
                      onPressed: () async {
                        final escolhido = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          initialDate: _mes,
                          helpText: 'Escolha o mês',
                        );
                        if (escolhido != null && mounted)
                          setState(
                            () => _mes = DateTime(
                              escolhido.year,
                              escolhido.month,
                              1,
                            ),
                          );
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_mes.month.toString().padLeft(2, '0')}/${_mes.year}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _exportarCsv,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Exportar CSV'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _cardResumo(
                  'Receitas do mês',
                  money(_receitas),
                  kPositivo,
                  'Soma das rendas registradas no período (valores informados).',
                ),
                const SizedBox(height: 12),
                _cardResumo(
                  'Gastos do mês',
                  money(_gastos),
                  kNegativo,
                  'Soma dos lançamentos de gasto no período. Transferências entre caixinhas não entram.',
                ),
                const SizedBox(height: 12),
                _cardResumo(
                  'Saldo do período',
                  money(_receitas - _gastos),
                  (_receitas - _gastos) >= 0 ? kPositivo : kNegativo,
                  'Receitas menos gastos. Saldo negativo não é erro: avisa que o mês consumiu reservas.',
                ),
                const SizedBox(height: 20),
                const Text(
                  'Gasto por categoria',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_categoriasOrdenadas.isEmpty)
                  const Text(
                    'Sem gastos categorizados no período.',
                    style: TextStyle(color: kTextoSecundario),
                  )
                else
                  ..._categoriasOrdenadas.map((e) {
                    final essencial = essenciais.containsKey(e.key);
                    return _barraLinha(
                      e.key,
                      e.value,
                      essencial ? kPositivo : kTextoSecundario,
                    );
                  }),
                const SizedBox(height: 20),
                const Text(
                  'Essencial × não essencial',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _barraLinha('Essencial', totalEssenciais, kPositivo),
                const SizedBox(height: 8),
                _barraLinha(
                  'Não essencial',
                  totalNaoEssenciais,
                  kTextoSecundario,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Evolução do saldo no mês',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, Object?>>>(
                  future: widget.store.saldoEvolucao(_de, _ate),
                  builder: (ctx, snap) {
                    if (!snap.hasData)
                      return const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    final dados = snap.data!;
                    if (dados.isEmpty)
                      return const Text('Sem dados para traçar a evolução.');
                    return GraficoLinha(
                      valores: dados
                          .map((e) => (e['saldoTotal'] as int).toDouble())
                          .toList(),
                      rotulos: [
                        dados.first['mes'] as String,
                        dados.last['mes'] as String,
                      ],
                      rotuloValor: 'R\$',
                      altura: 180,
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Como ler os totais',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                _legenda(
                  'Receitas',
                  'Rendas registradas no mês, com o valor e a data do fato.',
                ),
                _legenda(
                  'Gastos',
                  'Lançamentos de despesa no mês. Transferências entre caixinhas são ignoradas (não são receita nem despesa).',
                ),
                _legenda(
                  'Saldo do período',
                  'Receitas menos gastos. Pode ser negativo; não bloqueia nada.',
                ),
              ],
            ),
    );
  }

  Widget _cardResumo(String titulo, String valor, Color cor, String definicao) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontSize: 13, color: kTextoSecundario),
            ),
            const SizedBox(height: 6),
            Text(
              valor,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: cor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              definicao,
              style: const TextStyle(
                fontSize: 12,
                color: kTextoSecundario,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraLinha(String rotulo, int valor, Color cor) {
    final largura = (_maiorCategoria > 0 ? valor / _maiorCategoria : 0.0).clamp(
      0.0,
      1.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(rotulo, style: const TextStyle(fontSize: 13)),
            ),
            Text(
              money(valor),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(height: 10, color: const Color(0xFFE5E7EB)),
            FractionallySizedBox(
              widthFactor: largura,
              alignment: Alignment.centerLeft,
              child: Container(height: 10, color: cor),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legenda(String termo, String definicao) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          text: '$termo: ',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: kTextoPrincipal,
            fontSize: 13,
          ),
          children: [
            TextSpan(
              text: definicao,
              style: const TextStyle(color: kTextoSecundario, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
