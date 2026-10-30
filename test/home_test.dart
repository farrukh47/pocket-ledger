import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/data/ledger_repository.dart';
import 'package:pocket_ledger/domain/entry.dart';
import 'package:pocket_ledger/ui/home.dart';

class ReportRepository extends Fake implements LedgerRepository {
  final MonthReport report;
  final int balance;
  ReportRepository(this.report, {this.balance = 0});
  @override
  Future<MonthReport> month(DateTime month) async => report;
  @override
  Future<List<Map<String, Object?>>> history(DateTime month) async => [];
  @override
  Future<int> balanceThrough(DateTime month) async => balance;
}

void main() {
  testWidgets('Banking home and statement render on a narrow Android viewport', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final repository = ReportRepository(
      MonthReport([
        Entry(kind: 'income', amountMinor: 100000, category: 'Salary', date: dayKey(now)),
      ]),
      balance: 250000,
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Home(repository: repository),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Available balance'), findsOneWidget);
    expect(find.text('2,500.00'), findsOneWidget);
    expect(find.text('Money in'), findsOneWidget);
    expect(find.textContaining('PKR'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Statement'));
    await tester.pumpAndSettle();
    expect(find.text('Account statement'), findsOneWidget);
    expect(find.text('Closing balance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
