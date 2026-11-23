import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/data/db.dart';
import 'package:gymdesk/data/gym_repository.dart';
import 'package:gymdesk/domain/dates.dart';

/// A trimmed copy of the Mr. Gym 1.x (schema 4) tables that hold data worth keeping.
const _v4 = [
  'CREATE TABLE organizations (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, country_code TEXT NOT NULL DEFAULT \'\', default_currency TEXT NOT NULL DEFAULT \'USD\', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  'CREATE TABLE locations (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL, name TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  'CREATE TABLE members (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL, location_id TEXT NOT NULL, external_member_id TEXT, first_name TEXT NOT NULL, last_name TEXT NOT NULL DEFAULT \'\', phone TEXT, email TEXT, status TEXT NOT NULL DEFAULT \'active\', joined_at INTEGER, fee_day INTEGER, gender TEXT, notes TEXT, whatsapp_enabled INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  'CREATE INDEX members_name_idx ON members (first_name, last_name)',
  'CREATE TABLE memberships (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL, location_id TEXT NOT NULL, member_id TEXT NOT NULL, plan_id TEXT, start_at INTEGER NOT NULL, end_at INTEGER NOT NULL, status TEXT NOT NULL, price_amount REAL, currency_code TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  'CREATE TABLE attendance_events (id TEXT NOT NULL PRIMARY KEY, organization_id TEXT NOT NULL, location_id TEXT NOT NULL, member_id TEXT, external_member_id TEXT NOT NULL, source_id TEXT NOT NULL, occurred_at_utc INTEGER NOT NULL, occurred_at_local INTEGER NOT NULL, event_type TEXT NOT NULL, external_event_id TEXT, raw_payload_json TEXT, ingested_at INTEGER NOT NULL, match_status TEXT NOT NULL DEFAULT \'unmatched\', local_date TEXT, is_manual INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE risk_scores (id TEXT NOT NULL PRIMARY KEY, member_id TEXT NOT NULL, score INTEGER NOT NULL)',
  'CREATE TABLE app_meta_entries ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
];

int _secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

void main() {
  test('a 1.x database is migrated to the single-gym schema', () async {
    final joined = DateTime(2025, 8, 12);
    final visit = DateTime(2026, 11, 3, 18, 30);
    final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      for (final sql in _v4) {
        raw.execute(sql);
      }
      final now = _secs(DateTime(2026, 1, 1));
      raw.execute("INSERT INTO organizations VALUES ('o1', 'Mr. Gym Lahore', 'PK', 'PKR', $now, $now)");
      raw.execute("INSERT INTO locations VALUES ('l1', 'o1', 'Main', $now, $now)");
      raw.execute(
        "INSERT INTO members (id, organization_id, location_id, first_name, last_name, phone, status, joined_at, fee_day, notes, created_at, updated_at) "
        "VALUES ('m1', 'o1', 'l1', 'Ali', 'Raza', '03001234567', 'active', ${_secs(joined)}, 12, 'Knee injury', $now, $now)",
      );
      raw.execute(
        "INSERT INTO members (id, organization_id, location_id, first_name, status, created_at, updated_at) "
        "VALUES ('m2', 'o1', 'l1', 'Old Timer', 'cancelled', $now, $now)",
      );
      raw.execute(
        "INSERT INTO memberships VALUES ('ms1', 'o1', 'l1', 'm1', NULL, ${_secs(joined)}, ${_secs(joined) + 86400 * 30}, 'active', 2500, 'PKR', $now, $now)",
      );
      for (final id in ['e1', 'e2']) {
        raw.execute(
          "INSERT INTO attendance_events (id, organization_id, location_id, member_id, external_member_id, source_id, occurred_at_utc, occurred_at_local, event_type, ingested_at, local_date) "
          "VALUES ('$id', 'o1', 'l1', 'm1', 'm1', 'manual', ${_secs(visit)}, ${_secs(visit)}, 'check_in', $now, '2026-11-03')",
        );
      }
      raw.execute('PRAGMA user_version = 4');
    }));
    final repo = GymRepository(db);
    addTearDown(() async {
      await repo.dispose();
      await db.close();
    });

    final members = await repo.members();
    expect(members, hasLength(2));
    final ali = members.firstWhere((m) => m.id == 'm1');
    expect(ali.name, 'Ali Raza');
    expect(ali.phone, '03001234567');
    expect(ali.notes, 'Knee injury');
    expect(ali.fee, 2500);
    expect(ali.joinedOn, '2025-08-12');
    expect(ali.cycleDay, 12);
    final due = parseYmd(ali.nextDue);
    expect(due.day, 12);
    expect(due.isBefore(today()), isFalse);
    expect(members.firstWhere((m) => m.id == 'm2').status, 'inactive');

    // Duplicate check-ins on one day collapse into one.
    expect(await repo.checkinsFor('m1'), hasLength(1));
    expect((await repo.checkinsFor('m1')).single.day, '2026-11-03');

    final gym = await repo.gymInfo();
    expect(gym.name, 'Mr. Gym Lahore');
    expect(gym.currency, 'Rs');
    expect(await repo.isSetUp(), isTrue);
    expect(await repo.plans(), hasLength(4));

    final tables = (await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get())
        .map((r) => r.read<String>('name'))
        .toSet();
    expect(tables.contains('risk_scores'), isFalse);
    expect(tables.contains('organizations'), isFalse);
    expect(tables.containsAll(['members', 'payments', 'checkins', 'plans', 'kv']), isTrue);
  });
}
