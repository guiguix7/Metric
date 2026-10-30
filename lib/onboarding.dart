import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'finance.dart';
import 'pin_screen.dart';
import 'store.dart';
import 'theme.dart';

/// Onboarding guiado (R3 §6.1).
/// Ao terminar, cadastra a primeira renda com a regra de divisão vigente,
/// grava o PIN e sinaliza que o onboarding foi concluído (R1 §7, PROD-007).
class Onboarding extends StatefulWidget {
  final FinanceStore store;
  /// Chamado quando o onboarding é concluído; o app deixa de mostrá-lo.
  final VoidCallback onConcluir;
  const Onboarding({super.key, required this.store, required this.onConcluir});

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final _page = PageController();
  int _indice = 0;
  bool _carregando = false;

  String? _rendaTexto;
  String? _fonte;
  List<int> _rates = List.of(defaultRates);
  final Map<String, int> _saldosIniciais = {};

  static const List<Map<String, Object>> _presets = [
    {'nome': 'Ponto de partida', 'rates': [5000, 3000, 1000, 500, 500]},
    {'nome': 'Necessidades altas', 'rates': [6000, 2000, 1000, 500, 500]},
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  bool get _ultimaPagina => _indice == 5;

  Future<void> _avancar() async {
    if (_indice < 5) {
      _page.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
    } else {
      await _concluir();
    }
  }

  Future<void> _concluir() async {
    if (_rendaTexto == null) return;
    final cents = parseMoney(_rendaTexto!);
    setState(() => _carregando = true);
    try {
      await widget.store.saveRates(_rates);
      await widget.store.addIncome(cents, widget.store.today, _fonte ?? '');
      for (final entry in _saldosIniciais.entries) {
        if (entry.value != 0) {
          await widget.store.adjust(entry.value, entry.key, 'Saldo inicial do onboarding');
        }
      }
      await widget.store.setInitialized();
      if (!mounted) return;
      widget.onConcluir();
    } catch (e) {
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível finalizar: $e')));
    }
  }

  Widget _step(String texto, {IconData? icone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(children: [
        if (icone != null) Icon(icone, size: 20, color: kDestaque),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 15, height: 1.4))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kFundo,
      appBar: AppBar(title: const Text('Começar a usar o Metric'), backgroundColor: kSuperficie, elevation: 0, foregroundColor: kTextoPrincipal),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: PageView(
          controller: _page,
          onPageChanged: (i) => setState(() => _indice = i),
          children: [
            // 1. Boas-vindas
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  const Text('Bem-vindo ao Metric', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('Organize sua renda em cinco caixinhas e saiba, a qualquer momento, quanto você realmente pode gastar.',
                      style: TextStyle(fontSize: 16, color: kTextoSecundario, height: 1.5)),
                  const SizedBox(height: 28),
                  _step('Seus dados ficam apenas neste aparelho. O app funciona offline e sem conta.', icone: Icons.lock_outline),
                  _step('Nenhuma informação financeira sai do aparelho sem que você exporte um backup.', icone: Icons.cloud_off_outlined),
                  _step('As caixinhas organizam seu dinheiro; elas não movimentam dinheiro real.', icone: Icons.account_balance_outlined),
                  const Spacer(),
                ],
              ),
            ),
            // 2. Renda mensal líquida
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quanto você recebe por mês?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Informe a renda líquida (o que entra no bolso após impostos).',
                      style: TextStyle(color: kTextoSecundario)),
                  const SizedBox(height: 20),
                  TextField(
                    autofocus: true,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Renda mensal líquida', prefixText: 'R\$ ', hintText: 'Ex.: 3.000,00'),
                    onChanged: (v) => _rendaTexto = v,
                  ),
                  const SizedBox(height: 8),
                  if (_previewTexto != null) Text(_previewTexto!, style: const TextStyle(color: kDestaque, fontWeight: FontWeight.w600)),
                  const Spacer(),
                ],
              ),
            ),
            // 3. Divisão
            _divisaoPage(),
            // 4. Saldos iniciais (opcional)
            _saldosIniciaisPage(),
            // 5. PIN
            _pinPage(),
            // 6. Resumo
            _resumoPage(),
          ],
        ),
      ),
      bottomNavigationBar: _ultimaPagina ? null : Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_indice > 0)
              TextButton(
                  onPressed: () {
                    _page.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
                  },
                  child: const Text('Voltar')),
            _botao(_ultimaPagina ? 'Começar a usar' : 'Continuar', onTap: _podeAvancar ? () { _avancar(); } : null),
          ],
        ),
      ),
    );
  }

  String? get _previewTexto {
    if (_rendaTexto == null || _rendaTexto!.isEmpty) return null;
    try { return 'Prévia: ${money(parseMoney(_rendaTexto!))} por mês.'; } catch (_) { return null; }
  }

  bool get _rendaValido {
    if (_rendaTexto == null || _rendaTexto!.isEmpty) return false;
    try { return parseMoney(_rendaTexto!) > 0; } catch (_) { return false; }
  }
  bool get _podeAvancar {
    if (!_ultimaPagina) return _indice != 1 || _rendaValido;
    return true;
  }

  Widget _botao(String texto, {VoidCallback? onTap}) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(backgroundColor: kDestaque, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
      child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  // ---------------------------------------------------------------- divisão

  Widget _divisaoPage() {
    final cents = _rendaValido ? parseMoney(_rendaTexto!) : 0;
    final aloc = _rendaValido ? distribute(cents, _rates) : null;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Como dividir cada renda?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Escolha os percentuais. A soma pode chegar a 100%; o restante fica como não alocado.',
              style: TextStyle(color: kTextoSecundario)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: _presets.map((p) {
              final rates = List<int>.from(p['rates'] as List);
              final jaSelecionado = _rates == rates;
              return FilterChip(
                label: Text('${p['nome']}  (${rates.map((r) => (r / 100).toStringAsFixed(0)).join('/')}%)'),
                selected: jaSelecionado,
                onSelected: (_) => setState(() => _rates = rates),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Text('Personalizar', style: TextStyle(fontWeight: FontWeight.bold, color: kTextoPrincipal)),
          ...List.generate(5, (i) => _percentualField(i, cents)),
          const SizedBox(height: 12),
          if (_rates.fold<int>(0, (a, b) => a + b) > 10000)
            const Text('A soma não pode ultrapassar 100%.', style: TextStyle(color: kNegativo)),
          const SizedBox(height: 10),
          if (aloc != null) ...[
            const Divider(),
            const SizedBox(height: 8),
            Text('Prévia com ${money(cents)}:', style: const TextStyle(fontWeight: FontWeight.w600)),
            ...List.generate(5, (i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Text(boxNames[i]),
                  const Spacer(),
                  Text(money(aloc.amounts[boxIds[i]]!), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]))),
            if (aloc.unallocated > 0) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Text('Não alocado', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(money(aloc.unallocated)),
              ]),
            ],
            ],
          const Spacer(),
        ],
      ),
    );
  }

  Widget _percentualField(int i, int cents) {
    final controller = TextEditingController(text: (_rates[i] / 100).toStringAsFixed(2).replaceAll('.', ','));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 110, child: Text(boxNames[i], style: const TextStyle(fontSize: 14))),
        SizedBox(width: 70, child: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          decoration: const InputDecoration(suffixText: '%', contentPadding: EdgeInsets.symmetric(horizontal: 8)),
          onChanged: (v) {
            final texto = v.replaceAll(',', '.');
            final valor = int.tryParse(texto) ?? 0;
            setState(() => _rates[i] = valor * 100);
          },
        )),
        if (cents > 0) ...[
          const SizedBox(width: 8),
          Text(money((cents * _rates[i] ~/ 10000)), style: const TextStyle(fontSize: 12, color: kTextoSecundario)),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- saldos iniciais

  Widget _saldosIniciaisPage() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saldos iniciais (opcional)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Se alguma caixinhas já tem dinheiro separado, informe aqui. Pode pular.',
              style: TextStyle(color: kTextoSecundario)),
          const SizedBox(height: 16),
          ...List.generate(5, (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(boxIcon(boxIds[i]), color: boxColor(boxIds[i]), size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(boxNames[i])),
                SizedBox(width: 90, child: TextField(
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(prefixText: 'R\$ ', contentPadding: EdgeInsets.symmetric(horizontal: 8)),
                  onChanged: (v) {
                    try { _saldosIniciais[boxIds[i]] = parseMoney(v); } catch (_) { _saldosIniciais.remove(boxIds[i]); }
                  },
                )),
              ]))),
          const Spacer(),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _avancar, child: const Text('Pular'))),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- PIN

  Widget _pinPage() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Segurança', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Crie um PIN para proteger o acesso ao Metric. Ele é exigido sempre que o app for aberto.',
              style: TextStyle(color: kTextoSecundario)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              if (!mounted) return;
              final ctx = context;
              final biometria = !kIsWeb && await LocalAuthentication().canCheckBiometrics;
              if (!mounted) return;
              final pin = await Navigator.of(ctx).push<String>(
                MaterialPageRoute(builder: (_) => PinScreen(mode: 'criar', store: widget.store, biometriaDisponivel: biometria)),
              );
              if (pin != null && mounted) {
                setState(() {}); // PIN gravado na loja pela própria tela
              }
            },
            icon: const Icon(Icons.lock),
            label: const Text('Criar PIN de acesso'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _avancar(),
            child: const Text('Pular por agora (recomendado criar o PIN)'),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- resumo

  Widget _resumoPage() {
    final cents = _rendaValido ? parseMoney(_rendaTexto!) : 0;
    final aloc = cents > 0 ? distribute(cents, _rates) : null;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resumo antes de começar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Renda: ${money(cents)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ...List.generate(5, (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(children: [
                Text(boxNames[i]),
                const Spacer(),
                Text(aloc != null ? money(aloc.amounts[boxIds[i]]!) : '-'),
              ]))),
          if (aloc != null && aloc.unallocated > 0)
            Row(children: [const Text('Não alocado'), const Spacer(), Text(money(aloc.unallocated))]),
          const Spacer(),
          Align(alignment: Alignment.centerRight, child: _botao('Concluir', onTap: _carregando ? null : _concluir)),
        ],
      ),
    );
  }
}
