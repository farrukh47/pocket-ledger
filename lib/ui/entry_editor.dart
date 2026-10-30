import 'package:flutter/material.dart';
import '../domain/entry.dart';
import '../data/ledger_repository.dart';

class EntryEditor extends StatefulWidget {
  final LedgerRepository repository;
  final Entry? entry;
  const EntryEditor({super.key, required this.repository, this.entry});
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _kind;
  late String _category;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _kind = e?.kind ?? 'expense';
    _category = e?.category ?? expenseCategories.first;
    _date = e == null ? DateTime.now() : parseDay(e.date);
    _amount = TextEditingController(text: e == null ? '' : decimalAmount(e.amountMinor));
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(Entry(
        id: widget.entry?.id,
        kind: _kind,
        amountMinor: parseAmount(_amount.text),
        category: _category,
        date: dayKey(_date),
        note: _note.text.trim(),
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Could not save this entry. Your input is still here. Please try again.';
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = _kind == 'expense';
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry == null ? 'Add transaction' : 'Edit transaction'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'expense',
                        label: Text('Money out'),
                        icon: Icon(Icons.arrow_upward_rounded),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text('Money in'),
                        icon: Icon(Icons.arrow_downward_rounded),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: _saving
                        ? null
                        : (values) => setState(() {
                              _kind = values.first;
                              _category = categoriesFor(_kind).first;
                            }),
                  ),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: _amount,
                    enabled: !_saving,
                    autofocus: widget.entry == null,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    maxLength: 13,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: isExpense
                          ? const Color(0xFFC0392B)
                          : const Color(0xFF0F7A4E),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      helperText: 'Example: 1250.50',
                      counterText: '',
                    ),
                    validator: (value) {
                      try {
                        parseAmount(value ?? '');
                        return null;
                      } on FormatException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    key: ValueKey('$_kind/$_category'),
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categoriesFor(_kind)
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: _saving ? null : (s) => setState(() => _category = s!),
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _saving ? null : _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFD5E0DD)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 20,
                              color: Color(0xFF0F766E),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Date',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7C78),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dayKey(_date),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF6B7C78),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _note,
                    enabled: !_saving,
                    maxLength: 300,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'What was this for?',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(18),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Saving…' : 'Save transaction'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
