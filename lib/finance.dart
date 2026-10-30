/// Pure Dart financial domain. Amounts are always integer cents.
const boxIds = ['essenciais', 'livre', 'reserva', 'investido', 'metas'];
const boxNames = ['Essenciais', 'Livre', 'Reserva', 'Investido', 'Metas'];
const defaultRates = [5000, 3000, 1000, 500, 500];

class Allocation {
  final Map<String, int> amounts;
  final int unallocated;
  const Allocation(this.amounts, this.unallocated);
}

Allocation distribute(int cents, List<int> rates) {
  if (cents <= 0) throw ArgumentError('A renda precisa ser positiva.');
  if (rates.length != 5 ||
      rates.any((e) => e < 0 || e > 10000) ||
      rates.fold<int>(0, (a, b) => a + b) > 10000) {
    throw ArgumentError('A distribuição deve somar no máximo 100%.');
  }
  final amounts = <String, int>{};
  var sum = 0;
  for (var i = 0; i < 5; i++) {
    final value = cents * rates[i] ~/ 10000;
    amounts[boxIds[i]] = value;
    sum += value;
  }
  final unallocated =
      cents * (10000 - rates.fold<int>(0, (a, b) => a + b)) ~/ 10000;
  final remainder = cents - unallocated - sum;
  if (remainder > 0) {
    var index = 0;
    for (var i = 1; i < 5; i++) {
      if (rates[i] > rates[index]) index = i;
    }
    amounts[boxIds[index]] = amounts[boxIds[index]]! + remainder;
  }
  return Allocation(amounts, unallocated);
}

int parseMoney(String input) {
  final value = input.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (!RegExp(r'^\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?$|^\d+(?:,\d{1,2})?$')
      .hasMatch(value)) {
    throw FormatException('Digite um valor como 1.234,56');
  }
  final parts = value.replaceAll('.', '').split(',');
  return int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

String money(int cents) {
  final abs = cents.abs();
  final integer = (abs ~/ 100).toString();
  final grouped = integer.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => '.',
  );
  return '${cents < 0 ? '−' : ''}R\$ $grouped,${(abs % 100).toString().padLeft(2, '0')}';
}

Map<String, int> balances(Iterable<Map<String, Object?>> movements) {
  final result = {for (final id in boxIds) id: 0};
  for (final m in movements) {
    final id = m['box_id'] as String;
    if (!result.containsKey(id)) throw StateError('Caixinha desconhecida: $id');
    result[id] = result[id]! + (m['amount'] as int);
  }
  return result;
}
