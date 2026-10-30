import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metric/main.dart';

import 'fake_store.dart';

void main() {
  FinanceHome home(FakeFinanceStore store) => FinanceHome(
    store: store,
    mode: ThemeMode.light,
    onTheme: (_) {},
    desbloquear: (_) {},
  );

  Future<void> seedRenda(FakeFinanceStore store) async {
    await store.addIncome(100000, store.today, 'Salário');
  }

  /// Rola a lista da tela inicial até o texto ficar visível e toca (ignora
  /// aviso de hit-test: em testes o alvo pode estar parcialmente coberto pelo
  /// teclado virtual simulado).
  Future<void> tapVisible(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 800.0);
    await tester.tap(find.text(text).first, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  testWidgets('início mostra as cinco caixinhas', (tester) async {
    final store = FakeFinanceStore();
    await store.open();
    await tester.pumpWidget(MaterialApp(home: home(store)));
    await tester.pumpAndSettle();

    expect(find.text('Quanto você pode gastar?'), findsOneWidget);
    expect(find.text('Suas cinco caixinhas'), findsOneWidget);
    // O saldo de cada caixinhas (primeira informação da tela, R3 §6.2) começa em zero.
    expect(find.text('R\$ 0,00'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Metas'), 500.0);
    expect(find.text('Metas'), findsOneWidget);
  });

  testWidgets('registrar renda divide o valor entre as caixinhas', (
    tester,
  ) async {
    final store = FakeFinanceStore();
    await store.open();
    await tester.pumpWidget(MaterialApp(home: home(store)));
    await tester.pumpAndSettle();

    await tapVisible(tester, 'Registrar renda');
    await tester.enterText(find.byType(TextField).first, '3.000,00');
    await tester.tap(find.text('Ver divisão').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e dividir').first);
    await tester.pumpAndSettle();

    final b = await store.getBalances();
    expect(b['essenciais'], 150000);
    expect(b['livre'], 90000);
    expect(b['reserva'], 30000);
    expect(b['investido'], 15000);
    expect(b['metas'], 15000);

    expect(find.text('R\$ 900,00'), findsOneWidget);
  });

  testWidgets('gasto reduz a caixinha sugerida e aparece no extrato', (
    tester,
  ) async {
    final store = FakeFinanceStore();
    await store.open();
    await seedRenda(store);
    await tester.pumpWidget(MaterialApp(home: home(store)));
    await tester.pumpAndSettle();

    await tapVisible(tester, 'Registrar gasto');
    await tester.enterText(find.byType(TextField).first, '42,90');
    await tester.tap(find.text('Salvar gasto').first);
    await tester.pumpAndSettle();

    final b = await store.getBalances();
    expect(b['essenciais'], 50000 - 4290);
    expect(b['livre'], 30000);

    await tester.tap(find.text('Lançamentos').first);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('−R\$ 42,90'), findsOneWidget);
    expect(find.textContaining('Alimentação'), findsOneWidget);
  });

  testWidgets('transferência entre caixinhas não altera o total', (
    tester,
  ) async {
    final store = FakeFinanceStore();
    await store.open();
    await seedRenda(store);
    await tester.pumpWidget(MaterialApp(home: home(store)));
    await tester.pumpAndSettle();

    final fab = find.byType(FloatingActionButton).first;
    await tester.tap(fab);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transferir').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '200,00');
    await tester.tap(find.text('Transferir').first);
    await tester.pumpAndSettle();

    final b = await store.getBalances();
    expect(b['livre'], 30000 - 20000);
    expect(b['reserva'], 10000 + 20000);
    expect(b.values.fold<int>(0, (a, v) => a + v), 100000);
  });

  testWidgets('nova distribuição vale apenas para rendas futuras', (
    tester,
  ) async {
    final store = FakeFinanceStore();
    await store.open();
    await seedRenda(store);
    await tester.pumpWidget(MaterialApp(home: home(store)));
    await tester.pumpAndSettle();

    final antes = await store.getBalances();
    expect(antes['essenciais'], 50000);

    await store.saveRates([6000, 3000, 1000, 0, 0]);

    await tapVisible(tester, 'Registrar renda');
    await tester.enterText(find.byType(TextField).first, '1.000,00');
    await tester.tap(find.text('Ver divisão').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e dividir').first);
    await tester.pumpAndSettle();

    final depois = await store.getBalances();
    expect(depois['essenciais'], 50000 + 60000);
    expect(depois['livre'], 30000 + 30000);
  });

  testWidgets('estornar gasto devolve o valor à caixinha', (tester) async {
    final store = FakeFinanceStore();
    await store.open();
    await seedRenda(store);
    await tester.pumpWidget(MaterialApp(home: home(store)));
    await tester.pumpAndSettle();

    await tapVisible(tester, 'Registrar gasto');
    await tester.enterText(find.byType(TextField).first, '42,90');
    await tester.tap(find.text('Salvar gasto').first);
    await tester.pumpAndSettle();

    final aposGasto = await store.getBalances();
    expect(aposGasto['essenciais'], 50000 - 4290);

    await tester.tap(find.text('Lançamentos').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.restore).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estornar').first);
    await tester.pumpAndSettle();

    final aposEstorno = await store.getBalances();
    expect(aposEstorno['essenciais'], 50000);
  });

  testWidgets('backup e restauração preservam saldos', (tester) async {
    final store = FakeFinanceStore();
    await store.open();
    await seedRenda(store);
    await tester.pumpWidget(MaterialApp(home: home(store)));
    await tester.pumpAndSettle();

    final snapshot = await store.snapshot();
    expect(snapshot['version'], 2);

    await store.addIncome(200000, store.today, 'Salário');
    final depois = await store.getBalances();
    expect(depois['livre'], 30000 + 60000);

    await store.restore(snapshot as Map<String, dynamic>);
    final restaurado = await store.getBalances();
    // A restauração traz de volta o estado capturado no snapshot.
    expect(restaurado['livre'], 30000);
  });
}
