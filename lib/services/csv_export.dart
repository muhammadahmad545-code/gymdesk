import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db.dart';
import '../domain/dates.dart';
import '../domain/member_view.dart';

/// Spreadsheet-friendly CSV exports, shared through the Android share sheet.
abstract final class CsvExport {
  static String _cell(Object? v) {
    final s = v?.toString() ?? '';
    if (s.contains(RegExp(r'[",\n\r]')) || s.startsWith(RegExp(r'[=+\-@]'))) {
      // Quote, and neutralise spreadsheet formulas.
      final safe = s.startsWith(RegExp(r'[=+\-@]')) ? "'$s" : s;
      return '"${safe.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _rows(List<List<Object?>> rows) => '${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';

  static String members(List<MemberView> members, Map<String, String> planNames) => _rows([
        ['Name', 'Phone', 'Status', 'Plan', 'Fee', 'Months per payment', 'Joined', 'Next due', 'Birthday', 'Notes'],
        for (final m in members)
          [
            m.name,
            m.member.phone,
            m.badge,
            planNames[m.member.planId] ?? '',
            m.member.fee,
            m.member.planMonths,
            m.member.joinedOn,
            m.member.nextDue,
            m.member.birthday ?? '',
            m.member.notes,
          ],
      ]);

  static String payments(List<Payment> payments, Map<String, String> memberNames) => _rows([
        ['Paid on', 'Member', 'Amount', 'Months', 'From', 'To', 'Note'],
        for (final pay in payments)
          [
            DateFormat('yyyy-MM-dd HH:mm').format(pay.paidAt),
            memberNames[pay.memberId] ?? '(deleted member)',
            pay.amount,
            pay.months,
            pay.periodStart,
            ymd(addDays(parseYmd(pay.periodEnd), -1)),
            pay.note,
          ],
      ]);

  static String expenses(List<Expense> expenses) => _rows([
        ['Date', 'Category', 'Amount', 'Note'],
        for (final e in expenses) [e.day, e.category, e.amount, e.note],
      ]);

  static Future<void> share(String fileName, String csv, {String? subject}) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'exports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(csv, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: subject ?? fileName),
    );
  }
}
