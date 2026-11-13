import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../logic/date_math.dart';
import '../state/settings.dart';
import 'glass_tabs.dart';
import 'kit.dart';
import 'scale.dart';
import 'tools.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  static const titles = ['Today', 'Tools', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // Back from Tools or Settings goes to Today; back from Today leaves.
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => tab = 0);
      },
      child: _scaffold(p),
    );
  }

  Widget _scaffold(Pal p) {
    return GlassScaffold(
      background: const GradientBackground(),
      statusBarStyle: p.dark ? GlassStatusBarStyle.light : GlassStatusBarStyle.dark,
      appBar: GlassAppBar(
        title: Text(titles[tab],
            style: TextStyle(color: p.ink, fontSize: 17.sp, fontWeight: FontWeight.w600)),
      ),
      // The compass app's sheet glass as a floating capsule, with a pill
      // that slides under the selected tab.
      bottomBarHeight: 64.dp,
      bottomBar: GlassTabs(
        selected: tab,
        onSelected: (i) => setState(() => tab = i),
        items: const [
          (CupertinoIcons.calendar_today, 'Today'),
          (CupertinoIcons.square_grid_2x2_fill, 'Tools'),
          (CupertinoIcons.gear_alt_fill, 'Settings'),
        ],
      ),
      // Only the visible tab is built (a glass surface in an offstage tab is
      // still drawn), and it switches instantly, as an iOS tab bar does: the
      // bar's own indicator is the animation.
      body: KeyedSubtree(
        key: ValueKey(tab),
        child: const [TodayTab(), ToolsTab(), SettingsTab()][tab],
      ),
    );
  }
}

// ───────────────────────────────────────────── Today

class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final now = DateTime.now();
    final isWide = MediaQuery.sizeOf(context).width >= 720.dp;

    final heroCard = Pane(
      tint: p.accent.withValues(alpha: 0.035),
      padding: EdgeInsets.fromLTRB(22.dp, 20.dp, 22.dp, 22.dp),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Caption(DateFormat('EEEE').format(now), color: p.accent),
        SizedBox(height: 4.dp),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${now.day}',
              style: TextStyle(
                  color: p.ink, fontSize: 76.sp, height: 1, fontWeight: FontWeight.w300, letterSpacing: -3)),
          SizedBox(width: 12.dp),
          Padding(
            padding: EdgeInsets.only(bottom: 8.dp),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('MMMM').format(now),
                  style: TextStyle(color: p.ink, fontSize: 22.sp, fontWeight: FontWeight.w600)),
              Text('${now.year}', style: TextStyle(color: p.sub, fontSize: 16.sp)),
            ]),
          ),
        ]),
      ]),
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 960.dp : 640.dp),
        child: ListView(
          padding: pagePadding(context, tabBar: true),
          children: isWide
              ? [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            heroCard,
                            Gap(12.dp),
                            YearGlance(date: now),
                          ],
                        ),
                      ),
                      Gap(20.dp),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: const [
                            SectionTitle('Quick tools'),
                            _ToolList(limit: 3),
                          ],
                        ),
                      ),
                    ],
                  ),
                ]
              : [
                  heroCard,
                  Gap(12.dp),
                  YearGlance(date: now),
                  const SectionTitle('Quick tools'),
                  const _ToolList(limit: 3),
                ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────── Tools

class _Tool {
  const _Tool(this.title, this.subtitle, this.icon, this.color, this.page, {this.glyph});
  final String title, subtitle;
  final IconData icon;

  /// Text drawn in the tile instead of [icon] (Leap Year shows "29").
  final String? glyph;
  final Color color;
  final Widget Function() page;
}

final _tools = <_Tool>[
  _Tool('Between Dates', 'Years, months, days and time between two dates',
      CupertinoIcons.hourglass, const Color(0xFF1E7BF2), () => const BetweenScreen()),
  _Tool('Age', 'Exact age, next birthday and totals', Icons.cake_rounded,
      const Color(0xFFE5407F), () => const AgeScreen()),
  _Tool('Add or Subtract', 'Move a date forward or back', Icons.calculate_rounded,
      const Color(0xFFF08A1D), () => const AddScreen()),
  _Tool('Working Days', 'Business days between two dates', CupertinoIcons.briefcase_fill,
      const Color(0xFF14A37F), () => const WorkingDaysScreen()),
  _Tool('Weekday', 'The day of the week for any date', CupertinoIcons.calendar,
      const Color(0xFF6A4CF5), () => const WeekdayScreen()),
  _Tool('Leap Year', 'Check any year for 29 February', CupertinoIcons.calendar_badge_plus,
      const Color(0xFFF2564B), () => const LeapYearScreen(), glyph: '29'),
];

class ToolsTab extends StatelessWidget {
  const ToolsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 720.dp;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 960.dp : 640.dp),
        child: ListView(
          padding: pagePadding(context, tabBar: true),
          children: const [_ToolList()],
        ),
      ),
    );
  }
}

class _ToolList extends StatelessWidget {
  const _ToolList({this.limit});
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final list = limit == null ? _tools : _tools.take(limit!).toList();
    final isWide = MediaQuery.sizeOf(context).width >= 720.dp && limit == null;

    if (isWide) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 460.dp,
          mainAxisSpacing: 12.dp,
          crossAxisSpacing: 12.dp,
          mainAxisExtent: 88.dp,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) => Pane(
          padding: EdgeInsets.zero,
          child: _ToolRow(tool: list[i]),
        ),
      );
    }

    return Pane(
      padding: EdgeInsets.symmetric(vertical: 6.dp),
      child: Column(children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.only(left: 70.dp),
              child: Container(height: 0.6, color: p.faint),
            ),
          _ToolRow(tool: list[i]),
        ],
      ]),
    );
  }
}

class _ToolRow extends StatefulWidget {
  const _ToolRow({required this.tool});
  final _Tool tool;
  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.tool;
    return Semantics(
      button: true,
      label: '${t.title}. ${t.subtitle}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => down = true),
        onTapCancel: () => setState(() => down = false),
        onTapUp: (_) => setState(() => down = false),
        onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => t.page())),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: EdgeInsets.symmetric(horizontal: 6.dp),
          padding: EdgeInsets.symmetric(horizontal: 10.dp, vertical: 16.dp),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18.dp),
            color: down ? p.faint : Colors.transparent,
          ),
          child: Row(children: [
            Container(
              width: 40.dp,
              height: 40.dp,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.dp),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(t.color, Colors.white, 0.18)!, t.color],
                ),
              ),
              alignment: Alignment.center,
              child: t.glyph == null
                  ? Icon(t.icon, color: Colors.white, size: 21.dp)
                  : Text(t.glyph!,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: t.glyph!.length == 1 ? 26.sp : 17.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1)),
            ),
            SizedBox(width: 14.dp),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, style: TextStyle(color: p.ink, fontSize: 16.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 2.dp),
                Text(t.subtitle, style: TextStyle(color: p.sub, fontSize: 12.5.sp)),
              ]),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16.dp, color: p.sub),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────── Settings

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Pal.of(context);
    final sample = DateTime(DateTime.now().year, 7, 17);
    final isWide = MediaQuery.sizeOf(context).width >= 720.dp;

    final lookColumn = [
      const SectionTitle('Appearance'),
      Segments<Appearance>(
        values: Appearance.values,
        labels: const ['System', 'Light', 'Dark'],
        selected: s.appearance,
        onChanged: (v) => s.appearance = v,
      ),
      Gap(12.dp),
      Pane(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Caption('Colour'),
            const Spacer(),
            Text(s.accent.name, style: TextStyle(color: p.accent, fontSize: 13.sp, fontWeight: FontWeight.w600)),
          ]),
          SizedBox(height: 14.dp),
          Wrap(spacing: 12.dp, runSpacing: 12.dp, children: [
            for (var i = 0; i < accents.length; i++)
              Semantics(
                button: true,
                selected: i == s.accentIndex,
                label: accents[i].name,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => s.accentIndex = i,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: 40.dp,
                    height: 40.dp,
                    padding: EdgeInsets.all(3.dp),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: i == s.accentIndex ? accents[i].color : Colors.transparent, width: 2.2.dp),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [accents[i].light[1], accents[i].color],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    ];

    final preferencesColumn = [
      const SectionTitle('Date format'),
      Pane(
        padding: EdgeInsets.fromLTRB(18.dp, 6.dp, 18.dp, 6.dp),
        child: Column(children: [
          for (final f in dateFormats)
            Semantics(
              button: true,
              selected: f == s.dateFormat,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => s.dateFormat = f,
                child: SizedBox(
                  height: 48.dp,
                  child: Row(children: [
                    Expanded(
                      child: Text(DateFormat(f).format(sample),
                          style: TextStyle(color: p.ink, fontSize: 15.5.sp)),
                    ),
                    if (f == s.dateFormat) Icon(CupertinoIcons.checkmark_alt, color: p.accent, size: 20.dp),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      const SectionTitle('Preferences'),
      Pane(
        child: Column(children: [
          SwitchRow(
              label: '24-hour time',
              hint: s.time(DateTime(2026, 1, 1, 17, 30)),
              value: s.use24h,
              onChanged: (v) => s.use24h = v),
          const Hairline(),
          SwitchRow(
              label: 'Week starts on Monday',
              hint: s.mondayFirst ? 'ISO week numbers' : 'Sunday first, US week numbers',
              value: s.mondayFirst,
              onChanged: (v) => s.mondayFirst = v),
          const Hairline(),
          SwitchRow(
              label: 'Share button',
              hint: 'Show Share under results',
              value: s.showShare,
              onChanged: (v) => s.showShare = v),
        ]),
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 960.dp : 640.dp),
        child: ListView(
          padding: pagePadding(context, tabBar: true),
          children: [
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: lookColumn)),
                  Gap(20.dp),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: preferencesColumn)),
                ],
              )
            else ...[
              ...lookColumn,
              ...preferencesColumn,
            ],
            Gap(24.dp),
            Center(
              child: Text('Dates · ${dayOfYear(DateTime.now())} days into ${DateTime.now().year}',
                  style: TextStyle(color: p.sub, fontSize: 12.sp)),
            ),
          ],
        ),
      ),
    );
  }
}
