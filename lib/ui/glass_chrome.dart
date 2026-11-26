import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'one_ui.dart';

/// The app's chrome in One UI's flat material: the screen scaffold, the
/// compact app bar, the bottom dialog and the floor behind the system
/// navigation. The names are kept from the glass chrome they replaced, so
/// no screen had to change its calls. Nothing here blurs or samples the
/// screen: every bar is solid colour (One UI is fast on small processors
/// because of it).

enum GlassStatusBarStyle { light, dark }

/// A screen over [background], with an optional floating [appBar]. The body
/// runs behind the bar and the status bar; screens pad for it themselves
/// (`pagePadding`).
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    required this.body,
    this.background,
    this.appBar,
    this.statusBarStyle = GlassStatusBarStyle.dark,
    this.maxContentWidth,
    this.bottomBar,
    this.bottomBarHeight = 0,
    this.bottomBarPaintsInset = false,
  });

  /// True when [bottomBar] paints its own floor under the system navigation
  /// (the home dock). A floating bar that does not (a tool screen's action
  /// pills) still gets [NavButtonBacking] under it.
  final bool bottomBarPaintsInset;

  /// A floating bar over the foot of the body (the tab bar). The body runs
  /// under it; screens pad for it themselves.
  final Widget? bottomBar;
  final double bottomBarHeight;

  final Widget body;
  final Widget? background;
  final GlassAppBar? appBar;
  final GlassStatusBarStyle statusBarStyle;
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final overlay = statusBarStyle == GlassStatusBarStyle.light
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    final stack = Stack(
      children: [
        Positioned.fill(child: body),
        if (appBar != null)
          Positioned(left: 0, top: 0, right: 0, child: appBar!),
        if (bottomBar != null)
          Positioned(left: 0, right: 0, bottom: 0, child: bottomBar!),
      ],
    );
    final content = maxContentWidth != null
        ? Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth!),
              child: stack,
            ),
          )
        : stack;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        // The presets assume a BLACK nav bar and so draw white nav buttons.
        // Ours is transparent over the app, so the buttons must follow the
        // status icons, or they vanish on a light screen (Samsung 3-button).
        systemNavigationBarIconBrightness: overlay.statusBarIconBrightness,
      ),
      // The background sits OUTSIDE the Scaffold: the Scaffold shrinks its
      // body when the keyboard opens, and a background inside it would be
      // squeezed and redrawn (the sky visibly jumps). Out here it always
      // fills the whole screen and never moves.
      child: Stack(
        children: [
          Positioned.fill(
            child:
                background ??
                ColoredBox(color: OnePalette.of(context).background),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true,
            body: content,
          ),
          // The home dock paints its own floor under the system navigation;
          // every other screen gets the same floor here.
          if (!bottomBarPaintsInset) const NavButtonBacking(),
        ],
      ),
    );
  }
}

/// A compact One UI app bar: [leading], [title] and [actions] in a row
/// under the status bar, on the screen's own colour. Keep it to three items
/// including the title (guide p.16); more go into a ⋮ menu.
class GlassAppBar extends StatelessWidget {
  const GlassAppBar({
    super.key,
    this.leading,
    this.title,
    this.actions = const [],
    this.centerTitle = false,
  });

  final Widget? leading;
  final Widget? title;
  final List<Widget> actions;
  final bool centerTitle;

  static const double barHeight = 48;

  /// Space between the status bar and the buttons, so they don't touch it.
  static const double gap = 8;

  /// From the top of the screen to the bottom of the bar.
  static double bottomOf(BuildContext context) =>
      MediaQuery.paddingOf(context).top + gap + barHeight;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    final row = SizedBox(
      height: barHeight,
      child: NavigationToolbar(
        // Centred: the toolbar stretches its leading slot to the bar height,
        // which squashed a round button smaller than the bar into an oval.
        leading: leading == null
            ? null
            : Center(widthFactor: 1, child: leading),
        middle: title == null
            ? null
            : DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title!,
              ),
        trailing: actions.isEmpty
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: actions),
        centerMiddle: centerTitle,
        middleSpacing: 12,
      ),
    );

    // A solid bar in the screen's colour, as One UI's compact app bar: the

    // content scrolls under its edge, never shows through it.

    return ColoredBox(
      color: OnePalette.of(context).background,

      child: Padding(
        padding: EdgeInsets.only(top: top + gap, bottom: 6),

        child: row,
      ),
    );
  }
}

/// A One UI bottom dialog (guide p.37: dialogs that need an action sit at
/// the bottom, in reach). A solid popup-coloured card with 26dp corners,
/// floating 10dp in from the edges with a drag handle. It rises on the
/// settle spring ([kSettle], 400ms), landing in place without a bounce,
/// while the dim fades in; its content follows a beat behind (StaggerIn).
/// It closes quickly on an accelerating ease ([kExitMs]) or with the
/// finger, which
/// it follows exactly; a fast flick down closes it from anywhere. Pulled UP
/// it stretches on rubber and springs back. Instant with reduced motion.
/// The same on every screen size: a tablet gets it narrower (max 560dp),
/// still at the bottom. Tall content scrolls inside it.
///
/// Every sheet in the app goes through here (test/motion_coverage_test).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final p = OnePalette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: p.dark ? 0.6 : 0.45),
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: AnimationStyle(
      duration: motion(context, kSettleMs),
      reverseCurve: kExit,
      reverseDuration: motion(context, kExitMs),
    ),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) {
      final inset = MediaQuery.viewInsetsOf(ctx).bottom;
      final q = OnePalette.of(ctx);
      return _SheetSpring(
        child: _SheetStretch(
          child: Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Material(
                  color: q.popup,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(OneUi.radiusBlock),
                    side: MediaQuery.highContrastOf(ctx)
                        ? BorderSide(
                            color: q.ink.withValues(alpha: 0.7),
                            width: 1.5,
                          )
                        : BorderSide.none,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: q.sub.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            child: StaggerIn(
                              index: 2,
                              rise: 10,
                              child: builder(ctx),
                            ),
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
    },
  );
}

/// Flutter's sheet rises on a fixed decelerate and ignores the curve it is
/// given. This adds the difference between that curve and [kSettle] while
/// it opens, so the sheet arrives on the app's spring: quick off the mark,
/// landing without a bounce. A drag or the close is left alone,
/// so the sheet stays under the finger and a flick closes at its speed.
class _SheetSpring extends StatefulWidget {
  const _SheetSpring({required this.child});
  final Widget child;

  @override
  State<_SheetSpring> createState() => _SheetSpringState();
}

class _SheetSpringState extends State<_SheetSpring> {
  // Flutter's own opening curve for a modal sheet (bottom_sheet.dart).
  static const Curve _flutter = Cubic(0.0, 0.0, 0.2, 1.0);

  // Only the OPENING springs. A drag sets the controller by hand and leaves
  // its direction "forward", so status alone cannot tell a finger from the
  // open: once the sheet has arrived, the spring is off for good.
  bool _arrived = false;

  @override
  Widget build(BuildContext context) {
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: anim,
      child: widget.child,
      builder: (context, child) {
        if (anim.status == AnimationStatus.completed) _arrived = true;
        final t = anim.value;
        final dy = !_arrived && anim.status == AnimationStatus.forward
            ? _flutter.transform(t) - kSettle.transform(t)
            : 0.0;
        return FractionalTranslation(translation: Offset(0, dy), child: child);
      },
    );
  }
}

/// Pulling an open sheet UP stretches it a little on rubber, with more
/// resistance the further it goes, and it springs back on release. Pulling
/// down is the sheet's own drag to close.
class _SheetStretch extends StatefulWidget {
  const _SheetStretch({required this.child});
  final Widget child;

  @override
  State<_SheetStretch> createState() => _SheetStretchState();
}

class _SheetStretchState extends State<_SheetStretch>
    with SingleTickerProviderStateMixin {
  double _pull = 0; // raw finger travel upward, in dp
  double _from = 0; // where the release springs back from
  bool _held = false;
  // Set while something inside the sheet (a date wheel, a list) is
  // scrolling: that drag belongs to it, so the sheet does not stretch.
  bool _inner = false;
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: kSnapMs),
  );

  // Rubber: the first few dp follow the finger, then it stiffens.
  static double _rubber(double d) => 48 * (1 - math.exp(-d / 110));

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _up() {
    _inner = false;
    if (!_held) return;
    setState(() {
      _held = false;
      _from = _rubber(_pull);
      _pull = 0;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _from = 0;
    } else {
      _back.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // One fixed structure whatever the state: swapping the wrapper around
    // the child rebuilt everything inside it, so a date wheel being dragged
    // up was thrown back to its start mid-drag.
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        _inner = true;
        if (_held) {
          setState(() {
            _held = false;
            _pull = 0;
          });
        }
        return false;
      },
      child: Listener(
        onPointerMove: (e) {
          if (_inner) return;
          final next = _pull - e.delta.dy;
          if (next <= 0 && !_held) return;
          _back.stop();
          setState(() {
            _from = 0;
            _held = next > 0;
            _pull = math.max(0, next);
          });
        },
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: AnimatedBuilder(
          animation: _back,
          child: widget.child,
          builder: (context, child) {
            final dy = _held
                ? _rubber(_pull)
                : _from * (1 - kSnap.transform(_back.value));
            return Transform.translate(offset: Offset(0, -dy), child: child);
          },
        ),
      ),
    );
  }
}

/// A solid floor of the page colour under the system navigation (the
/// back/home/recents buttons, or the gesture handle), so content never
/// scrolls under them. The same floor the home dock paints under its pills
/// (owner's call, 2026-11-23, extended to every screen 2026-11-26), with
/// nothing above the inset: the page runs right up to it.
class NavButtonBacking extends StatelessWidget {
  const NavButtonBacking({super.key});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).viewPadding.bottom;
    if (h <= 0) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: h,
      child: IgnorePointer(
        child: ColoredBox(color: OnePalette.of(context).background),
      ),
    );
  }
}
