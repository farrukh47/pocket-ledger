import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/entry.dart';
import '../data/app_update.dart';
import '../data/ledger_repository.dart';
import '../data/document_service.dart';
import 'entry_editor.dart';

const _income = Color(0xFF0F7A4E);
const _expense = Color(0xFFC0392B);
const _ink = Color(0xFF14212B);
const _muted = Color(0xFF6B7C78);
const _teal = Color(0xFF0F766E);
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
String monthLabel(DateTime date) => '${_months[date.month - 1]} ${date.year}';

class _ViewData {
  final MonthReport report;
  final List<Map<String, Object?>> history;
  final int balance;
  _ViewData(this.report, this.history, this.balance);
}

class Home extends StatefulWidget {
  final LedgerRepository repository;
  const Home({super.key, required this.repository});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _tab = 0;
  String _filter = 'all';
  bool _working = false;
  String _version = '';
  late Future<_ViewData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final label = await AppUpdate.currentVersionLabel();
      if (mounted) setState(() => _version = label);
    } catch (_) {
      // Keep the UI usable if version lookup fails.
    }
  }

  Future<_ViewData> _load() async {
    final month = _month;
    final report = await widget.repository.month(month);
    final history = await widget.repository.history(month);
    final balance = await widget.repository.balanceThrough(month);
    return _ViewData(report, history, balance);
  }

  void _refresh() {
    if (mounted) setState(() => _data = _load());
  }

  void _changeMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    if (next.year < 2000 || next.year > 2100) return;
    setState(() {
      _month = next;
      _data = _load();
    });
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _edit([Entry? entry]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EntryEditor(repository: widget.repository, entry: entry),
      ),
    );
    if (changed == true && mounted) {
      _refresh();
      _message('Transaction saved.');
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _delete(Entry e) async {
    if (_working ||
        !await _confirm(
          'Delete transaction?',
          '${e.category} · ${money(e.amountMinor)}\nThis entry will be permanently removed.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _working = true);
    try {
      await widget.repository.delete(e.id!);
      _refresh();
      _message('Transaction deleted.');
    } catch (_) {
      _message('Could not delete. Please try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _menu(String action) async {
    if (action == 'update') {
      await _checkUpdate();
      return;
    }
    await _documents(action);
  }

  Future<void> _checkUpdate() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final current = await AppUpdate.currentVersionLabel();
      final update = await AppUpdate.check();
      if (!mounted) return;
      if (update == null) {
        _message('You are on the latest version ($current).');
        return;
      }
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Update ${update.label}'),
          content: Text(
            'A newer build is available.\n\n'
            'Current: $current\n'
            'Latest: ${update.label}\n\n'
            'Download and install now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Downloading update'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 14),
                Text('Please keep the app open…'),
              ],
            ),
          ),
        ),
      );

      try {
        final apk = await AppUpdate.download(update);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        _message('Opening installer for ${update.label}…');
        await AppUpdate.install(apk);
      } catch (_) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        rethrow;
      }
    } on FormatException catch (e) {
      _message(e.message);
    } on PlatformException catch (e) {
      _message(e.message ?? 'Could not install the update.');
    } catch (_) {
      _message('Update check failed. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _documents(String action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (action == 'restore') {
        final content = await DocumentService.openBackup();
        if (content == null || !mounted) return;
        final entries = LedgerRepository.decodeBackup(content);
        if (!await _confirm(
          'Replace your ledger?',
          'Restore ${entries.length} transactions from this backup? This replaces all current entries. Save a backup first if you need them.',
        )) {
          return;
        }
        await widget.repository.restore(content);
        _refresh();
        _message('Backup restored.');
      } else {
        final csv = action == 'csv';
        final content = csv
            ? reportCsv(await widget.repository.month(_month))
            : await widget.repository.backup();
        final saved = await DocumentService.save(
          csv
              ? 'pocket-ledger-${dayKey(_month).substring(0, 7)}.csv'
              : 'pocket-ledger-backup.json',
          content,
          csv ? 'text/csv' : 'application/json',
        );
        if (saved) _message(csv ? 'Statement exported.' : 'Backup saved.');
      }
    } on FormatException catch (e) {
      _message(
        action == 'restore'
            ? 'Invalid backup. Your current data has not been changed.'
            : e.message,
      );
    } catch (_) {
      _message('File operation failed. Please try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pickMonth() async {
    var year = _month.year;
    var month = _month.month;
    final value = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Choose month'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: year,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Year'),
                items: List.generate(
                  101,
                  (i) => DropdownMenuItem(
                    value: 2000 + i,
                    child: Text('${2000 + i}'),
                  ),
                ),
                onChanged: (v) => update(() => year = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: month,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Month'),
                items: List.generate(
                  12,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text(_months[i]),
                  ),
                ),
                onChanged: (v) => update(() => month = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, DateTime(year, month)),
              child: const Text('View month'),
            ),
          ],
        ),
      ),
    );
    if (value != null && mounted) {
      setState(() {
        _month = value;
        _data = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pocket Ledger'),
          if (_version.isNotEmpty)
            Text(
              'v$_version',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _muted,
                letterSpacing: 0,
              ),
            ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          enabled: !_working,
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: _menu,
          itemBuilder: (_) => [
            if (_version.isNotEmpty)
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  'Version $_version',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ),
            const PopupMenuItem(value: 'update', child: Text('Check for updates')),
            const PopupMenuItem(value: 'csv', child: Text('Export statement (CSV)')),
            const PopupMenuItem(value: 'backup', child: Text('Save full backup')),
            const PopupMenuItem(value: 'restore', child: Text('Restore backup')),
          ],
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (v) => setState(() => _tab = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'Activity',
        ),
        NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights_rounded),
          label: 'Statement',
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _working ? null : () => _edit(),
      icon: const Icon(Icons.add_rounded),
      label: const Text('New'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2EAE7)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _pickMonth,
                      child: Text(
                        monthLabel(_month),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (_working) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: FutureBuilder<_ViewData>(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load your account.'),
                        TextButton(onPressed: _refresh, child: const Text('Retry')),
                      ],
                    ),
                  );
                }
                final data = snapshot.data!;
                if (_tab == 1) return _activity(data.report);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: _tab == 0 ? _home(data) : _statement(data),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _home(_ViewData data) {
    final report = data.report;
    final closing = DateTime(_month.year, _month.month + 1, 0);
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F766E), Color(0xFF134E4A), Color(0xFF0B2530)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _teal.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Available balance',
                    style: TextStyle(
                      color: Color(0xFFB6DED6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    data.balance >= 0 ? 'In credit' : 'Overdrawn',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(data.balance),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.8,
                  height: 1.05,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'As of ${dayKey(closing)} · all income minus expenses',
              style: const TextStyle(color: Color(0xFF8FBFB6), fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _flowCard(
              'Money in',
              money(report.income),
              _income,
              Icons.arrow_downward_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _flowCard(
              'Money out',
              money(report.expenses),
              _expense,
              Icons.arrow_upward_rounded,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _panel(
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This month net',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money(report.net),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: report.net >= 0 ? _income : _expense,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F3F1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${report.entries.length} txn${report.entries.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: _teal,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      _sectionTitle('Spending this month'),
      _panel(_DailyChart(report: report, month: _month)),
      const SizedBox(height: 28),
      Row(
        children: [
          Expanded(child: _sectionTitle('Recent activity')),
          TextButton(
            onPressed: () => setState(() => _tab = 1),
            child: const Text('See all'),
          ),
        ],
      ),
      if (report.entries.isEmpty)
        _empty(
          'No activity yet',
          'Add your first income or expense to open this month’s statement.',
        )
      else
        ...report.entries.take(6).map(_entryTile),
    ];
  }

  Widget _flowCard(String label, String value, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2EAE7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _activity(MonthReport report) {
    final rows =
        report.entries.where((e) => _filter == 'all' || e.kind == _filter).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'income', label: Text('In')),
              ButtonSegment(value: 'expense', label: Text('Out')),
            ],
            selected: {_filter},
            onSelectionChanged: (v) => setState(() => _filter = v.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${rows.length} transactions',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? _empty('No transactions', 'Add an entry or choose another month.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _entryTile(rows[i]),
                ),
        ),
      ],
    );
  }

  Widget _entryTile(Entry e) {
    final incoming = e.kind == 'income';
    final color = incoming ? _income : _expense;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _working ? null : () => _edit(e),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2EAE7)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    incoming
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.category,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.date + (e.note.isEmpty ? '' : ' · ${e.note}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${incoming ? '+' : '−'}${money(e.amountMinor)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Transaction actions',
                  enabled: !_working,
                  onSelected: (v) {
                    if (v == 'edit') {
                      _edit(e);
                    } else {
                      _delete(e);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _statement(_ViewData data) {
    final report = data.report;
    final categories = report.categories;
    final opening = data.balance - report.net;
    return [
      _sectionTitle('Account statement'),
      _panel(
        Column(
          children: [
            _statementRow('Opening balance', money(opening), _ink),
            _statementRow('Money in', money(report.income), _income),
            _statementRow('Money out', money(report.expenses), _expense),
            const Divider(height: 24),
            _statementRow(
              'Closing balance',
              money(data.balance),
              data.balance >= 0 ? _income : _expense,
              emphasize: true,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${report.entries.length} transactions in ${monthLabel(_month)}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      _sectionTitle('Spending by category'),
      if (categories.isEmpty)
        _empty(
          'No spending this month',
          'Expense categories appear once you record money out.',
        )
      else
        _panel(
          Column(
            children: [
              for (final e in categories.entries) ...[
                _categoryBar(e.key, e.value, report.expenses),
                if (e.key != categories.keys.last) const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      const SizedBox(height: 28),
      _sectionTitle('Six-month overview'),
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'Cash flow ending in the selected month.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
      ),
      ...List.generate(6, (i) {
        final date = DateTime(_month.year, _month.month - i);
        final key = dayKey(date).substring(0, 7);
        final matching = data.history.where((row) => row['month'] == key);
        final row = matching.isEmpty ? null : matching.first;
        final income = (row?['income'] as num?)?.toInt() ?? 0;
        final expense = (row?['expense'] as num?)?.toInt() ?? 0;
        final net = income - expense;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        monthLabel(date),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                    Text(
                      money(net),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: net >= 0 ? _income : _expense,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'In  ${money(income)}',
                        style: const TextStyle(color: _income, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Out  ${money(expense)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: _expense, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _working ? null : () => _documents('csv'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Color(0xFFD5E0DD)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.download_outlined),
        label: const Text('Export statement'),
      ),
    ];
  }

  Widget _categoryBar(String name, int amount, int total) {
    final share = total == 0 ? 0.0 : amount / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600, color: _ink),
              ),
            ),
            Text(
              money(amount),
              style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '$name: ${(share * 100).toStringAsFixed(1)} percent of spending',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 8,
              backgroundColor: const Color(0xFFE7EEEC),
              color: _teal,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(share * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ),
      ],
    );
  }

  Widget _panel(Widget child) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2EAE7)),
        ),
        child: child,
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
            letterSpacing: -0.2,
          ),
        ),
      );

  Widget _statementRow(
    String label,
    String value,
    Color color, {
    bool emphasize = false,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: emphasize ? _ink : _muted,
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: emphasize ? 17 : 15,
              ),
            ),
          ],
        ),
      );

  Widget _empty(String title, String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.account_balance_outlined,
                size: 28,
                color: _teal,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.4),
            ),
          ],
        ),
      );
}

class _DailyChart extends StatelessWidget {
  final MonthReport report;
  final DateTime month;
  const _DailyChart({required this.report, required this.month});

  @override
  Widget build(BuildContext context) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final values = List.generate(days, (i) => report.spentOnDay(i + 1));
    final peak = values.fold<int>(1, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Highest day  ${money(values.fold<int>(0, math.max))}',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 108,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(
              days,
              (i) => Expanded(
                child: Tooltip(
                  message:
                      '${dayKey(DateTime(month.year, month.month, i + 1))}: ${money(values[i])}',
                  child: Semantics(
                    label: 'Day ${i + 1}: ${money(values[i])}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        height: math.max(3.0, values[i] / peak * 100),
                        decoration: BoxDecoration(
                          gradient: values[i] == 0
                              ? null
                              : const LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Color(0xFF0F766E), Color(0xFF2DD4A8)],
                                ),
                          color: values[i] == 0 ? const Color(0xFFE7EEEC) : null,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('1', style: TextStyle(fontSize: 11, color: _muted)),
            const Text('Day of month', style: TextStyle(fontSize: 11, color: _muted)),
            Text('$days', style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      ],
    );
  }
}
