import 'dart:async';

import 'package:drift/drift.dart';

import '../domain/dates.dart';
import 'db.dart';
import 'ids.dart';
import 'legacy_migration.dart';

class AppError implements Exception {
  const AppError(this.message);
  final String message;
  @override
  String toString() => message;
}

class GymInfo {
  const GymInfo({required this.name, required this.currency, required this.countryCode});
  final String name;
  final String currency;

  /// Dialling code used to turn local numbers (0300…) into WhatsApp numbers (92300…).
  final String countryCode;
}

/// All reads and writes of gym data. Screens reload when [changes] fires.
class GymRepository {
  GymRepository(this._db) {
    _listen();
  }

  AppDatabase _db;
  AppDatabase get db => _db;
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<void>? _sub;

  /// Fires after any table changes (and after a restore swaps the database).
  Stream<void> get changes => _changes.stream;

  void _listen() {
    _sub?.cancel();
    _sub = _db.tableUpdates(TableUpdateQuery.any()).listen((_) => _changes.add(null));
  }

  /// Points the repository at a freshly opened database (after a restore).
  void replaceDatabase(AppDatabase db) {
    _db = db;
    _listen();
    _changes.add(null);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _changes.close();
  }

  // ---------------------------------------------------------------- settings

  static const kGymName = 'gym.name';
  static const kCurrency = 'gym.currency';
  static const kCountryCode = 'gym.countryCode';

  Future<String?> getKv(String key) async =>
      (await (_db.select(_db.kv)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setKv(String key, String value) =>
      _db.into(_db.kv).insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));

  Future<GymInfo> gymInfo() async {
    final rows = await _db.select(_db.kv).get();
    final map = {for (final r in rows) r.key: r.value};
    return GymInfo(
      name: map[kGymName] ?? 'My gym',
      currency: map[kCurrency] ?? 'Rs',
      countryCode: map[kCountryCode] ?? '92',
    );
  }

  Future<bool> isSetUp() async => (await getKv(kGymName))?.trim().isNotEmpty ?? false;

  Future<void> setupGym({required String name, required String currency, required double monthlyFee}) async {
    final n = name.trim();
    if (n.isEmpty) throw const AppError('Enter your gym name.');
    if (monthlyFee < 0) throw const AppError('The monthly fee cannot be negative.');
    await _db.transaction(() async {
      await setKv(kGymName, n);
      await setKv(kCurrency, currency.trim());
      if ((await _db.select(_db.plans).get()).isEmpty) {
        for (final plan in defaultPlans(monthlyFee)) {
          await _db.into(_db.plans).insert(plan);
        }
      }
    });
  }

  Future<void> updateGym({String? name, String? currency, String? countryCode}) async {
    if (name != null) {
      if (name.trim().isEmpty) throw const AppError('Enter your gym name.');
      await setKv(kGymName, name.trim());
    }
    if (currency != null) await setKv(kCurrency, currency.trim());
    if (countryCode != null) await setKv(kCountryCode, countryCode.replaceAll(RegExp(r'\D'), ''));
  }

  // ------------------------------------------------------------------- plans

  Future<List<Plan>> plans() =>
      (_db.select(_db.plans)..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.months)])).get();

  Future<void> savePlan({String? id, required String name, required int months, required double price}) async {
    if (name.trim().isEmpty) throw const AppError('Enter a plan name.');
    if (months < 1 || months > 36) throw const AppError('A plan lasts between 1 and 36 months.');
    if (price < 0) throw const AppError('The price cannot be negative.');
    if (id == null) {
      final count = (await plans()).length;
      await _db.into(_db.plans).insert(
            PlansCompanion.insert(id: newId(), name: name.trim(), months: Value(months), price: Value(price), sortOrder: Value(count)),
          );
    } else {
      await (_db.update(_db.plans)..where((t) => t.id.equals(id)))
          .write(PlansCompanion(name: Value(name.trim()), months: Value(months), price: Value(price)));
    }
  }

  Future<void> deletePlan(String id) => _db.transaction(() async {
        await (_db.update(_db.members)..where((t) => t.planId.equals(id))).write(const MembersCompanion(planId: Value(null)));
        await (_db.delete(_db.plans)..where((t) => t.id.equals(id))).go();
      });

  // ----------------------------------------------------------------- members

  Future<List<Member>> members() =>
      (_db.select(_db.members)..orderBy([(t) => OrderingTerm.asc(t.name.collate(Collate.noCase))])).get();

  Future<Member?> member(String id) => (_db.select(_db.members)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Member> _require(String id) async {
    final m = await member(id);
    if (m == null) throw const AppError('This member no longer exists.');
    return m;
  }

  static String _cleanPhone(String phone) => phone.trim();

  static void _validate({required String name, required String phone, required double fee, required int months}) {
    if (name.trim().isEmpty) throw const AppError('Enter the member\'s name.');
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.trim().isNotEmpty && digits.length < 7) throw const AppError('That phone number looks too short.');
    if (fee < 0) throw const AppError('The fee cannot be negative.');
    if (months < 1 || months > 36) throw const AppError('A plan lasts between 1 and 36 months.');
  }

  /// Adds a member. With [paidNow] the first period is recorded as paid from [joinedOn].
  Future<String> addMember({
    required String name,
    String phone = '',
    String notes = '',
    DateTime? birthday,
    String? planId,
    required double fee,
    int planMonths = 1,
    required DateTime joinedOn,
    bool paidNow = true,
  }) async {
    _validate(name: name, phone: phone, fee: fee, months: planMonths);
    final id = newId();
    final joined = dateOnly(joinedOn);
    final end = addMonths(joined, planMonths);
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.members).insert(
            MembersCompanion.insert(
              id: id,
              name: name.trim(),
              phone: Value(_cleanPhone(phone)),
              notes: Value(notes.trim()),
              birthday: Value(birthday == null ? null : ymd(birthday)),
              planId: Value(planId),
              fee: Value(fee),
              planMonths: Value(planMonths),
              joinedOn: ymd(joined),
              cycleDay: joined.day,
              nextDue: ymd(paidNow ? end : joined),
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (paidNow) {
        await _db.into(_db.payments).insert(
              PaymentsCompanion.insert(
                id: newId(),
                memberId: id,
                amount: fee,
                months: Value(planMonths),
                paidAt: now,
                periodStart: ymd(joined),
                periodEnd: ymd(end),
                previousDue: ymd(joined),
                previousCycleDay: Value(joined.day),
              ),
            );
      }
    });
    return id;
  }

  Future<void> updateMember(
    String id, {
    required String name,
    required String phone,
    required String notes,
    required DateTime? birthday,
    required String? planId,
    required double fee,
    required int planMonths,
    required DateTime joinedOn,
  }) async {
    _validate(name: name, phone: phone, fee: fee, months: planMonths);
    await _require(id);
    await (_db.update(_db.members)..where((t) => t.id.equals(id))).write(
      MembersCompanion(
        name: Value(name.trim()),
        phone: Value(_cleanPhone(phone)),
        notes: Value(notes.trim()),
        birthday: Value(birthday == null ? null : ymd(birthday)),
        planId: Value(planId),
        fee: Value(fee),
        planMonths: Value(planMonths),
        joinedOn: Value(ymd(joinedOn)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateNotes(String id, String notes) => (_db.update(_db.members)..where((t) => t.id.equals(id)))
      .write(MembersCompanion(notes: Value(notes.trim()), updatedAt: Value(DateTime.now())));

  /// Moves the next due date by hand (e.g. to correct a mistake).
  Future<void> setNextDue(String id, DateTime due) => (_db.update(_db.members)..where((t) => t.id.equals(id))).write(
        MembersCompanion(nextDue: Value(ymd(due)), cycleDay: Value(due.day), updatedAt: Value(DateTime.now())),
      );

  Future<void> setActive(String id, bool active) async {
    await _require(id);
    await (_db.update(_db.members)..where((t) => t.id.equals(id))).write(
      MembersCompanion(
        status: Value(active ? 'active' : 'inactive'),
        // Leaving ends any freeze.
        frozenSince: active ? const Value.absent() : const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> freeze(String id, {DateTime? on}) async {
    final m = await _require(id);
    if (m.status != 'active') throw const AppError('Only active members can be frozen.');
    if (m.frozenSince != null) return;
    await (_db.update(_db.members)..where((t) => t.id.equals(id)))
        .write(MembersCompanion(frozenSince: Value(ymd(dateOnly(on ?? DateTime.now()))), updatedAt: Value(DateTime.now())));
  }

  /// Ends a freeze and pushes the due date back by the number of frozen days.
  Future<int> unfreeze(String id, {DateTime? on}) async {
    final m = await _require(id);
    final since = tryParseYmd(m.frozenSince);
    if (since == null) return 0;
    final days = daysBetween(since, dateOnly(on ?? DateTime.now())).clamp(0, 3650);
    final due = addDays(parseYmd(m.nextDue), days);
    await (_db.update(_db.members)..where((t) => t.id.equals(id))).write(
      MembersCompanion(
        frozenSince: const Value(null),
        nextDue: Value(ymd(due)),
        cycleDay: days == 0 ? const Value.absent() : Value(due.day),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return days;
  }

  Future<void> deleteMember(String id) => _db.transaction(() async {
        await (_db.delete(_db.checkins)..where((t) => t.memberId.equals(id))).go();
        await (_db.delete(_db.payments)..where((t) => t.memberId.equals(id))).go();
        await (_db.delete(_db.members)..where((t) => t.id.equals(id))).go();
      });

  // ---------------------------------------------------------------- payments

  /// Records a fee payment covering [months]. The period starts at the member's due date, or
  /// today when [fromToday] (for someone returning after a long gap).
  Future<Payment> recordPayment({
    required String memberId,
    required double amount,
    required int months,
    bool fromToday = false,
    String note = '',
    DateTime? paidAt,
  }) async {
    if (amount < 0) throw const AppError('The amount cannot be negative.');
    if (months < 1 || months > 36) throw const AppError('Choose between 1 and 36 months.');
    final m = await _require(memberId);
    final now = paidAt ?? DateTime.now();
    final start = fromToday ? dateOnly(now) : parseYmd(m.nextDue);
    final anchor = fromToday ? start.day : m.cycleDay;
    final end = addMonths(start, months, anchorDay: anchor);
    final payment = Payment(
      id: newId(),
      memberId: memberId,
      amount: amount,
      months: months,
      paidAt: now,
      periodStart: ymd(start),
      periodEnd: ymd(end),
      previousDue: m.nextDue,
      previousCycleDay: m.cycleDay,
      note: note.trim(),
    );
    await _db.transaction(() async {
      await _db.into(_db.payments).insert(payment);
      await (_db.update(_db.members)..where((t) => t.id.equals(memberId))).write(
        MembersCompanion(
          nextDue: Value(ymd(end)),
          cycleDay: Value(anchor),
          status: const Value('active'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
    return payment;
  }

  Future<List<Payment>> paymentsFor(String memberId) => (_db.select(_db.payments)
        ..where((t) => t.memberId.equals(memberId))
        ..orderBy([(t) => OrderingTerm.desc(t.paidAt), (t) => OrderingTerm.desc(t.periodEnd)]))
      .get();

  /// Undoes a payment. Only the member's latest payment can be undone, so the due date is
  /// restored exactly.
  Future<void> undoPayment(String paymentId) async {
    final p = await (_db.select(_db.payments)..where((t) => t.id.equals(paymentId))).getSingleOrNull();
    if (p == null) return;
    final latest = await paymentsFor(p.memberId);
    if (latest.isEmpty || latest.first.id != p.id) throw const AppError('Only the latest payment can be undone.');
    await _db.transaction(() async {
      await (_db.delete(_db.payments)..where((t) => t.id.equals(paymentId))).go();
      final m = await member(p.memberId);
      if (m != null) {
        await (_db.update(_db.members)..where((t) => t.id.equals(p.memberId))).write(
          MembersCompanion(
            nextDue: Value(p.previousDue),
            cycleDay: Value(p.previousCycleDay ?? m.cycleDay),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  /// Payments with paidAt in [from, to).
  Future<List<Payment>> paymentsBetween(DateTime from, DateTime to) => (_db.select(_db.payments)
        ..where((t) => t.paidAt.isBiggerOrEqualValue(from) & t.paidAt.isSmallerThanValue(to))
        ..orderBy([(t) => OrderingTerm.desc(t.paidAt)]))
      .get();

  Future<List<Payment>> allPayments() =>
      (_db.select(_db.payments)..orderBy([(t) => OrderingTerm.desc(t.paidAt)])).get();

  // ---------------------------------------------------------------- check-ins

  /// Marks attendance for today. Returns false when the member already checked in today.
  Future<bool> checkIn(String memberId, {DateTime? at}) async {
    final m = await _require(memberId);
    if (m.status != 'active') throw const AppError('This member is inactive. Reactivate them first.');
    final now = at ?? DateTime.now();
    if (await _hasCheckin(memberId, ymd(now))) return false;
    await _db.into(_db.checkins).insert(
          CheckinsCompanion.insert(id: newId(), memberId: memberId, day: ymd(now), at: now),
          mode: InsertMode.insertOrIgnore,
        );
    return true;
  }

  Future<bool> _hasCheckin(String memberId, String day) async =>
      (await (_db.select(_db.checkins)..where((t) => t.memberId.equals(memberId) & t.day.equals(day))).get()).isNotEmpty;

  Future<void> undoCheckIn(String memberId, DateTime day) =>
      (_db.delete(_db.checkins)..where((t) => t.memberId.equals(memberId) & t.day.equals(ymd(day)))).go();

  Future<List<Checkin>> checkinsOn(DateTime day) =>
      (_db.select(_db.checkins)..where((t) => t.day.equals(ymd(day)))..orderBy([(t) => OrderingTerm.desc(t.at)])).get();

  Future<List<Checkin>> checkinsFor(String memberId, {int limit = 60}) => (_db.select(_db.checkins)
        ..where((t) => t.memberId.equals(memberId))
        ..orderBy([(t) => OrderingTerm.desc(t.day)])
        ..limit(limit))
      .get();

  Future<int> checkinCountFor(String memberId, {required DateTime from}) async {
    final c = _db.checkins.id.count();
    final q = _db.selectOnly(_db.checkins)
      ..addColumns([c])
      ..where(_db.checkins.memberId.equals(memberId) & _db.checkins.day.isBiggerOrEqualValue(ymd(from)));
    return (await q.getSingle()).read(c) ?? 0;
  }

  /// Check-ins per day (yyyy-MM-dd → count) for days in [from, to].
  Future<Map<String, int>> checkinCountsByDay(DateTime from, DateTime to) async {
    final c = _db.checkins.id.count();
    final q = _db.selectOnly(_db.checkins)
      ..addColumns([_db.checkins.day, c])
      ..where(_db.checkins.day.isBetweenValues(ymd(from), ymd(to)))
      ..groupBy([_db.checkins.day]);
    return {for (final r in await q.get()) r.read(_db.checkins.day)!: r.read(c) ?? 0};
  }

  // ---------------------------------------------------------------- expenses

  static const expenseCategories = ['Rent', 'Electricity', 'Salaries', 'Equipment', 'Maintenance', 'Supplies', 'Other'];

  Future<void> saveExpense({String? id, required String category, required double amount, required DateTime day, String note = ''}) async {
    if (amount <= 0) throw const AppError('Enter an amount above zero.');
    final cat = category.trim().isEmpty ? 'Other' : category.trim();
    if (id == null) {
      await _db.into(_db.expenses).insert(ExpensesCompanion.insert(
            id: newId(),
            category: cat,
            amount: amount,
            day: ymd(day),
            note: Value(note.trim()),
            createdAt: DateTime.now(),
          ));
    } else {
      await (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(ExpensesCompanion(
        category: Value(cat),
        amount: Value(amount),
        day: Value(ymd(day)),
        note: Value(note.trim()),
      ));
    }
  }

  Future<void> deleteExpense(String id) => (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();

  /// Expenses with day in [from, to] (calendar days), newest first.
  Future<List<Expense>> expensesBetween(DateTime from, DateTime to) => (_db.select(_db.expenses)
        ..where((t) => t.day.isBetweenValues(ymd(from), ymd(to)))
        ..orderBy([(t) => OrderingTerm.desc(t.day), (t) => OrderingTerm.desc(t.createdAt)]))
      .get();

  Future<List<Expense>> allExpenses() =>
      (_db.select(_db.expenses)..orderBy([(t) => OrderingTerm.desc(t.day), (t) => OrderingTerm.desc(t.createdAt)])).get();

  /// Wipes all gym data (used by "Erase all data").
  Future<void> eraseAll() => _db.transaction(() async {
        for (final t in _db.allTables) {
          await _db.delete(t).go();
        }
      });
}
