import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../state/settings.dart';
import 'ambient.dart';
import 'glass_chrome.dart';
import 'glass_surface.dart';
import 'motion.dart';
import 'scale.dart';

export 'glass_chrome.dart';
export 'motion.dart';

final numberFmt = NumberFormat.decimalPattern();
String n(num v) => numberFmt.format(v);

/// Colours for text and accents on top of the glass.
class Pal {
  Pal._(this.dark, this.accentRaw);
  factory Pal.of(BuildContext context) => Pal._(
    Theme.of(context).brightness == Brightness.dark,
    SettingsScope.of(context).accent.color,
  );

  final bool dark;

  /// The pure brand colour, for swatches and filled chips that carry their
  /// own light text — never trust it as a foreground on the glass.
  final Color accentRaw;

  /// The accent adjusted so it always reads as text or an icon on the glass.
  /// A dark accent (Graphite) vanishes against the dark field; a very pale one
  /// would wash out on the light field. [_readable] lifts or deepens its
  /// lightness into a legible band for the current theme, so every accent keeps
  /// its hue while staying visible. The hue and saturation are untouched, so
  /// Coral still reads coral and Graphite still reads slate.
  late final Color accent = _readable(accentRaw, dark);

  Color get ink => dark ? Colors.white : const Color(0xFF14151A);
  Color get sub => dark ? const Color(0xB3FFFFFF) : const Color(0x9914151A);
  Color get faint => dark ? const Color(0x1FFFFFFF) : const Color(0x1414151A);

  static Color _readable(Color c, bool dark) {
    if (!dark) return c;
    final hsl = HSLColor.fromColor(c);
    // Only a near-grey accent (Graphite) disappears on the dark field — a
    // saturated colour carries itself by its chroma, so the vivid accents are
    // left exactly as shipped. We lift lightness only when there is little
    // colour to rely on.
    if (hsl.saturation < 0.25 && hsl.lightness < 0.62) {
      return hsl.withLightness(0.70).toColor();
    }
    return c;
  }
}

/// The colour field behind every screen. Glass refracts and blurs what is
/// behind it, so a flat background makes it read as plain grey: a soft,
/// multi-stop diagonal gradient is what lets the liquid effect show.
class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key});

  @override
  Widget build(BuildContext context) =>
      AmbientBackground(accent: SettingsScope.of(context).accent.color);
}

/// Padding that clears the glass app bar on top and the tab bar below.
EdgeInsets pagePadding(BuildContext context, {bool tabBar = false}) {
  final mq = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(
    16,
    mq.top + GlassAppBar.gap + GlassAppBar.barHeight + 14,
    16,
    mq.bottom + (tabBar ? 64.dp + 14.dp + 20.dp : 28.dp),
  );
}

/// A page's scrolling column. On a wide screen a page shorter than the
/// window sits in its vertical middle instead of leaving a band of empty
/// space under it; a phone keeps the usual top-aligned list.
class PageScroll extends StatelessWidget {
  const PageScroll({
    super.key,
    required this.padding,
    required this.children,
    this.top = false,
    this.fill = false,
    this.fit = false,
  });
  final EdgeInsets padding;
  final List<Widget> children;

  /// Keep the page under its title on a wide screen too. A dense page
  /// (Today, Tools) floating in the middle leaves a band of nothing
  /// between the title and the content.
  final bool top;

  /// On a wide screen, stretch the page to the window's height: children
  /// wrapped in Expanded share what is left, so a short page grows into
  /// the screen instead of sitting small in it.
  final bool fill;

  /// On a wide screen, never run under the tab bar: a page taller than the
  /// window (a short 1280 x 720 desktop) is scaled down to fit between the
  /// title and the bar, centred. For pages that are one screen by design.
  final bool fit;

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    if (wide && fill) {
      return LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, c.maxHeight - padding.vertical),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      );
    }
    if (!wide || top) {
      return ListView(padding: padding, children: children);
    }
    // Centre between the page title and the top of the tab bar. The top
    // padding reserves the whole title bar, whose text sits high in it, so
    // the true middle is a little above the padded box's middle.
    final lift = 12.dp;
    final centred = padding.copyWith(
      top: math.max(0.0, padding.top - lift),
      bottom: padding.bottom + lift,
    );
    if (fit) {
      return LayoutBuilder(
        builder: (context, c) => Padding(
          padding: centred,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: math.max(0.0, c.maxWidth - centred.horizontal),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        padding: centred,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, c.maxHeight - centred.vertical),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A pushed tool screen: glass bar with a back button, gradient behind.
class ToolScreen extends StatelessWidget {
  const ToolScreen({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return GlassScaffold(
      background: const GradientBackground(),
      statusBarStyle: p.dark
          ? GlassStatusBarStyle.light
          : GlassStatusBarStyle.dark,
      appBar: GlassAppBar(
        title: Text(
          title,
          style: TextStyle(
            color: p.ink,
            fontSize: isWideLayout(context) ? 20.sp : 17.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Lined up with the cards' left edge (the bar adds its own 8).
        leading: Padding(
          padding: EdgeInsets.only(left: 8.dp),
          child: RoundGlassButton(
            icon: CupertinoIcons.chevron_back,
            semanticLabel: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      bottomBarHeight: _actions == null ? 0 : 58.dp,
      bottomBar: _actions == null
          ? null
          : SpringIn(
              key: const ValueKey('actions'),
              from: Offset(0, 110.dp),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24.dp,
                  0,
                  24.dp,
                  math.max(MediaQuery.paddingOf(context).bottom + 14.dp, 24.dp),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 440.dp),
                    child: ResultActions(
                      shareText: _actions!.shareText,
                      onReset: _actions!.onReset,
                      bar: true,
                    ),
                  ),
                ),
              ),
            ),
      body: Listener(
        onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
            child: PageScroll(
              padding: pagePadding(context, tabBar: _actions != null),
              children: _layout(context),
            ),
          ),
        ),
      ),
    );
  }

  /// A phone gets one column. A wide screen lays the page out the way an
  /// iPad or desktop app does: what you set (the input cards, with Reset /
  /// Copy / Share under them) heads the left column, and every result block,
  /// its heading kept with its card, goes into whichever column is shorter,
  /// so the two come out level instead of one long column beside an empty one.
  /// Reset / Copy / Share, shown as the floating bottom toolbar.
  ResultActions? get _actions =>
      children.whereType<ResultActions>().firstOrNull;

  List<Widget> _layout(BuildContext context) {
    final children = this.children.where((w) => w is! ResultActions).toList();
    Widget rise(Widget w, int i) => SpringIn(
      from: Offset(0, 18.dp + 6.dp * i.clamp(0, 6)),
      soft: true,
      child: w,
    );

    final wide = pageColumns(context, minColumn: 380) > 1;
    if (!wide) {
      return [for (var i = 0; i < children.length; i++) rise(children[i], i)];
    }

    var split = children.indexWhere((w) => w is SectionTitle);
    if (split < 0) split = 1;
    final inputs = children.sublist(0, split).where((w) => w is! Gap).toList();
    final rest = children.sublist(split).where((w) => w is! Gap).toList();

    // Blocks: a heading always travels with the card under it.
    final blocks = <List<Widget>>[];
    for (var i = 0; i < rest.length; i++) {
      if (rest[i] is SectionTitle && i + 1 < rest.length) {
        blocks.add([rest[i], rest[++i]]);
      } else {
        blocks.add([rest[i]]);
      }
    }

    // Measured at its own height first; given a taller fixed height (to
    // end level with the other column), its last card takes the extra. One
    // fixed structure either way, so nothing below is rebuilt by it.
    Widget stack(List<Widget> items) => _StretchLast(
      children: [
        ...items.sublist(0, items.length - 1),
        _PaneFill(fill: true, child: items.last),
      ],
    );
    final lead = <Widget>[
      // The first card on each side sits level: results open with a
      // heading, so the inputs get one too.
      if (blocks.isNotEmpty && blocks.first.first is SectionTitle)
        const SectionTitle('Choose'),
      for (var i = 0; i < inputs.length; i++) ...[
        if (i > 0) Gap(12.dp),
        inputs[i],
      ],
    ];
    return [
      BalancedColumns(
        gap: 20.dp,
        children: [
          BalancedBlock(
            heading: true,
            // The same 12 under the inputs as under every other block, or
            // the card placed beneath them sits flush against them.
            child: rise(
              Padding(
                padding: EdgeInsets.only(bottom: 12.dp),
                child: stack(lead),
              ),
              0,
            ),
          ),
          for (var i = 0; i < blocks.length; i++)
            BalancedBlock(
              heading: blocks[i].first is SectionTitle,
              child: rise(
                Padding(
                  padding: EdgeInsets.only(bottom: 12.dp),
                  child: stack(blocks[i]),
                ),
                i + 1,
              ),
            ),
        ],
      ),
    ];
  }
}

/// Two columns filled like a masonry wall: the first child heads the left
/// column, and each child after it goes into whichever column is shorter at
/// that moment, so the columns end about level whatever the content.
class BalancedColumns extends MultiChildRenderObjectWidget {
  const BalancedColumns({super.key, required this.gap, super.children});
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBalancedColumns(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBalancedColumns renderObject,
  ) => renderObject.gap = gap;
}

class _BalancedData extends ContainerBoxParentData<RenderBox> {
  /// Whether this block opens with a section heading.
  bool heading = false;
}

/// Marks a [BalancedColumns] block that opens with a section heading.
class BalancedBlock extends ParentDataWidget<_BalancedData> {
  const BalancedBlock({super.key, required this.heading, required super.child});
  final bool heading;

  @override
  void applyParentData(RenderObject renderObject) {
    final d = renderObject.parentData! as _BalancedData;
    if (d.heading != heading) {
      d.heading = heading;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => BalancedColumns;
}

class RenderBalancedColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BalancedData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BalancedData> {
  RenderBalancedColumns(this._gap);

  List<bool> _heads = [];
  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BalancedData) child.parentData = _BalancedData();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    final col = (w - _gap) / 2;
    final kids = <RenderBox>[];
    _heads = [];
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(BoxConstraints.tightFor(width: col), parentUsesSize: true);
      kids.add(c);
      _heads.add((c.parentData! as _BalancedData).heading);
    }
    // Every way to send the blocks after the first left or right (each
    // column keeps reading order), keeping the one whose columns end most
    // level. A screen has a handful of blocks, so this is a few hundred
    // sums at most; past 12 it falls back to "the shorter column".
    final n = kids.length;
    var best = 0;
    if (n > 1 && n <= 13) {
      var bestTall = double.infinity;
      for (var mask = 0; mask < 1 << (n - 1); mask++) {
        var l = kids[0].size.height, r = 0.0;
        for (var i = 1; i < n; i++) {
          if (mask & (1 << (i - 1)) != 0) {
            r += kids[i].size.height;
          } else {
            l += kids[i].size.height;
          }
        }
        // The right column should open on a heading, level with the
        // left's, so a split that starts it on a bare card costs extra.
        var firstRight = 0;
        while (firstRight < n - 1 && mask & (1 << firstRight) == 0) {
          firstRight++;
        }
        final bare = firstRight < n - 1 && !_heads[firstRight + 1];
        final tall = (l > r ? l : r) + (bare ? 60 : 0);
        if (tall < bestTall - 0.5) {
          bestTall = tall;
          best = mask;
        }
      }
    }
    final heights = [0.0, 0.0];
    final lastOn = [-1, -1];
    for (var i = 0; i < n; i++) {
      final int side;
      if (i == 0) {
        side = 0;
      } else if (n <= 13) {
        side = best & (1 << (i - 1)) != 0 ? 1 : 0;
      } else {
        side = heights[1] < heights[0] ? 1 : 0;
      }
      (kids[i].parentData! as _BalancedData).offset = Offset(
        side == 0 ? 0 : col + _gap,
        heights[side],
      );
      heights[side] += kids[i].size.height;
      lastOn[side] = i;
    }
    // Level the two columns: the shorter one's last block is laid out again
    // that much taller, and its last card takes up the difference.
    final short = heights[0] < heights[1] ? 0 : 1;
    final diff = (heights[0] - heights[1]).abs();
    final k = lastOn[short];
    if (diff > 1 && k >= 0) {
      final kid = kids[k];
      kid.layout(
        BoxConstraints.tightFor(width: col, height: kid.size.height + diff),
        parentUsesSize: true,
      );
      heights[short] += diff;
    }
    size = constraints.constrain(
      Size(w, heights[0] > heights[1] ? heights[0] : heights[1]),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// The widest the content gets: a phone column on a phone, more on a
/// tablet or desktop.
double contentMaxWidth(BuildContext context) =>
    isWideLayout(context) ? 1040.dp : 640.dp;

/// How many columns the page gets: as many as fit at [minColumn] each, so an
/// unfolded foldable (about 600 wide) keeps one roomy column and a tablet or
/// desktop window gets two. Text never has to squeeze to fit.
int pageColumns(BuildContext context, {double minColumn = 430, int max = 2}) {
  final room =
      math.min(MediaQuery.sizeOf(context).width, contentMaxWidth(context)) - 32;
  final gap = 20.dp;
  return ((room + gap) / (minColumn.dp + gap)).floor().clamp(1, max);
}

/// A glass card. Content inside stays plain; no glass buttons nest in it.
class Pane extends StatelessWidget {
  const Pane({super.key, required this.child, this.padding, this.tint});
  final Widget child;
  final EdgeInsets? padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    // A card stretched to level two columns keeps its content in its
    // middle; cards inside it are not stretched.
    final fill = _PaneFill.of(context);
    return GlassSurface(
      radius: 18.dp,
      padding: padding ?? EdgeInsets.fromLTRB(18.dp, 16.dp, 18.dp, 16.dp),
      tint: tint,
      child: !fill
          ? child
          : _PaneFill(
              fill: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [child],
              ),
            ),
    );
  }
}

/// Tells a [Pane] it has been stretched taller than its content.
class _PaneFill extends InheritedWidget {
  const _PaneFill({required this.fill, required super.child});
  final bool fill;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PaneFill>()?.fill ?? false;

  @override
  bool updateShouldNotify(_PaneFill old) => old.fill != fill;
}

class Gap extends StatelessWidget {
  const Gap([this.size = 12, Key? key]) : super(key: key);
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

class Caption extends StatelessWidget {
  const Caption(this.text, {super.key, this.color, this.align});
  final String text;
  final Color? color;
  final TextAlign? align;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    textAlign: align,
    style: TextStyle(
      color: color ?? Pal.of(context).sub,
      fontSize: 11.5.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(6.dp, 18.dp, 6.dp, 8.dp),
    child: Caption(text),
  );
}

/// One date (and optionally time) the user picks. Tapping the date or the
/// time opens the glass picker for that half.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.withTime = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool withTime;

  Future<void> _pickDate(BuildContext context) async {
    final d = await showGlassDatePicker(
      context: context,
      initialDateTime: value,
      minimumDate: DateTime(1, 1, 1),
      maximumDate: DateTime(9999, 12, 31),
      title: label,
    );
    if (d != null) {
      onChanged(DateTime(d.year, d.month, d.day, value.hour, value.minute));
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final s = SettingsScope.of(context);
    final d = await showGlassDatePicker(
      context: context,
      initialDateTime: value,
      time: true,
      use24hFormat: s.use24h,
      title: label,
    );
    if (d != null) {
      onChanged(DateTime(value.year, value.month, value.day, d.hour, d.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = SettingsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Caption(label),
            const Spacer(),
            Caption(DateFormat('EEEE').format(value), color: p.accent),
          ],
        ),
        SizedBox(height: 6.dp),
        Row(
          children: [
            Expanded(
              child: _Tap(
                onTap: () => _pickDate(context),
                semantic: '$label, ${s.date(value)}. Change date',
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.date(value),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 6.dp),
                    Icon(CupertinoIcons.calendar, size: 18.dp, color: p.accent),
                  ],
                ),
              ),
            ),
            if (withTime)
              _Tap(
                onTap: () => _pickTime(context),
                semantic: 'Time ${s.time(value)}. Change time',
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.dp,
                    vertical: 7.dp,
                  ),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20.dp),
                  ),
                  child: Text(
                    s.time(value),
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({
    required this.child,
    required this.onTap,
    required this.semantic,
  });
  final Widget child;
  final VoidCallback onTap;
  final String semantic;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantic,
    excludeSemantics: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 44.dp),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: child,
          ),
        ),
      ),
    ),
  );
}

class Hairline extends StatelessWidget {
  const Hairline({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 12.dp),
    child: Container(height: 0.6.dp, color: Pal.of(context).faint),
  );
}

/// A label with a switch. The switch's glass appears only while it moves,
/// so it is safe inside a card.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: p.ink,
                  fontSize: 15.5.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (hint != null)
                Padding(
                  padding: EdgeInsets.only(top: 2.dp),
                  child: Text(
                    hint!,
                    style: TextStyle(color: p.sub, fontSize: 12.5.sp),
                  ),
                ),
            ],
          ),
        ),
        // The plain iOS switch: it slides, with none of the glass switch's
        // jelly stretch. Drawn at 0.8: full size was heavy beside the text.
        Transform.scale(
          scale: 0.8,
          alignment: Alignment.centerRight,
          child: CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: p.accent,
            inactiveTrackColor: p.dark
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

/// A big number with its unit underneath.
class BigFigure extends StatelessWidget {
  const BigFigure(this.value, this.unit, {super.key, this.size = 34});
  final String value, unit;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: p.ink,
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(height: 2.dp),
        Caption(unit),
      ],
    );
  }
}

/// A two-column grid of small stat cards.
class StatGrid extends StatelessWidget {
  const StatGrid(this.items, {super.key, this.perRow});
  final List<(String value, String label)> items;

  /// Tiles per row. Left unset, it follows the width it is given: two on a
  /// phone, three when there is room and the tiles divide evenly into
  /// threes, so a set of six takes two rows instead of three.
  final int? perRow;

  @override
  Widget build(BuildContext context) {
    if (perRow != null) return _grid(context, perRow!);
    return LayoutBuilder(
      builder: (context, c) =>
          _grid(context, c.maxWidth >= 460.dp && items.length % 3 == 0 ? 3 : 2),
    );
  }

  Widget _grid(BuildContext context, int perRow) {
    final p = Pal.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += perRow) {
      Widget tile((String, String) it) => Expanded(
        child: Pane(
          padding: EdgeInsets.fromLTRB(16.dp, 14.dp, 16.dp, 14.dp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  it.$1,
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(height: 4.dp),
              Text(
                it.$2,
                style: TextStyle(color: p.sub, fontSize: 12.5.sp),
              ),
            ],
          ),
        ),
      );
      rows.add(
        Padding(
          // Gaps only BETWEEN rows: a trailing one left the grid's last tile
          // 12 short of a card beside it that ends level with the column.
          padding: EdgeInsets.only(
            bottom: i + perRow < items.length ? 12.dp : 0,
          ),
          // Every tile in a row is as tall as the tallest, so a label that
          // wraps to two lines never leaves its neighbours short.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < perRow; j++) ...[
                  if (j > 0) SizedBox(width: 12.dp),
                  if (i + j < items.length)
                    tile(items[i + j])
                  else
                    const Expanded(child: SizedBox()),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// A key/value line inside a result card.
class ResultLine extends StatelessWidget {
  const ResultLine(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.dp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: p.sub, fontSize: 14.sp),
            ),
          ),
          SizedBox(width: 12.dp),
          // Expanded, not Flexible: a loose child shrinks to its text, so
          // the value sat mid-card and the right half of the card was empty.
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: p.ink,
                fontSize: 14.5.sp,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reset / Copy / Share, as floating glass capsules below the result.
/// They sit on the page, never inside a card (no glass inside glass).
class ResultActions extends StatelessWidget {
  const ResultActions({
    super.key,
    required this.shareText,
    this.onReset,
    this.bar = false,
  });
  final String Function() shareText;
  final VoidCallback? onReset;

  /// Drawn as one floating glass toolbar (the tool screens pin it to the
  /// bottom, always in reach) instead of three pills under the result.
  final bool bar;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = SettingsScope.of(context);
    Widget pill(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: GlassPress(
        onTap: onTap,
        label: label,
        builder: (down) => SizedBox(
          height: 50.dp,
          child: GlassSurface(
            radius: 25.dp,
            thick: true,
            lit: down,
            // Shrinks rather than clips when three pills share a narrow
            // phone at a large font size.
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.dp),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18.dp, color: p.ink),
                      SizedBox(width: 8.dp),
                      Text(
                        label,
                        style: TextStyle(
                          color: p.ink,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (bar) return _bar(context, p, s);
    return Padding(
      padding: EdgeInsets.only(top: 14.dp),
      child: Row(
        children: [
          if (onReset != null) ...[
            pill(CupertinoIcons.arrow_counterclockwise, 'Reset', onReset!),
            SizedBox(width: 10.dp),
          ],
          pill(CupertinoIcons.doc_on_doc, 'Copy', () {
            Clipboard.setData(ClipboardData(text: shareText()));
            showToast(
              context,
              message: 'Copied',
              icon: CupertinoIcons.checkmark_alt,
            );
          }),
          if (s.showShare) ...[
            SizedBox(width: 10.dp),
            pill(CupertinoIcons.share, 'Share', () {
              SharePlus.instance.share(ShareParams(text: shareText()));
            }),
          ],
        ],
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: shareText()));
    showToast(context, message: 'Copied', icon: CupertinoIcons.checkmark_alt);
  }

  /// One glass capsule holding the three actions, split by hairlines, as an
  /// iOS bottom toolbar.
  Widget _bar(BuildContext context, Pal p, Settings s) {
    final height = 58.dp;
    Widget item(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: GlassPress(
        onTap: onTap,
        label: label,
        child: SizedBox(
          height: height,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 19.dp, color: p.accent),
                  SizedBox(width: 8.dp),
                  Text(
                    label,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Widget divider() => Container(width: 0.8, height: 24.dp, color: p.faint);
    return GlassSurface(
      radius: height / 2,
      thick: true,
      padding: EdgeInsets.symmetric(horizontal: 6.dp),
      child: Row(
        children: [
          if (onReset != null) ...[
            item(CupertinoIcons.arrow_counterclockwise, 'Reset', onReset!),
            divider(),
          ],
          item(CupertinoIcons.doc_on_doc, 'Copy', () => _copy(context)),
          if (s.showShare) ...[
            divider(),
            item(CupertinoIcons.share, 'Share', () {
              SharePlus.instance.share(ShareParams(text: shareText()));
            }),
          ],
        ],
      ),
    );
  }
}

/// A glass segmented control for short choices: one glass capsule with a
/// lighter pill that springs under the choice, the same pill as the tab bar.
class Segments<T> extends StatelessWidget {
  const Segments({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final height = 46.dp;
    final index = values.indexOf(selected).clamp(0, values.length - 1);
    return GlassSurface(
      radius: height / 2,
      thick: true,
      padding: EdgeInsets.all(4.dp),
      child: SizedBox(
        height: height - 8.dp,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth / values.length;
            return Stack(
              children: [
                SpringValue(
                  value: index.toDouble(),
                        // Firm enough to settle without a wobble; kept inside the
                        // bar so the pill never slides past the end tab and clips.
                        dampingRatio: 0.8,
                  builder: (context, at, child) => Positioned(
                    left: w * at.clamp(0.0, (values.length - 1).toDouble()),
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: child!,
                  ),
                  child: SelectionPill(dark: p.dark),
                ),
                Row(
                  children: [
                    for (var i = 0; i < values.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == index,
                          label: labels[i],
                          excludeSemantics: true,
                          onTap: () => onChanged(values[i]),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (i == index) return;
                                HapticFeedback.selectionClick();
                                onChanged(values[i]);
                              },
                              child: Center(
                                child: Text(
                                  labels[i],
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: i == index ? p.ink : p.sub,
                                    fontSize: 14.sp,
                                    fontWeight: i == index
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The lighter pill under a chosen segment or tab.
class SelectionPill extends StatelessWidget {
  const SelectionPill({super.key, required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: dark
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.white.withValues(alpha: 0.8),
      border: Border.all(
        color: Colors.white.withValues(alpha: dark ? 0.18 : 0.9),
        width: 0.8,
      ),
      boxShadow: dark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
              ),
            ],
    ),
  );
}

/// `.interactive()` glass, as iOS does it: swells under the finger, and
/// settles back with a small bounce on release, keeping its speed if pressed
/// again mid-bounce. A soft light follows the finger in the glass. Pass
/// [builder] instead of [child] to also brighten the glass while it is held
/// (`GlassSurface(lit: down)`).
class GlassPress extends StatefulWidget {
  const GlassPress({
    super.key,
    required this.onTap,
    required this.label,
    this.child,
    this.builder,
  }) : assert(child != null || builder != null);
  final VoidCallback onTap;
  final String label;
  final Widget? child;
  final Widget Function(bool down)? builder;

  @override
  State<GlassPress> createState() => _GlassPressState();
}

class _GlassPressState extends State<GlassPress> {
  bool _down = false;
  bool _hover = false;
  Offset? _at; // the finger, in this button's own coordinates

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!_hover) setState(() => _hover = true);
        },
        onExit: (_) {
          if (_hover) setState(() => _hover = false);
        },
        child: Listener(
          onPointerDown: (e) => setState(() => _at = e.localPosition),
          onPointerMove: (e) {
            if (_down) setState(() => _at = e.localPosition);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _set(true),
            onTapCancel: () => _set(false),
            onTapUp: (_) => _set(false),
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onTap();
            },
            child: SpringValue(
              value: _down && !still ? 1 : (_hover && !still ? 0.33 : 0),
              stiffness: _down ? 420 : 180,
              dampingRatio: _down ? 0.8 : 0.5,
              child: widget.builder?.call(_down) ?? widget.child,
              builder: (context, v, child) => Transform.scale(
                scale: 1 + 0.06 * v,
                child: PressGlow(
                  point: _at,
                  strength: v.clamp(0.0, 1.0),
                  child: child!,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round glass button (back, previous, next).
class RoundGlassButton extends StatelessWidget {
  const RoundGlassButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final size = this.size ?? 44.dp;
    return GlassPress(
      onTap: onPressed,
      label: semanticLabel,
      builder: (down) => SizedBox.square(
        dimension: size,
        child: GlassSurface(
          radius: size / 2,
          thick: true,
          lit: down,
          // Centred by eye, not by box: a box-centred chevron reads as
          // pushed toward its open side, so it moves slightly the way it
          // points.
          child: Center(
            child: Transform.translate(
              offset: Offset(_lean(icon) * size * 0.035, 0),
              child: Icon(icon, color: p.ink, size: size * 0.42),
            ),
          ),
        ),
      ),
    );
  }

  /// -1 for a chevron pointing left, +1 pointing right.
  static double _lean(IconData i) {
    if (i == CupertinoIcons.chevron_left || i == CupertinoIcons.chevron_back) {
      return -1;
    }
    if (i == CupertinoIcons.chevron_right ||
        i == CupertinoIcons.chevron_forward) {
      return 1;
    }
    return 0;
  }
}

/// A date or a time, picked on iOS wheels inside a glass sheet (a centred
/// glass card on a tablet or desktop). Returns null if dismissed.
Future<DateTime?> showGlassDatePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  DateTime? minimumDate,
  DateTime? maximumDate,
  bool time = false,
  bool use24hFormat = false,
  String? title,
}) {
  var picked = initialDateTime;
  return showGlassSheet<DateTime>(
    context,
    builder: (ctx) {
      final p = Pal.of(ctx);
      return Padding(
        padding: EdgeInsets.fromLTRB(16.dp, 8.dp, 16.dp, 12.dp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title ?? (time ? 'Time' : 'Date'),
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 17.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GlassPress(
                  label: 'Done',
                  onTap: () => Navigator.of(ctx).pop(picked),
                  builder: (down) => SizedBox(
                    height: 40.dp,
                    child: GlassSurface(
                      radius: 20.dp,
                      lit: down,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(
                            p.accentRaw,
                            Colors.white,
                            0.12,
                          )!.withValues(alpha: 0.96),
                          Color.lerp(
                            p.accentRaw,
                            Colors.black,
                            0.10,
                          )!.withValues(alpha: 0.96),
                        ],
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 18.dp),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.dp),
            SizedBox(
              height: 216.dp,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: p.dark ? Brightness.dark : Brightness.light,
                  primaryColor: p.accent,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontFamily: 'Inter',
                      color: p.ink,
                      fontSize: 21.sp,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: time
                      ? CupertinoDatePickerMode.time
                      : CupertinoDatePickerMode.date,
                  initialDateTime: initialDateTime,
                  minimumDate: minimumDate,
                  maximumDate: maximumDate,
                  use24hFormat: use24hFormat,
                  itemExtent: 36.dp,
                  onDateTimeChanged: (d) => picked = d,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// The toast on screen now: a new one replaces it rather than stacking.
void Function()? _closeToast;

/// A small glass toast near the bottom of the screen. It springs up from
/// below and drops back out; moved by position, never faded, so its glass is
/// never drawn over an empty layer (a white flash).
void showToast(
  BuildContext context, {
  required String message,
  IconData? icon,
  Duration? duration,
}) {
  duration ??= Duration(
    milliseconds: (1800 + 50 * message.length).clamp(2000, 6000),
  );
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final p = Pal.of(context);
  late final OverlayEntry entry;
  var gone = false;
  final shown = ValueNotifier<bool>(false);
  final reduce = MediaQuery.disableAnimationsOf(context);
  void close() {
    if (gone) return;
    gone = true;
    if (identical(_closeToast, close)) _closeToast = null;
    if (reduce) {
      entry.remove();
      shown.dispose();
      return;
    }
    shown.value = false;
    Future.delayed(const Duration(milliseconds: 260), () {
      entry.remove();
      shown.dispose();
    });
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final bottom = mq.viewInsets.bottom > 0
          ? mq.viewInsets.bottom + 16.dp
          : mq.padding.bottom + 96.dp;
      final body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: IgnorePointer(
            child: GlassSurface(
              radius: 22.dp,
              thick: true,
              padding: EdgeInsets.symmetric(horizontal: 18.dp, vertical: 12.dp),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18.dp, color: p.accent),
                    SizedBox(width: 10.dp),
                  ],
                  Flexible(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return ValueListenableBuilder<bool>(
        valueListenable: shown,
        child: body,
        builder: (ctx, on, child) => TweenAnimationBuilder<double>(
          tween: Tween(end: on ? 1 : 0),
          duration: Duration(
            milliseconds: reduce ? 0 : (on ? kSpringSoftMs : 240),
          ),
          curve: on ? kSpringSoft : Curves.easeInCubic,
          child: child,
          builder: (ctx, v, child) => Positioned(
            left: 16.dp,
            right: 16.dp,
            bottom: bottom - (bottom + 140.dp) * (1 - v),
            child: child!,
          ),
        ),
      );
    },
  );
  final old = _closeToast;
  _closeToast = close;
  old?.call();
  overlay.insert(entry);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!gone) shown.value = true;
  });
  Future.delayed(duration, close);
}

/// A column whose last child takes any height it is given beyond the
/// children's own: laid out loose, it is an ordinary column.
class _StretchLast extends MultiChildRenderObjectWidget {
  const _StretchLast({super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderStretchLast();
}

class _StretchData extends ContainerBoxParentData<RenderBox> {}

class _RenderStretchLast extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StretchData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StretchData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StretchData) child.parentData = _StretchData();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    var y = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
      (c.parentData! as _StretchData).offset = Offset(0, y);
      y += c.size.height;
    }
    final extra = constraints.hasBoundedHeight ? constraints.minHeight - y : 0;
    final last = lastChild;
    if (extra > 0.5 && last != null) {
      last.layout(
        BoxConstraints.tightFor(width: w, height: last.size.height + extra),
        parentUsesSize: true,
      );
      y += extra;
    }
    size = constraints.constrain(Size(w, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
