import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../domain/entry.dart';

class LedgerRepository {
  final Database db;
  LedgerRepository(this.db);

  static Future<LedgerRepository> open() async {
    final db = await openDatabase(
      path.join(await getDatabasesPath(), 'pocket_ledger.db'),
      version: 1, onCreate: createSchema,
    );
    return LedgerRepository(db);
  }

  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''CREATE TABLE entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL CHECK(kind IN ('income','expense')),
      amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor) = 'integer'
        AND amount_minor > 0 AND amount_minor <= 999999999999),
      category TEXT NOT NULL,
      date TEXT NOT NULL CHECK(length(date) = 10),
      note TEXT NOT NULL DEFAULT '' CHECK(length(note) <= 300)
    )''');
    await db.execute('CREATE INDEX entries_date ON entries(date DESC, id DESC)');
  }

  Future<MonthReport> month(DateTime month) async {
    final rows = await db.query('entries', where: 'date >= ? AND date < ?',
      whereArgs: [dayKey(DateTime(month.year, month.month)),
        dayKey(DateTime(month.year, month.month + 1))], orderBy: 'date DESC, id DESC');
    return MonthReport(rows.map(Entry.fromMap).toList());
  }

  Future<List<Map<String, Object?>>> history(DateTime month) => db.rawQuery('''
    SELECT substr(date,1,7) AS month,
      SUM(CASE WHEN kind = 'income' THEN amount_minor ELSE 0 END) AS income,
      SUM(CASE WHEN kind = 'expense' THEN amount_minor ELSE 0 END) AS expense
    FROM entries WHERE date >= ? AND date < ?
    GROUP BY substr(date,1,7) ORDER BY month DESC
    ''', [dayKey(DateTime(month.year, month.month - 5)),
      dayKey(DateTime(month.year, month.month + 1))]);

  /// Running ledger balance through the last day of [month] (income − expenses).
  Future<int> balanceThrough(DateTime month) async {
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN kind = 'income' THEN amount_minor ELSE 0 END), 0)
        - COALESCE(SUM(CASE WHEN kind = 'expense' THEN amount_minor ELSE 0 END), 0)
        AS balance
      FROM entries WHERE date < ?
      ''', [dayKey(DateTime(month.year, month.month + 1))]);
    return (rows.first['balance'] as num?)?.toInt() ?? 0;
  }

  Future<void> save(Entry entry) async {
    // Revalidate at the persistence boundary, including calls outside the form.
    final valid = Entry.fromMap(entry.toMap());
    if (valid.id == null) {
      await db.insert('entries', valid.toMap(includeId: false));
    } else {
      final count = await db.update('entries', valid.toMap(includeId: false),
        where: 'id = ?', whereArgs: [valid.id]);
      if (count != 1) throw StateError('Entry no longer exists.');
    }
  }

  Future<void> delete(int id) async {
    if (await db.delete('entries', where: 'id = ?', whereArgs: [id]) != 1) {
      throw StateError('Entry no longer exists.');
    }
  }

  Future<String> backup() async {
    final rows = await db.query('entries', orderBy: 'id');
    final source = jsonEncode({'version': 1, 'currency': 'PKR', 'entries': rows});
    decodeBackup(source);
    return source;
  }

  static List<Entry> decodeBackup(String source) {
    if (utf8.encode(source).length > 5 * 1024 * 1024) {
      throw const FormatException('Backup exceeds 5 MB.');
    }
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> || data.length != 3 ||
        data['version'] is! int || data['version'] != 1 || data['currency'] != 'PKR' ||
        data['entries'] is! List || (data['entries'] as List).length > 20000) {
      throw const FormatException('This is not a supported PKR backup.');
    }
    final ids = <int>{};
    return (data['entries'] as List).map((row) {
      if (row is! Map<String, dynamic>) throw const FormatException('Invalid entry.');
      final entry = Entry.fromMap(row);
      if (entry.id == null || !ids.add(entry.id!)) {
        throw const FormatException('Missing or duplicate entry ID.');
      }
      return entry;
    }).toList();
  }

  Future<void> restore(String source) async {
    final entries = decodeBackup(source);
    await db.transaction((txn) async {
      await txn.delete('entries');
      final batch = txn.batch();
      for (final entry in entries) { batch.insert('entries', entry.toMap()); }
      await batch.commit(noResult: true);
    });
  }
}

String reportCsv(MonthReport report) {
  String cell(String s) {
    if (RegExp(r'^[\s]*[=+@\-\t\r\n]').hasMatch(s)) s = "'$s";
    return '"${s.replaceAll('"', '""')}"';
  }
  final rows = [
    'Date,Type,Category,Amount,Note',
    ...report.entries.map((e) => [cell(e.date), cell(e.kind), cell(e.category),
      decimalAmount(e.amountMinor), cell(e.note)].join(',')),
  ];
  return '\uFEFF${rows.join('\r\n')}\r\n';
}
