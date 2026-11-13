import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_surface.dart';
import 'kit.dart';
import 'scale.dart';

/// The floating tab bar: one capsule of the compass app's sheet glass, with
/// a lighter glass pill that slides under the selected tab. Glass cannot
/// sample glass, so the tabs share ONE surface instead of each drawing their
/// own.
class GlassTabs extends StatelessWidget {
  const GlassTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<(IconData, String)> items;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final height = 64.dp;
    void select(int i) {
      if (i == selected) return;
      HapticFeedback.selectionClick();
      onSelected(i);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(24.dp, 0, 24.dp, bottom + 14.dp),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GlassSurface(
          radius: height / 2,
          thick: true,
          padding: EdgeInsets.all(5.dp),
          child: SizedBox(
            height: height - 10.dp,
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth / items.length;
              return Stack(children: [
                // The selection pill.
                AnimatedPositioned(
                  duration: Duration(milliseconds: still ? 0 : 340),
                  curve: Curves.easeOutCubic,
                  left: w * selected,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: p.dark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.75),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: p.dark ? 0.18 : 0.9), width: 0.8),
                      boxShadow: p.dark
                          ? null
                          : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)],
                    ),
                  ),
                ),
                Row(children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == selected,
                        label: items[i].$2,
                        excludeSemantics: true,
                        onTap: () => select(i),
                        // Switches on touch DOWN, as an iOS tab bar does. A
                        // tap recognizer waits for the release and drops the
                        // press if the finger drifts, so a tab sometimes
                        // needed a second press.
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (_) => select(i),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(items[i].$1,
                                size: 22.dp, color: i == selected ? p.accent : p.sub),
                            SizedBox(height: 2.dp),
                            Text(items[i].$2,
                                style: TextStyle(
                                    fontSize: 11.sp,
                                    fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                                    color: i == selected ? p.accent : p.sub)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}
