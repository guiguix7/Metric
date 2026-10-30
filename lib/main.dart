import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'finance.dart';
import 'store.dart';
import 'theme.dart';
import 'onboarding.dart';
import 'pin_screen.dart';
import 'caixa_detalhe.dart';
import 'recorrencias_screen.dart';
import 'relatorio_mensal.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
  runApp(const MetricApp());
}

class MetricApp extends StatefulWidget {
  const MetricApp({super.key});
  @override
  State<MetricApp> createState() => _MetricAppState();
}

class _MetricAppState extends State<MetricApp> with WidgetsBindingObserver {
  final store = SqfliteFinanceStore();
  bool ready = false;
  String? error;
  ThemeMode mode = ThemeMode.system;
  bool emOnboarding = true;
  bool biometriaDisponivel = false;
  bool trancado = false;
  DateTime? _pausadoEm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (!mounted || !ready) return;
    if (state == AppLifecycleState.paused) {
      _pausadoEm = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _pausadoEm = null;
      await _avaliarTrancado();
    }
  }

  Future<void> _init() async {
    try {
      await store.open();
      final tema = await store.setting('tema');
      final inic = await store.initialized;
      final bio = !kIsWeb && await LocalAuthentication().canCheckBiometrics;
      if (!mounted) return;
      setState(() {
        mode = tema == 'dark'
            ? ThemeMode.dark
            : tema == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
        emOnboarding = !inic;
        biometriaDisponivel = bio;
        ready = true;
      });
      await _avaliarTrancado();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  /// Tranca o acesso se o app ficou em segundo plano além do limite configurado.
  Future<void> _avaliarTrancado() async {
    final temPin = await store.pinStored() != null;
    if (!temPin) {
      setState(() => trancado = false);
      return;
    }
    final limiteMin =
        int.tryParse(
          await store.setting('bloqueio_automatico_minutos') ?? '5',
        ) ??
        5;
    final passou =
        _pausadoEm != null &&
        DateTime.now().difference(_pausadoEm!) >= Duration(minutes: limiteMin);
    if (!mounted) return;
    setState(() => trancado = passou);
  }

  Future<void> _desbloquear(bool ok) async {
    if (!mounted) return;
    setState(() => trancado = !ok);
  }

  @override
  Widget build(BuildContext context) {
    Widget corpo;
    if (error != null) {
      corpo = Scaffold(
        body: Center(child: Text('Erro ao abrir dados: $error')),
      );
    } else if (!ready) {
      corpo = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (emOnboarding) {
      corpo = Onboarding(
        store: store,
        onConcluir: () {
          if (!mounted) return;
          setState(() => emOnboarding = false);
        },
      );
    } else if (trancado) {
      corpo = PinScreen(
        mode: 'desbloquear',
        store: store,
        biometriaDisponivel: biometriaDisponivel,
      );
    } else {
      corpo = FinanceHome(
        store: store,
        mode: mode,
        onTheme: (m) async {
          await store.setSetting('tema', m.name);
          setState(() => mode = m);
        },
        desbloquear: _desbloquear,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Metric',
      themeMode: mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        scaffoldBackgroundColor: kFundo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: corpo,
    );
  }
}

Future<bool> localAuthDisponivel() async {
  if (kIsWeb) return false;
  try {
    return await LocalAuthentication().canCheckBiometrics;
  } catch (_) {
    return false;
  }
}

class FinanceHome extends StatefulWidget {
  final FinanceStore store;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<bool> desbloquear;
  const FinanceHome({
    super.key,
    required this.store,
    required this.mode,
    required this.onTheme,
    required this.desbloquear,
  });

  @override
  State<FinanceHome> createState() => _FinanceHomeState();
}

class _FinanceHomeState extends State<FinanceHome> {
  int tab = 0;
  Map<String, int> sums = {for (final id in boxIds) id: 0};
  List<Map<String, Object?>> entries = [], categories = [];
  List<int> rates = List.of(defaultRates);
  bool busy = true;
  String? error;
  String? filtroBox;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final a = await widget.store.getBalances();
      final b = await widget.store.movements(boxId: filtroBox);
      final c = await widget.store.categories();
      final r = await widget.store.rates();
      if (mounted)
        setState(() {
          sums = a;
          entries = b;
          categories = c;
          rates = r;
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

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> perform(Future<void> Function() f) async {
    try {
      await f();
      await refresh();
      if (mounted) message('Salvo no aparelho.');
    } catch (e) {
      if (mounted) message('Não foi possível salvar: $e');
    }
  }

  Future<void> income() async {
    final value = TextEditingController(), source = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar renda'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: value,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Valor (ex.: 3.000,00)',
                prefixText: 'R\$ ',
              ),
            ),
            TextField(
              controller: source,
              decoration: const InputDecoration(labelText: 'Fonte (opcional)'),
            ),
            const SizedBox(height: 12),
            const Text('Prévia da divisão atual:'),
            ...List.generate(
              5,
              (i) => Text(
                '${boxNames[i]}: ${(rates[i] / 100).toStringAsFixed(2)}%',
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
            onPressed: () {
              try {
                final cents = parseMoney(value.text);
                final allocation = distribute(cents, rates);
                Navigator.pop(ctx);
                _confirmIncome(cents, source.text, allocation);
              } catch (e) {
                message('$e');
              }
            },
            child: const Text('Ver divisão'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmIncome(
    int cents,
    String source,
    Allocation allocation,
  ) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dividir ${money(cents)}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(
              5,
              (i) => ListTile(
                dense: true,
                title: Text(boxNames[i]),
                trailing: Text(money(allocation.amounts[boxIds[i]]!)),
              ),
            ),
            if (allocation.unallocated > 0)
              ListTile(
                title: const Text('Não alocado'),
                trailing: Text(money(allocation.unallocated)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              perform(
                () => widget.store.addIncome(cents, widget.store.today, source),
              );
            },
            child: const Text('Confirmar e dividir'),
          ),
        ],
      ),
    );
  }

  Future<void> expense() async {
    if (categories.isEmpty) {
      message('Crie uma categoria antes de registrar um gasto.');
      return;
    }
    final value = TextEditingController(), note = TextEditingController();
    int selected = categories.first['id'] as int;
    String payment = 'Pix';
    String? override;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final c = categories.firstWhere((c) => c['id'] == selected);
          final sugerido = c['essential'] == 1 ? 'essenciais' : 'livre';
          return AlertDialog(
            title: const Text('Registrar gasto'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: value,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Valor (ex.: 42,90)',
                      prefixText: 'R\$ ',
                    ),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['id'] as int,
                            child: Text(
                              '${c['name']} (${c['essential'] == 1 ? 'essencial' : 'não essencial'})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setLocal(() {
                      selected = v!;
                      override = null;
                    }),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: payment,
                    decoration: const InputDecoration(
                      labelText: 'Forma de pagamento',
                    ),
                    items: ['Pix', 'Débito', 'Crédito', 'Dinheiro', 'Boleto']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setLocal(() => payment = v!),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: override ?? sugerido,
                    decoration: const InputDecoration(
                      labelText: 'Debitar da caixinha',
                    ),
                    items: List.generate(
                      5,
                      (i) => DropdownMenuItem(
                        value: boxIds[i],
                        child: Text(boxNames[i]),
                      ),
                    ),
                    onChanged: (v) => setLocal(() => override = v),
                  ),
                  TextField(
                    controller: note,
                    decoration: const InputDecoration(
                      labelText: 'Observação (opcional)',
                    ),
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
                onPressed: () {
                  try {
                    final cents = parseMoney(value.text);
                    Navigator.pop(ctx);
                    perform(
                      () => widget.store.addExpense(
                        cents,
                        widget.store.today,
                        selected,
                        override ?? sugerido,
                        payment,
                        note.text,
                      ),
                    );
                  } catch (e) {
                    message('$e');
                  }
                },
                child: const Text('Salvar gasto'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> transferir() async {
    final amount = TextEditingController(), reason = TextEditingController();
    String from = 'livre', to = 'reserva';
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, local) => AlertDialog(
          title: const Text('Transferir entre caixinhas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor em R\$'),
              ),
              DropdownButtonFormField<String>(
                initialValue: from,
                decoration: const InputDecoration(labelText: 'Origem'),
                items: List.generate(
                  5,
                  (i) => DropdownMenuItem(
                    value: boxIds[i],
                    child: Text(boxNames[i]),
                  ),
                ),
                onChanged: (v) => local(() => from = v!),
              ),
              DropdownButtonFormField<String>(
                initialValue: to,
                decoration: const InputDecoration(labelText: 'Destino'),
                items: List.generate(
                  5,
                  (i) => DropdownMenuItem(
                    value: boxIds[i],
                    child: Text(boxNames[i]),
                  ),
                ),
                onChanged: (v) => local(() => to = v!),
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
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
              onPressed: () {
                try {
                  final cents = parseMoney(amount.text);
                  if (from == to)
                    throw ArgumentError('Escolha caixinhas diferentes');
                  Navigator.pop(ctx);
                  perform(
                    () => widget.store.transfer(cents, from, to, reason.text),
                  );
                } catch (e) {
                  message('$e');
                }
              },
              child: const Text('Transferir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> editarRates() async {
    final fields = List.generate(
      5,
      (i) => TextEditingController(
        text: (rates[i] / 100).toStringAsFixed(2).replaceAll('.', ','),
      ),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Distribuição das próximas rendas'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...List.generate(
                5,
                (i) => TextField(
                  controller: fields[i],
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '${boxNames[i]} (%)'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A soma não pode ultrapassar 100%. O restante fica não alocado.',
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
            onPressed: () {
              try {
                final values = fields.map((f) {
                  final texto = f.text.replaceAll(',', '.');
                  final match = RegExp(r'^\d+(?:\.\d{1,2})?$');
                  if (!match.hasMatch(texto))
                    throw const FormatException('Percentual inválido');
                  final parts = texto.split('.');
                  return int.parse(parts[0]) * 100 +
                      (parts.length > 1
                          ? int.parse(parts[1].padRight(2, '0'))
                          : 0);
                }).toList();
                if (values.fold<int>(0, (a, b) => a + b) > 10000)
                  throw ArgumentError('Total maior que 100%');
                Navigator.pop(ctx);
                perform(() => widget.store.saveRates(values));
              } catch (e) {
                message('$e');
              }
            },
            child: const Text('Salvar percentuais'),
          ),
        ],
      ),
    );
  }

  Future<void> backup() async {
    try {
      final json = jsonEncode(await widget.store.snapshot());
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/metric-backup-${widget.store.today}.json');
      await file.writeAsString(json, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Backup Metric. Guarde este arquivo em local seguro: contém dados financeiros legíveis.',
        ),
      );
    } catch (e) {
      message('Erro ao exportar: $e');
    }
  }

  Future<void> importarBackup() async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (selection == null || selection.files.single.path == null) return;
      final content = await File(selection.files.single.path!).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Substituir todos os dados?'),
          content: Text(
            'Backup versão ${data['version']}. ${((data['movements'] as List?) ?? []).length} movimentos. '
            'Esta ação substitui os registros atuais e não pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Substituir'),
            ),
          ],
        ),
      );
      if (confirm == true) await perform(() => widget.store.restore(data));
    } catch (e) {
      message('Importação não realizada: $e');
    }
  }

  Future<void> novaCategoria() async {
    final name = TextEditingController();
    bool essential = true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, local) => AlertDialog(
          title: const Text('Nova categoria'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              SwitchListTile(
                title: const Text('Essencial'),
                value: essential,
                onChanged: (v) => local(() => essential = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                perform(() => widget.store.addCategory(name.text, essential));
              },
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget card(
    String titulo,
    String valor, {
    String? nota,
    String? id,
    VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: id != null
            ? Icon(boxIcon(id), color: boxColor(id))
            : const Icon(Icons.savings_outlined),
        title: Text(titulo),
        subtitle: nota == null ? null : Text(nota),
        trailing: Text(
          valor,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Widget homeView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Quanto você pode gastar?', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 8),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Caixinha Livre · saldo calculado',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  money(sums['livre']!),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'O saldo acumula entre meses e não é o saldo do banco.',
                  style: TextStyle(fontSize: 13, color: kTextoSecundario),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Suas cinco caixinhas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        ...List.generate(
          5,
          (i) => card(
            boxNames[i],
            money(sums[boxIds[i]]!),
            nota:
                '${(rates[i] / 100).toStringAsFixed(2)}% de cada nova renda${sums[boxIds[i]]! < 0 ? ' · Saldo negativo' : ''}',
            id: boxIds[i],
            onTap: () => setState(() => tab = 3),
          ),
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Comece registrando uma renda para distribuir o dinheiro entre suas caixinhas.',
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: income,
          icon: const Icon(Icons.add),
          label: const Text('Registrar renda'),
        ),
        OutlinedButton.icon(
          onPressed: expense,
          icon: const Icon(Icons.remove),
          label: const Text('Registrar gasto'),
        ),
      ],
    );
  }

  Widget entriesView() {
    final filtradas = entries.where((e) {
      if (filtroBox == null) return true;
      return e['box_id'] == filtroBox;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'Extrato completo',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('Todas'),
              selected: filtroBox == null,
              onSelected: (_) => setState(() => filtroBox = null),
            ),
            ...List.generate(5, (i) {
              final id = boxIds[i];
              return FilterChip(
                label: Text(boxNames[i]),
                selected: filtroBox == id,
                onSelected: (_) => setState(() => filtroBox = id),
              );
            }),
          ],
        ),
        const SizedBox(height: 12),
        if (filtradas.isEmpty)
          const ListTile(title: Text('Nenhum lançamento encontrado.')),
        ...filtradas.map((e) {
          final i = boxIds.indexOf(e['box_id'] as String);
          final valor = e['amount'] as int;
          final id = e['id'] as int;
          return ListTile(
            leading: Icon(
              valor < 0 ? Icons.arrow_upward : Icons.arrow_downward,
              color: valor < 0 ? kNegativo : kPositivo,
            ),
            title: Text('${e['type']} · ${boxNames[i]}'),
            subtitle: Text(
              '${e['date']} · ${e['category_name'] ?? e['note'] ?? 'Sem categoria'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  money(valor),
                  style: TextStyle(color: valor < 0 ? kNegativo : null),
                ),
                if (valor < 0 && e['type'] == 'gasto')
                  IconButton(
                    icon: const Icon(Icons.restore, size: 20),
                    tooltip: 'Estornar',
                    onPressed: () => _estornarLancamento(id),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _estornarLancamento(int id) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estornar lançamento?'),
        content: const Text(
          'O valor volta para a caixinha de origem. Não pode ser desfeito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Estornar'),
          ),
        ],
      ),
    );
    if (confirme == true) {
      await perform(() => widget.store.estornar(id, 'Estorno via extrato'));
    }
  }

  Widget caixasView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Saldos acumulados',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        ...List.generate(
          5,
          (i) => card(
            boxNames[i],
            money(sums[boxIds[i]]!),
            nota: 'Saldo calculado pelo extrato',
            id: boxIds[i],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CaixaDetalhe(store: widget.store, caixaId: boxIds[i]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: transferir,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Transferir entre caixinhas'),
        ),
      ],
    );
  }

  Widget maisView() {
    return ListView(
      children: [
        ListTile(
          title: const Text('Distribuição da renda'),
          subtitle: const Text('Ajustar percentuais para futuras rendas'),
          leading: const Icon(Icons.tune),
          onTap: editarRates,
        ),
        ListTile(
          title: const Text('Recorrências e assinaturas'),
          subtitle: const Text(
            'Criar, pausar e acompanhar cobranças recorrentes',
          ),
          leading: const Icon(Icons.repeat),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecorrenciasScreen(store: widget.store),
            ),
          ),
        ),
        ListTile(
          title: const Text('Relatório mensal'),
          subtitle: const Text(
            'Receitas, gastos, categorias e evolução dos saldos',
          ),
          leading: const Icon(Icons.assessment),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RelatorioMensalScreen(store: widget.store),
            ),
          ),
        ),
        ListTile(
          title: const Text('Categorias'),
          leading: const Icon(Icons.category_outlined),
          onTap: novaCategoria,
        ),
        const Divider(),
        ListTile(
          title: const Text('Exportar backup'),
          subtitle: const Text('JSON sem criptografia: armazene com cuidado'),
          leading: const Icon(Icons.upload_file),
          onTap: backup,
        ),
        ListTile(
          title: const Text('Importar backup'),
          subtitle: const Text('Substituir todos os dados após confirmação'),
          leading: const Icon(Icons.download),
          onTap: importarBackup,
        ),
        const Divider(),
        ListTile(
          title: const Text('Tema'),
          leading: const Icon(Icons.palette_outlined),
          trailing: DropdownButton<ThemeMode>(
            value: widget.mode,
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('Sistema')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Claro')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Escuro')),
            ],
            onChanged: (v) {
              if (v != null) widget.onTheme(v);
            },
          ),
        ),
        ListTile(
          title: const Text('Bloqueio automático'),
          subtitle: Text(
            'Trancar após ${_limiteBloqueio()} min em segundo plano',
          ),
          leading: const Icon(Icons.lock),
          onTap: _editarBloqueio,
        ),
        const Divider(),
        ListTile(
          title: const Text('Privacidade'),
          subtitle: const Text(
            'Funciona offline e sem conta. As caixinhas não movimentam dinheiro real.',
          ),
          leading: const Icon(Icons.privacy_tip),
        ),
      ],
    );
  }

  Future<int> _limiteBloqueio() async {
    final v = await widget.store.setting('bloqueio_automatico_minutos');
    return int.tryParse(v ?? '5') ?? 5;
  }

  Future<void> _editarBloqueio() async {
    if (!mounted) return;
    final ctx = context;
    final limite = await _limiteBloqueio();
    if (!mounted) return;
    final controller = TextEditingController(text: limite.toString());
    final ok = await showDialog<int>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Bloqueio automático'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutos em segundo plano',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != null && ok > 0 && mounted) {
      await widget.store.setSetting(
        'bloqueio_automatico_minutos',
        ok.toString(),
      );
      if (mounted) message('Bloqueio atualizado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metric'),
        actions: [
          IconButton(
            onPressed: refresh,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text('Erro: $error'))
          : [
              homeView(),
              entriesView(),
              const Center(child: Text('Use o botão + para registrar.')),
              caixasView(),
              maisView(),
            ][tab],
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          builder: (ctx) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Registrar renda'),
                  onTap: () {
                    Navigator.pop(ctx);
                    income();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: const Text('Registrar gasto'),
                  onTap: () {
                    Navigator.pop(ctx);
                    expense();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('Transferir'),
                  onTap: () {
                    Navigator.pop(ctx);
                    transferir();
                  },
                ),
              ],
            ),
          ),
        ),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) {
          if (i == 2) {
            showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: Wrap(
                  children: [
                    ListTile(
                      title: const Text('Renda'),
                      onTap: () {
                        Navigator.pop(ctx);
                        income();
                      },
                    ),
                    ListTile(
                      title: const Text('Gasto'),
                      onTap: () {
                        Navigator.pop(ctx);
                        expense();
                      },
                    ),
                  ],
                ),
              ),
            );
          } else {
            setState(() => tab = i);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Lançamentos',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            label: 'Registrar',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            label: 'Caixinhas',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Mais'),
        ],
      ),
    );
  }
}
