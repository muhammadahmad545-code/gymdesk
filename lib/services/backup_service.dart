import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';
import '../data/gym_repository.dart';
import 'crypto.dart';

/// Encrypted backup files (`.mrgym-backup`): a consistent SQLite snapshot encrypted with a
/// password the owner chooses. The password is never stored.
class BackupService {
  BackupService({
    required this.repo,
    required this.databasePath,
    Future<Directory> Function()? workDir,
  }) : _workDir = workDir ?? getApplicationDocumentsDirectory;

  final GymRepository repo;

  /// Path of the live database file.
  final String databasePath;
  final Future<Directory> Function() _workDir;

  static const extension = 'mrgym-backup';
  static const minPasswordLength = 6;

  Future<Directory> _backupDir() async {
    final dir = Directory(p.join((await _workDir()).path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes an encrypted backup and returns the file (the caller shares or saves it).
  Future<File> create(String password) async {
    if (password.length < minPasswordLength) {
      throw const AppError('Use a backup password of at least $minPasswordLength characters.');
    }
    final dir = await _backupDir();
    final stamp = DateTime.now();
    final snapshot = File(p.join(dir.path, '.snapshot-${stamp.millisecondsSinceEpoch}.sqlite'));
    try {
      await _snapshot(repo.db, snapshot);
      final plain = await snapshot.readAsBytes();
      final package = await GymCrypto.encryptAsync(plain, password);
      package['app'] = 'dev.basalt.mrgym';
      package['schemaVersion'] = repo.db.schemaVersion;
      final name = 'gymdesk-${_stamp(stamp)}.$extension';
      final out = File(p.join(dir.path, name));
      await out.writeAsString(jsonEncode(package), flush: true);
      await _prune(dir, keep: 5);
      return out;
    } on AppError {
      rethrow;
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('no space') || text.contains('enospc') || text.contains('full')) {
        throw const AppError('Not enough free storage to create a backup.');
      }
      throw AppError('The backup could not be created ($e).');
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  /// A consistent copy of the live database, including anything still in the WAL.
  static Future<void> _snapshot(AppDatabase db, File target) async {
    if (await target.exists()) await target.delete();
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Not in WAL mode: nothing to checkpoint.
    }
    final path = target.path.replaceAll("'", "''");
    await db.customStatement("VACUUM INTO '$path'");
    if (!await target.exists() || await target.length() < 512) {
      throw const AppError('The backup snapshot was empty.');
    }
  }

  /// Decrypts [file], checks it, migrates it if it came from an older version, then swaps it in
  /// for the live database. On any failure the live data is left unchanged.
  Future<void> restore(File file, String password) async {
    final Map<String, dynamic> package;
    try {
      package = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      throw const AppError('This is not a Gymdesk backup file.');
    }
    if (package['formatVersion']?.toString() != GymCrypto.backupFormatVersion || package['ciphertext'] is! String) {
      throw const AppError('This backup was made by an incompatible version of Gymdesk.');
    }
    final Uint8List plain;
    try {
      plain = await GymCrypto.decryptAsync(package, password);
    } catch (_) {
      throw const AppError('Wrong backup password, or the file is damaged.');
    }
    final expected = package['sha256'];
    if (expected is String && expected.isNotEmpty && GymCrypto.sha256Hex(plain) != expected) {
      throw const AppError('The backup file is damaged.');
    }
    if (plain.length < 100 || ascii.decode(plain.sublist(0, 15), allowInvalid: true) != 'SQLite format 3') {
      throw const AppError('The backup does not contain a Gymdesk database.');
    }

    final live = File(databasePath);
    final temp = File('$databasePath.restore');
    final safety = File('$databasePath.before-restore');
    await _deleteWithSidecars(temp);
    await temp.writeAsBytes(plain, flush: true);

    // Open the restored copy on its own first: this runs any schema migration and checks it.
    final probe = AppDatabase(NativeDatabase(temp));
    try {
      final check = await probe.customSelect('PRAGMA integrity_check').get();
      final result = check.isEmpty ? '' : check.first.data.values.first.toString();
      if (result.toLowerCase() != 'ok') throw const AppError('The backup database failed its integrity check.');
      await probe.customSelect('SELECT COUNT(*) FROM members').get();
    } on AppError {
      await probe.close();
      await _deleteWithSidecars(temp);
      rethrow;
    } catch (e) {
      await probe.close();
      await _deleteWithSidecars(temp);
      throw AppError('The backup could not be read ($e).');
    }
    await probe.close();

    final old = repo.db;
    await old.close();
    try {
      await _deleteWithSidecars(safety);
      if (await live.exists()) await live.rename(safety.path);
      await _deleteSidecars(live);
      await temp.rename(live.path);
      await _deleteSidecars(temp);
      final reopened = AppDatabase.openFile(live);
      await reopened.customSelect('SELECT COUNT(*) FROM members').get();
      repo.replaceDatabase(reopened);
      await _deleteWithSidecars(safety);
    } catch (e) {
      // Put the previous database back.
      try {
        await _deleteWithSidecars(live);
        if (await safety.exists()) await safety.rename(live.path);
      } catch (_) {}
      repo.replaceDatabase(AppDatabase.openFile(live));
      throw AppError('Restore failed and your existing data was kept ($e).');
    }
  }

  static Future<void> _deleteSidecars(File f) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final s = File('${f.path}$suffix');
      if (await s.exists()) await s.delete();
    }
  }

  static Future<void> _deleteWithSidecars(File f) async {
    if (await f.exists()) await f.delete();
    await _deleteSidecars(f);
  }

  Future<void> _prune(Directory dir, {required int keep}) async {
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.$extension')).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final f in files.skip(keep)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  static String _stamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}-${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }
}
