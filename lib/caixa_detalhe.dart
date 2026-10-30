import 'package:flutter/material.dart';

import 'finance.dart';
import 'store.dart';
import 'theme.dart';
import 'grafico_linha.dart';

/// Detalhe de uma caixinha (R3 §6.6): saldo, evolução, extrato próprio,
/// transferência para outra caixinha e ajuste de saldo com justificativa.
class CaixaDetalhe extends StatefulWidget {
  final FinanceStore store;
  final String caixaId;
  const CaixaDetalhe({super.key, required this.store, required this.caixaId});

  @override
  State<CaixaDetalhe> createState() => _CaixaDetalheState();
}

class _CaixaDetalheState extends State<CaixaDetalhe> {
  Map<String, int> sums = {};
  List<Map<String, Object?>> extrato = [];
  bool busy = true;
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final a = await widget.store.getBalances();
      final b = await widget.store.movements(boxId: widget.caixaId);
      if (mounted)
        setState(() {
          sums = a;
          extrato = b;
          busy = false;
          error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          busy = false;
        });
    }
  }

  List<Map<String, Object?>> _evolucaoMensal() {
    final agora = DateTime.now();
    final de = '${agora.year}-${agora.month.toString().padLeft(2, '0')}-01';
    final ate = DateTime(
      agora.year,
      agora.month + 1,
      0,
    ).toIso8601String().substring(0, 10);
    final ordenados = List<Map<String, Object?>>.from(extrato)
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    int running = 0;
    // saldo inicial do período
    for (final m in ordenados) {
      if ((m['date'] as String).compareTo(de) < 0) {
        running += (m['amount'] as int);
      }
    }
    final porMes = <String, int>{};
    for (final m in ordenados) {
      final date = m['date'] as String;
      if (date.compareTo(de) < 0 || date.compareTo(ate) > 0) continue;
      running += (m['amount'] as int);
      final mes = date.substring(0, 7);
      porMes[mes] = running;
    }
    if (porMes.isEmpty) return [];
    final chaves = porMes.keys.toList()..sort();
    return chaves.map((mes) => {'mes': mes, 'saldo': porMes[mes]!}).toList();
  }

  Future<void> _transferir() async {
    final destinos = boxIds.where((id) => id != widget.caixaId).toList();
    String para = destinos.first;
    final valorTexto = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Transferir saída de ${boxNames[boxIds.indexOf(widget.caixaId)]}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valorTexto,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: para,
              decoration: const InputDecoration(labelText: 'Destino'),
              items: destinos
                  .map(
                    (id) => DropdownMenuItem(
                      value: id,
                      child: Text(boxNames[boxIds.indexOf(id)]),
                    ),
                  )
                  .toList(),
              onChanged: (v) => para = v!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final cents = parseMoney(valorTexto.text);
                Navigator.pop(ctx);
                await widget.store.transfer(
                  cents,
                  widget.caixaId,
                  para,
                  'Transferência do extrato',
                );
                await refresh();
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Transferir'),
          ),
        ],
      ),
    );
  }

  Future<void> _ajustar() async {
    final valorTexto = TextEditingController();
    final justificativa = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajustar saldo da caixinha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valorTexto,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor (positivo ou negativo)',
                prefixText: 'R\$ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: justificativa,
              decoration: const InputDecoration(
                labelText: 'Justificativa (obrigatória)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final cents = parseMoney(valorTexto.text);
                if (justificativa.text.trim().isEmpty)
                  throw ArgumentError('Informe a justificativa');
                Navigator.pop(ctx);
                await widget.store.adjust(
                  cents,
                  widget.caixaId,
                  justificativa.text,
                );
                await refresh();
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('Ajustar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nome = boxNames[boxIds.indexOf(widget.caixaId)];
    final cor = boxColor(widget.caixaId);
    final saldo = sums[widget.caixaId] ?? 0;
    final evolucao = _evolucaoMensal();

    return Scaffold(
      appBar: AppBar(
        title: Text(nome),
        backgroundColor: cor.withValues(alpha: 0.9),
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text('Erro: $error'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Icon(boxIcon(widget.caixaId), color: cor, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nome,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Saldo calculado pelos lançamentos',
                            style: const TextStyle(
                              fontSize: 13,
                              color: kTextoSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(saldo),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: saldo < 0 ? kNegativo : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Evolução do saldo (mês)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (evolucao.isEmpty)
                  const Text(
                    'Não há lançamentos suficientes para traçar a evolução.',
                    style: TextStyle(color: kTextoSecundario),
                  )
                else
                  GraficoLinha(
                    valores: evolucao
                        .map((e) => (e['saldo'] as int).toDouble())
                        .toList(),
                    rotulos: [
                      evolucao.first['mes'] as String,
                      evolucao.last['mes'] as String,
                    ],
                    rotuloValor: 'R\$',
                    altura: 180,
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Extrato da caixinha',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (extrato.isEmpty)
                  const Center(child: Text('Sem lançamentos nesta caixinha.')),
                ...extrato.map((e) {
                  final valor = e['amount'] as int;
                  return ListTile(
                    leading: Icon(
                      valor < 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      color: valor < 0 ? kNegativo : kPositivo,
                    ),
                    title: Text('${e['type']} · ${e['date']}'),
                    subtitle: Text('${e['note'] ?? 'Sem observação'}'),
                    trailing: Text(
                      money(valor),
                      style: TextStyle(
                        color: valor < 0 ? kNegativo : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _transferir,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Transferir para outra caixinha'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _ajustar,
                        icon: const Icon(Icons.edit),
                        label: const Text('Ajustar saldo'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
