import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/domain/entry.dart';
import 'package:pocket_ledger/data/ledger_repository.dart';

void main() {
  test('Money uses exact minor units and rejects excess precision', () {
    expect(parseAmount('0.10') + parseAmount('0.20'), 30);
    expect(parseAmount('1250.5'), 125050);
    for (final input in ['0', '-1', '1.234', 'NaN', '1e3', '1,000', '99999999999']) {
      expect(() => parseAmount(input), throwsFormatException);
    }
    expect(money(-125050), '-1,250.50');
    expect(money(125050), '1,250.50');
  });
  test('Dates do not silently overflow and leap days are valid', () {
    expect(dayKey(parseDay('2024-02-29')), '2024-02-29');
    expect(() => parseDay('2025-02-29'), throwsFormatException);
    expect(() => parseDay('2026-04-31'), throwsFormatException);
  });
  test('Reports distinguish income from spending', () {
    final report = MonthReport([
      Entry(kind: 'income', amountMinor: 100000, category: 'Salary', date: '2026-10-01'),
      Entry(kind: 'expense', amountMinor: 25000, category: 'Food', date: '2026-10-02'),
      Entry(kind: 'expense', amountMinor: 5000, category: 'Food', date: '2026-10-03'),
    ]);
    expect(report.net, 70000);
    expect(report.categories, {'Food': 30000});
    expect(report.spentOnDay(2), 25000);
    expect(MonthReport([]).net, 0);
  });
  test('Category and transaction type must match', () {
    expect(() => Entry(kind: 'income', amountMinor: 1, category: 'Food', date: '2026-10-01'),
      throwsFormatException);
  });
  test('CSV protects text cells from spreadsheet formula execution', () {
    final csv = reportCsv(MonthReport([
      Entry(kind: 'expense', amountMinor: 1, category: 'Food', date: '2026-10-01',
        note: '=1+1'),
    ]));
    expect(csv, contains("\"'=1+1\""));
    expect(csv, contains('0.01,'));
    expect(csv, isNot(contains('Currency')));
  });
  test('Restore rejects unknown fields, duplicate IDs and foreign currency', () {
    expect(() => LedgerRepository.decodeBackup('{"version":1,"currency":"USD","entries":[]}'),
      throwsFormatException);
    expect(() => Entry.fromMap({'kind': 'income', 'amount_minor': 1, 'category': 'Salary',
      'date': '2026-10-01', 'note': '', 'extra': true}), throwsFormatException);
    const row = '{"id":1,"kind":"income","amount_minor":100,"category":"Salary","date":"2026-10-01","note":""}';
    expect(() => LedgerRepository.decodeBackup('{"version":1,"currency":"PKR","entries":[$row,$row]}'),
      throwsFormatException);
  });
}
