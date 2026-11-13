import 'package:dates/logic/date_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leap years follow the Gregorian rule', () {
    expect(isLeapYear(2024), isTrue);
    expect(isLeapYear(1900), isFalse);
    expect(isLeapYear(2000), isTrue);
    expect(isLeapYear(2026), isFalse);
    expect(nextLeapYear(2026), 2028);
    expect(previousLeapYear(2026), 2024);
    expect(previousLeapYear(2024), 2020);
    expect(nextLeapDay(DateTime(2026, 8, 7)), DateTime.utc(2028, 2, 29));
  });

  test('adding a month clamps to the end of a short month', () {
    expect(addMonths(DateTime.utc(2025, 1, 31), 1), DateTime.utc(2025, 2, 28));
    expect(addMonths(DateTime.utc(2024, 1, 31), 1), DateTime.utc(2024, 2, 29));
    expect(addMonths(DateTime.utc(2025, 3, 15), -3), DateTime.utc(2024, 12, 15));
  });

  test('span matches a calendar reading', () {
    final s = spanBetween(DateTime(1985, 1, 17), DateTime(2026, 8, 7), ignoreTime: true);
    expect([s.years, s.months, s.days], [41, 6, 21]);
    expect(s.totalMonths, 498);
    expect(s.totalDays, 15177);
    expect(s.negative, isFalse);
  });

  test('span anchors months on the start, so month ends do not drift', () {
    final s = spanBetween(DateTime(2025, 1, 31), DateTime(2025, 3, 31), ignoreTime: true);
    expect([s.years, s.months, s.days], [0, 2, 0]);
    final t = spanBetween(DateTime(2025, 1, 31), DateTime(2025, 2, 28), ignoreTime: true);
    expect([t.months, t.days], [1, 0]); // consistent with Jan 31 + 1 month
  });

  test('span keeps time and reports direction', () {
    final s = spanBetween(DateTime(2026, 1, 2, 10, 30), DateTime(2026, 1, 1, 8, 0));
    expect(s.negative, isTrue);
    expect([s.days, s.hours, s.minutes], [1, 2, 30]);
  });

  test('include end date adds the last day', () {
    final s = spanBetween(DateTime(2026, 1, 1), DateTime(2026, 1, 1),
        ignoreTime: true, includeEnd: true);
    expect(s.totalDays, 1);
  });

  test('span is DST-proof', () {
    // A local span across a clock change still counts whole days.
    final s = spanBetween(DateTime(2026, 3, 1), DateTime(2026, 4, 1), ignoreTime: true);
    expect(s.totalDays, 31);
    expect(s.totalHours, 31 * 24);
  });

  test('shift adds and subtracts', () {
    expect(shiftDate(DateTime(2026, 8, 7), months: 6, days: 3), DateTime.utc(2027, 2, 10));
    expect(shiftDate(DateTime(2026, 3, 31), months: 1, subtract: true), DateTime.utc(2026, 2, 28));
    expect(shiftDate(DateTime(2026, 1, 1), weeks: 2), DateTime.utc(2026, 1, 15));
  });

  test('day and week of year', () {
    expect(dayOfYear(DateTime(2026, 8, 7)), 219);
    expect(dayOfYear(DateTime(2024, 12, 31)), 366);
    expect(weekOfYear(DateTime(2026, 1, 1)), 1); // Thursday
    expect(weekOfYear(DateTime(2027, 1, 1)), 53); // ISO: belongs to 2026
    expect(weekOfYear(DateTime(2026, 8, 7)), 32);
    expect(weekOfYear(DateTime(2026, 1, 3), mondayFirst: false), 1);
    expect(weekOfYear(DateTime(2026, 1, 4), mondayFirst: false), 2);
    expect(weeksInYear(2026), 53);
    expect(quarterOf(DateTime(2026, 8, 7)), 3);
  });

  test('working days count each weekday', () {
    // 1 Jan 2026 (Thu) .. 7 Aug 2026 (Fri) inclusive = 219 days.
    final r = workingDays(DateTime(2026, 1, 1), DateTime(2026, 8, 7), {1, 2, 3, 4, 5});
    expect(r.working + r.nonWorking, 219);
    expect(r.perWeekday[4], 32); // Thursdays
    expect(r.perWeekday[6], 31); // Saturdays
    expect(r.nonWorking, 62);
    final open = workingDays(DateTime(2026, 1, 1), DateTime(2026, 1, 1), {4}, includeEnd: false);
    expect(open.working, 0);
  });

  test('birthdays, including 29 February', () {
    final nb = nextBirthday(DateTime(1985, 1, 17), DateTime(2026, 8, 7));
    expect(nb.date, DateTime.utc(2027, 1, 17));
    expect(nb.turning, 42);
    final leap = nextBirthday(DateTime(2000, 2, 29), DateTime(2026, 2, 1));
    expect(leap.date, DateTime.utc(2026, 2, 28));
    final today = nextBirthday(DateTime(1990, 8, 7), DateTime(2026, 8, 7));
    expect(today.daysAway, 0);
  });
}
