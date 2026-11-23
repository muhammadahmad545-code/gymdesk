import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/data/db.dart';
import 'package:gymdesk/data/gym_repository.dart';
import 'package:gymdesk/domain/dates.dart';
import 'package:gymdesk/services/backup_service.dart';
import 'package:gymdesk/services/crypto.dart';
import 'package:path/path.dart' as p;

void main() {
  test('encryption round-trips and rejects the wrong password', () {
    final plain = Uint8List.fromList(utf8.encode('SQLite format 3 and more'));
    final package = GymCrypto.encrypt(plain, 'correct horse');
    expect(GymCrypto.decrypt(jsonDecode(jsonEncode(package)) as Map<String, dynamic>, 'correct horse'), plain);
    expect(() => GymCrypto.decrypt(package, 'wrong'), throwsArgumentError);
  });

  test('PIN hashes verify only the same PIN', () async {
    final (hash, salt) = await GymCrypto.hashNewPin('2468');
    expect(await GymCrypto.verifyPin('2468', hash, salt), isTrue);
    expect(await GymCrypto.verifyPin('2469', hash, salt), isFalse);
  });

  test('a backup restores members, payments and check-ins over newer data', () async {
    final dir = await Directory.systemTemp.createTemp('mrgym_backup_test');
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = p.join(dir.path, AppDatabase.fileName);
    final repo = GymRepository(AppDatabase.openFile(File(dbPath)));
    final service = BackupService(repo: repo, databasePath: dbPath, workDir: () async => dir);

    await repo.setupGym(name: 'Backup Gym', currency: 'Rs', monthlyFee: 2000);
    final id = await repo.addMember(name: 'Kept Member', fee: 2000, joinedOn: today());
    await repo.checkIn(id);

    expect(() => service.create('123'), throwsA(isA<AppError>()));
    final file = await service.create('secret-pass');
    expect(file.path, endsWith('.${BackupService.extension}'));
    expect(await file.readAsString(), isNot(contains('Kept Member')));

    // Change data after the backup, then restore.
    await repo.addMember(name: 'Added Later', fee: 1, joinedOn: today());
    await repo.updateGym(name: 'Renamed');

    await expectLater(service.restore(file, 'not-it'), throwsA(isA<AppError>()));
    expect((await repo.members()).length, 2, reason: 'a failed restore leaves data alone');

    await service.restore(file, 'secret-pass');
    final names = (await repo.members()).map((m) => m.name).toList();
    expect(names, ['Kept Member']);
    expect((await repo.gymInfo()).name, 'Backup Gym');
    expect(await repo.paymentsFor(id), hasLength(1));
    expect(await repo.checkinsFor(id), hasLength(1));

    // The restored database is writable.
    await repo.addMember(name: 'After Restore', fee: 1, joinedOn: today());
    expect(await repo.members(), hasLength(2));

    await repo.dispose();
    await repo.db.close();
  });

  test('a file that is not a backup is rejected', () async {
    final dir = await Directory.systemTemp.createTemp('mrgym_backup_bad');
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = p.join(dir.path, AppDatabase.fileName);
    final repo = GymRepository(AppDatabase.openFile(File(dbPath)));
    final service = BackupService(repo: repo, databasePath: dbPath, workDir: () async => dir);
    final bad = File(p.join(dir.path, 'notes.txt'))..writeAsStringSync('hello');
    await expectLater(service.restore(bad, 'x'), throwsA(isA<AppError>()));
    await repo.dispose();
    await repo.db.close();
  });
}
