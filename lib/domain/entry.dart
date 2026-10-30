const maxAmountMinor = 999999999999;
const incomeCategories = ['Salary', 'Freelance', 'Business', 'Gift', 'Other income'];
const expenseCategories = [
  'Food', 'Groceries', 'Transport', 'Bills', 'Shopping', 'Health',
  'Family', 'Education', 'Home', 'Other expense',
];

List<String> categoriesFor(String kind) =>
    kind == 'income' ? incomeCategories : expenseCategories;

int parseAmount(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Enter an amount with up to 2 decimal places.');
  }
  final parts = value.split('.');
  final minor = int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if (minor <= 0 || minor > maxAmountMinor) {
    throw const FormatException('Amount must be between 0.01 and 9,999,999,999.99.');
  }
  return minor;
}

String decimalAmount(int minor) =>
    '${minor ~/ 100}.${(minor.abs() % 100).toString().padLeft(2, '0')}';

String money(int minor) {
  final whole = (minor.abs() ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${minor < 0 ? '-' : ''}$whole.${(minor.abs() % 100).toString().padLeft(2, '0')}';
}

String dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

DateTime parseDay(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid date.');
  }
  final day = DateTime.tryParse(value);
  if (day == null || dayKey(day) != value || day.year < 2000 || day.year > 2100) {
    throw const FormatException('Date must be between 2000 and 2100.');
  }
  return day;
}

class Entry {
  final int? id;
  final String kind;
  final int amountMinor;
  final String category;
  final String date;
  final String note;

  Entry({this.id, required this.kind, required this.amountMinor,
    required this.category, required this.date, this.note = ''}) {
    if (kind != 'income' && kind != 'expense') {
      throw const FormatException('Invalid transaction type.');
    }
    if (amountMinor <= 0 || amountMinor > maxAmountMinor) {
      throw const FormatException('Invalid amount.');
    }
    if (!categoriesFor(kind).contains(category)) {
      throw const FormatException('Invalid category for this type.');
    }
    parseDay(date);
    if (note.length > 300 || note.contains('\u0000')) {
      throw const FormatException('Notes must be 300 characters or fewer.');
    }
    if (id != null && id! <= 0) throw const FormatException('Invalid entry ID.');
  }

  Map<String, Object?> toMap({bool includeId = true}) => {
    if (includeId && id != null) 'id': id,
    'kind': kind, 'amount_minor': amountMinor,
    'category': category, 'date': date, 'note': note,
  };

  factory Entry.fromMap(Map<String, Object?> row) {
    const keys = {'id', 'kind', 'amount_minor', 'category', 'date', 'note'};
    if (row.keys.any((key) => !keys.contains(key)) ||
        (row['id'] != null && row['id'] is! int) ||
        row['kind'] is! String || row['amount_minor'] is! int ||
        row['category'] is! String || row['date'] is! String || row['note'] is! String) {
      throw const FormatException('Invalid entry data.');
    }
    return Entry(id: row['id'] as int?, kind: row['kind'] as String,
      amountMinor: row['amount_minor'] as int, category: row['category'] as String,
      date: row['date'] as String, note: row['note'] as String);
  }
}

class MonthReport {
  final List<Entry> entries;
  MonthReport(List<Entry> values) : entries = List.unmodifiable(values);
  int get income => entries.where((e) => e.kind == 'income')
      .fold(0, (sum, e) => sum + e.amountMinor);
  int get expenses => entries.where((e) => e.kind == 'expense')
      .fold(0, (sum, e) => sum + e.amountMinor);
  int get net => income - expenses;
  Map<String, int> get categories {
    final totals = <String, int>{};
    for (final e in entries.where((e) => e.kind == 'expense')) {
      totals.update(e.category, (v) => v + e.amountMinor, ifAbsent: () => e.amountMinor);
    }
    return Map.fromEntries(totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
  int spentOnDay(int day) => entries.where((e) =>
    e.kind == 'expense' && parseDay(e.date).day == day)
      .fold(0, (sum, e) => sum + e.amountMinor);
}
