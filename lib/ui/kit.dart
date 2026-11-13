import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../state/settings.dart';
import 'ambient.dart';
import 'glass_surface.dart';
import 'scale.dart';

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
      16, mq.top + 44 + 14, 16, mq.bottom + (tabBar ? 64.dp + 14.dp + 20.dp : 28.dp));
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
      statusBarStyle: p.dark ? GlassStatusBarStyle.light : GlassStatusBarStyle.dark,
      appBar: GlassAppBar(
        title: Text(title,
            style: TextStyle(color: p.ink, fontSize: 17.sp, fontWeight: FontWeight.w600)),
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
      body: Listener(
        onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        child: ListView(
          padding: pagePadding(context),
          children: children,
        ),
      ),
    );
  }
}

/// A glass card. Content inside stays plain; no glass buttons nest in it.
class Pane extends StatelessWidget {
  const Pane({super.key, required this.child, this.padding, this.tint});
  final Widget child;
  final EdgeInsets? padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 26.dp,
      padding: padding ?? EdgeInsets.fromLTRB(18.dp, 16.dp, 18.dp, 16.dp),
      tint: tint,
      child: child,
    );
  }
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
    final s = SettingsScope.of(context);
    final d = await showGlassDatePicker(
      context: context,
      initialDateTime: value,
      minimumDate: DateTime(1, 1, 1),
      maximumDate: DateTime(9999, 12, 31),
      tintColor: s.accent.color,
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
      mode: GlassDatePickerMode.time,
      style: GlassDatePickerStyle.compact,
      use24hFormat: s.use24h,
      tintColor: s.accent.color,
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
        Row(children: [
          Caption(label),
          const Spacer(),
          Caption(DateFormat('EEEE').format(value), color: p.accent),
        ]),
        SizedBox(height: 6.dp),
        Row(children: [
          Expanded(
            child: _Tap(
              onTap: () => _pickDate(context),
              semantic: '$label, ${s.date(value)}. Change date',
              child: Row(children: [
                Flexible(
                  child: Text(s.date(value),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink, fontSize: 22.sp, fontWeight: FontWeight.w600)),
                ),
                SizedBox(width: 6.dp),
                Icon(CupertinoIcons.calendar, size: 18.dp, color: p.accent),
              ]),
            ),
          ),
          if (withTime)
            _Tap(
              onTap: () => _pickTime(context),
              semantic: 'Time ${s.time(value)}. Change time',
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.dp, vertical: 7.dp),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20.dp),
                ),
                child: Text(s.time(value),
                    style: TextStyle(
                        color: p.accent, fontSize: 15.sp, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ],
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.child, required this.onTap, required this.semantic});
  final Widget child;
  final VoidCallback onTap;
  final String semantic;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 44.dp),
            child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: child),
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
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.hint});
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: p.ink, fontSize: 15.5.sp, fontWeight: FontWeight.w500)),
          if (hint != null)
            Padding(
              padding: EdgeInsets.only(top: 2.dp),
              child: Text(hint!, style: TextStyle(color: p.sub, fontSize: 12.5.sp)),
            ),
        ]),
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
    ]);
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
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value,
            style: TextStyle(
                color: p.ink,
                fontSize: size,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      SizedBox(height: 2.dp),
      Caption(unit),
    ]);
  }
}

/// A two-column grid of small stat cards.
class StatGrid extends StatelessWidget {
  const StatGrid(this.items, {super.key});
  final List<(String value, String label)> items;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      Widget tile((String, String) it) => Expanded(
            child: Pane(
              padding: EdgeInsets.fromLTRB(16.dp, 14.dp, 16.dp, 14.dp),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(it.$1,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                SizedBox(height: 4.dp),
                Text(it.$2, style: TextStyle(color: p.sub, fontSize: 12.5.sp)),
              ]),
            ),
          );
      rows.add(Padding(
        padding: EdgeInsets.only(bottom: 12.dp),
        child: Row(children: [
          tile(items[i]),
          SizedBox(width: 12.dp),
          if (i + 1 < items.length) tile(items[i + 1]) else const Expanded(child: SizedBox()),
        ]),
      ));
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, style: TextStyle(color: p.sub, fontSize: 14.sp))),
        SizedBox(width: 12.dp),
        Flexible(
          flex: 2,
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 14.5.sp,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
    );
  }
}

/// Reset / Copy / Share, as floating glass capsules below the result.
/// They sit on the page, never inside a card (no glass inside glass).
class ResultActions extends StatelessWidget {
  const ResultActions({super.key, required this.shareText, this.onReset});
  final String Function() shareText;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = SettingsScope.of(context);
    Widget pill(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: GlassPress(
            onTap: onTap,
            label: label,
            child: SizedBox(
              height: 50.dp,
              child: GlassSurface(
                radius: 25.dp,
                thick: true,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 18.dp, color: p.ink),
                  SizedBox(width: 8.dp),
                  Text(label, style: TextStyle(color: p.ink, fontSize: 15.sp, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(top: 14.dp),
      child: Row(children: [
        if (onReset != null) ...[
          pill(CupertinoIcons.arrow_counterclockwise, 'Reset', onReset!),
          SizedBox(width: 10.dp),
        ],
        pill(CupertinoIcons.doc_on_doc, 'Copy', () {
          Clipboard.setData(ClipboardData(text: shareText()));
          GlassToast.show(context,
              message: 'Copied',
              icon: const Icon(CupertinoIcons.checkmark_alt),
              duration: const Duration(milliseconds: 1600));
        }),
        if (s.showShare) ...[
          SizedBox(width: 10.dp),
          pill(CupertinoIcons.share, 'Share', () {
            SharePlus.instance.share(ShareParams(text: shareText()));
          }),
        ],
      ]),
    );
  }
}

/// A glass segmented control for short choices, used on the page: the
/// cards' glass with a pill that slides under the choice, the same pill as
/// the tab bar. The library's control stretched like jelly and, being a
/// shader, drew over the title bar when scrolled under it.
class Segments<T> extends StatelessWidget {
  const Segments({super.key, required this.values, required this.labels, required this.selected, required this.onChanged});
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final height = 46.dp;
    final index = values.indexOf(selected).clamp(0, values.length - 1);
    return GlassSurface(
      radius: height / 2,
      thick: true,
      padding: EdgeInsets.all(4.dp),
      child: SizedBox(
        height: height - 8.dp,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth / values.length;
          return Stack(children: [
            AnimatedPositioned(
              duration: Duration(milliseconds: still ? 0 : 260),
              curve: Curves.easeOutCubic,
              left: w * index,
              top: 0,
              bottom: 0,
              width: w,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: p.dark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.8),
                  border: Border.all(color: Colors.white.withValues(alpha: p.dark ? 0.18 : 0.9), width: 0.8),
                  boxShadow: p.dark
                      ? null
                      : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
                ),
              ),
            ),
            Row(children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: labels[i],
                    excludeSemantics: true,
                    onTap: () => onChanged(values[i]),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (i == index) return;
                        HapticFeedback.selectionClick();
                        onChanged(values[i]);
                      },
                      child: Center(
                        child: Text(labels[i],
                            style: TextStyle(
                                color: i == index ? p.ink : p.sub,
                                fontSize: 14.sp,
                                fontWeight: i == index ? FontWeight.w600 : FontWeight.w500)),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      ),
    );
  }
}

/// Tap handling for the app's own glass buttons: a short press-in, haptics
/// left to the caller. The library's glass buttons draw through a shader
/// that ignores the whole-app scale ([ScaleToWidth]), so on any phone not
/// exactly 418 dp wide they were cut flat on the right and bottom; these
/// use the cards' glass instead.
class GlassPress extends StatefulWidget {
  const GlassPress({super.key, required this.onTap, required this.label, required this.child});
  final VoidCallback onTap;
  final String label;
  final Widget child;

  @override
  State<GlassPress> createState() => _GlassPressState();
}

class _GlassPressState extends State<GlassPress> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _set(true),
          onTapCancel: () => _set(false),
          onTapUp: (_) => _set(false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? 0.94 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      );
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
      child: SizedBox.square(
        dimension: size,
        child: GlassSurface(
          radius: size / 2,
          thick: true,
          // Centred by eye, not by box: a box-centred chevron reads as
          // pushed toward its open side, so it moves slightly the way it
          // points. (Nudging it the other way was tried and read worse.)
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
    if (i == CupertinoIcons.chevron_left || i == CupertinoIcons.chevron_back) return -1;
    if (i == CupertinoIcons.chevron_right || i == CupertinoIcons.chevron_forward) return 1;
    return 0;
  }
}
