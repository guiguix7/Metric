import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:metric/finance.dart';
import 'package:metric/store.dart';

class FakeFinanceStore implements FinanceStore {
  final settings = <String, String>{};
  List<int> _rates = List.of(defaultRates);
  final _incomes = <Map<String, Object?>>[];
  final _movements = <Map<String, Object?>>[];
  final _categories = <Map<String, Object?>>[];
  final _recorrencias = <Map<String, Object?>>[];

  int _movementSeq = 0;
  int _incomeSeq = 0;
  int _categorySeq = 0;
  int _recorrenciaSeq = 0;

  String? _pin;
  int _pinTentativas = 0;
  String? _pinBloqueadoAte;

  @override
  Future<bool> get initialized async => settings['onboarding_done'] == '1';

  @override
  Future<void> setInitialized() async => settings['onboarding_done'] = '1';

  @override
  Future<void> open() async {
    if (_categories.isEmpty) {
      for (final c in [
        ['Moradia', 1],
        ['Alimentação', 1],
        ['Transporte', 1],
        ['Saúde', 1],
        ['Educação', 1],
        ['Lazer', 0],
        ['Delivery', 0],
        ['Compras', 0],
        ['Assinaturas', 0],
      ]) {
        _categorySeq++;
        _categories.add({
          'id': _categorySeq,
          'name': c[0],
          'essential': c[1],
          'active': 1,
        });
      }
    }
  }

  // ----------------------------------------------------------------- settings

  @override
  Future<String?> setting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String value) async =>
      settings[key] = value;

  @override
  Future<int> mesFinanceiroInicio() async {
    final v = settings['mes_financeiro_inicio'];
    return v == null ? 1 : int.tryParse(v) ?? 1;
  }

  // ----------------------------------------------------------------- PIN

  @override
  Future<String?> pinStored() async => _pin;

  @override
  Future<void> setPin(String pin) async {
    pin = pin.trim();
    if (pin.length < 4 || !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('O PIN deve ter ao menos 4 dígitos numéricos.');
    }
    final salt = _randomSalt(16);
    final hash = sha256.convert(utf8.encode('$pin::$salt')).toString();
    _pin = '$salt:$hash';
    _pinTentativas = 0;
    _pinBloqueadoAte = null;
  }

  @override
  bool verificaPin(String pin, String? stored) {
    if (stored == null || pin.isEmpty) return false;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final hash = sha256.convert(utf8.encode('$pin::${parts[0]}')).toString();
    return _constEq(parts[1], hash);
  }

  static bool _constEq(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result += a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  @override
  Future<int> tentativasPin() async => _pinTentativas;

  @override
  Future<void> registraFalhaPin() async {
    _pinTentativas++;
    if (_pinTentativas % 5 == 0) {
      _pinBloqueadoAte = DateTime.now()
          .add(const Duration(minutes: 1))
          .toIso8601String();
    }
  }

  @override
  Future<void> resetaTentativasPin() async {
    _pinTentativas = 0;
    _pinBloqueadoAte = null;
  }

  @override
  Future<bool> podeTentarPin() async {
    if (_pinBloqueadoAte == null) return true;
    return DateTime.now().isAfter(DateTime.parse(_pinBloqueadoAte!));
  }

  // ----------------------------------------------------------------- regras

  @override
  Future<List<int>> rates() async => List.of(_rates);

  @override
  Future<void> saveRates(List<int> rates) async {
    if (rates.length != 5 ||
        rates.any((n) => n < 0 || n > 10000) ||
        rates.reduce((a, b) => a + b) > 10000) {
      throw ArgumentError('Percentuais inválidos');
    }
    _rates = List.of(rates);
  }

  @override
  String get today => '2026-10-29';

  @override
  String get now => '2026-10-29T10:00:00.000';

  // ----------------------------------------------------------------- rendas

  @override
  Future<void> addIncome(int cents, String date, String source) async {
    if (cents <= 0) throw ArgumentError('A renda precisa ser positiva.');
    final ruleId = 1;
    final a = distribute(cents, _rates);
    _incomeSeq++;
    _incomes.add({
      'id': _incomeSeq,
      'amount': cents,
      'date': date,
      'source': source,
      'rule_id': ruleId,
      'unallocated': a.unallocated,
      'created_at': now,
    });
    for (final entry in a.amounts.entries) {
      if (entry.value != 0) {
        _addMovement(
          entry.key,
          entry.value,
          'aporte',
          date,
          incomeId: _incomeSeq,
        );
      }
    }
  }

  // ----------------------------------------------------------------- lançamentos

  @override
  Future<void> addExpense(
    int cents,
    String date,
    int categoryId,
    String boxId,
    String payment,
    String note, {
    int? recorrenciaId,
  }) async {
    if (cents <= 0 || !boxIds.contains(boxId))
      throw ArgumentError('Gasto inválido');
    _addMovement(
      boxId,
      -cents,
      'gasto',
      date,
      categoryId: categoryId,
      payment: payment,
      note: note,
      recorrenciaId: recorrenciaId,
    );
  }

  @override
  Future<void> estornar(int movementId, String note) async {
    final original = _movements.firstWhere(
      (m) => m['id'] == movementId,
      orElse: () => <String, Object?>{},
    );
    if (original.isEmpty) throw StateError('Lançamento não encontrado.');
    final box = original['box_id'] as String;
    final cents = -(original['amount'] as int);
    if (cents <= 0)
      throw StateError('Não há valor a estornar neste lançamento.');
    _addMovement(
      box,
      cents,
      'estorno',
      today,
      categoryId: original['category_id'] as int?,
      payment: original['payment'] as String?,
      sourceMovementId: movementId,
      note: note.isNotEmpty ? note : 'Estorno do lançamento #$movementId',
    );
  }

  @override
  Future<void> transfer(int cents, String from, String to, String note) async {
    if (cents <= 0 ||
        from == to ||
        !boxIds.contains(from) ||
        !boxIds.contains(to)) {
      throw ArgumentError('Transferência inválida');
    }
    final pair = '$now-$from-$to';
    _addMovement(
      from,
      -cents,
      'transferência',
      today,
      note: note,
      pairKey: pair,
    );
    _addMovement(to, cents, 'transferência', today, note: note, pairKey: pair);
  }

  @override
  Future<void> adjust(int cents, String box, String reason) async {
    if (cents == 0 || !boxIds.contains(box) || reason.trim().isEmpty) {
      throw ArgumentError('Informe um valor e uma justificativa');
    }
    _addMovement(box, cents, 'ajuste', today, note: reason);
  }

  @override
  Future<Map<String, int>> getBalances() async => balances(_movements);

  @override
  Future<List<Map<String, Object?>>> movements({
    String? de,
    String? ate,
    String? boxId,
    String? type,
    int? categoryId,
  }) async {
    var resultado = List<Map<String, Object?>>.from(_movements)
      ..sort((a, b) {
        final da = (a['date'] as String).compareTo(b['date'] as String);
        if (da != 0) return da;
        return (a['id'] as int).compareTo(b['id'] as int);
      });
    // anexa o nome da categoria, como faz o JOIN do SQLite
    final categoriaPorId = <int, String>{};
    for (final c in _categories) {
      categoriaPorId[c['id'] as int] = c['name'] as String;
    }
    resultado = resultado.map((m) {
      final catId = m['category_id'];
      if (catId == null) return m;
      return Map<String, Object?>.from(m)
        ..['category_name'] = categoriaPorId[catId as int];
    }).toList();
    resultado = resultado.reversed.toList();
    if (de != null) {
      resultado = resultado
          .where((m) => (m['date'] as String).compareTo(de) >= 0)
          .toList();
    }
    if (ate != null) {
      resultado = resultado
          .where((m) => (m['date'] as String).compareTo(ate) <= 0)
          .toList();
    }
    if (boxId != null) {
      resultado = resultado.where((m) => m['box_id'] == boxId).toList();
    }
    if (type != null) {
      resultado = resultado.where((m) => m['type'] == type).toList();
    }
    if (categoryId != null) {
      resultado = resultado
          .where((m) => m['category_id'] == categoryId)
          .toList();
    }
    return resultado;
  }

  @override
  Future<List<Map<String, Object?>>> categories() async =>
      _categories.where((c) => (c['active'] as int) == 1).toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  @override
  Future<List<Map<String, Object?>>> categoriesAll() async =>
      List<Map<String, Object?>>.from(_categories)
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  @override
  Future<void> addCategory(String name, bool essential) async {
    if (name.trim().isEmpty) throw ArgumentError('Nome obrigatório');
    _categorySeq++;
    _categories.add({
      'id': _categorySeq,
      'name': name.trim(),
      'essential': essential ? 1 : 0,
      'active': 1,
    });
  }

  @override
  Future<void> archiveCategory(int id) async {
    final c = _categories.firstWhere((c) => c['id'] == id);
    c['active'] = 0;
  }

  // ----------------------------------------------------------------- recorrências

  @override
  Future<List<Map<String, Object?>>> recorrencias({bool? pausada}) async {
    var lista = List<Map<String, Object?>>.from(_recorrencias);
    if (pausada != null) {
      lista = lista
          .where((r) => (r['pausada'] as int) == (pausada ? 1 : 0))
          .toList();
    }
    return lista..sort(
      (a, b) =>
          (a['proxima_data'] as String).compareTo(b['proxima_data'] as String),
    );
  }

  @override
  Future<int> saveRecorrencia({
    int? id,
    required String descricao,
    required int valorCents,
    required String periodicidade,
    required String proximaData,
    required String boxId,
    int? categoryId,
    bool pausada = false,
    String? dataInicio,
    String? dataFim,
  }) async {
    if (descricao.trim().isEmpty) throw ArgumentError('Descrição obrigatória');
    if (valorCents <= 0) throw ArgumentError('Valor inválido');
    if (!['mensal', 'anual'].contains(periodicidade))
      throw ArgumentError('Periodicidade inválida');
    if (!boxIds.contains(boxId)) throw ArgumentError('Caixinha inválida');
    final row = {
      'id': id ?? ++_recorrenciaSeq,
      'descricao': descricao.trim(),
      'valor': valorCents,
      'periodicidade': periodicidade,
      'proxima_data': proximaData,
      'box_id': boxId,
      'category_id': categoryId,
      'pausada': pausada ? 1 : 0,
      'data_inicio': dataInicio,
      'data_fim': dataFim,
      'criada_em': now,
    };
    if (id == null) {
      _recorrencias.add(row);
    } else {
      final idx = _recorrencias.indexWhere((r) => r['id'] == id);
      _recorrencias[idx] = row;
    }
    return row['id'] as int;
  }

  @override
  Future<void> setRecorrenciaPausada(int id, bool pausada) async {
    final r = _recorrencias.firstWhere((r) => r['id'] == id);
    r['pausada'] = pausada ? 1 : 0;
  }

  @override
  Future<void> deleteRecorrencia(int id) async {
    _recorrencias.removeWhere((r) => r['id'] == id);
  }

  @override
  Future<List<int>> gerarOcorrenciasVencidas({String? hoje}) async {
    final ref = hoje ?? today;
    final created = <int>[];
    for (final r in List<Map<String, Object?>>.from(_recorrencias)) {
      if ((r['pausada'] as int) != 0) continue;
      final fim = r['data_fim'] as String?;
      if (fim != null && fim.compareTo(ref) < 0) continue;
      final proxima = r['proxima_data'] as String;
      if (proxima.compareTo(ref) > 0) continue;
      _addMovement(
        r['box_id'] as String,
        -(r['valor'] as int),
        'gasto',
        proxima,
        categoryId: r['category_id'] as int?,
        note: r['descricao'] as String?,
        recorrenciaId: r['id'] as int,
      );
      created.add(_movementSeq);
      var prox = _addMes(proxima, r['periodicidade'] == 'anual' ? 12 : 1);
      while (prox.compareTo(ref) <= 0) {
        prox = _addMes(prox, r['periodicidade'] == 'anual' ? 12 : 1);
      }
      r['proxima_data'] = prox;
    }
    return created;
  }

  @override
  Future<Map<String, double>> equivalenciaMensalRecorrencias({
    String? ate,
  }) async {
    final ref = ate ?? today;
    final totais = <String, double>{};
    for (final r in _recorrencias) {
      if ((r['pausada'] as int) != 0) continue;
      final inicio = r['data_inicio'] as String?;
      if (inicio != null && inicio.compareTo(ref) > 0) continue;
      final fim = r['data_fim'] as String?;
      if (fim != null && fim.compareTo(ref) < 0) continue;
      final box = r['box_id'] as String;
      final valor = (r['valor'] as int);
      final mes = r['periodicidade'] == 'anual' ? valor / 12 : valor.toDouble();
      totais[box] = (totais[box] ?? 0) + mes;
    }
    return totais;
  }

  // ----------------------------------------------------------------- relatórios

  @override
  Future<Map<String, Object?>> resumoPeriodo(String de, String ate) async {
    final totalReceitas = _incomes
        .where(
          (i) =>
              (i['date'] as String).compareTo(de) >= 0 &&
              (i['date'] as String).compareTo(ate) <= 0,
        )
        .fold<int>(0, (a, i) => a + (i['amount'] as int));
    final gastoMovs = _movements.where((m) => m['type'] == 'gasto');
    final totalGastos = gastoMovs
        .where(
          (m) =>
              (m['date'] as String).compareTo(de) >= 0 &&
              (m['date'] as String).compareTo(ate) <= 0,
        )
        .fold<int>(0, (a, m) => a - (m['amount'] as int));

    final essenciais = <String, int>{};
    final naoEssenciais = <String, int>{};
    for (final m in gastoMovs) {
      final date = m['date'] as String;
      if (date.compareTo(de) < 0 || date.compareTo(ate) > 0) continue;
      final catId = m['category_id'];
      if (catId == null) continue;
      final cat = _categories.firstWhere((c) => c['id'] == catId);
      final mapa = (cat['essential'] as int) == 1 ? essenciais : naoEssenciais;
      mapa[cat['name'] as String] =
          (mapa[cat['name'] as String] ?? 0) - (m['amount'] as int);
    }

    return {
      'de': de,
      'ate': ate,
      'receitas': totalReceitas,
      'gastos': totalGastos,
      'saldo': totalReceitas - totalGastos,
      'essenciais': essenciais,
      'naoEssenciais': naoEssenciais,
    };
  }

  @override
  Future<List<Map<String, Object?>>> saldoEvolucao(
    String de,
    String ate,
  ) async {
    final boxes = List.of(boxIds);
    var running = {for (final b in boxes) b: 0};
    for (final m in _movements) {
      final date = m['date'] as String;
      if (date.compareTo(de) < 0) {
        running = Map.from(running)
          ..update(m['box_id'] as String, (v) => v + (m['amount'] as int));
      }
    }
    int saldoAnterior = running.values.fold<int>(0, (a, b) => a + b);

    final preenchido = <String, Map<String, Object?>>{};
    var cursor = DateTime.parse(de);
    final fim = DateTime.parse(ate);
    while (!cursor.isAfter(fim)) {
      final mes = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
      preenchido[mes] = {'mes': mes, 'saldoTotal': saldoAnterior};
      cursor = DateTime(
        cursor.year,
        cursor.month + 1,
        0,
      ).add(const Duration(days: 1));
    }
    for (final m in _movements) {
      final date = m['date'] as String;
      if (date.compareTo(de) < 0 || date.compareTo(ate) > 0) continue;
      running = Map.from(running)
        ..update(m['box_id'] as String, (v) => v + (m['amount'] as int));
      final mes = date.substring(0, 7);
      preenchido[mes] = {
        'mes': mes,
        'saldoTotal': running.values.fold<int>(0, (a, b) => a + b),
      };
    }
    return preenchido.values.toList()
      ..sort((a, b) => (a['mes'] as String).compareTo(b['mes'] as String));
  }

  @override
  Future<String> exportarCsvLancamentos({String? de, String? ate}) async {
    final rows = await movements(de: de, ate: ate);
    final buffer = StringBuffer();
    buffer.writeln(
      'Data,Tipo,Caixinha,Categoria,Valor (R\$),Forma de pagamento,Observação',
    );
    var total = 0;
    for (final m in rows) {
      final cents = m['amount'] as int;
      total += cents;
      buffer.writeln(
        '${m['date']},${m['type']},${boxNames[boxIds.indexOf(m['box_id'] as String)]},${_csvField(m['category_name'] as String?)},${money(cents)},${_csvField(m['payment'] as String?)},${_csvField(m['note'] as String?)}',
      );
    }
    buffer.writeln();
    buffer.writeln('Total,,,,${money(total)},,');
    return buffer.toString();
  }

  // ----------------------------------------------------------------- backup / restore

  @override
  Future<Map<String, Object?>> snapshot() async => {
    'version': 2,
    'settings': settings.entries
        .map((e) => {'key': e.key, 'value': e.value} as Map<String, Object?>)
        .toList(),
    'rules': [],
    'incomes': _deepCopy(_incomes),
    'categories': _deepCopy(_categories),
    'recorrencias': _deepCopy(_recorrencias),
    'movements': _deepCopy(_movements),
    'balances': await getBalances(),
    'exportado_em': now,
  };

  @override
  Future<void> restore(Map<String, dynamic> data) async {
    _incomes.clear();
    _movements.clear();
    _categories.clear();
    _recorrencias.clear();
    if (data['incomes'] is List) _incomes.addAll(_deepCopy(data['incomes']));
    if (data['movements'] is List)
      _movements.addAll(_deepCopy(data['movements']));
    if (data['categories'] is List)
      _categories.addAll(_deepCopy(data['categories']));
    if (data['recorrencias'] is List)
      _recorrencias.addAll(_deepCopy(data['recorrencias']));
  }

  // ----------------------------------------------------------------- internos

  void _addMovement(
    String boxId,
    int amount,
    String type,
    String date, {
    int? incomeId,
    int? categoryId,
    String? payment,
    String? note,
    int? recorrenciaId,
    int? sourceMovementId,
    String? pairKey,
  }) {
    _movementSeq++;
    _movements.add(
      {
        'id': _movementSeq,
        'box_id': boxId,
        'amount': amount,
        'type': type,
        'date': date,
        'category_id': categoryId,
        'payment': payment,
        'note': note,
        'income_id': incomeId,
        'recorrencia_id': recorrenciaId,
        'source_movement_id': sourceMovementId,
        'pair_key': pairKey,
        'created_at': now,
      }..removeWhere((_, v) => v == null),
    );
  }

  List<Map<String, Object?>> _deepCopy(List list) =>
      list.cast<Map>().map((e) => Map<String, Object?>.from(e)).toList();

  String _randomSalt(int bytes) {
    final r = Random.secure();
    return List.generate(
      bytes,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _addMes(String isoData, int meses) {
    final d = DateTime.parse(isoData);
    var ano = d.year;
    var mes = d.month + meses;
    while (mes > 12) {
      mes -= 12;
      ano += 1;
    }
    while (mes < 1) {
      mes += 12;
      ano -= 1;
    }
    final ultimoDiaMes = DateTime(ano, mes + 1, 0).day;
    final dia = ultimoDiaMes < d.day ? ultimoDiaMes : d.day;
    return DateTime(ano, mes, dia).toIso8601String().substring(0, 10);
  }

  String _csvField(String? v) {
    final s = v ?? '';
    if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
    return s;
  }
}
