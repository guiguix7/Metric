import 'package:flutter/material.dart';

import 'finance.dart';
import 'store.dart';
import 'theme.dart';

/// Recorrências e assinaturas (R3 §6.8).
/// O lançamento é criado apenas quando a data de cobrança chega
/// (gerarOcorrenciasVencidas), ou seja, confirmado quando ocorre.
class RecorrenciasScreen extends StatefulWidget {
  final FinanceStore store;
  const RecorrenciasScreen({super.key, required this.store});

  @override
  State<RecorrenciasScreen> createState() => _RecorrenciasScreenState();
}

class _RecorrenciasScreenState extends State<RecorrenciasScreen> {
  List<Map<String, Object?>> lista = [];
  Map<String, double> mensal = {};
  bool busy = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      await widget.store.gerarOcorrenciasVencidas();
      final l = await widget.store.recorrencias();
      final m = await widget.store.equivalenciaMensalRecorrencias();
      if (mounted)
        setState(() {
          lista = l;
          mensal = m;
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

  Future<void> _criar() async {
    final descricao = TextEditingController();
    final valor = TextEditingController();
    String periodicidade = 'mensal';
    String proxima = widget.store.today;
    String box = 'livre';
    int? categoria;
    final cats = await widget.store.categories();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Nova recorrência'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descricao,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                  ),
                  TextField(
                    controller: valor,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor (ex.: 49,90)',
                      prefixText: 'R\$ ',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    value: periodicidade,
                    decoration: const InputDecoration(
                      labelText: 'Periodicidade',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'mensal', child: Text('Mensal')),
                      DropdownMenuItem(value: 'anual', child: Text('Anual')),
                    ],
                    onChanged: (v) => setLocal(() => periodicidade = v!),
                  ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Próxima cobrança (dd/mm/aaaa)',
                    ),
                    onChanged: (v) => proxima = v,
                  ),
                  DropdownButtonFormField<String>(
                    value: box,
                    decoration: const InputDecoration(labelText: 'Caixinha'),
                    items: List.generate(
                      5,
                      (i) => DropdownMenuItem(
                        value: boxIds[i],
                        child: Text(boxNames[i]),
                      ),
                    ),
                    onChanged: (v) => setLocal(() => box = v!),
                  ),
                  DropdownButtonFormField<int?>(
                    value: categoria,
                    decoration: const InputDecoration(
                      labelText: 'Categoria (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Sem categoria'),
                      ),
                      ...cats.map(
                        (c) => DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text(
                            '${c['name']} (${c['essential'] == 1 ? 'essencial' : 'não essencial'})',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => categoria = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await widget.store.saveRecorrencia(
                      descricao: descricao.text,
                      valorCents: parseMoney(valor.text),
                      periodicidade: periodicidade,
                      proximaData: proxima,
                      boxId: box,
                      categoryId: categoria,
                    );
                    Navigator.pop(ctx);
                    await _carregar();
                  } catch (e) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
                child: const Text('Criar'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalPorMes = mensal.values.fold<double>(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(title: const Text('Recorrências e assinaturas')),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text('Erro: $error'))
          : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total mensal equivalente',
                          style: TextStyle(
                            fontSize: 14,
                            color: kTextoSecundario,
                          ),
                        ),
                        Text(
                          money(totalPorMes.round()),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          children: mensal.entries
                              .map(
                                (e) => Chip(
                                  label: Text(
                                    '${boxNames[boxIds.indexOf(e.key)]} ${money(e.value.round()).replaceAll('R\$ ', '')}',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                if (lista.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('Nenhuma recorrência cadastrada.'),
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final r in lista)
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: Icon(
                                boxIcon(r['box_id'] as String),
                                color: boxColor(r['box_id'] as String),
                              ),
                              title: Text(r['descricao'] as String),
                              subtitle: Text(
                                '${money(r['valor'] as int).replaceFirst('R\$ ', '')} · ${r['periodicidade']} · próxima: ${r['proxima_data']}',
                              ),
                              trailing: Switch(
                                value: (r['pausada'] as int) == 1,
                                onChanged: (v) async {
                                  await widget.store.setRecorrenciaPausada(
                                    r['id'] as int,
                                    v,
                                  );
                                  await _carregar();
                                },
                              ),
                              onTap: () async {
                                final confirme = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Encerrar recorrência?'),
                                    content: Text(
                                      'Desativar "${r['descricao']}"? Lançamentos já criados permanecem.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Não'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Encerrar'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirme == true) {
                                  await widget.store.deleteRecorrencia(
                                    r['id'] as int,
                                  );
                                  await _carregar();
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _criar,
        child: const Icon(Icons.add),
      ),
    );
  }
}
