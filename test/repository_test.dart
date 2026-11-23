import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/data/db.dart';
import 'package:gymdesk/data/gym_repository.dart';
import 'package:gymdesk/domain/dates.dart';
import 'package:gymdesk/domain/member_view.dart';

void main() {
  late AppDatabase db;
  late GymRepository repo;

  setUp(() async {
    db = AppDatabase.memory();
    repo = GymRepository(db);
    await repo.setupGym(name: 'Iron Temple', currency: 'Rs', monthlyFee: 3000);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  test('gym setup stores the name and creates starter plans', () async {
    expect(await repo.isSetUp(), isTrue);
    expect((await repo.gymInfo()).name, 'Iron Temple');
    final plans = await repo.plans();
    expect(plans.map((p) => p.name), ['Monthly', 'Quarterly', 'Half-yearly', 'Yearly']);
    expect(plans[1].price, 9000);
    expect(plans[1].months, 3);
  });

  test('setup and members validate input', () async {
    expect(() => repo.setupGym(name: ' ', currency: 'Rs', monthlyFee: 1), throwsA(isA<AppError>()));
    expect(() => repo.addMember(name: '', fee: 1, joinedOn: today()), throwsA(isA<AppError>()));
    expect(() => repo.addMember(name: 'A', phone: '12', fee: 1, joinedOn: today()), throwsA(isA<AppError>()));
    expect(() => repo.addMember(name: 'A', fee: -1, joinedOn: today()), throwsA(isA<AppError>()));
  });

  test('a member who paid on joining is due one plan period later', () async {
    final joined = DateTime(2026, 1, 31);
    final id = await repo.addMember(name: 'Ali Khan', phone: '0300 1234567', fee: 3000, joinedOn: joined);
    final m = (await repo.member(id))!;
    expect(m.nextDue, '2026-02-28');
    expect(m.cycleDay, 31);
    final pays = await repo.paymentsFor(id);
    expect(pays, hasLength(1));
    expect(pays.single.amount, 3000);

    // Paying again from the due date keeps the 31st as the fee day.
    await repo.recordPayment(memberId: id, amount: 3000, months: 1);
    expect((await repo.member(id))!.nextDue, '2026-03-31');
  });

  test('an unpaid member is due from the joining date, then payment and undo move the due date', () async {
    final t = today();
    final id = await repo.addMember(name: 'Sara', fee: 3000, joinedOn: t, paidNow: false);
    var view = MemberView((await repo.member(id))!, t);
    expect(view.isDueToday, isTrue);
    expect(view.isDueSoon, isTrue);
    expect(view.isOverdue, isFalse);
    expect(await repo.paymentsFor(id), isEmpty);

    final pay = await repo.recordPayment(memberId: id, amount: 9000, months: 3, note: 'cash');
    view = MemberView((await repo.member(id))!, t);
    expect(view.due, addMonths(t, 3));
    expect(view.isDueSoon, isFalse);
    expect(pay.note, 'cash');

    await repo.undoPayment(pay.id);
    expect((await repo.member(id))!.nextDue, ymd(t));
    expect(await repo.paymentsFor(id), isEmpty);
  });

  test('only the latest payment can be undone', () async {
    final id = await repo.addMember(name: 'Bilal', fee: 100, joinedOn: DateTime(2026, 1, 1));
    final first = (await repo.paymentsFor(id)).single;
    await repo.recordPayment(memberId: id, amount: 100, months: 1);
    expect(() => repo.undoPayment(first.id), throwsA(isA<AppError>()));
  });

  test('overdue members can restart their cycle from today', () async {
    final t = today();
    final joined = addMonths(t, -3);
    final id = await repo.addMember(name: 'Late', fee: 50, joinedOn: joined, paidNow: false);
    final view = MemberView((await repo.member(id))!, t);
    expect(view.isOverdue, isTrue);
    expect(view.daysUntilDue, lessThan(0));

    await repo.recordPayment(memberId: id, amount: 50, months: 1, fromToday: true);
    final m = (await repo.member(id))!;
    expect(m.nextDue, ymd(addMonths(t, 1)));
    expect(m.cycleDay, t.day);
  });

  test('check-in is once per day and can be undone', () async {
    final id = await repo.addMember(name: 'Hamza', fee: 10, joinedOn: today());
    expect(await repo.checkIn(id), isTrue);
    expect(await repo.checkIn(id), isFalse);
    expect(await repo.checkinsOn(today()), hasLength(1));
    expect(await repo.checkinCountFor(id, from: today()), 1);
    final counts = await repo.checkinCountsByDay(addDays(today(), -1), today());
    expect(counts[ymd(today())], 1);

    await repo.undoCheckIn(id, today());
    expect(await repo.checkinsOn(today()), isEmpty);
  });

  test('inactive members cannot check in and are not billable', () async {
    final id = await repo.addMember(name: 'Gone', fee: 10, joinedOn: today(), paidNow: false);
    await repo.setActive(id, false);
    expect(() => repo.checkIn(id), throwsA(isA<AppError>()));
    final view = MemberView((await repo.member(id))!, today());
    expect(view.isInactive, isTrue);
    expect(view.isOverdue || view.isDueSoon, isFalse);
    expect(view.matches(MemberFilter.inactive), isTrue);
    await repo.setActive(id, true);
    expect(await repo.checkIn(id), isTrue);
  });

  test('freezing pauses fees and unfreezing moves the due date by the frozen days', () async {
    final t = today();
    final id = await repo.addMember(name: 'Usman', fee: 10, joinedOn: t);
    final dueBefore = parseYmd((await repo.member(id))!.nextDue);
    await repo.freeze(id, on: addDays(t, -10));
    final frozen = MemberView((await repo.member(id))!, t);
    expect(frozen.isFrozen, isTrue);
    expect(frozen.isBillable, isFalse);
    expect(frozen.matches(MemberFilter.frozen), isTrue);

    final moved = await repo.unfreeze(id, on: t);
    expect(moved, 10);
    final m = (await repo.member(id))!;
    expect(m.frozenSince, isNull);
    expect(m.nextDue, ymd(addDays(dueBefore, 10)));
  });

  test('search matches names and phone digits', () async {
    final id = await repo.addMember(name: 'Zainab Ahmed', phone: '0321-5550000', fee: 10, joinedOn: today());
    final view = MemberView((await repo.member(id))!, today());
    expect(view.matchesQuery('zain'), isTrue);
    expect(view.matchesQuery('AHMED'), isTrue);
    expect(view.matchesQuery('5550'), isTrue);
    expect(view.matchesQuery('12'), isFalse);
    expect(view.matchesQuery('nobody'), isFalse);
  });

  test('revenue counts payments by the date they were paid', () async {
    final id = await repo.addMember(name: 'Payer', fee: 1000, joinedOn: today(), paidNow: false);
    await repo.recordPayment(memberId: id, amount: 1000, months: 1, paidAt: DateTime(2026, 3, 15, 10));
    await repo.recordPayment(memberId: id, amount: 2500, months: 1, paidAt: DateTime(2026, 4, 2, 10));
    final march = await repo.paymentsBetween(DateTime(2026, 3), DateTime(2026, 4));
    expect(march.map((p) => p.amount), [1000]);
  });

  test('deleting a member removes their payments and check-ins', () async {
    final id = await repo.addMember(name: 'Temp', fee: 10, joinedOn: today());
    await repo.checkIn(id);
    await repo.deleteMember(id);
    expect(await repo.member(id), isNull);
    expect(await repo.paymentsFor(id), isEmpty);
    expect(await repo.checkinsOn(today()), isEmpty);
  });

  test('deleting a plan leaves members on a custom fee', () async {
    final plan = (await repo.plans()).first;
    final id = await repo.addMember(name: 'Planned', fee: plan.price, planId: plan.id, joinedOn: today());
    await repo.deletePlan(plan.id);
    final m = (await repo.member(id))!;
    expect(m.planId, isNull);
    expect(m.fee, plan.price);
  });

  test('expenses are saved, listed by month, edited and deleted', () async {
    await repo.saveExpense(category: 'Rent', amount: 25000, day: DateTime(2026, 11, 1), note: 'November');
    await repo.saveExpense(category: 'Electricity', amount: 8000, day: DateTime(2026, 10, 20));
    final nov = await repo.expensesBetween(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    expect(nov.map((e) => e.category), ['Rent']);
    expect(nov.single.amount, 25000);
    await repo.saveExpense(id: nov.single.id, category: 'Rent', amount: 26000, day: DateTime(2026, 11, 2));
    expect((await repo.allExpenses()).first.amount, 26000);
    expect(() => repo.saveExpense(category: 'Rent', amount: 0, day: DateTime(2026, 11, 1)), throwsA(isA<AppError>()));
    await repo.deleteExpense(nov.single.id);
    expect((await repo.allExpenses()).map((e) => e.category), ['Electricity']);
  });
}
