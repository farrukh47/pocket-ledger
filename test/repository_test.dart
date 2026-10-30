import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pocket_ledger/data/ledger_repository.dart';
import 'package:pocket_ledger/domain/entry.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late LedgerRepository repository;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: LedgerRepository.createSchema));
    repository = LedgerRepository(db);
  });
  tearDown(() => db.close());

  test('CRUD and month boundaries include last day and exclude next month', () async {
    for (final date in ['2026-09-30', '2026-10-01', '2026-10-31', '2026-11-01']) {
      await repository.save(Entry(kind: 'expense', amountMinor: 100, category: 'Food', date: date));
    }
    var report = await repository.month(DateTime(2026, 10));
    expect(report.expenses, 200);
    expect(report.entries.first.date, '2026-10-31');
    final entry = report.entries.first;
    await repository.save(Entry(id: entry.id, kind: 'income', amountMinor: 500,
      category: 'Salary', date: entry.date));
    report = await repository.month(DateTime(2026, 10));
    expect(report.net, 400);
    await repository.delete(entry.id!);
    expect((await repository.month(DateTime(2026, 10))).expenses, 100);
    final history = await repository.history(DateTime(2026, 10));
    expect(history.length, 2);
  });
  test('Backup round trip and failed restore preserve current records', () async {
    await repository.save(Entry(kind: 'income', amountMinor: 12345,
      category: 'Salary', date: '2026-10-30', note: 'Monthly pay'));
    final backup = await repository.backup();
    await repository.restore('{"version":1,"currency":"PKR","entries":[]}');
    expect((await repository.month(DateTime(2026, 10))).entries, isEmpty);
    await repository.restore(backup);
    expect((await repository.month(DateTime(2026, 10))).income, 12345);
    await expectLater(repository.restore('{"version":99}'), throwsFormatException);
    expect((await repository.month(DateTime(2026, 10))).income, 12345);
  });
  test('Balance carries forward through month end', () async {
    await repository.save(Entry(kind: 'income', amountMinor: 100000,
      category: 'Salary', date: '2026-09-15'));
    await repository.save(Entry(kind: 'expense', amountMinor: 20000,
      category: 'Food', date: '2026-09-20'));
    await repository.save(Entry(kind: 'income', amountMinor: 50000,
      category: 'Freelance', date: '2026-10-05'));
    await repository.save(Entry(kind: 'expense', amountMinor: 10000,
      category: 'Bills', date: '2026-10-10'));
    expect(await repository.balanceThrough(DateTime(2026, 9)), 80000);
    expect(await repository.balanceThrough(DateTime(2026, 10)), 120000);
    expect(await repository.balanceThrough(DateTime(2026, 8)), 0);
  });
  test('SQLite rejects invalid money even outside the repository', () async {
    await expectLater(db.rawInsert('INSERT INTO entries(kind,amount_minor,category,date,note) VALUES (?,?,?,?,?)',
      ['expense', -1, 'Food', '2026-10-30', '']), throwsA(isA<DatabaseException>()));
    expect((await repository.month(DateTime(2026, 10))).entries, isEmpty);
  });
}
