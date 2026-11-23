// One UI, after Samsung's One UI Design Guidelines and its support library
// (SESL), drawn with plain Flutter. The same file is copied into every app
// (dates, compass, breeze, scorio, levels): keep the copies identical.
//
// Why flat: One UI runs fast on phones with small processors because its
// surfaces are solid colour. Nothing here blurs, samples the screen behind
// it (BackdropFilter), runs a fragment shader or animates a shadow. A card
// is a filled rounded rectangle; the one shadow is a small static one under
// floating controls.
//
// Sources, cited by page where the guide has one:
// * One UI Design Guidelines (design.samsung.com/global/contents/one-ui/,
//   oneui_design_guide_eng.pdf): viewing/interaction areas p.7, focus blocks
//   p.8, dark theme p.9-11, 24dp margins p.13, app bar p.16-28, bottom
//   navigation p.31, buttons p.35, dialogs at the bottom p.37, lists p.41,
//   radius 26dp p.66.
// * SESL (Samsung's own androidx fork): the colour, radius, elevation and
//   motion values, which supersede the guide's older palette.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// The One UI design tokens.
class OneUi {
  OneUi._();

  // Radii. Focus blocks, dialogs and popups are 26 (guide p.66, SESL
  // sesl_rounded_corner_radius); buttons 18; floating bars fully round.
  static const double radiusBlock = 26;
  static const double radiusButton = 18;
  static const double radiusThumb = 12;

  /// Cards sit this far from the screen edge (SESL list containers), and
  /// their content a further [blockPadH] in, so text and touch targets keep
  /// the guide's 24dp keyline (p.13) while the block itself is wide.
  static const double blockInset = 12;
  static const double blockPadH = 20;

  /// The guide's minimum margin for content outside a block (titles,
  /// section headers, captions).
  static const double keyline = 24;

  /// Between two focus blocks.
  static const double blockGap = 12;

  /// A list row: one line of 17sp title, an optional 14sp line under it.
  static const double rowMinHeight = 60;
  static const double rowPadV = 14;

  /// The collapsed app bar under the status bar (SESL action bar height).
  static const double barHeight = 56;

  /// The expanded app bar: 39.67% of the screen height on a phone, 18.78%
  /// on a tablet (p.28).
  static const double expandedFraction = 0.3967;
  static const double expandedFractionTablet = 0.1878;

  /// Below this height the expandable app bar is not used (p.19).
  static const double expandMinHeight = 580;

  /// Expanded title (SESL appbar 34sp; 30sp with a subtitle) and the
  /// collapsed one.
  static const double titleExpanded = 34;
  static const double titleCollapsed = 20;

  /// Touch targets: never smaller than this.
  static const double minTouch = 48;

  // Motion (SESL interpolators) for what changes in place: a header snap,
  // a fade, a colour: 150-350ms and never past the mark. Things that travel
  // (the tab pill, a sheet, a page) ride springs in each app's motion.dart.
  static const Curve sineOut80 = Cubic(0.17, 0.17, 0.2, 1);
  static const Curve sineInOut80 = Cubic(0.33, 0, 0.2, 1);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);

  /// A duration, or none at all when the user has asked for less motion.
  static Duration motion(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

/// The colours of one theme. Light is SESL's grey field with near-white
/// blocks; dark is near-black, so the screen merges with the bezel (p.9),
/// with dark-grey tonal blocks.
@immutable
class OnePalette {
  const OnePalette._({
    required this.dark,
    required this.background,
    required this.block,
    required this.popup,
    required this.container,
    required this.divider,
    required this.ink,
    required this.sub,
    required this.primary,
  });

  factory OnePalette.of(BuildContext context, {Color? accent}) =>
      OnePalette.forBrightness(
        Theme.of(context).brightness,
        accent: accent ?? Theme.of(context).colorScheme.primary,
      );

  factory OnePalette.forBrightness(Brightness b, {Color? accent}) {
    final dark = b == Brightness.dark;
    return OnePalette._(
      dark: dark,
      background: dark ? const Color(0xFF010102) : const Color(0xFFF3F3F5),
      block: dark ? const Color(0xFF17171A) : const Color(0xFFFCFCFF),
      popup: dark ? const Color(0xFF252528) : const Color(0xFFFCFCFF),
      container: dark ? const Color(0xFF3A3A3D) : const Color(0xFFE4E4E7),
      divider: dark ? const Color(0xFF3A3A3D) : const Color(0xFFE4E4E7),
      ink: dark ? const Color(0xFFFCFCFF) : const Color(0xFF010102),
      sub: dark ? const Color(0xFF9A9AA0) : const Color(0xFF6F6F75),
      primary: readablePrimary(accent ?? defaultPrimary, dark),
    );
  }

  /// SESL primary_50.
  static const Color defaultPrimary = Color(0xFF387AFF);

  final bool dark;
  final Color background;
  final Color block;
  final Color popup;
  final Color container;
  final Color divider;
  final Color ink;
  final Color sub;
  final Color primary;

  /// The primary for SMALL text and icons (a brief card's eyebrow, a quick
  /// action's label, a setting's value): 4.5:1 against the block, as the
  /// guide's contrast rule asks of text (p.86). [primary] only promises the
  /// 3:1 a large or non-text element needs.
  Color get primaryText => _towards(primary, block, 4.5, dark);

  /// The tonal wash behind a selected item (a tab, a chip): the primary,
  /// thin enough to sit under primary-coloured text.
  Color get selected => primary.withValues(alpha: dark ? 0.22 : 0.12);

  /// What a press lays over a block: a grey veil, as One UI's ripple.
  Color get pressed => dark ? const Color(0x24FFFFFF) : const Color(0x14000000);

  /// An accent that keeps 3:1 against the theme's blocks (guide p.86): a
  /// near-grey or very dark accent is lifted in dark mode, a very pale one
  /// deepened in light mode. Hue is kept.
  /// [c] stepped darker (light theme) or lighter (dark theme) until it has
  /// [ratio] contrast against [bg]; hue and saturation are kept.
  static Color _towards(Color c, Color bg, double ratio, bool dark) {
    double contrast(Color a) {
      final l1 = a.computeLuminance(), l2 = bg.computeLuminance();
      return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
    }

    if (contrast(c) >= ratio) return c;
    var hsl = HSLColor.fromColor(c);
    for (var i = 0; i < 50 && contrast(hsl.toColor()) < ratio; i++) {
      hsl = hsl.withLightness(
        (hsl.lightness + (dark ? 0.02 : -0.02)).clamp(0.0, 1.0),
      );
    }
    return hsl.toColor();
  }

  static Color readablePrimary(Color c, bool dark) {
    final block = dark ? const Color(0xFF17171A) : const Color(0xFFFCFCFF);
    double contrast(Color a) {
      final l1 = a.computeLuminance(), l2 = block.computeLuminance();
      return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
    }

    var hsl = HSLColor.fromColor(c);
    var changed = false;
    if (dark && hsl.lightness < 0.55) {
      hsl = hsl.withLightness(0.66);
      changed = true;
    }
    if (!dark && hsl.lightness > 0.62) {
      hsl = hsl.withLightness(0.48);
      changed = true;
    }
    // Some hues (yellow, cyan) stay bright at any lightness: keep stepping
    // away from the block until the 3:1 holds.
    for (var i = 0; i < 40 && contrast(hsl.toColor()) < 3; i++) {
      final l = hsl.lightness + (dark ? 0.02 : -0.02);
      hsl = hsl.withLightness(l.clamp(0.0, 1.0));
      changed = true;
    }
    return changed ? hsl.toColor() : c;
  }

  /// Time-of-day accent for brief cards: a whisper of the primary in the
  /// morning and a cooler one at night. A tint only, never a gradient.
  Color briefTint(DateTime now) {
    final h = now.hour + now.minute / 60;
    // 0 at midday, 1 at midnight.
    final night = (math.cos((h - 12) / 24 * 2 * math.pi) * -0.5 + 0.5);
    final warm = dark ? const Color(0xFF2B2A35) : const Color(0xFFF5F7FF);
    return Color.lerp(
      Color.lerp(block, primary, dark ? 0.10 : 0.05)!,
      warm,
      night * 0.5,
    )!;
  }
}

/// A Material 3 theme in One UI's colours. Each app passes its own accent
/// and font.
ThemeData oneUiTheme(
  Brightness b, {
  Color? accent,
  String fontFamily = 'Inter',
}) {
  final p = OnePalette.forBrightness(b, accent: accent);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent ?? OnePalette.defaultPrimary,
        brightness: b,
      ).copyWith(
        primary: p.primary,
        onPrimary: Colors.white,
        surface: p.block,
        onSurface: p.ink,
        onSurfaceVariant: p.sub,
        surfaceContainerLowest: p.background,
        surfaceContainerLow: p.block,
        surfaceContainer: p.block,
        surfaceContainerHigh: p.popup,
        surfaceContainerHighest: p.container,
        outline: p.divider,
        outlineVariant: p.divider,
        // No M3 tint over elevated surfaces: One UI blocks are flat.
        surfaceTint: Colors.transparent,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.divider,
    // One UI's press feedback is a ripple that spreads from the finger.
    splashFactory: InkRipple.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: p.pressed,
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: p.ink,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: OneUi.titleCollapsed,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
    ),
    switchTheme: oneSwitchTheme(p),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.primary,
      inactiveTrackColor: p.container,
      thumbColor: p.primary,
      overlayColor: p.primary.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.primary : null,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, OneUi.minTouch),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OneUi.radiusButton),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        minimumSize: const Size(64, OneUi.minTouch),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OneUi.radiusButton),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.popup,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.popup,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(OneUi.radiusBlock)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.popup,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OneUi.radiusBlock),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.popup,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OneUi.radiusBlock),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.primary),
  );
}

/// One UI's switch: a primary track with a white thumb when on, a grey
/// track when off, no outline.
SwitchThemeData oneSwitchTheme(OnePalette p) => SwitchThemeData(
  thumbColor: const WidgetStatePropertyAll(Color(0xFFFCFCFF)),
  trackColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.selected)
        ? p.primary
        : (p.dark ? const Color(0xFF5A5A5F) : const Color(0xFFBDBDC2)),
  ),
  trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
  thumbIcon: const WidgetStatePropertyAll(null),
  overlayColor: WidgetStatePropertyAll(p.pressed),
);

/// Whether a screen of [size] (real dp) may show the expanded app bar:
/// never in a phone's full-screen landscape, and elsewhere only when the
/// window is taller than 580dp (guide p.19).
bool oneUiCanExpand(Size size) {
  if (size.height <= OneUi.expandMinHeight) return false;
  final phone = size.shortestSide < 600;
  final landscape = size.width > size.height;
  return !(phone && landscape);
}

/// The screen's real size in dp, whatever scaling the app applies to its
/// own tree.
Size oneUiWindowSize(BuildContext context) {
  final view = View.of(context);
  return view.physicalSize / view.devicePixelRatio;
}

/// How far the expandable header can collapse, for a header of
/// [expandedHeight] over a collapsed bar of [collapsedHeight]; a pure
/// function so the snap can be tested.
double oneUiSnapTarget(double offset, double range, {double threshold = 0.5}) {
  // Within half a pixel of either end counts as there: the short-content
  // filler can leave the scroll extent a rounding error under [range], and
  // snapping to an offset the list cannot reach ended in a scroll that
  // re-snapped forever (an endless animation, found on a 360x760 phone).
  if (range <= 0 || offset <= 0.5 || offset >= range - 0.5) return offset;
  return offset < range * threshold ? 0 : range;
}

/// A first-depth screen with One UI's expandable app bar: a large centred
/// title in the viewing area that collapses into the 56dp bar as the
/// content scrolls up, and snaps to one state or the other when the finger
/// lifts half-way (p.18, p.24). On a short or landscape phone window only
/// the collapsed bar is shown (p.19). Deeper screens pass
/// [expandable] false and open collapsed (p.23).
class OneScrollPage extends StatefulWidget {
  const OneScrollPage({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.expandable = true,
    this.controller,
    this.bottomPadding = 0,
    this.physics,
    this.startCollapsed = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// At most two: the title counts as the third item (p.16). More go into
  /// a ⋮ menu ([OneOverflowButton]).
  final List<Widget> actions;
  final List<Widget> slivers;
  final bool expandable;
  final ScrollController? controller;
  final double bottomPadding;
  final ScrollPhysics? physics;

  /// Open with the bar collapsed (small title, top left); pulling down at
  /// the top expands it to the big centred title. On by default, the
  /// owner's call (2026-11-23): the big title shows only on a pull down.
  final bool startCollapsed;

  /// The collapsed and expanded heights of the bar in [context].
  static (double, double) extents(
    BuildContext context, {
    bool expandable = true,
  }) {
    final top = MediaQuery.paddingOf(context).top;
    final screen = MediaQuery.sizeOf(context);
    final window = oneUiWindowSize(context);
    final collapsed = top + OneUi.barHeight;
    if (!expandable || !oneUiCanExpand(window)) return (collapsed, collapsed);
    final fraction = window.shortestSide >= 600
        ? OneUi.expandedFractionTablet
        : OneUi.expandedFraction;
    return (collapsed, math.max(collapsed, top + screen.height * fraction));
  }

  @override
  State<OneScrollPage> createState() => _OneScrollPageState();
}

class _OneScrollPageState extends State<OneScrollPage> {
  ScrollController? _own;
  ScrollController get _c => widget.controller ?? _own!;
  bool _snapping = false;
  double _range = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller == null && _own == null) {
      final (min, max) = OneScrollPage.extents(
        context,
        expandable: widget.expandable,
      );
      _own = ScrollController(
        initialScrollOffset: widget.startCollapsed ? max - min : 0,
      );
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  bool _onEnd(ScrollEndNotification n) {
    if (n.depth != 0 || _snapping || !_c.hasClients) return false;
    final target = oneUiSnapTarget(_c.offset, _range);
    if (target == _c.offset) return false;
    // On the next frame: the scroll that ended is still settling. A frame
    // callback rather than a microtask keeps the snap on the frame clock
    // (a microtask fired from a test's real-time zone started an animation
    // its pumps never drove, leaving the list ignoring touches).
    _snapping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_c.hasClients) {
        _snapping = false;
        return;
      }
      final to = oneUiSnapTarget(_c.offset, _range);
      final d = OneUi.motion(context, OneUi.medium);
      if (to == _c.offset) {
        // Nothing to do (the list moved again in the meantime).
      } else if (d == Duration.zero) {
        _c.jumpTo(to);
      } else {
        await _c.animateTo(to, duration: d, curve: OneUi.sineOut80);
      }
      _snapping = false;
    });
    WidgetsBinding.instance.scheduleFrame();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final (collapsed, expanded) = OneScrollPage.extents(
      context,
      expandable: widget.expandable,
    );
    _range = expanded - collapsed;
    return NotificationListener<ScrollEndNotification>(
      onNotification: _onEnd,
      child: CustomScrollView(
        controller: _c,
        physics: widget.physics,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _OneHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              leading: widget.leading,
              actions: widget.actions,
              top: top,
              min: collapsed,
              max: expanded,
              palette: OnePalette.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            ),
          ),
          ...widget.slivers,
          SliverToBoxAdapter(child: SizedBox(height: widget.bottomPadding)),
          // When the content is short, room to collapse the bar fully, so a
          // snap to "collapsed" has somewhere to go.
          if (_range > 0)
            SliverLayoutBuilder(
              builder: (context, c) => SliverToBoxAdapter(
                child: SizedBox(
                  height: math.max(
                    0.0,
                    c.viewportMainAxisExtent + _range - c.precedingScrollExtent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OneHeader extends SliverPersistentHeaderDelegate {
  _OneHeader({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.actions,
    required this.top,
    required this.min,
    required this.max,
    required this.palette,
    required this.textScaler,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final double top;
  final double min;
  final double max;
  final OnePalette palette;
  final TextScaler textScaler;

  @override
  double get minExtent => min;
  @override
  double get maxExtent => max;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final range = max - min;
    // 0 expanded, 1 collapsed.
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final p = palette;
    // The big title fades out over the first 60% of the collapse; the bar's
    // own title fades in over the last 30%. Text colour carries the fade,
    // so nothing draws into an offscreen layer.
    final big = (1 - t / 0.6).clamp(0.0, 1.0);
    final small = range <= 0 ? 1.0 : ((t - 0.7) / 0.3).clamp(0.0, 1.0);
    final h = math.max(min, max - shrinkOffset);
    return ColoredBox(
      color: p.background,
      child: SizedBox(
        height: h,
        child: Stack(
          children: [
            if (range > 0 && big > 0)
              Positioned(
                left: OneUi.keyline,
                right: OneUi.keyline,
                top: top,
                bottom: OneUi.barHeight,
                // Scaled down, never clipped, when the room is shorter than
                // the text: a short tablet window at a large font size, or
                // the moment before the title fades out mid-collapse.
                // As the bar collapses the big title shrinks a little and
                // drifts up toward the bar, so the two titles read as one
                // title moving rather than two swapping. Scroll-driven, so
                // it tracks the finger and needs no reduced-motion branch.
                child: Transform.translate(
                  offset: Offset(0, -16 * (1 - big)),
                  child: Transform.scale(
                    scale: 1 - 0.12 * (1 - big),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: subtitle == null
                                  ? OneUi.titleExpanded
                                  : 30,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                              color: p.ink.withValues(alpha: big),
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              subtitle!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                color: p.sub.withValues(alpha: big * p.sub.a),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: OneUi.barHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    if (leading != null)
                      leading!
                    else
                      const SizedBox(width: OneUi.keyline - 4),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Transform.translate(
                          offset: Offset(0, 8 * (1 - small)),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: OneUi.titleCollapsed,
                              fontWeight: FontWeight.w600,
                              color: p.ink.withValues(alpha: small),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_OneHeader old) =>
      old.title != title ||
      old.subtitle != subtitle ||
      old.leading != leading ||
      old.actions != actions ||
      old.top != top ||
      old.min != min ||
      old.max != max ||
      old.palette.dark != palette.dark ||
      old.palette.primary != palette.primary ||
      old.textScaler != textScaler;
}

/// An app bar icon button: a plain icon with a round ripple, 48dp target,
/// as One UI's action buttons (no plate behind the icon).
class OneIconButton extends StatelessWidget {
  const OneIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
    this.size = 24,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: size,
      color: color ?? p.ink,
      constraints: const BoxConstraints(
        minWidth: OneUi.minTouch,
        minHeight: OneUi.minTouch,
      ),
      style: IconButton.styleFrom(
        highlightColor: p.pressed,
        overlayColor: p.ink,
      ),
      icon: Icon(icon, semanticLabel: tooltip),
    );
  }
}

/// A focus block (p.8): a solid rounded container, 26dp corners, that
/// groups related rows or holds one card's content. Children are separated
/// by inset dividers when [divided].
class FocusBlock extends StatelessWidget {
  const FocusBlock({
    super.key,
    required this.children,
    this.divided = true,
    this.padding = EdgeInsets.zero,
    this.color,
    this.dividerIndent = OneUi.blockPadH,
  });

  final List<Widget> children;
  final bool divided;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && divided) {
        items.add(
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: dividerIndent,
              end: OneUi.blockPadH,
            ),
            child: ColoredBox(
              color: p.divider,
              child: const SizedBox(height: 1, width: double.infinity),
            ),
          ),
        );
      }
      items.add(children[i]);
    }
    return Material(
      color: color ?? p.block,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OneUi.radiusBlock),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items,
        ),
      ),
    );
  }
}

/// A One UI list row: an optional leading icon, a one-line 17sp title, a
/// 14sp secondary line (the current value of a setting is shown in the
/// primary colour, as One UI does), and an optional trailing control.
class OneListRow extends StatelessWidget {
  const OneListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleIsValue = false,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool subtitleIsValue;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    final ink = enabled ? p.ink : p.ink.withValues(alpha: 0.38);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: OneUi.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OneUi.blockPadH,
          vertical: OneUi.rowPadV,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 16)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, color: ink, height: 1.25),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        color: subtitleIsValue && enabled
                            ? p.primaryText
                            : p.sub,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
    if (onTap == null || !enabled) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// A section header above a focus block: small, in the secondary colour,
/// on the screen's keyline (p.42).
class OneSectionHeader extends StatelessWidget {
  const OneSectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OneUi.keyline,
        OneUi.keyline - 4,
        OneUi.keyline,
        8,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: p.sub,
          ),
        ),
      ),
    );
  }
}

/// A Now Brief-style summary card at the top of a main screen: one big
/// glanceable fact, a line or two of context, and at most two quick
/// actions. Its block carries the time-of-day tint.
class BriefCard extends StatelessWidget {
  const BriefCard({
    super.key,
    required this.headline,
    this.eyebrow,
    this.lines = const [],
    this.actions = const [],
    this.leading,
    this.now,
  });

  final String? eyebrow;
  final String headline;
  final List<String> lines;
  final List<Widget> actions;
  final Widget? leading;

  /// For the time-of-day tint; the current time when null.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    return FocusBlock(
      divided: false,
      color: p.briefTint(now ?? DateTime.now()),
      padding: const EdgeInsets.fromLTRB(
        OneUi.blockPadH,
        18,
        OneUi.blockPadH,
        18,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (eyebrow != null)
                    Text(
                      eyebrow!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.primaryText,
                      ),
                    ),
                  if (eyebrow != null) const SizedBox(height: 4),
                  Text(
                    headline,
                    // A long name (a file's, a place's) stays a headline,
                    // not a wall of large type pushing the list away.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: p.ink,
                    ),
                  ),
                  for (final l in lines) ...[
                    const SizedBox(height: 4),
                    Text(
                      l,
                      style: TextStyle(fontSize: 14, height: 1.3, color: p.sub),
                    ),
                  ],
                ],
              ),
            ),
            if (leading != null) ...[const SizedBox(width: 12), leading!],
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    );
  }
}

/// A quick action on a brief card: a tonal pill, 40dp tall inside a 48dp
/// target.
class BriefAction extends StatelessWidget {
  const BriefAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    return Semantics(
      button: true,
      child: OnePressScale(
        child: Material(
          color: p.selected,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: p.primaryText),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Press feedback for something you tap as an object (a card, a pill, a
/// button): it sinks to [pressed] scale the moment the finger lands (90ms,
/// ease-out, so it answers at once) and comes back on a near-critical
/// spring, with no rebound past full size. A finger that slides off into a
/// scroll lets it go. Never blocks the tap: it only listens to the pointer.
/// Instant with reduced motion. Rows inside a block keep their ripple
/// instead; a full-width row shrinking reads as the list jumping.
class OnePressScale extends StatefulWidget {
  const OnePressScale({super.key, required this.child, this.pressed = 0.97});

  final Widget child;
  final double pressed;

  @override
  State<OnePressScale> createState() => _OnePressScaleState();
}

class _OnePressScaleState extends State<OnePressScale>
    with SingleTickerProviderStateMixin {
  // Ratio 0.85, at rest in ~340ms: back to size with nothing to see past it.
  static const _release = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 34,
  );
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  Offset? _start;

  bool get _still => MediaQuery.disableAnimationsOf(context);

  void _down(PointerDownEvent e) {
    if (_still) return;
    _start = e.position;
    _c.animateTo(
      widget.pressed,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _move(PointerMoveEvent e) {
    final s = _start;
    if (s != null && (e.position - s).distance > 18) _up(); // touch slop
  }

  void _up([PointerEvent? _]) {
    _start = null;
    if (_still) {
      _c.value = 1;
      return;
    }
    if (_c.value == 1 && !_c.isAnimating) return;
    _c.animateWith(SpringSimulation(_release, _c.value, 1, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Its whole box answers, even where the child paints nothing; it only
    // listens, so whatever is below still gets the tap.
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) =>
          Transform.scale(scale: _c.value, child: child),
    ),
  );
}

/// The app's floating bottom navigation: a capsule inset 16dp from the
/// screen edges, above the gesture or 3-button area, on a solid surface
/// (one small static shadow in light, a hairline in dark; nothing blurs).
///
/// The selected item is a tonal pill holding its icon AND its label; the
/// others show their icon only (named for screen readers and in a tooltip).
/// A switch moves everything at once in about 250ms on near-critical
/// springs: the pill slides and stretches toward the new item (its leading
/// edge ahead of its trailing one), the new item widens as its label opens
/// and fades in, the old one closes, and the icon turns from outline to
/// filled. No wobble, nothing past its mark. Instant with reduced motion.
///
/// 64dp tall, every item at least 48dp wide; centred at [maxWidth] on a
/// tablet. Switches on touch down.
class OneBottomNav extends StatelessWidget {
  const OneBottomNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.activeIcons,
  }) : assert(items.length >= 2 && items.length <= 5);

  /// Each item's (outline icon, label).
  final List<(IconData, String)> items;

  /// The filled icon each item shows when it is selected; the outline one
  /// is kept when null.
  final List<IconData>? activeIcons;
  final int selected;
  final ValueChanged<int> onSelected;

  static const double height = 64;
  static const double radius = 28;
  static const double maxWidth = 430;
  static const double sideInset = 16;

  /// The space the bar takes at the foot of the screen, for content to pad
  /// itself above it.
  static double footprint(BuildContext context) =>
      height + math.max(MediaQuery.paddingOf(context).bottom + 8, 16);

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sideInset,
        0,
        sideInset,
        math.max(bottom + 8, 16),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.dark ? p.popup : p.block,
                borderRadius: BorderRadius.circular(radius),
                border: p.dark ? Border.all(color: p.divider, width: 1) : null,
                boxShadow: p.dark
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 12,
                          offset: Offset(0, 3),
                        ),
                      ],
              ),
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: _NavBody(
                    items: items,
                    activeIcons: activeIcons,
                    selected: selected,
                    onSelected: (i) {
                      if (i == selected) return;
                      HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                    palette: p,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBody extends StatefulWidget {
  const _NavBody({
    required this.items,
    required this.activeIcons,
    required this.selected,
    required this.onSelected,
    required this.palette,
  });

  final List<(IconData, String)> items;
  final List<IconData>? activeIcons;
  final int selected;
  final ValueChanged<int> onSelected;
  final OnePalette palette;

  @override
  State<_NavBody> createState() => _NavBodyState();
}

class _NavBodyState extends State<_NavBody> with TickerProviderStateMixin {
  // Positions are in ITEM units (0 = first item). The widths ride one spring
  // (ratio 0.9, at rest ~230ms); the pill's two edges ride their own, the
  // leading one quicker (ratio 0.9, ~200ms) than the trailing one
  // (critically damped, ~260ms), so the pill stretches toward the new item.
  static const _widths = SpringDescription(
    mass: 1,
    stiffness: 1029,
    damping: 57.7,
  );
  static const _lead = SpringDescription(
    mass: 1,
    stiffness: 1361,
    damping: 66.4,
  );
  static const _trail = SpringDescription(
    mass: 1,
    stiffness: 1044,
    damping: 64.6,
  );

  late final AnimationController _p = _ctl();
  late final AnimationController _l = _ctl();
  late final AnimationController _r = _ctl();

  AnimationController _ctl() => AnimationController.unbounded(
    vsync: this,
    value: widget.selected.toDouble(),
  );

  int get _n => widget.items.length;

  /// How much wider the selected item is than an unselected one, in item
  /// widths: the selected item takes half the bar.
  double get _k => (_n - 1).toDouble();

  @override
  void didUpdateWidget(_NavBody old) {
    super.didUpdateWidget(old);
    if (widget.selected == old.selected) return;
    final to = widget.selected.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _p.value = to;
      _l.value = to;
      _r.value = to;
      return;
    }
    final forward = to > _l.value;
    void go(AnimationController c, SpringDescription s) =>
        c.animateWith(SpringSimulation(s, c.value, to, c.velocity));
    go(_p, _widths);
    go(_l, forward ? _trail : _lead);
    go(_r, forward ? _lead : _trail);
  }

  @override
  void dispose() {
    _p.dispose();
    _l.dispose();
    _r.dispose();
    super.dispose();
  }

  /// How selected item [i] is when the widths stand at [p]: 1 on it, 0 a
  /// whole item away.
  static double _on(double p, int i) => (1 - (p - i).abs()).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final unit = w / (_n + _k);
        final pillW = unit * (1 + _k);
        return Stack(
          children: [
            Positioned.fill(
              child: KeyedSubtree(
                key: const ValueKey('one-nav-pill'),
                child: CustomPaint(
                  painter: OneNavIndicatorPainter(
                    left: _l.drive(_Times(unit)),
                    right: _r.drive(_Times(unit, plus: pillW)),
                    color: p.selected,
                    radius: OneBottomNav.radius - 6,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _p,
              builder: (context, _) {
                final at = _p.value;
                return Row(
                  children: [
                    for (var i = 0; i < _n; i++)
                      SizedBox(
                        width: unit * (1 + _k * _on(at, i)),
                        child: _item(i, _on(at, i)),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _item(int i, double on) {
    final p = widget.palette;
    final selected = i == widget.selected;
    final (icon, label) = widget.items[i];
    final shown = on > 0.5 ? (widget.activeIcons?[i] ?? icon) : icon;
    final color = Color.lerp(p.sub, p.primary, on)!;
    final open = Curves.easeOut.transform(on);
    Widget body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(shown, size: 24, color: color),
        // The label opens with the item: clipped to a growing width and
        // faded in, so it reads as part of the pill's arrival.
        ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: open,
            child: Opacity(
              opacity: ((on - 0.3) / 0.7).clamp(0.0, 1.0),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    body = Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: () => widget.onSelected(i),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => widget.onSelected(i),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            // A long label or a large font shrinks rather than overflows.
            child: FittedBox(fit: BoxFit.scaleDown, child: body),
          ),
        ),
      ),
    );
    // Icon-only items name themselves on a long press too.
    return selected
        ? body
        : Tooltip(message: label, excludeFromSemantics: true, child: body);
  }
}

/// Item units to pixels, for the pill's edges.
class _Times extends Animatable<double> {
  const _Times(this.unit, {this.plus = 0});
  final double unit, plus;
  @override
  double transform(double t) => t * unit + plus;
}

/// Paints the navigation's selection pill from its two edge springs.
/// Public so a test can read where the pill is.
class OneNavIndicatorPainter extends CustomPainter {
  OneNavIndicatorPainter({
    required this.left,
    required this.right,
    required this.color,
    required this.radius,
  }) : super(repaint: Listenable.merge([left, right]));

  final ValueListenable<double> left;
  final ValueListenable<double> right;
  final Color color;
  final double radius;

  /// The pill's current edges, clamped to the bar.
  (double, double) edges(double width) {
    final l = left.value.clamp(0.0, width);
    final r = right.value.clamp(l, width);
    return (l, r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (l, r) = edges(size.width);
    canvas.drawRRect(
      RRect.fromLTRBR(l, 0, r, size.height, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(OneNavIndicatorPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.left.value != left.value ||
      old.right.value != right.value;
}
