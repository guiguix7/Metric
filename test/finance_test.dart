import 'package:flutter_test/flutter_test.dart';
import 'package:metric/finance.dart';

void main() {
  test('renda 1000,01 conserva centavos com maior percentual', () {
    final a = distribute(100001, defaultRates);
    expect(a.amounts['essenciais'], 50001);
    expect(a.amounts['livre'], 30000);
    expect(a.amounts['reserva'], 10000);
    expect(a.amounts['investido'], 5000);
    expect(a.amounts['metas'], 5000);
    expect(a.unallocated, 0);
    expect(a.amounts.values.reduce((a, b) => a + b), 100001);
  });

  test('renda ímpar com empate no maior percentual vai para Essenciais', () {
    final a = distribute(10001, [5000, 5000, 0, 0, 0]);
    expect(a.amounts['essenciais'], 5001);
    expect(a.amounts['livre'], 5000);
    expect(a.unallocated, 0);
  });

  test('percentuais abaixo de 100 preservam não alocado', () {
    final a = distribute(10000, [4000, 3000, 1000, 0, 0]);
    expect(a.unallocated, 2000);
    expect(a.amounts.values.reduce((a, b) => a + b), 8000);
  });

  test('soma acima de 100 não é permitida', () =>
      expect(() => distribute(100, [6000, 5000, 0, 0, 0]), throwsArgumentError));

  test('percentuais inválidos (negativos ou >100 individual) não são permitidos', () {
    expect(() => distribute(100, [10001, 0, 0, 0, 0]), throwsArgumentError);
    expect(() => distribute(100, [-1, 0, 0, 0, 0]), throwsArgumentError);
  });

  test('distribuição com tudo zerado deixa tudo não alocado', () {
    final a = distribute(10000, [0, 0, 0, 0, 0]);
    expect(a.unallocated, 10000);
    expect(a.amounts.values.every((v) => v == 0), isTrue);
  });

  test('renda não positiva é rejeitada', () =>
      expect(() => distribute(0, defaultRates), throwsArgumentError));

  test('saldo negativo atravessa meses', () {
    final movements = <Map<String, Object?>>[
      {'box_id': 'essenciais', 'amount': 150000},
      {'box_id': 'essenciais', 'amount': -165000},
      {'box_id': 'essenciais', 'amount': 150000},
    ];
    expect(balances(movements)['essenciais'], 135000);
  });

  test('transferência não altera soma total dos saldos', () {
    final result = balances([
      {'box_id': 'livre', 'amount': -5000},
      {'box_id': 'reserva', 'amount': 5000},
    ]);
    expect(result.values.reduce((a, b) => a + b), 0);
  });

  test('caixinha desconhecida no saldo lança erro', () =>
      expect(() => balances([{'box_id': 'inexistente', 'amount': 100}]), throwsStateError));

  test('parse dinheiro brasileiro aceita com e sem milhar', () {
    expect(parseMoney('1.234,56'), 123456);
    expect(parseMoney('1234'), 123400);
    expect(parseMoney('0,50'), 50);
    expect(parseMoney('1.000,01'), 100001);
  });

  test('parse dinheiro brasileiro rejeita formato inválido', () {
    expect(() => parseMoney('12,345'), throwsFormatException);
    expect(() => parseMoney('abc'), throwsFormatException);
    expect(() => parseMoney(''), throwsFormatException);
    expect(() => parseMoney('-10,00'), throwsFormatException);
  });

  test('money formata reais com centavos, sinal negativo e ponto de milhar', () {
    expect(money(123456), 'R\$ 1.234,56');
    expect(money(-15000), '−R\$ 150,00');
    expect(money(500), 'R\$ 5,00');
    expect(money(0), 'R\$ 0,00');
  });
}
