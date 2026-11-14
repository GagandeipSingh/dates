import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_surface.dart';
import 'motion.dart';

/// The app's chrome, drawn with the compass app's glass. These keep the names
/// and arguments the screens used from liquid_glass_widgets, so swapping the
/// package out changed no call site.
///
/// The compass rule holds: only the FLOATING layer is glass. The bar is a
/// light blur behind its controls (so a list scrolled under it stays
/// legible), and the controls on it are the glass.

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
  });

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
      ),
      // The background sits OUTSIDE the Scaffold: the Scaffold shrinks its
      // body when the keyboard opens, and a background inside it would be
      // squeezed and redrawn (the sky visibly jumps). Out here it always
      // fills the whole screen and never moves.
      child: Stack(
        children: [
          if (background != null) Positioned.fill(child: background!),
          Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true,
            body: content,
          ),
        ],
      ),
    );
  }
}

/// A floating top bar: [leading], [title] and [actions] in a 44-pt row under
/// the status bar, over a soft blur.
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

  static const double barHeight = 44;

  /// Space between the status bar and the buttons, so they don't touch it.
  static const double gap = 8;

  /// From the top of the screen to the bottom of the bar.
  static double bottomOf(BuildContext context) =>
      MediaQuery.paddingOf(context).top + gap + barHeight;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
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

    if (MediaQuery.highContrastOf(context)) {
      return ColoredBox(
        color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        child: Padding(
          padding: EdgeInsets.only(top: top + gap),
          child: row,
        ),
      );
    }

    // No strip behind the bar: only its buttons are glass, floating over the
    // background as the compass app's controls do.
    return Padding(
      padding: EdgeInsets.only(top: top + gap, bottom: 6),
      child: row,
    );
  }
}

/// A glass bottom sheet: on phones it slides up smoothly as an ergonomic
/// rounded floating card; on larger screens (tablets, foldables, desktop)
/// it seamlessly presents as a centered floating liquid glass modal card.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final isWide = isWideLayout(context);
  if (isWide) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: motion(context, kSpringMs),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        final pop = CurvedAnimation(
          parent: anim,
          curve: kSpring,
          reverseCurve: Curves.easeInCubic,
        );
        final screenH = MediaQuery.sizeOf(ctx).height;
        return Center(
          child: FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(pop),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: math.min(640, screenH - 32),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassSurface(
                    radius: 34,
                    thick: true,
                    // The same glass as the cards and bars, a little more frosted
                    // so its words read over the list, and a shade deeper so it
                    // sits above them.
                    blur: 12,
                    tint: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF16181C).withValues(alpha: 0.30)
                        : const Color(0xFFEEF0F4).withValues(alpha: 0.55),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Material(
                      type: MaterialType.transparency,
                      child: SingleChildScrollView(child: builder(ctx)),
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

  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    // A soft dim behind, as iOS sets a sheet apart from the screen under
    // it; it also keeps the bright controls below from glowing through.
    barrierColor: Colors.black.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.28 : 0.12,
    ),
    isScrollControlled: true,
    useSafeArea: true,
    // Rises on a soft spring and settles, as an iOS sheet does.
    sheetAnimationStyle: AnimationStyle(
      duration: motion(context, kSpringMs),
      reverseCurve: Curves.easeInCubic,
      reverseDuration: motion(context, 240),
    ),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) {
      final inset = MediaQuery.viewInsetsOf(ctx).bottom;
      return _SheetSpring(
        child: _SheetStretch(
          child: Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                child: GlassSurface(
                  radius: 34,
                  thick: true,
                  // The same glass as the cards and bars, a little more frosted
                  // so its words read over the list, and a shade deeper so it
                  // sits above them.
                  blur: 12,
                  tint: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF16181C).withValues(alpha: 0.30)
                      : const Color(0xFFEEF0F4).withValues(alpha: 0.55),
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.onSurface.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(child: builder(ctx)),
                      ),
                    ],
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
/// given, so the sheet arrived flat. This adds the difference between that
/// curve and the app's spring while it opens: the sheet runs a little past
/// its resting place and settles back, as an iOS sheet does. A drag or the
/// close is left alone.
class _SheetSpring extends StatelessWidget {
  const _SheetSpring({required this.child});
  final Widget child;

  // Flutter's own opening curve for a modal sheet (bottom_sheet.dart).
  static const Curve _flutter = Cubic(0.0, 0.0, 0.2, 1.0);

  @override
  Widget build(BuildContext context) {
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (context, child) {
        final t = anim.value;
        final dy = anim.status == AnimationStatus.forward
            ? _flutter.transform(t) - kSpring.transform(t)
            : 0.0;
        return FractionalTranslation(translation: Offset(0, dy), child: child);
      },
    );
  }
}

/// Pulling an open sheet UP stretches it a little on rubber, with more
/// resistance the further it goes, and it springs back on release, as an
/// iOS sheet does. Pulling down is the sheet's own drag to close.
class _SheetStretch extends StatefulWidget {
  const _SheetStretch({required this.child});
  final Widget child;

  @override
  State<_SheetStretch> createState() => _SheetStretchState();
}

class _SheetStretchState extends State<_SheetStretch> {
  double _pull = 0; // raw finger travel upward, in dp
  double _from = 0; // where the release springs back from
  int _release = 0;
  bool _held = false;

  // Rubber: the first few dp follow the finger, then it stiffens.
  static double _rubber(double d) => 48 * (1 - math.exp(-d / 110));

  void _up() {
    if (!_held) return;
    setState(() {
      _held = false;
      _from = _rubber(_pull);
      _pull = 0;
      _release++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    Widget body;
    if (_held) {
      body = Transform.translate(
        offset: Offset(0, -_rubber(_pull)),
        child: widget.child,
      );
    } else if (_from > 0 && !still) {
      body = TweenAnimationBuilder<double>(
        key: ValueKey(_release),
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: kSpringMs),
        curve: kSpring,
        child: widget.child,
        builder: (context, v, child) =>
            Transform.translate(offset: Offset(0, -_from * v), child: child),
      );
    } else {
      body = widget.child;
    }
    return Listener(
      onPointerMove: (e) {
        final next = _pull - e.delta.dy;
        if (next <= 0 && !_held) return;
        setState(() {
          _held = next > 0;
          _pull = math.max(0, next);
        });
      },
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: body,
    );
  }
}
