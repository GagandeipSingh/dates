import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../logic/date_math.dart';
import '../state/settings.dart';
import 'kit.dart';
import 'scale.dart';

String plural(int v, String one, [String? many]) =>
    '${n(v)} ${v == 1 ? one : (many ?? '${one}s')}';

DateTime _now() {
  final d = DateTime.now();
  return DateTime(d.year, d.month, d.day, d.hour, d.minute);
}

// ───────────────────────────────────────────── Between two dates

class BetweenScreen extends StatefulWidget {
  const BetweenScreen({super.key});
  @override
  State<BetweenScreen> createState() => _BetweenScreenState();
}

class _BetweenScreenState extends State<BetweenScreen> {
  late DateTime start, end;
  bool ignoreTime = true, includeEnd = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    end = _now();
    start = DateTime(end.year, 1, 1);
    ignoreTime = true;
    includeEnd = false;
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Pal.of(context);
    final r = spanBetween(
      start,
      end,
      ignoreTime: ignoreTime,
      includeEnd: includeEnd,
    );
    String text() => [
      '${s.date(start)} → ${s.date(end)}',
      '${plural(r.years, 'year')}, ${plural(r.months, 'month')}, ${plural(r.days, 'day')}'
          '${ignoreTime ? '' : ', ${plural(r.hours, 'hour')}, ${plural(r.minutes, 'minute')}'}',
      '${n(r.totalDays)} days in total',
    ].join('\n');

    return ToolScreen(
      title: 'Between Dates',
      children: [
        Pane(
          child: Column(
            children: [
              DateTimeField(
                label: 'Start',
                value: start,
                withTime: !ignoreTime,
                onChanged: (v) => setState(() => start = v),
              ),
              const Hairline(),
              DateTimeField(
                label: 'End',
                value: end,
                withTime: !ignoreTime,
                onChanged: (v) => setState(() => end = v),
              ),
              const Hairline(),
              SwitchRow(
                label: 'Include time',
                value: !ignoreTime,
                onChanged: (v) => setState(() => ignoreTime = !v),
              ),
              SizedBox(height: 10.dp),
              SwitchRow(
                label: 'Include end date',
                hint: 'Count the last day too',
                value: includeEnd,
                onChanged: (v) => setState(() => includeEnd = v),
              ),
            ],
          ),
        ),
        const SectionTitle('Result'),
        Pane(
          tint: p.accent.withValues(alpha: 0.10),
          child: Column(
            children: [
              if (r.negative)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.dp),
                  child: Text(
                    'End is before start — showing the gap',
                    style: TextStyle(color: p.sub, fontSize: 12.5.sp),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: BigFigure(
                      n(r.years),
                      r.years == 1 ? 'Year' : 'Years',
                    ),
                  ),
                  Expanded(
                    child: BigFigure(
                      n(r.months),
                      r.months == 1 ? 'Month' : 'Months',
                    ),
                  ),
                  Expanded(
                    child: BigFigure(n(r.days), r.days == 1 ? 'Day' : 'Days'),
                  ),
                ],
              ),
              if (!ignoreTime) ...[
                SizedBox(height: 14.dp),
                Row(
                  children: [
                    const Spacer(),
                    Expanded(
                      flex: 2,
                      child: BigFigure(n(r.hours), 'Hours', size: 24.dp),
                    ),
                    Expanded(
                      flex: 2,
                      child: BigFigure(n(r.minutes), 'Minutes', size: 24.dp),
                    ),
                    const Spacer(),
                  ],
                ),
              ],
              const Hairline(),
              ResultLine(
                'In months',
                '${plural(r.totalMonths, 'month')} ${plural(r.days, 'day')}',
              ),
              ResultLine(
                'In weeks',
                '${plural(r.totalWeeks, 'week')} ${plural(r.weekRemainderDays, 'day')}',
              ),
              ResultLine('In days', plural(r.totalDays, 'day')),
              ResultLine('In hours', plural(r.totalHours, 'hour')),
              ResultLine('In minutes', plural(r.totalMinutes, 'minute')),
              ResultLine('In seconds', plural(r.totalSeconds, 'second')),
            ],
          ),
        ),
        ResultActions(shareText: text, onReset: () => setState(_reset)),
      ],
    );
  }
}

// ───────────────────────────────────────────── Add / subtract

class AddScreen extends StatefulWidget {
  const AddScreen({super.key});
  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  DateTime start = _now();
  bool subtract = false;
  final ctl = {
    for (final k in ['Years', 'Months', 'Weeks', 'Days'])
      k: TextEditingController(),
  };

  int _v(String k) => int.tryParse(ctl[k]!.text) ?? 0;

  @override
  void dispose() {
    for (final c in ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Pal.of(context);
    final r = shiftDate(
      start,
      years: _v('Years'),
      months: _v('Months'),
      weeks: _v('Weeks'),
      days: _v('Days'),
      subtract: subtract,
    );
    final gap = dateOnly(r).difference(dateOnly(start)).inDays.abs();
    String text() =>
        '${s.date(start)} ${subtract ? '−' : '+'} ${_v('Years')}y ${_v('Months')}m ${_v('Weeks')}w ${_v('Days')}d = '
        '${DateFormat('EEEE').format(r)}, ${s.date(r)}';

    return ToolScreen(
      title: 'Add or Subtract',
      children: [
        Segments<bool>(
          values: const [false, true],
          labels: const ['Add', 'Subtract'],
          selected: subtract,
          onChanged: (v) => setState(() => subtract = v),
        ),
        Gap(14.dp),
        Pane(
          child: Column(
            children: [
              DateTimeField(
                label: 'From',
                value: start,
                onChanged: (v) => setState(() => start = v),
              ),
              const Hairline(),
              Row(
                children: [
                  for (final k in ctl.keys) ...[
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: ctl[k],
                            onChanged: (_) => setState(() {}),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(5),
                            ],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.ink,
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w700,
                            ),
                            cursorColor: p.accent,
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(
                                color: p.sub.withValues(alpha: 0.5),
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: p.faint,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12.dp,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14.dp),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          SizedBox(height: 6.dp),
                          Caption(k),
                        ],
                      ),
                    ),
                    if (k != 'Days') SizedBox(width: 8.dp),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SectionTitle('Result'),
        Pane(
          tint: p.accent.withValues(alpha: 0.10),
          child: Column(
            children: [
              Caption(DateFormat('EEEE').format(r), color: p.accent),
              SizedBox(height: 6.dp),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  s.date(r),
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 32.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const Hairline(),
              ResultLine(
                'Days ${subtract ? 'back' : 'ahead'}',
                plural(gap, 'day'),
              ),
              ResultLine(
                'Day of year',
                '${dayOfYear(r)} of ${daysInYear(r.year)}',
              ),
              ResultLine(
                'Week',
                '${weekOfYear(r, mondayFirst: s.mondayFirst)}',
              ),
            ],
          ),
        ),
        ResultActions(
          shareText: text,
          onReset: () => setState(() {
            start = _now();
            subtract = false;
            for (final c in ctl.values) {
              c.clear();
            }
          }),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────── Age

class AgeScreen extends StatefulWidget {
  const AgeScreen({super.key});
  @override
  State<AgeScreen> createState() => _AgeScreenState();
}

class _AgeScreenState extends State<AgeScreen> {
  DateTime birth = DateTime(2000, 1, 1);
  DateTime on = _now();
  bool ignoreTime = true;

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Pal.of(context);
    final r = spanBetween(birth, on, ignoreTime: ignoreTime);
    final nb = nextBirthday(birth, on);
    String text() =>
        'Age on ${s.date(on)}: ${plural(r.years, 'year')}, ${plural(r.months, 'month')}, ${plural(r.days, 'day')}\n'
        'Next birthday: ${s.date(nb.date)} (in ${plural(nb.daysAway, 'day')})';

    return ToolScreen(
      title: 'Age',
      children: [
        Pane(
          child: Column(
            children: [
              DateTimeField(
                label: 'Date of birth',
                value: birth,
                withTime: !ignoreTime,
                onChanged: (v) => setState(() => birth = v),
              ),
              const Hairline(),
              DateTimeField(
                label: 'Age on',
                value: on,
                withTime: !ignoreTime,
                onChanged: (v) => setState(() => on = v),
              ),
              const Hairline(),
              SwitchRow(
                label: 'Include time of birth',
                value: !ignoreTime,
                onChanged: (v) => setState(() => ignoreTime = !v),
              ),
            ],
          ),
        ),
        const SectionTitle('Your age'),
        Pane(
          tint: p.accent.withValues(alpha: 0.10),
          child: Column(
            children: [
              if (r.negative)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.dp),
                  child: Text(
                    'Birth date is after the "age on" date',
                    style: TextStyle(color: p.sub, fontSize: 12.5.sp),
                  ),
                ),
              Row(
                children: [
                  Expanded(child: BigFigure(n(r.years), 'Years', size: 44.dp)),
                  Expanded(
                    child: BigFigure(n(r.months), 'Months', size: 30.dp),
                  ),
                  Expanded(child: BigFigure(n(r.days), 'Days', size: 30.dp)),
                ],
              ),
              if (!ignoreTime) ...[
                SizedBox(height: 10.dp),
                Text(
                  'and ${plural(r.hours, 'hour')} ${plural(r.minutes, 'minute')}',
                  style: TextStyle(color: p.sub, fontSize: 14.sp),
                ),
              ],
            ],
          ),
        ),
        Gap(12.dp),
        // Wide: the card ends the left column and is stretched level with
        // the totals, so it stacks big and centred rather than leaving a
        // one-line row floating in an empty card.
        if (pageColumns(context, minColumn: 380) > 1)
          Pane(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44.dp,
                  height: 44.dp,
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(13.dp),
                  ),
                  child: Icon(CupertinoIcons.gift_fill, color: p.accent),
                ),
                SizedBox(height: 10.dp),
                Text(
                  nb.daysAway == 0 ? 'Today' : plural(nb.daysAway, 'day'),
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  nb.daysAway == 0
                      ? 'Happy birthday!'
                      : 'until your next birthday',
                  style: TextStyle(color: p.sub, fontSize: 14.sp),
                ),
                SizedBox(height: 4.dp),
                Text(
                  '${DateFormat('EEEE').format(nb.date)}, ${s.date(nb.date)} · turning ${nb.turning}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.sub, fontSize: 13.sp),
                ),
              ],
            ),
          )
        else
        Pane(
          child: Row(
            children: [
              Container(
                width: 46.dp,
                height: 46.dp,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14.dp),
                ),
                child: Icon(CupertinoIcons.gift_fill, color: p.accent),
              ),
              SizedBox(width: 14.dp),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nb.daysAway == 0
                          ? 'Happy birthday!'
                          : 'Next birthday in ${plural(nb.daysAway, 'day')}',
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.dp),
                    Text(
                      '${DateFormat('EEEE').format(nb.date)}, ${s.date(nb.date)} · turning ${nb.turning}',
                      style: TextStyle(color: p.sub, fontSize: 13.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Totals'),
        StatGrid([
          (n(r.totalMonths), 'Months'),
          (n(r.totalWeeks), 'Weeks'),
          (n(r.totalDays), 'Days'),
          (n(r.totalHours), 'Hours'),
          (n(r.totalMinutes), 'Minutes'),
          (n(r.totalSeconds), 'Seconds'),
        ]),
        ResultActions(
          shareText: text,
          onReset: () => setState(() {
            birth = DateTime(2000, 1, 1);
            on = _now();
            ignoreTime = true;
          }),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────── Weekday

class WeekdayScreen extends StatefulWidget {
  const WeekdayScreen({super.key});
  @override
  State<WeekdayScreen> createState() => _WeekdayScreenState();
}

class _WeekdayScreenState extends State<WeekdayScreen> {
  DateTime date = _now();

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Pal.of(context);
    String text() => '${s.date(date)} is a ${DateFormat('EEEE').format(date)}';

    return ToolScreen(
      title: 'Weekday',
      children: [
        Pane(
          child: DateTimeField(
            label: 'Date',
            value: date,
            onChanged: (v) => setState(() => date = v),
          ),
        ),
        const SectionTitle('It falls on'),
        Pane(
          tint: p.accent.withValues(alpha: 0.10),
          child: Row(
            children: [
              _DayTile(date: date),
              SizedBox(width: 16.dp),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        DateFormat('EEEE').format(date),
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 30.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Text(
                      '${s.date(date)} · ${date.weekday >= 6 ? 'Weekend' : 'Weekday'}',
                      style: TextStyle(color: p.sub, fontSize: 13.5.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Gap(12.dp),
        // Two pieces, so a wide page can set them side by side.
        YearGlance(date: date, stats: false),
        Gap(12.dp),
        YearGlance(date: date, progress: false),
        ResultActions(
          shareText: text,
          onReset: () => setState(() => date = _now()),
        ),
      ],
    );
  }
}

/// Year facts for one date, shared by Weekday and the Today tab.
class YearGlance extends StatelessWidget {
  const YearGlance({
    super.key,
    required this.date,
    this.progress = true,
    this.stats = true,
    this.statsPerRow,
  });
  final DateTime date;

  /// Which parts to draw: a wide page puts the progress card beside the
  /// tools and the stat tiles in a full-width band under both.
  final bool progress;
  final bool stats;
  final int? statsPerRow;

  Widget _bar(
    Pal p, {
    required String title,
    required double value,
    required String from,
    required String left,
    required String to,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Caption(title),
          const Spacer(),
          Text(
            '${(value * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              color: p.accent,
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      SizedBox(height: 12.dp),
      ProgressBar(value: value),
      SizedBox(height: 10.dp),
      Row(
        children: [
          Text(
            from,
            style: TextStyle(color: p.sub, fontSize: 12.sp),
          ),
          SizedBox(width: 8.dp),
          Expanded(
            child: Text(
              left,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.ink,
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 8.dp),
          Text(
            to,
            style: TextStyle(color: p.sub, fontSize: 12.sp),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Pal.of(context);
    final doy = dayOfYear(date);
    final total = daysInYear(date.year);
    final prog = yearProgress(date);
    final leap = nextLeapDay(date);
    final toLeap = leap.difference(dateOnly(date)).inDays;
    final parts = <Widget>[
      if (progress)
        Pane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(
                p,
                title: 'Year progress',
                value: prog,
                from: 'Jan 1',
                left: '${n(total - doy)} days left',
                to: 'Dec 31',
              ),
              // The month under the year: the card stretches to match the
              // column beside it on wide screens, and a second bar fills it
              // with something worth reading instead of empty glass.
              SizedBox(height: 22.dp),
              _bar(
                p,
                title: DateFormat('MMMM').format(date),
                value: date.day / daysInMonth(date.year, date.month),
                from: '1 ${DateFormat('MMM').format(date)}',
                left:
                    '${plural(daysInMonth(date.year, date.month) - date.day, 'day')} left',
                to:
                    '${daysInMonth(date.year, date.month)} '
                    '${DateFormat('MMM').format(date)}',
              ),
            ],
          ),
        ),
      if (progress && stats) Gap(12.dp),
      if (stats)
        StatGrid(perRow: statsPerRow, [
          ('$doy', 'Day of year · of $total'),
          (
            '${weekOfYear(date, mondayFirst: s.mondayFirst)}',
            'Week · of ${weeksInYear(date.year, mondayFirst: s.mondayFirst)}',
          ),
          ('Q${quarterOf(date)}', 'Quarter'),
          (
            isLeapYear(date.year) ? 'Leap' : 'Common',
            '${date.year} · $total days',
          ),
          (
            toLeap == 0 ? 'Today' : n(toLeap),
            toLeap == 0 ? 'Feb 29 is today' : 'Days to Feb 29, ${leap.year}',
          ),
          (
            n(daysInMonth(date.year, date.month)),
            'Days in ${DateFormat('MMMM').format(date)}',
          ),
        ]),
    ];
    // Alone, the progress card is returned as itself, so a wide page can
    // stretch it to level its column.
    return parts.length == 1 ? parts.first : Column(children: parts);
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6.dp),
      child: SizedBox(
        height: 10.dp,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: p.faint),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6.dp),
                  gradient: LinearGradient(
                    colors: [p.accent.withValues(alpha: 0.75), p.accent],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny calendar leaf: month band over the day number.
class _DayTile extends StatelessWidget {
  const _DayTile({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // A calendar page: white in light mode, a raised dark page in dark mode.
    // The dark page is lighter than the card and carries a rim, or it
    // vanishes into the card behind it.
    return Container(
      width: 64.dp,
      height: 68.dp,
      decoration: BoxDecoration(
        color: p.dark ? const Color(0xFF3A3C46) : Colors.white,
        border: p.dark
            ? Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1)
            : null,
        borderRadius: BorderRadius.circular(16.dp),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.35 : 0.12),
            blurRadius: 10.dp,
            offset: Offset(0, 4.dp),
          ),
        ],
      ),
      // Month and day sit together as one block, centred on the page.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat('MMM').format(date).toUpperCase(),
              style: TextStyle(
                color: p.accent,
                fontSize: 11.sp,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 4.dp),
            Text(
              '${date.day}',
              style: TextStyle(
                color: p.dark ? Colors.white : const Color(0xFF222222),
                fontSize: 30.sp,
                height: 1,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────── Working days

class WorkingDaysScreen extends StatefulWidget {
  const WorkingDaysScreen({super.key});
  @override
  State<WorkingDaysScreen> createState() => _WorkingDaysScreenState();
}

class _WorkingDaysScreenState extends State<WorkingDaysScreen> {
  late DateTime start, end;
  bool includeEnd = true;

  @override
  void initState() {
    super.initState();
    end = _now();
    start = DateTime(end.year, end.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Pal.of(context);
    final work = s.workdays;
    final r = workingDays(start, end, work, includeEnd: includeEnd);
    final order = s.mondayFirst ? [1, 2, 3, 4, 5, 6, 7] : [7, 1, 2, 3, 4, 5, 6];
    String name(int d, String pat) =>
        DateFormat(pat).format(DateTime(2024, 1, d)); // 1 Jan 2024 = Monday
    String text() =>
        '${s.date(start)} → ${s.date(end)}: ${plural(r.working, 'working day')}, '
        '${plural(r.nonWorking, 'day')} off';

    return ToolScreen(
      title: 'Working Days',
      children: [
        Pane(
          child: Column(
            children: [
              DateTimeField(
                label: 'Start',
                value: start,
                onChanged: (v) => setState(() => start = v),
              ),
              const Hairline(),
              DateTimeField(
                label: 'End',
                value: end,
                onChanged: (v) => setState(() => end = v),
              ),
              const Hairline(),
              SwitchRow(
                label: 'Include end date',
                value: includeEnd,
                onChanged: (v) => setState(() => includeEnd = v),
              ),
            ],
          ),
        ),
        const SectionTitle('Working week'),
        Pane(
          padding: EdgeInsets.fromLTRB(10.dp, 14.dp, 10.dp, 14.dp),
          child: Row(
            children: [
              for (final d in order)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: work.contains(d),
                    label: name(d, 'EEEE'),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final next = {...work};
                        next.contains(d) ? next.remove(d) : next.add(d);
                        s.workdays = next;
                      },
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            width: 38.dp,
                            height: 38.dp,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: work.contains(d) ? p.accent : p.faint,
                            ),
                            child: Text(
                              name(d, 'EEEEE'),
                              style: TextStyle(
                                color: work.contains(d) ? Colors.white : p.sub,
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SectionTitle('Result'),
        Pane(
          tint: p.accent.withValues(alpha: 0.10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: BigFigure(n(r.working), 'Working days', size: 40.dp),
                  ),
                  Expanded(
                    child: BigFigure(n(r.nonWorking), 'Days off', size: 40.dp),
                  ),
                ],
              ),
              const Hairline(),
              for (final d in order)
                ResultLine(
                  '${name(d, 'EEEE')}${work.contains(d) ? '' : '  · off'}',
                  n(r.perWeekday[d] ?? 0),
                ),
              const Hairline(),
              ResultLine('Total days', n(r.working + r.nonWorking)),
            ],
          ),
        ),
        ResultActions(
          shareText: text,
          onReset: () => setState(() {
            end = _now();
            start = DateTime(end.year, end.month, 1);
            includeEnd = true;
            s.workdays = {1, 2, 3, 4, 5};
          }),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────── Leap year

class LeapYearScreen extends StatefulWidget {
  const LeapYearScreen({super.key});
  @override
  State<LeapYearScreen> createState() => _LeapYearScreenState();
}

class _LeapYearScreenState extends State<LeapYearScreen> {
  int year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final leap = isLeapYear(year);
    final today = DateTime.now();
    final last = previousLeapYear(year), next = nextLeapYear(year);
    final upcoming = <int>[];
    for (var y = next; upcoming.length < 5; y = nextLeapYear(y)) {
      upcoming.add(y);
    }
    String reason() {
      if (year % 400 == 0) {
        return 'Divisible by 400, so century rule allows it.';
      }
      if (year % 100 == 0) return 'A century year not divisible by 400.';
      if (year % 4 == 0) return 'Divisible by 4.';
      return 'Not divisible by 4.';
    }

    String text() =>
        '$year ${leap ? 'is' : 'is not'} a leap year (${daysInYear(year)} days)';

    Widget arrow(IconData icon, String label, int delta) => RoundGlassButton(
      icon: icon,
      size: 52.dp,
      semanticLabel: label,
      onPressed: () {
        HapticFeedback.selectionClick();
        setState(() => year = (year + delta).clamp(1, 9999));
      },
    );

    return ToolScreen(
      title: 'Leap Year',
      children: [
        Row(
          children: [
            arrow(CupertinoIcons.chevron_left, 'Previous year', -1),
            SizedBox(width: 12.dp),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => year = today.year),
                child: Pane(
                  padding: EdgeInsets.symmetric(vertical: 12.dp),
                  child: Column(
                    children: [
                      Text(
                        '$year',
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 30.sp,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Caption(
                        year == today.year ? 'This year' : 'Tap for this year',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.dp),
            arrow(CupertinoIcons.chevron_right, 'Next year', 1),
          ],
        ),
        Gap(14.dp),
        Pane(
          tint: (leap ? p.accent : p.sub).withValues(alpha: 0.10),
          child: Row(
            children: [
              Container(
                width: 52.dp,
                height: 52.dp,
                decoration: BoxDecoration(
                  color: leap ? p.accent : p.faint,
                  borderRadius: BorderRadius.circular(16.dp),
                ),
                alignment: Alignment.center,
                child: Text(
                  leap ? '29' : '28',
                  style: TextStyle(
                    color: leap ? Colors.white : p.sub,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 14.dp),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      leap
                          ? '$year is a leap year'
                          : '$year is not a leap year',
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2.dp),
                    Text(
                      '${daysInYear(year)} days. ${reason()}',
                      style: TextStyle(color: p.sub, fontSize: 13.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Four-year cycle'),
        Pane(
          padding: EdgeInsets.fromLTRB(8.dp, 16.dp, 8.dp, 16.dp),
          child: Row(
            children: [
              for (var y = year - 1; y <= year + 2; y++)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$y',
                        style: TextStyle(
                          color: y == year ? p.accent : p.ink,
                          fontSize: 16.sp,
                          fontWeight: y == year
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8.dp),
                      Container(
                        width: 10.dp,
                        height: 10.dp,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLeapYear(y) ? p.accent : Colors.transparent,
                          border: Border.all(
                            color: isLeapYear(y) ? p.accent : p.sub,
                            width: 1.4.dp,
                          ),
                        ),
                      ),
                      SizedBox(height: 6.dp),
                      Text(
                        isLeapYear(y) ? 'Leap' : '',
                        style: TextStyle(color: p.accent, fontSize: 11.sp),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SectionTitle('At a glance'),
        StatGrid([
          ('$last', 'Last leap year'),
          ('$next', 'Next leap year'),
          (
            n(nextLeapDay(today).difference(dateOnly(today)).inDays),
            'Days until Feb 29',
          ),
          (n(daysInYear(year)), 'Days in $year'),
        ]),
        const SectionTitle('Upcoming leap years'),
        // The rule sits inside the card, under a hairline, so the card is
        // the page's last block and can stretch level with the other column.
        Pane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final y in upcoming)
                ResultLine(
                  '$y',
                  y - year == 1 ? 'next year' : 'in ${y - year} years',
                ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12.dp),
                child: Divider(height: 1, thickness: 1, color: p.faint),
              ),
              Text(
                'A leap year has 366 days, with 29 February. Years divisible by 4 are leap years, '
                'except century years, which must also be divisible by 400.',
                style: TextStyle(color: p.sub, fontSize: 12.5.sp, height: 1.4),
              ),
            ],
          ),
        ),
        ResultActions(shareText: text),
      ],
    );
  }
}
