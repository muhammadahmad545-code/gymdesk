import 'package:basalt/basalt.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_services.dart';
import '../data/db.dart';
import '../data/gym_repository.dart';
import '../domain/dates.dart';
import '../domain/member_view.dart';
import '../services/csv_export.dart';
import 'common.dart';
import 'expenses_screen.dart';
import 'live.dart';

class _Stats {
  _Stats({required this.members, required this.months, required this.revenue, required this.days, required this.visits, required this.spent});

  final List<MemberView> members;

  /// First day of each of the last 6 months, oldest first, with revenue collected in that month.
  final List<DateTime> months;
  final List<double> revenue;

  /// Expenses in the same months.
  final List<double> spent;

  /// The last 14 days, oldest first, with check-ins per day.
  final List<DateTime> days;
  final List<int> visits;

  int count(MemberFilter f) => members.where((m) => m.matches(f)).length;
  int get newThisMonth {
    final start = DateTime(months.last.year, months.last.month);
    return members.where((m) => !(tryParseYmd(m.member.joinedOn) ?? DateTime(1970)).isBefore(start)).length;
  }
}

/// Monthly revenue, attendance trend and member counts, computed straight from payments and
/// check-ins.
Future<_Stats> _loadStats(GymRepository repo, DateTime now) async {
  final t = dateOnly(now);
  final months = [for (var i = 5; i >= 0; i--) DateTime(t.year, t.month - i)];
  final payments = await repo.paymentsBetween(months.first, DateTime(t.year, t.month + 1));
  final revenue = [
    for (final m in months)
      payments
          .where((p) => p.paidAt.year == m.year && p.paidAt.month == m.month)
          .fold<double>(0, (sum, p) => sum + p.amount),
  ];
  final expenses = await repo.expensesBetween(months.first, addDays(DateTime(t.year, t.month + 1), -1));
  final spent = [
    for (final m in months)
      expenses.where((e) => parseYmd(e.day).year == m.year && parseYmd(e.day).month == m.month).fold<double>(0, (sum, e) => sum + e.amount),
  ];
  final days = [for (var i = 13; i >= 0; i--) addDays(t, -i)];
  final counts = await repo.checkinCountsByDay(days.first, days.last);
  return _Stats(
    members: [for (final m in await repo.members()) MemberView(m, now)],
    months: months,
    revenue: revenue,
    spent: spent,
    days: days,
    visits: [for (final d in days) counts[ymd(d)] ?? 0],
  );
}

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = context.basalt;
    return Live<_Stats>(
      load: (repo) => _loadStats(repo, DateTime.now()),
      builder: (context, s) {
        final thisMonth = s.revenue.last;
        final lastMonth = s.revenue[s.revenue.length - 2];
        final totalVisits = s.visits.fold<int>(0, (a, b) => a + b);
        return BPage(
          title: 'Analytics',
          children: [
            Row(
              children: [
                Expanded(child: BStatTile(label: 'Active', value: '${s.count(MemberFilter.active)}', hint: 'members', icon: Icons.people_rounded, color: p.accent)),
                const SizedBox(width: Gap.md),
                Expanded(child: BStatTile(label: 'Joined', value: '${s.newThisMonth}', hint: 'this month', icon: Icons.person_add_alt_1_rounded, color: p.accent)),
              ],
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Expanded(
                  child: BStatTile(
                    label: 'Collected',
                    value: app.money(thisMonth),
                    icon: Icons.payments_outlined,
                    color: p.success,
                    hint: 'this month · last ${app.money(lastMonth)}',
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: BStatTile(
                    label: 'Visits',
                    value: '$totalVisits',
                    icon: Icons.how_to_reg_rounded,
                    color: p.accent,
                    hint: '14 days · ${(totalVisits / 14).toStringAsFixed(1)}/day',
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            BCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExpensesScreen())),
              semanticLabel: 'Profit this month. Open expenses',
              child: Row(
                children: [
                  BIconTile(thisMonth - s.spent.last >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      color: thisMonth - s.spent.last >= 0 ? p.success : p.danger),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(thisMonth - s.spent.last >= 0 ? 'Profit this month' : 'Loss this month', style: BasaltType.label.copyWith(color: p.textMuted)),
                        Text(app.money((thisMonth - s.spent.last).abs()), style: BasaltType.title.copyWith(color: p.text)),
                        Text('Collected ${app.money(thisMonth)} · spent ${app.money(s.spent.last)}', style: BasaltType.caption.copyWith(color: p.textFaint)),
                      ],
                    ),
                  ),
                  Text('Expenses', style: BasaltType.label.copyWith(color: p.accent)),
                  Icon(Icons.chevron_right_rounded, color: p.textFaint),
                ],
              ),
            ),
            const BSectionTitle('Revenue by month'),
            BCard(
              child: s.revenue.every((v) => v == 0)
                  ? Text('No payments in the last 6 months yet.', style: BasaltType.body.copyWith(color: p.textMuted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.money(s.revenue.fold(0.0, (a, b) => a + b)), style: BasaltType.title.copyWith(color: p.text)),
                        Text('Collected in the last 6 months', style: BasaltType.caption.copyWith(color: p.textMuted)),
                        const SizedBox(height: Gap.lg),
                        BBars(
                          values: s.revenue,
                          labels: [for (final m in s.months) DateFormat('MMM').format(m)],
                          highlight: s.revenue.length - 1,
                        ),
                      ],
                    ),
            ),
            const BSectionTitle('Check-ins, last 14 days'),
            BCard(
              child: totalVisits == 0
                  ? Text('No check-ins in the last 14 days.', style: BasaltType.body.copyWith(color: p.textMuted))
                  : BBars(
                      values: [for (final v in s.visits) v.toDouble()],
                      labels: [for (final d in s.days) '${d.day}'],
                      highlight: s.visits.length - 1,
                    ),
            ),
            const BSectionTitle('Members'),
            BCard(
              child: Column(
                children: [
                  InfoLine('Active', '${s.count(MemberFilter.active)}'),
                  InfoLine('Due this week', '${s.count(MemberFilter.due)}', valueColor: p.warning),
                  InfoLine('Overdue', '${s.count(MemberFilter.overdue)}', valueColor: p.danger),
                  InfoLine('Frozen', '${s.count(MemberFilter.frozen)}'),
                  InfoLine('Inactive', '${s.count(MemberFilter.inactive)}'),
                ],
              ),
            ),
            BGroup(
              title: 'Export',
              children: [
                BListRow(
                  icon: Icons.table_view_outlined,
                  title: 'Export members (CSV)',
                  subtitle: 'Names, phones, plans and due dates',
                  chevron: true,
                  onTap: () => attempt(context, () async {
                    final plans = {for (final pl in await app.repo.plans()) pl.id: pl.name};
                    final members = [for (final m in await app.repo.members()) MemberView(m, DateTime.now())];
                    await CsvExport.share('gymdesk-members-${ymd(DateTime.now())}.csv', CsvExport.members(members, plans));
                  }),
                ),
                BListRow(
                  icon: Icons.receipt_long_outlined,
                  title: 'Export payments (CSV)',
                  subtitle: 'Every payment with dates and amounts',
                  chevron: true,
                  onTap: () => attempt(context, () async {
                    final names = {for (final m in await app.repo.members()) m.id: m.name};
                    final List<Payment> pays = await app.repo.allPayments();
                    await CsvExport.share('gymdesk-payments-${ymd(DateTime.now())}.csv', CsvExport.payments(pays, names));
                  }),
                ),
                BListRow(
                  icon: Icons.receipt_outlined,
                  title: 'Export expenses (CSV)',
                  subtitle: 'Every expense with category and date',
                  chevron: true,
                  onTap: () => attempt(context, () async {
                    await CsvExport.share('gymdesk-expenses-${ymd(DateTime.now())}.csv', CsvExport.expenses(await app.repo.allExpenses()));
                  }),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
