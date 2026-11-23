import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/data/db.dart';
import 'package:gymdesk/domain/dates.dart';
import 'package:gymdesk/domain/member_view.dart';
import 'package:gymdesk/services/reminders.dart';

MemberView _member(String name, DateTime due, DateTime now, {String status = 'active', String? frozen}) => MemberView(
      Member(
        id: name,
        name: name,
        phone: '',
        notes: '',
        fee: 1000,
        planMonths: 1,
        joinedOn: '2026-01-01',
        cycleDay: due.day,
        nextDue: ymd(due),
        status: status,
        frozenSince: frozen,
        createdAt: now,
        updatedAt: now,
      ),
      now,
    );

void main() {
  final now = DateTime(2026, 11, 17, 8, 0);
  const nine = TimeOfDay(hour: 9, minute: 0);

  List<PlannedReminder> plan(List<MemberView> members, {DateTime? at, bool backups = false, DateTime? lastBackup}) => planReminders(
        members: members,
        now: at ?? now,
        time: nine,
        fees: true,
        backups: backups,
        lastBackup: lastBackup,
        backupEveryDays: 7,
      );

  test('a member due in 3 days triggers a reminder on that day, then overdue reminders', () {
    final r = plan([_member('Ali', DateTime(2026, 11, 20), now)]);
    expect(r.first.when, DateTime(2026, 11, 20, 9));
    expect(r.first.title, '1 fee due today');
    expect(r.first.body, contains('Ali'));
    expect(r[1].when, DateTime(2026, 11, 21, 9));
    expect(r[1].title, '1 overdue fee');
    // Every following day until the horizon keeps reminding.
    expect(r.length, reminderHorizonDays - 3);
  });

  test("today's reminder is skipped once the reminder time has passed", () {
    final members = [_member('Ali', DateTime(2026, 11, 17), now)];
    expect(plan(members).first.when, DateTime(2026, 11, 17, 9));
    expect(plan(members, at: DateTime(2026, 11, 17, 10)).first.when, DateTime(2026, 11, 18, 9));
  });

  test('frozen and inactive members do not create fee reminders', () {
    final r = plan([
      _member('Frozen', DateTime(2026, 11, 1), now, frozen: '2026-10-01'),
      _member('Left', DateTime(2026, 11, 1), now, status: 'inactive'),
    ]);
    expect(r, isEmpty);
  });

  test('several members are summarised in one notification', () {
    final day = DateTime(2026, 11, 18);
    final r = plan([for (final n in ['A', 'B', 'C', 'D', 'E']) _member(n, day, now), _member('Late', DateTime(2026, 11, 1), now)]);
    final first = r.first;
    expect(first.when, DateTime(2026, 11, 17, 9));
    expect(first.title, '1 overdue fee');
    final second = r[1];
    expect(second.title, '5 fees due today');
    expect(second.body, contains('+2 more'));
    expect(second.body, contains('Overdue: Late'));
  });

  test('backup reminders start when the last backup is a week old and repeat every 3 days', () {
    final r = plan(
      [_member('Ali', DateTime(2027, 6, 1), now)],
      backups: true,
      lastBackup: DateTime(2026, 11, 15),
    );
    final backups = r.where((x) => x.title == 'Time to back up').map((x) => x.when).toList();
    expect(backups.take(3), [DateTime(2026, 11, 22, 9), DateTime(2026, 11, 25, 9), DateTime(2026, 11, 28, 9)]);
  });

  test('no backup reminders without members', () {
    expect(plan([], backups: true), isEmpty);
  });
}
