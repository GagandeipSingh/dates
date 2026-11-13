import 'dart:ui';

import 'package:flutter/material.dart';

/// Glass for CONTENT cards, built the way the compass app builds its glass:
/// a backdrop blur, a translucent fill and a one-pixel rim that catches the
/// light at the corners. Unlike the shader glass, it does not fall back to a
/// flat white card while the list scrolls.
///
/// The navigation chrome (bars, tab bar, switches, segments, buttons) still
/// uses liquid_glass_widgets, which is where the refraction belongs.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.thick = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// A faint colour wash for the result cards.
  final Color? tint;

  /// The compass app's sheet glass: more blur and a denser fill, for a
  /// surface that carries text over busy content (the tab bar).
  final bool thick;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);

    if (MediaQuery.highContrastOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          borderRadius: shape,
          border: Border.all(color: dark ? Colors.white70 : Colors.black54, width: 1.2),
        ),
        child: Padding(padding: padding, child: child),
      );
    }

    var fill = thick
        ? (dark ? Colors.black.withValues(alpha: 0.30) : Colors.white.withValues(alpha: 0.58))
        : (dark ? Colors.black.withValues(alpha: 0.24) : Colors.white.withValues(alpha: 0.46));
    if (tint != null) fill = Color.alphaBlend(tint!, fill);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          // Outer only, so nothing shows through the pane and greys it.
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.06),
            blurRadius: 18,
            blurStyle: BlurStyle.outer,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: thick ? 12 : 14, sigmaY: thick ? 12 : 14),
          child: CustomPaint(
            foregroundPainter: _Rim(radius: radius, dark: dark),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: shape,
                color: fill,
                // A soft top-down sheen, brighter at the top edge.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.06 : 0.22),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(color: fill, borderRadius: shape),
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The edge that makes glass read as glass: bright at the top-left, again at
/// the bottom-right, faint between.
class _Rim extends CustomPainter {
  const _Rim({required this.radius, required this.dark});
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    final hi = dark ? 0.42 : 0.9;
    final lo = dark ? 0.08 : 0.35;
    Color w(double a) => Colors.white.withValues(alpha: a);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [w(hi), w(lo), w(lo), w(hi * 0.7)],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Rim old) => old.radius != radius || old.dark != dark;
}
