import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';
import '../data/db.dart';
import '../data/gym_repository.dart';
import '../domain/dates.dart';
import '../domain/member_view.dart';
import 'common.dart';
import 'live.dart';

IconData expenseIcon(String category) => switch (category) {
      'Rent' => Icons.home_work_outlined,
      'Electricity' => Icons.bolt_rounded,
      'Salaries' => Icons.badge_outlined,
      'Equipment' => Icons.fitness_center_rounded,
      'Maintenance' => Icons.build_outlined,
      'Supplies' => Icons.inventory_2_outlined,
      _ => Icons.receipt_outlined,
    };

class _Month {
  _Month(this.expenses, this.collected);
  final List<Expense> expenses;
  final double collected;
  double get spent => expenses.fold(0, (a, e) => a + e.amount);
}

/// What the gym spends each month, and the profit left after fees collected.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<_Month> _load(GymRepository repo) async {
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1);
    final expenses = await repo.expensesBetween(from, addDays(to, -1));
    final payments = await repo.paymentsBetween(from, to);
    return _Month(expenses, payments.fold<double>(0, (a, p) => a + p.amount));
  }

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.basalt;
    final isCurrent = _month.year == DateTime.now().year && _month.month == DateTime.now().month;
    return Live<_Month>(
      deps: _month,
      load: _load,
      builder: (context, m) {
        final profit = m.collected - m.spent;
        return SubPage(
          title: 'Expenses',
          bottom: BButton(label: 'Add expense', icon: Icons.add_rounded, expand: true, onPressed: () => showExpenseSheet(context)),
          children: [
            Row(
              children: [
                IconButton(tooltip: 'Previous month', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: BasaltType.heading.copyWith(color: p.text),
                  ),
                ),
                IconButton(tooltip: 'Next month', onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(child: BStatTile(label: 'Collected', value: app.money(m.collected), icon: Icons.payments_outlined, color: p.success)),
                const SizedBox(width: Gap.md),
                Expanded(child: BStatTile(label: 'Spent', value: app.money(m.spent), icon: Icons.receipt_long_outlined, color: p.danger)),
              ],
            ),
            const SizedBox(height: Gap.md),
            BCard(
              borderColor: profit >= 0 ? p.success.withValues(alpha: 0.5) : p.danger.withValues(alpha: 0.5),
              child: Row(
                children: [
                  BIconTile(profit >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: profit >= 0 ? p.success : p.danger),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profit >= 0 ? 'Profit' : 'Loss', style: BasaltType.label.copyWith(color: p.textMuted)),
                        Text(app.money(profit.abs()), style: BasaltType.title.copyWith(color: p.text)),
                      ],
                    ),
                  ),
                  Text('fees − expenses', style: BasaltType.caption.copyWith(color: p.textFaint)),
                ],
              ),
            ),
            BSectionTitle('${m.expenses.length} expense${m.expenses.length == 1 ? '' : 's'}'),
            if (m.expenses.isEmpty)
              const BEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No expenses this month',
                message: 'Add rent, electricity, salaries or equipment to see the gym’s real profit.',
              )
            else
              BGroup(
                children: [
                  for (final e in m.expenses)
                    BListRow(
                      icon: expenseIcon(e.category),
                      iconColor: p.danger,
                      title: e.category,
                      subtitle: [shortDate(parseYmd(e.day)), if (e.note.isNotEmpty) e.note].join(' · '),
                      trailing: Text('−${app.money(e.amount)}', style: BasaltType.bodyStrong.copyWith(color: p.text)),
                      onTap: () => showExpenseSheet(context, existing: e),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

Future<void> showExpenseSheet(BuildContext context, {Expense? existing}) =>
    showSheet<void>(context, title: existing == null ? 'Add expense' : 'Edit expense', builder: (_) => _ExpenseForm(existing: existing));

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({this.existing});
  final Expense? existing;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  late String _category = widget.existing?.category ?? 'Rent';
  late final _amount = TextEditingController(text: widget.existing == null ? '' : amountText(widget.existing!.amount));
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _day = widget.existing == null ? today() : parseYmd(widget.existing!.day);
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      BToast.show(context, 'Enter an amount above zero.');
      return;
    }
    setState(() => _busy = true);
    final ok = await attempt(context, () async {
      await context.app.repo.saveExpense(id: widget.existing?.id, category: _category, amount: amount, day: _day, note: _note.text);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) {
      Navigator.pop(context);
      BToast.show(context, widget.existing == null ? 'Expense added' : 'Expense updated');
    }
  }

  Future<void> _delete() async {
    final e = widget.existing!;
    if (!await bConfirm(context, title: 'Delete this expense?', message: '${e.category}, ${context.app.money(e.amount)}', confirmLabel: 'Delete', danger: true)) return;
    if (!mounted) return;
    await attempt(context, () => context.app.repo.deleteExpense(e.id));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2015),
      lastDate: today(),
    );
    if (picked != null) setState(() => _day = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final c in GymRepository.expenseCategories)
              BChip(label: c, icon: expenseIcon(c), selected: _category == c, onTap: () => setState(() => _category = c)),
          ],
        ),
        const SizedBox(height: Gap.lg),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: 'Amount', prefixText: '${context.app.gym.value.currency} '),
        ),
        const SizedBox(height: Gap.md),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)'), maxLength: 80),
        BListRow(
          icon: Icons.event_outlined,
          title: 'Date',
          subtitle: DateFormat('EEEE, d MMMM yyyy').format(_day),
          chevron: true,
          onTap: _pickDay,
        ),
        const SizedBox(height: Gap.md),
        BButton(label: widget.existing == null ? 'Save expense' : 'Save changes', busy: _busy, expand: true, onPressed: _save),
        if (widget.existing != null) ...[
          const SizedBox(height: Gap.sm),
          BButton(label: 'Delete', variant: BButtonVariant.ghost, onPressed: _delete),
        ],
      ],
    );
  }
}
