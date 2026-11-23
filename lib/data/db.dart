import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'legacy_migration.dart';

part 'db.g.dart';

/// Calendar dates (joined, due, birthday, check-in day…) are `yyyy-MM-dd` text.
@DataClassName('Member')
@TableIndex(name: 'members_next_due_idx', columns: {#nextDue})
class Members extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get birthday => text().nullable()();
  TextColumn get planId => text().nullable()();

  /// Price of one plan period.
  RealColumn get fee => real().withDefault(const Constant(0))();

  /// Months covered by one payment of [fee].
  IntColumn get planMonths => integer().withDefault(const Constant(1))();
  TextColumn get joinedOn => text()();

  /// Day of month the fee falls on.
  IntColumn get cycleDay => integer()();

  /// The date the next fee is due (paid up to the day before).
  TextColumn get nextDue => text()();

  /// `active` or `inactive` (left the gym).
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// Set while the membership is frozen; unfreezing moves [nextDue] by the frozen days.
  TextColumn get frozenSince => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Plan')
class Plans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get months => integer().withDefault(const Constant(1))();
  RealColumn get price => real().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Payment')
@TableIndex(name: 'payments_member_idx', columns: {#memberId})
@TableIndex(name: 'payments_paid_at_idx', columns: {#paidAt})
class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get memberId => text()();
  RealColumn get amount => real()();
  IntColumn get months => integer().withDefault(const Constant(1))();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get periodStart => text()();
  TextColumn get periodEnd => text()();

  /// The member's due date before this payment, so the latest payment can be undone exactly.
  TextColumn get previousDue => text()();
  IntColumn get previousCycleDay => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Checkin')
@TableIndex(name: 'checkins_day_idx', columns: {#day})
class Checkins extends Table {
  TextColumn get id => text()();
  TextColumn get memberId => text()();
  TextColumn get day => text()();
  DateTimeColumn get at => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {memberId, day},
      ];
}

/// Money the gym spends (rent, salaries, electricity…), so Analytics can show profit.
@DataClassName('Expense')
@TableIndex(name: 'expenses_day_idx', columns: {#day})
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get category => text()();
  RealColumn get amount => real()();

  /// `yyyy-MM-dd`.
  TextColumn get day => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Gym settings that travel with backups (name, currency…).
@DataClassName('KvEntry')
class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Members, Plans, Payments, Checkins, Expenses, Kv])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  static const fileName = 'mr_gym.sqlite';

  /// Version 4 was the multi-location 1.x schema; 5 is the single-gym 2.0 schema; 6 adds expenses.
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // The legacy migration ends with createAll(), which already includes expenses.
          if (from < 5) {
            await migrateLegacyDatabase(this, m);
          } else if (from < 6) {
            await m.createTable(expenses);
            await m.createIndex(Index('expenses_day_idx', 'CREATE INDEX IF NOT EXISTS expenses_day_idx ON expenses (day)'));
          }
        },
      );

  static Future<String> defaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, fileName);
  }

  static AppDatabase openFile(File file) => AppDatabase(NativeDatabase.createInBackground(file));

  static AppDatabase memory() => AppDatabase(NativeDatabase.memory());
}
