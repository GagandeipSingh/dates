import 'dart:math' as math;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../state/settings.dart';
import 'glass_chrome.dart';
import 'date_dock.dart';
import 'glass_surface.dart';
import 'motion.dart';
import 'one_ui.dart';
import 'scale.dart';

export 'glass_chrome.dart';
export 'motion.dart';
export 'one_ui.dart';

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

  /// One UI's text and line colours (one_ui.dart).
  late final OnePalette one = OnePalette.forBrightness(
    dark ? Brightness.dark : Brightness.light,
    accent: accentRaw,
  );
  Color get ink => one.ink;
  Color get sub => one.sub;
  Color get faint => one.divider;

  static Color _readable(Color c, bool dark) {
    if (!dark) return c;
    final hsl = HSLColor.fromColor(c);
    // Only a near-grey accent (Graphite) disappears on the dark field — a
    // saturated colour carries itself by its chroma, so the vivid accents are
    // left exactly as shipped. We lift lightness only when there is little
    // colour to rely on.
    if (hsl.saturation < 0.35 && hsl.lightness < 0.62) {
      // ...and a little colour with it, or the lifted accent is the same
      // pale grey as secondary text (see OnePalette.readablePrimary).
      return hsl.withLightness(0.70).withSaturation(0.45).toColor();
    }
    return c;
  }
}

/// The field behind every screen: One UI's flat grey (light) or near-black
/// (dark). The name is kept from the gradient it replaced; a flat field is
/// what makes the focus blocks stand out (guide p.8) and costs nothing.
class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key});

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Pal.of(context).one.background);
}

/// Padding for a page's content under its One UI app bar ([PageScroll]
/// draws the bar): blocks sit [OneUi.blockInset] from the edges, and the
/// foot clears the bottom navigation or toolbar.
EdgeInsets pagePadding(BuildContext context, {bool tabBar = false}) {
  final mq = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(
    OneUi.blockInset,
    4,
    OneUi.blockInset,
    // Over the dock: 16dp clear on a phone, 4 on a wide window, where the
    // page is short of height and the dock floats far from its corners.
    tabBar
        ? DateDock.footprint(context) + (isWideLayout(context) ? 4 : 16)
        : mq.bottom + 28,
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
    this.title,
    this.leading,
    this.actions = const [],
    this.startCollapsed = true,
  });
  final EdgeInsets padding;
  final List<Widget> children;

  /// The screen's One UI app bar: a large title that collapses as the page
  /// scrolls ([OneScrollPage]). A screen without one draws its own.
  final String? title;
  final Widget? leading;
  final List<Widget> actions;

  /// A second-depth screen: opens with the bar collapsed (guide p.23).
  final bool startCollapsed;

  /// Keep the page under its title on a wide screen too. A dense page
  /// (Today, Tools) floating in the middle leaves a band of nothing
  /// between the title and the content.
  final bool top;

  /// On a wide screen, stretch the page to the window's height: children
  /// wrapped in Expanded share what is left, so a short page grows into
  /// the screen instead of sitting small in it.
  final bool fill;

  /// The page's content assembling as it arrives: each top-level block
  /// rises and fades in a beat after the one above it (StaggerIn), once,
  /// when the screen is first built. A block that is a layout instruction
  /// (Expanded, Spacer) is left as it is.
  List<Widget> get _kids => [
    for (var i = 0; i < children.length; i++)
      children[i] is ParentDataWidget
          ? children[i]
          : StaggerIn(index: i, child: children[i]),
  ];

  @override
  Widget build(BuildContext context) => StaggerScope(child: _page(context));

  Widget _page(BuildContext context) {
    final t = title;
    if (t == null) return _content(context);
    final wide = isWideLayout(context);
    if (!wide || top) {
      return OneScrollPage(
        title: t,
        leading: leading,
        actions: actions,
        startCollapsed: startCollapsed,
        slivers: [
          // Built whole, as the column it was: these pages are a screen or
          // two of cards, and a lazy list left rows unbuilt below the
          // expanded title (focus, find and scroll-to could not reach them).
          SliverPadding(
            padding: padding,
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _kids,
              ),
            ),
          ),
        ],
      );
    }
    // The wide layouts size themselves to the window (centred, fitted or
    // filled): the bar stays collapsed above them and they take the rest.
    return OneScrollPage(
      title: t,
      leading: leading,
      actions: actions,
      expandable: false,
      slivers: [SliverFillRemaining(child: _content(context))],
    );
  }

  Widget _content(BuildContext context) {
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
                children: _kids,
              ),
            ),
          ),
        ),
      );
    }
    if (!wide || top) {
      return ListView(padding: padding, children: _kids);
    }
    // Centre between the page title and the top of the tab bar. The top
    // padding reserves the whole title bar, whose text sits high in it, so
    // the true middle is a little above the padded box's middle.
    final lift = 12.dp;
    final centred = padding.copyWith(
      top: math.max(0.0, padding.top - lift),
      bottom: padding.bottom + lift,
    );
    // A page taller than the window scrolls at its full size. It used to be
    // scaled down to fit and centred, which shrank Today and Settings and
    // pulled their left edge in, off the title's and away from Tools.
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
            children: _kids,
          ),
        ),
      ),
    );
  }
}

/// A pushed tool screen: a One UI app bar with a back button, opening
/// collapsed as a second-depth screen does.
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
      bottomBarHeight: _actions == null ? 0 : 58.dp,
      bottomBar: _actions == null
          ? null
          : KeyedSubtree(
              // Arrives with the screen (see rise above).
              key: const ValueKey('actions'),
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
              title: title,
              startCollapsed: true,
              leading: OneIconButton(
                icon: PhosphorIconsBold.caretLeft,
                size: 20,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
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
    // The cards arrive with the screen, as on iOS. They used to rise one
    // after another as it slid in, which redrew every glass card on every
    // frame of the slide and made the open stutter; the screen now slides
    // in as one still picture (StillWhileMoving), which needs it still.
    Widget rise(Widget w, int i) => w;

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
    // A One UI focus block: 26dp corners, content on the 20dp inner keyline.
    return GlassSurface(
      radius: OneUi.radiusBlock,
      padding: padding ?? EdgeInsets.fromLTRB(20.dp, 18.dp, 20.dp, 18.dp),
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
  // Sentence case: One UI capitalises the first letter only (guide p.64).
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    style: TextStyle(
      color: color ?? Pal.of(context).sub,
      fontSize: 13.5.sp,
      fontWeight: FontWeight.w600,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  // On the 24dp keyline: the page's 12 plus 12 here.
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(12.dp, 22.dp, 12.dp, 8.dp),
    child: Semantics(header: true, child: Caption(text)),
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
            // The label gives way (wraps) at a large font size; the
            // weekday beside it never does.
            Expanded(child: Caption(label)),
            SizedBox(width: 8.dp),
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
                    Icon(
                      PhosphorIconsFill.calendarBlank,
                      size: 18.dp,
                      color: p.accent,
                    ),
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
  // One UI's list divider: 1px in the divider colour, inside the block's
  // padding, so it is inset from both edges rather than full width.
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 12.dp),
    child: Container(height: 1, color: Pal.of(context).faint),
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
                style: TextStyle(color: p.ink, fontSize: 17.sp),
              ),
              if (hint != null)
                Padding(
                  padding: EdgeInsets.only(top: 2.dp),
                  child: Text(
                    hint!,
                    style: TextStyle(color: p.sub, fontSize: 14.sp),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(width: 12.dp),
        // The Android switch in One UI's colours (oneSwitchTheme): a
        // control of its own beside the text, never a coupled block.
        // Drawn at 80% (owner's call: the full Material size read too big);
        // the scale is paint-only, so the 48dp touch target is unchanged.
        Transform.scale(
          scale: 0.8,
          child: Switch(value: value, onChanged: onChanged),
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
          // Counts to a new answer as the inputs change.
          child: CountText(
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
                child: CountText(
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
            child: CountText(
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
            pill(PhosphorIconsBold.arrowCounterClockwise, 'Reset', onReset!),
            SizedBox(width: 10.dp),
          ],
          pill(PhosphorIconsBold.copy, 'Copy', () {
            Clipboard.setData(ClipboardData(text: shareText()));
            showToast(
              context,
              message: 'Copied',
              icon: PhosphorIconsBold.check,
            );
          }),
          if (s.showShare) ...[
            SizedBox(width: 10.dp),
            pill(PhosphorIconsBold.shareNetwork, 'Share', () {
              SharePlus.instance.share(ShareParams(text: shareText()));
            }),
          ],
        ],
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: shareText()));
    showToast(context, message: 'Copied', icon: PhosphorIconsBold.check);
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
            item(PhosphorIconsBold.arrowCounterClockwise, 'Reset', onReset!),
            divider(),
          ],
          item(PhosphorIconsBold.copy, 'Copy', () => _copy(context)),
          if (s.showShare) ...[
            divider(),
            item(PhosphorIconsBold.shareNetwork, 'Share', () {
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
    final height = 48.dp;
    final index = values.indexOf(selected).clamp(0, values.length - 1);
    // One UI's segmented subtabs: a grey track with the choice on a raised
    // pill that springs across (none with reduced motion).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.dark ? const Color(0xFF252528) : const Color(0xFFE4E4E7),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Padding(
        padding: EdgeInsets.all(4.dp),
        child: SizedBox(
          height: height - 8.dp,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth / values.length;
              return Stack(
                children: [
                  // The pill on the snap spring, which keeps its speed if
                  // another segment is chosen mid-flight and lands without
                  // a wobble; kept inside the track so it never slides past
                  // the end segment. Moved by a transform.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: SpringValue(
                      value: index.toDouble(),
                      child: SelectionPill(dark: p.dark),
                      builder: (context, at, child) => Transform.translate(
                        offset: Offset(
                          w * at.clamp(0.0, (values.length - 1).toDouble()),
                          0,
                        ),
                        child: child,
                      ),
                    ),
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
      ),
    );
  }
}

/// The raised pill under a chosen segment.
class SelectionPill extends StatelessWidget {
  const SelectionPill({super.key, required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: dark ? const Color(0xFF4A4A4F) : const Color(0xFFFCFCFF),
      boxShadow: dark
          ? null
          : const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
    ),
  );
}

/// A pressable surface: a grey veil while it is held (pass [builder] and
/// draw `GlassSurface(lit: down)`), a light haptic on the tap, and the
/// app's press ([PressScale]): it sinks to 0.97 in 90ms the moment the
/// finger lands and comes back on the snap spring, never past full size.
/// Still with reduced motion.
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
        // No pointer tracking here: the veil is one state change down and
        // one up, never a rebuild per finger move; PressScale moves a
        // transform only.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _set(true),
          onTapCancel: () => _set(false),
          onTapUp: (_) => _set(false),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          // The app's one press (PressScale): down in 90ms, back on the
          // snap spring without a rebound.
          child: PressScale(
            child:
                widget.builder?.call(_down || (_hover && !still)) ??
                widget.child!,
          ),
        ),
      ),
    );
  }
}

/// A round icon button (back, previous, next): One UI's plain icon with a
/// round ripple and a 48dp target, no plate behind it.
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
    final size = math.max(this.size ?? 48.dp, OneUi.minTouch);
    return SizedBox.square(
      dimension: size,
      child: OneIconButton(
        icon: icon,
        tooltip: semanticLabel,
        size: 22.dp,
        onPressed: onPressed,
      ),
    );
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
  return showAppSheet<DateTime>(
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

/// A small toast at the top of the screen. It slides down on [kSettle] and
/// back up on [kExit]; moved by position, never faded, so its glass is
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
    Future.delayed(const Duration(milliseconds: kExitMs + 20), () {
      entry.remove();
      shown.dispose();
    });
  }

  entry = OverlayEntry(
    builder: (ctx) {
      // At the TOP, sliding down from under the status bar. Android 13+ (and
      // Samsung earlier) shows its own "Copied" pill near the bottom whenever
      // an app writes the clipboard, so a toast down there landed on it.
      // It starts BELOW the title bar: right under the status bar it sat on
      // the page title and back button (seen on a 360 x 640 Android 9 phone).
      final mq = MediaQuery.of(ctx);
      final top = mq.padding.top + 52.dp;
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
            milliseconds: reduce ? 0 : (on ? kSettleMs : kExitMs),
          ),
          curve: on ? kSettle : kExit,
          child: child,
          // Down from above the screen on the settle spring, back up on an
          // accelerating ease: moved by a transform, never re-laid out.
          builder: (ctx, v, child) => Positioned(
            left: 16.dp,
            right: 16.dp,
            top: top,
            child: Transform.translate(
              offset: Offset(0, -(top + 140.dp) * (1 - v)),
              child: child!,
            ),
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
