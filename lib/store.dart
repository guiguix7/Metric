import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

import 'finance.dart';

/// Contrato de persistência do Metric.
///
/// Implementado por [SqfliteFinanceStore] (SQLite local). Em testes pode ser
/// substituído por um fake em memória, já que as regras de negócio vivem em
/// finance.dart e não dependem de banco (R2 §3, princípio 1).
abstract class FinanceStore {
  /// Abre (ou cria) o banco. Deve ser chamado antes de qualquer outra operação.
  Future<void> open();

  /// Se o onboarding inicial já foi concluído.
  Future<bool> get initialized;
  Future<void> setInitialized();

  // ----------------------------------------------------------------- settings

  Future<String?> setting(String key);
  Future<void> setSetting(String key, String value);

  /// Dia de início do mês financeiro (1..31). Padrão: 1 (R1 §8.12).
  Future<int> mesFinanceiroInicio();

  // ----------------------------------------------------------------- PIN

  /// "salt:hash" ou null se ainda não houver PIN cadastrado.
  Future<String?> pinStored();

  /// Cadastra ou altera o PIN (mínimo 4 dígitos). Guarda somente hash com sal
  /// — nunca o PIN em texto claro (R2 §5).
  Future<void> setPin(String pin);

  /// Comparação de hash em tempo constante.
  bool verificaPin(String pin, String? stored);

  Future<int> tentativasPin();
  Future<void> registraFalhaPin();
  Future<void> resetaTentativasPin();

  /// Pode tentar digitar o PIN agora? (respeita bloqueio por atraso crescente)
  Future<bool> podeTentarPin();

  // ----------------------------------------------------------------- regras de distribuição

  Future<List<int>> rates();
  Future<void> saveRates(List<int> rates);

  String get today;
  String get now;

  // ----------------------------------------------------------------- rendas

  Future<void> addIncome(int cents, String date, String source);

  // ----------------------------------------------------------------- lançamentos

  Future<void> addExpense(int cents, String date, int categoryId, String boxId,
      String payment, String note,
      {int? recorrenciaId});

  /// Estorna um lançamento devolvendo seu valor à caixinha de origem,
  /// vinculado ao lançamento original (R1 §8.9).
  Future<void> estornar(int movementId, String note);

  Future<void> transfer(int cents, String from, String to, String note);

  /// Ajuste manual de saldo com justificativa obrigatória (R1 §8.5).
  Future<void> adjust(int cents, String box, String reason);

  /// Saldo por caixinha derivado exclusivamente dos movimentos (R2 §2.3).
  Future<Map<String, int>> getBalances();

  Future<List<Map<String, Object?>>> movements({
    String? de,
    String? ate,
    String? boxId,
    String? type,
    int? categoryId,
  });

  Future<List<Map<String, Object?>>> categories();
  Future<List<Map<String, Object?>>> categoriesAll();
  Future<void> addCategory(String name, bool essential);
  Future<void> archiveCategory(int id);

  // ----------------------------------------------------------------- recorrências / assinaturas

  Future<List<Map<String, Object?>>> recorrencias({bool? pausada});
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
  });
  Future<void> setRecorrenciaPausada(int id, bool pausada);
  Future<void> deleteRecorrencia(int id);

  /// Gera lançamentos de gasto das recorrências vencidas e avança a próxima
  /// data. Retorna os ids dos movimentos criados.
  Future<List<int>> gerarOcorrenciasVencidas({String? hoje});

  /// Valor equivalente por mês das recorrências ativas (R1 §8.10).
  Future<Map<String, double>> equivalenciaMensalRecorrencias({String? ate});

  // ----------------------------------------------------------------- relatórios

  Future<Map<String, Object?>> resumoPeriodo(String de, String ate);

  /// Evolução do saldo total por mês no período (R3 §7.4).
  Future<List<Map<String, Object?>>> saldoEvolucao(String de, String ate);

  /// CSV dos lançamentos do período (R2 §6, R3 §6.10).
  Future<String> exportarCsvLancamentos({String? de, String? ate});

  // ----------------------------------------------------------------- backup / restore

  Future<Map<String, Object?>> snapshot();
  Future<void> restore(Map<String, dynamic> data);
}

/// Banco local SQLite (sqflite). Esquema versão 2.
///
/// Todas as quantias são inteiros de centavos (finance.dart).
/// Datas são civis ISO (yyyy-MM-dd) no fuso do aparelho.
class SqfliteFinanceStore extends FinanceStore {
  static const int schemaVersion = 2;

  Database? _db;
  Database get db => _db ?? (throw StateError('Banco não inicializado'));

  @override
  Future<bool> get initialized async {
    final v = await setting('onboarding_done');
    return v == '1';
  }

  @override
  Future<void> setInitialized() async => await setSetting('onboarding_done', '1');

  @override
  Future<void> open() async {
    _db = await openDatabase(
      path.join(await getDatabasesPath(), 'metric.db'),
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await _ensureDefaults();
  }

  Future<void> _onCreate(Database d, int _) async {
    await d.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await d.execute(
        'CREATE TABLE rules (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL, rates TEXT NOT NULL)');
    await d.execute(
        'CREATE TABLE incomes (id INTEGER PRIMARY KEY AUTOINCREMENT, amount INTEGER NOT NULL CHECK(amount > 0), date TEXT NOT NULL, source TEXT, rule_id INTEGER NOT NULL, unallocated INTEGER NOT NULL, created_at TEXT NOT NULL)');
    await d.execute(
        'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, essential INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 1)');
    await d.execute(
        'CREATE TABLE movements (id INTEGER PRIMARY KEY AUTOINCREMENT, box_id TEXT NOT NULL, amount INTEGER NOT NULL, type TEXT NOT NULL, date TEXT NOT NULL, category_id INTEGER, payment TEXT, note TEXT, income_id INTEGER, recorrencia_id INTEGER, source_movement_id INTEGER, pair_key TEXT, created_at TEXT NOT NULL)');
    await d.execute(
        "CREATE TABLE recorrencias (id INTEGER PRIMARY KEY AUTOINCREMENT, descricao TEXT NOT NULL, valor INTEGER NOT NULL CHECK(valor > 0), periodicidade TEXT NOT NULL CHECK(periodicidade IN ('mensal','anual')), proxima_data TEXT NOT NULL, box_id TEXT NOT NULL, category_id INTEGER, pausada INTEGER NOT NULL DEFAULT 0, data_inicio TEXT, data_fim TEXT, criada_em TEXT NOT NULL)");
    await d.execute('CREATE INDEX idx_movements_date ON movements(date)');
    await d.execute('CREATE INDEX idx_movements_box ON movements(box_id)');
    await d.execute('CREATE INDEX idx_movements_source ON movements(source_movement_id)');
    await d.execute('CREATE INDEX idx_recorrencias_proxima ON recorrencias(proxima_data)');
    await _seedCategories(d);
    await d.insert('rules', {
      'created_at': DateTime.now().toIso8601String(),
      'rates': jsonEncode(defaultRates),
    });
    await d.insert('settings', {'key': 'schema_version', 'value': schemaVersion.toString()});
  }

  Future<void> _onUpgrade(Database d, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await d.execute('ALTER TABLE movements ADD COLUMN recorrencia_id INTEGER');
      await d.execute('ALTER TABLE movements ADD COLUMN source_movement_id INTEGER');
      await d.execute(
          "CREATE TABLE IF NOT EXISTS recorrencias (id INTEGER PRIMARY KEY AUTOINCREMENT, descricao TEXT NOT NULL, valor INTEGER NOT NULL CHECK(valor > 0), periodicidade TEXT NOT NULL CHECK(periodicidade IN ('mensal','anual')), proxima_data TEXT NOT NULL, box_id TEXT NOT NULL, category_id INTEGER, pausada INTEGER NOT NULL DEFAULT 0, data_inicio TEXT, data_fim TEXT, criada_em TEXT NOT NULL)");
      await d.execute('CREATE INDEX IF NOT EXISTS idx_movements_source ON movements(source_movement_id)');
      await d.execute('CREATE INDEX IF NOT EXISTS idx_recorrencias_proxima ON recorrencias(proxima_data)');
      await _seedCategoriesIfMissing(d);
      await d.insert('settings', {'key': 'schema_version', 'value': newVersion.toString()});
    }
  }

  Future<void> _ensureDefaults() async {
    if (await setting('mes_financeiro_inicio') == null) {
      await setSetting('mes_financeiro_inicio', '1');
    }
  }

  Future<void> _seedCategories(Database d) async {
    for (final c in [
      ['Moradia', 1],
      ['Alimentação', 1],
      ['Transporte', 1],
      ['Saúde', 1],
      ['Educação', 1],
      ['Lazer', 0],
      ['Delivery', 0],
      ['Compras', 0],
      ['Assinaturas', 0]
    ]) {
      await d.insert('categories', {'name': c[0], 'essential': c[1]});
    }
  }

  Future<void> _seedCategoriesIfMissing(Database d) async {
    final existing = await d.query('categories');
    if (existing.isEmpty) await _seedCategories(d);
  }

  // ----------------------------------------------------------------- settings

  @override
  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> setSetting(String key, String value) async =>
      db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<int> mesFinanceiroInicio() async {
    final v = await setting('mes_financeiro_inicio');
    return v == null ? 1 : int.tryParse(v) ?? 1;
  }

  // ----------------------------------------------------------------- PIN

  @override
  Future<String?> pinStored() => setting('pin');

  @override
  Future<void> setPin(String pin) async {
    pin = pin.trim();
    if (pin.length < 4 || !RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('O PIN deve ter ao menos 4 dígitos numéricos.');
    }
    final salt = _randomSalt(16);
    final hash = sha256.convert(utf8.encode('$pin::$salt')).toString();
    await setSetting('pin', '$salt:$hash');
    await setSetting('pin_tentativas', '0');
    await setSetting('pin_bloqueado_ate', '');
  }

  @override
  bool verificaPin(String pin, String? stored) {
    if (stored == null || pin.isEmpty) return false;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final hash = sha256.convert(utf8.encode('$pin::${parts[0]}')).toString();
    return _constEq(parts[1], hash);
  }

  @override
  Future<int> tentativasPin() async {
    final v = await setting('pin_tentativas');
    return int.tryParse(v ?? '0') ?? 0;
  }

  @override
  Future<void> registraFalhaPin() async {
    final atual = await tentativasPin() + 1;
    await setSetting('pin_tentativas', atual.toString());
    if (atual % 5 == 0) {
      final minutos = 1 << (atual ~/ 5 - 1);
      await setSetting('pin_bloqueado_ate',
          DateTime.now().add(Duration(minutes: minutos)).toIso8601String());
    }
  }

  @override
  Future<void> resetaTentativasPin() async {
    await setSetting('pin_tentativas', '0');
    await setSetting('pin_bloqueado_ate', '');
  }

  @override
  Future<bool> podeTentarPin() async {
    final ate = await setting('pin_bloqueado_ate');
    if (ate == null || ate.isEmpty) return true;
    return DateTime.now().isAfter(DateTime.parse(ate));
  }

  String _randomSalt(int bytes) {
    final r = Random.secure();
    return List.generate(bytes, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constEq(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result += a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  // ----------------------------------------------------------------- regras de distribuição

  @override
  Future<List<int>> rates() async {
    final rows = await db.query('rules', orderBy: 'id DESC', limit: 1);
    return rows.isEmpty ? List.of(defaultRates) : (jsonDecode(rows.first['rates'] as String) as List).cast<int>();
  }

  @override
  Future<void> saveRates(List<int> rates) async {
    if (rates.length != 5 || rates.any((n) => n < 0 || n > 10000) || rates.reduce((a, b) => a + b) > 10000) {
      throw ArgumentError('Percentuais inválidos');
    }
    await db.insert('rules', {'created_at': now, 'rates': jsonEncode(rates)});
  }

  @override
  String get today => DateTime.now().toIso8601String().substring(0, 10);

  @override
  String get now => DateTime.now().toIso8601String();

  // ----------------------------------------------------------------- rendas

  @override
  Future<void> addIncome(int cents, String date, String source) async {
    if (cents <= 0) throw ArgumentError('A renda precisa ser positiva.');
    final ruleRows = await db.query('rules', orderBy: 'id DESC', limit: 1);
    if (ruleRows.isEmpty) throw StateError('Nenhuma regra de distribuição cadastrada.');
    final ruleId = ruleRows.first['id'] as int;
    final currentRates = (jsonDecode(ruleRows.first['rates'] as String) as List).cast<int>();
    final a = distribute(cents, currentRates);
    await db.transaction((txn) async {
      final incomeId = await txn.insert('incomes', {
        'amount': cents,
        'date': date,
        'source': source,
        'rule_id': ruleId,
        'unallocated': a.unallocated,
        'created_at': now,
      });
      for (final entry in a.amounts.entries) {
        if (entry.value != 0) {
          await txn.insert('movements', {
            'box_id': entry.key,
            'amount': entry.value,
            'type': 'aporte',
            'date': date,
            'income_id': incomeId,
            'created_at': now,
          });
        }
      }
    });
  }

  // ----------------------------------------------------------------- lançamentos

  @override
  Future<void> addExpense(int cents, String date, int categoryId, String boxId, String payment, String note,
      {int? recorrenciaId}) async {
    if (cents <= 0 || !boxIds.contains(boxId)) throw ArgumentError('Gasto inválido');
    await db.insert('movements', {
      'box_id': boxId,
      'amount': -cents,
      'type': 'gasto',
      'date': date,
      'category_id': categoryId,
      'payment': payment,
      'note': note,
      'recorrencia_id': recorrenciaId,
      'created_at': now,
    });
  }

  @override
  Future<void> estornar(int movementId, String note) async {
    final original = await db.query('movements', where: 'id = ?', whereArgs: [movementId]);
    if (original.isEmpty) throw StateError('Lançamento não encontrado.');
    final o = original.first;
    final box = o['box_id'] as String;
    final cents = -(o['amount'] as int);
    if (cents <= 0) throw StateError('Não há valor a estornar neste lançamento.');
    await db.transaction((txn) async {
      await txn.insert('movements', {
        'box_id': box,
        'amount': cents,
        'type': 'estorno',
        'date': today,
        'category_id': o['category_id'],
        'payment': o['payment'],
        'note': note.isNotEmpty ? note : 'Estorno do lançamento #$movementId',
        'source_movement_id': movementId,
        'created_at': now,
      });
    });
  }

  @override
  Future<void> transfer(int cents, String from, String to, String note) async {
    if (cents <= 0 || from == to || !boxIds.contains(from) || !boxIds.contains(to)) {
      throw ArgumentError('Transferência inválida');
    }
    final pair = '$now-$from-$to';
    await db.transaction((txn) async {
      await txn.insert('movements', {
        'box_id': from,
        'amount': -cents,
        'type': 'transferência',
        'date': today,
        'note': note,
        'pair_key': pair,
        'created_at': now,
      });
      await txn.insert('movements', {
        'box_id': to,
        'amount': cents,
        'type': 'transferência',
        'date': today,
        'note': note,
        'pair_key': pair,
        'created_at': now,
      });
    });
  }

  @override
  Future<void> adjust(int cents, String box, String reason) async {
    if (cents == 0 || !boxIds.contains(box) || reason.trim().isEmpty) {
      throw ArgumentError('Informe um valor e uma justificativa');
    }
    await db.insert('movements', {
      'box_id': box,
      'amount': cents,
      'type': 'ajuste',
      'date': today,
      'note': reason,
      'created_at': now,
    });
  }

  @override
  Future<Map<String, int>> getBalances() async => balances(await db.query('movements'));

  @override
  Future<List<Map<String, Object?>>> movements({
    String? de,
    String? ate,
    String? boxId,
    String? type,
    int? categoryId,
  }) async {
    final clauses = <String>[];
    final args = <Object>[];
    if (de != null) {
      clauses.add('date >= ?');
      args.add(de);
    }
    if (ate != null) {
      clauses.add('date <= ?');
      args.add(ate);
    }
    if (boxId != null) {
      clauses.add('box_id = ?');
      args.add(boxId);
    }
    if (type != null) {
      clauses.add('type = ?');
      args.add(type);
    }
    if (categoryId != null) {
      clauses.add('category_id = ?');
      args.add(categoryId);
    }
    final where = clauses.isEmpty ? '' : "WHERE ${clauses.join(' AND ')}";
    return db.rawQuery(
        'SELECT m.*, c.name AS category_name FROM movements m LEFT JOIN categories c ON c.id = m.category_id $where ORDER BY m.date DESC, m.id DESC',
        args);
  }

  @override
  Future<List<Map<String, Object?>>> categories() =>
      db.query('categories', where: 'active = 1', orderBy: 'name');

  @override
  Future<List<Map<String, Object?>>> categoriesAll() =>
      db.query('categories', orderBy: 'name');

  @override
  Future<void> addCategory(String name, bool essential) async {
    if (name.trim().isEmpty) throw ArgumentError('Nome obrigatório');
    await db.insert('categories', {'name': name.trim(), 'essential': essential ? 1 : 0});
  }

  @override
  Future<void> archiveCategory(int id) =>
      db.update('categories', {'active': 0}, where: 'id = ?', whereArgs: [id]);

  // ----------------------------------------------------------------- recorrências / assinaturas

  @override
  Future<List<Map<String, Object?>>> recorrencias({bool? pausada}) async {
    final clauses = <String>[];
    final args = <Object>[];
    if (pausada != null) {
      clauses.add('pausada = ?');
      args.add(pausada ? 1 : 0);
    }
    return db.query('recorrencias',
        where: clauses.isEmpty ? null : clauses.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'proxima_data ASC, descricao ASC');
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
    if (!['mensal', 'anual'].contains(periodicidade)) throw ArgumentError('Periodicidade inválida');
    if (!boxIds.contains(boxId)) throw ArgumentError('Caixinha inválida');
    final row = {
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
      return await db.insert('recorrencias', row);
    }
    await db.update('recorrencias', row, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  @override
  Future<void> setRecorrenciaPausada(int id, bool pausada) =>
      db.update('recorrencias', {'pausada': pausada ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> deleteRecorrencia(int id) => db.delete('recorrencias', where: 'id = ?', whereArgs: [id]);

  @override
  Future<List<int>> gerarOcorrenciasVencidas({String? hoje}) async {
    final ref = hoje ?? today;
    final rows = await db.query(
        'recorrencias',
        where: 'pausada = 0 AND (data_fim IS NULL OR data_fim >= ?) AND proxima_data <= ?',
        whereArgs: [ref, ref],
        orderBy: 'proxima_data ASC');
    final created = <int>[];
    for (final r in rows) {
      final id = r['id'] as int;
      await db.transaction((txn) async {
        final movementId = await txn.insert('movements', {
          'box_id': r['box_id'],
          'amount': -(r['valor'] as int),
          'type': 'gasto',
          'date': r['proxima_data'],
          'category_id': r['category_id'],
          'note': r['descricao'],
          'recorrencia_id': id,
          'created_at': now,
        });
        created.add(movementId);
        final passo = (r['periodicidade'] as String) == 'anual' ? 12 : 1;
        var prox = _addMes(r['proxima_data'] as String, passo);
        while (prox.compareTo(ref) <= 0) {
          prox = _addMes(prox, passo);
        }
        await txn.update('recorrencias', {'proxima_data': prox}, where: 'id = ?', whereArgs: [id]);
      });
    }
    return created;
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

  @override
  Future<Map<String, double>> equivalenciaMensalRecorrencias({String? ate}) async {
    final ref = ate ?? today;
    final rows = await db.query(
        'recorrencias',
        where: 'pausada = 0 AND (data_inicio IS NULL OR data_inicio <= ?) AND (data_fim IS NULL OR data_fim >= ?)',
        whereArgs: [ref, ref]);
    final totais = <String, double>{};
    for (final r in rows) {
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
    final recebido = await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS total FROM incomes WHERE date >= ? AND date <= ?', [de, ate]);
    final totalReceitas = (recebido.first['total'] as int?) ?? 0;

    final gastos = await db.rawQuery(
        'SELECT COALESCE(SUM(-amount),0) AS total FROM movements WHERE type = ? AND date >= ? AND date <= ?',
        ['gasto', de, ate]);
    final totalGastos = (gastos.first['total'] as int?) ?? 0;

    final porCategoria = await db.rawQuery(
        '''SELECT c.name AS categoria, c.essential AS essencial, COALESCE(SUM(-m.amount),0) AS total
           FROM movements m JOIN categories c ON c.id = m.category_id
           WHERE m.type = ? AND m.date >= ? AND m.date <= ?
           GROUP BY c.id ORDER BY total DESC''',
        ['gasto', de, ate]);

    final essenciais = <String, int>{};
    final naoEssenciais = <String, int>{};
    for (final r in porCategoria) {
      final mapa = (r['essencial'] as int) == 1 ? essenciais : naoEssenciais;
      mapa[r['categoria'] as String] = ((r['total'] as int?) ?? 0);
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
  Future<List<Map<String, Object?>>> saldoEvolucao(String de, String ate) async {
    final all = await db.query('movements', where: 'date <= ?', whereArgs: [ate], orderBy: 'date ASC, id ASC');
    final boxes = List.of(boxIds);
    var running = {for (final b in boxes) b: 0};
    for (final m in all) {
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
      final dias = DateTime(cursor.year, cursor.month + 1, 0).day;
      cursor = DateTime(cursor.year, cursor.month, dias).add(const Duration(days: 1));
    }

    for (final m in all) {
      final date = m['date'] as String;
      if (date.compareTo(de) < 0 || date.compareTo(ate) > 0) continue;
      running = Map.from(running)
        ..update(m['box_id'] as String, (v) => v + (m['amount'] as int));
      final mes = date.substring(0, 7);
      preenchido[mes] = {'mes': mes, 'saldoTotal': running.values.fold<int>(0, (a, b) => a + b)};
    }

    return preenchido.values.toList()
      ..sort((a, b) => (a['mes'] as String).compareTo(b['mes'] as String));
  }

  @override
  Future<String> exportarCsvLancamentos({String? de, String? ate}) async {
    final rows = await movements(de: de, ate: ate);
    final buffer = StringBuffer();
    buffer.writeln('Data,Tipo,Caixinha,Categoria,Valor (R\$),Forma de pagamento,Observação');
    var total = 0;
    for (final m in rows) {
      final cents = m['amount'] as int;
      total += cents;
      buffer.writeln(
          '${m['date']},${m['type']},${_boxNome(m['box_id'] as String)},${_csvField(m['category_name'] as String?)},${money(cents)},${_csvField(m['payment'] as String?)},${_csvField(m['note'] as String?)}');
    }
    buffer.writeln();
    buffer.writeln('Total,,,,${money(total)},,');
    return buffer.toString();
  }

  String _boxNome(String id) => boxNames[boxIds.indexOf(id)];

  String _csvField(String? v) {
    final s = v ?? '';
    if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  // ----------------------------------------------------------------- backup / restore

  @override
  Future<Map<String, Object?>> snapshot() async => {
    'version': 2,
    'schema_version': schemaVersion,
    'settings': await db.query('settings'),
    'rules': await db.query('rules'),
    'incomes': await db.query('incomes'),
    'categories': await db.query('categories'),
    'recorrencias': await db.query('recorrencias'),
    'movements': await db.query('movements'),
    'balances': await getBalances(),
    'exportado_em': now,
  };

  @override
  Future<void> restore(Map<String, dynamic> data) async {
    final version = data['version'];
    if (version == null || (version is! int && version is! String)) {
      throw FormatException('Versão do backup não informada');
    }
    final v = int.parse(version.toString());
    if (v > schemaVersion) {
      throw FormatException('Backup de versão futura ($v), não suportado por esta versão ($schemaVersion).');
    }
    for (final table in ['settings', 'rules', 'incomes', 'categories', 'movements']) {
      if (data[table] is! List) throw const FormatException('Backup incompleto');
    }
    await db.transaction((txn) async {
      for (final table in ['movements', 'incomes', 'recorrencias', 'rules', 'categories', 'settings']) {
        await txn.delete(table);
      }
      const ordem = ['settings', 'rules', 'incomes', 'categories', 'recorrencias', 'movements'];
      for (final table in ordem) {
        final items = data[table];
        if (items is List) {
          for (final item in items) {
            await txn.insert(table, Map<String, Object?>.from(item as Map));
          }
        }
      }
      if ((await txn.query('rules', limit: 1)).isEmpty) {
        await txn.insert('rules', {
          'created_at': now,
          'rates': jsonEncode(defaultRates),
        });
      }
      final rows = await txn.query('movements');
      final computed = balances(rows);
      final informados = (data['balances'] as Map?)?.cast<String, dynamic>();
      if (informados != null &&
          boxIds.any((id) => (computed[id] ?? 0) != (informados[id] as num?)?.toInt())) {
        throw const FormatException('Saldos do backup divergem dos lançamentos restaurados.');
      }
    });
    await _ensureDefaults();
  }
}
