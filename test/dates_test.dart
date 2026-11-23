import 'package:flutter_test/flutter_test.dart';
import 'package:gymdesk/domain/dates.dart';

void main() {
  test('addMonths keeps the day or clamps to the end of the month', () {
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
    expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    expect(addMonths(DateTime(2026, 12, 10), 12), DateTime(2027, 12, 10));
    expect(addMonths(DateTime(2026, 1, 10), -1), DateTime(2025, 12, 10));
    expect(addMonths(DateTime(2026, 1, 10), -13), DateTime(2024, 12, 10));
    // The anchor day stops 31st-of-month fees drifting to the 28th.
    expect(addMonths(DateTime(2026, 2, 28), 1, anchorDay: 31), DateTime(2026, 3, 31));
  });

  test('nextCycleDate finds the next fee date on the anchor day', () {
    final joined = DateTime(2026, 1, 31);
    expect(nextCycleDate(joined, DateTime(2026, 1, 10)), DateTime(2026, 1, 31));
    expect(nextCycleDate(joined, DateTime(2026, 2, 3)), DateTime(2026, 2, 28));
    expect(nextCycleDate(joined, DateTime(2026, 3, 1)), DateTime(2026, 3, 31));
    expect(nextCycleDate(DateTime(2025, 6, 5), DateTime(2026, 11, 5)), DateTime(2026, 11, 5));
    expect(nextCycleDate(DateTime(2025, 6, 5), DateTime(2026, 11, 6)), DateTime(2026, 12, 5));
  });

  test('ymd round-trips and daysBetween ignores clock time', () {
    expect(ymd(DateTime(2026, 3, 7)), '2026-03-07');
    expect(parseYmd('2026-03-07'), DateTime(2026, 3, 7));
    expect(tryParseYmd('nonsense'), isNull);
    expect(daysBetween(DateTime(2026, 3, 1, 23), DateTime(2026, 3, 2, 1)), 1);
    expect(daysBetween(DateTime(2026, 3, 10), DateTime(2026, 3, 1)), -9);
  });

  test('nextBirthday handles the year boundary and 29 February', () {
    expect(nextBirthday(DateTime(1990, 1, 2), DateTime(2026, 12, 30)), DateTime(2027, 1, 2));
    expect(nextBirthday(DateTime(1992, 2, 29), DateTime(2026, 1, 1)), DateTime(2026, 2, 28));
    expect(nextBirthday(DateTime(1990, 5, 5), DateTime(2026, 5, 5)), DateTime(2026, 5, 5));
  });
}
