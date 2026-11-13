// Pure date arithmetic. No Flutter imports, so every rule here is unit-tested.
//
// All maths runs on UTC wall-clock values: a local DateTime crossing a DST
// change gains or loses an hour, and "days between" would then come out one
// short. Callers pass local dates; we copy the fields into UTC first.

DateTime asUtc(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);

DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

bool isLeapYear(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

int daysInMonth(int y, int m) => const [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1] +
    (m == 2 && isLeapYear(y) ? 1 : 0);

int daysInYear(int y) => isLeapYear(y) ? 366 : 365;

/// Adds months keeping the day where possible: Jan 31 + 1 month is Feb 28/29,
/// never Mar 3 (which is what DateTime's own overflow would give).
DateTime addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final day = d.day.clamp(1, daysInMonth(y, m));
  return DateTime.utc(y, m, day, d.hour, d.minute, d.second);
}

/// A calendar span: whole years, months and days plus the time left over.
class Span {
  const Span({
    required this.years,
    required this.months,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.total,
    required this.negative,
  });

  final int years, months, days, hours, minutes;

  /// The exact absolute duration.
  final Duration total;

  /// True when the end is before the start.
  final bool negative;

  int get totalMonths => years * 12 + months;
  int get totalDays => total.inDays;
  int get totalWeeks => totalDays ~/ 7;
  int get weekRemainderDays => totalDays % 7;
  int get totalHours => total.inHours;
  int get totalMinutes => total.inMinutes;
  int get totalSeconds => total.inSeconds;
}

/// The span from [a] to [b]. Order does not matter; [Span.negative] says
/// whether it ran backwards. [includeEnd] counts the end day itself, the way
/// "1 Jan to 1 Jan" is one day of leave rather than zero.
Span spanBetween(DateTime a, DateTime b,
    {bool ignoreTime = false, bool includeEnd = false}) {
  var s = ignoreTime ? dateOnly(a) : asUtc(a);
  var e = ignoreTime ? dateOnly(b) : asUtc(b);
  final negative = e.isBefore(s);
  if (negative) {
    final t = s;
    s = e;
    e = t;
  }
  if (includeEnd) e = e.add(const Duration(days: 1));

  // Count whole months from the start, re-anchored on the ORIGINAL start each
  // time so Jan 31 -> Feb 28 -> Mar 31 does not drift to Mar 28.
  var months = (e.year - s.year) * 12 + (e.month - s.month);
  while (months > 0 && addMonths(s, months).isAfter(e)) {
    months--;
  }
  final anchor = addMonths(s, months);
  final rest = e.difference(anchor);
  return Span(
    years: months ~/ 12,
    months: months % 12,
    days: rest.inDays,
    hours: rest.inHours % 24,
    minutes: rest.inMinutes % 60,
    total: e.difference(s),
    negative: negative,
  );
}

/// Shifts [d] by the given amounts; [subtract] runs it backwards.
DateTime shiftDate(DateTime d,
    {int years = 0, int months = 0, int weeks = 0, int days = 0, bool subtract = false}) {
  final sign = subtract ? -1 : 1;
  var r = addMonths(dateOnly(d), sign * (years * 12 + months));
  r = r.add(Duration(days: sign * (weeks * 7 + days)));
  return r;
}

/// Day of the year, 1-based.
int dayOfYear(DateTime d) =>
    dateOnly(d).difference(DateTime.utc(d.year, 1, 1)).inDays + 1;

/// Week of the year. Monday-first uses ISO 8601 (week 1 holds the first
/// Thursday). Sunday-first uses the US rule (week 1 holds 1 January).
int weekOfYear(DateTime d, {bool mondayFirst = true}) {
  final x = dateOnly(d);
  if (mondayFirst) {
    final thursday = x.add(Duration(days: 4 - x.weekday));
    return (dayOfYear(thursday) - 1) ~/ 7 + 1;
  }
  final jan1 = DateTime.utc(x.year, 1, 1);
  final offset = jan1.weekday % 7; // Sunday -> 0
  return (dayOfYear(x) - 1 + offset) ~/ 7 + 1;
}

/// Number of weeks the year has under the same rule [weekOfYear] uses.
int weeksInYear(int y, {bool mondayFirst = true}) {
  if (mondayFirst) return weekOfYear(DateTime.utc(y, 12, 28));
  return weekOfYear(DateTime.utc(y, 12, 31), mondayFirst: false);
}

int quarterOf(DateTime d) => (d.month - 1) ~/ 3 + 1;

/// How far through its year [d] is, 0..1, counting the day itself as done.
double yearProgress(DateTime d) => dayOfYear(d) / daysInYear(d.year);

/// Counts each weekday (1 = Monday .. 7 = Sunday) between two dates.
/// [includeEnd] counts the end date; the start date always counts.
Map<int, int> weekdayCounts(DateTime a, DateTime b, {bool includeEnd = true}) {
  var s = dateOnly(a), e = dateOnly(b);
  if (e.isBefore(s)) {
    final t = s;
    s = e;
    e = t;
  }
  var n = e.difference(s).inDays + (includeEnd ? 1 : 0);
  final counts = {for (var w = 1; w <= 7; w++) w: n ~/ 7};
  final rem = n % 7;
  for (var i = 0; i < rem; i++) {
    final w = (s.weekday - 1 + i) % 7 + 1;
    counts[w] = counts[w]! + 1;
  }
  return counts;
}

class WorkingDays {
  const WorkingDays(this.working, this.nonWorking, this.perWeekday);
  final int working, nonWorking;
  final Map<int, int> perWeekday;
}

WorkingDays workingDays(DateTime a, DateTime b, Set<int> workdays,
    {bool includeEnd = true}) {
  final c = weekdayCounts(a, b, includeEnd: includeEnd);
  var w = 0, off = 0;
  c.forEach((day, n) => workdays.contains(day) ? w += n : off += n);
  return WorkingDays(w, off, c);
}

/// The next leap year strictly after [y], and the last one strictly before.
int nextLeapYear(int y) {
  var x = y + 1;
  while (!isLeapYear(x)) {
    x++;
  }
  return x;
}

int previousLeapYear(int y) {
  var x = y - 1;
  while (!isLeapYear(x)) {
    x--;
  }
  return x;
}

/// The next 29 February on or after [from].
DateTime nextLeapDay(DateTime from) {
  final f = dateOnly(from);
  var y = f.year;
  while (true) {
    if (isLeapYear(y)) {
      final d = DateTime.utc(y, 2, 29);
      if (!d.isBefore(f)) return d;
    }
    y++;
  }
}

/// A birthday in a given year. Someone born on 29 February celebrates on
/// 28 February in a common year (the more common convention).
DateTime birthdayIn(DateTime birth, int year) {
  final day = birth.month == 2 && birth.day == 29 && !isLeapYear(year) ? 28 : birth.day;
  return DateTime.utc(year, birth.month, day);
}

class NextBirthday {
  const NextBirthday(this.date, this.daysAway, this.turning);
  final DateTime date;
  final int daysAway;
  final int turning;
}

NextBirthday nextBirthday(DateTime birth, DateTime today) {
  final t = dateOnly(today);
  var b = birthdayIn(birth, t.year);
  if (b.isBefore(t)) b = birthdayIn(birth, t.year + 1);
  return NextBirthday(b, b.difference(t).inDays, b.year - birth.year);
}
