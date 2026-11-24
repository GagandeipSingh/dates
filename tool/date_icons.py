"""Generates the launcher icons that show today's date: WED / 28.

The app icon is a white page with the weekday in red over the day of the
month (assets/icon/fg.png). It was drawn once, for WED 28, by stretching each
word's ink into a measured box: Inter Display (optical size 32), the weekday
at weight 720 and the date at 430. This script reproduces that exact drawing
for every weekday and every day: it reads the stretch and the baselines off
"WED" and "28" and applies the SAME stretch to MON..SUN and 1..31, so every
letter and figure keeps the shape it has in the shipped icon. A word is never
re-stretched to fill a box ("1" stays one figure wide, as it would in print).

The daily icons are drawn heavier than that original (owner's call,
2026-11-24: weekday 800, date 560, weekday a little lower), so --check no longer matches fg.png.

Output, all under android/app/src/main (rerun after changing anything here):
  res/drawable/date_wd_<mon..sun>.xml       the weekday, a vector
  res/drawable/date_day_<1..31>.xml         the date, a vector
  res/mipmap-anydpi-v26/ic_date_<wd>_<d>.xml one adaptive icon per combination
  res/values/date_icons.xml                 the same names below Android 8,
                                            pointing at the normal icon
  AndroidManifest.xml                       one launcher alias per combination,
                                            between the DATE ICONS markers

DateIcon.kt enables the alias for today and disables the rest.

  python tool/date_icons.py            write everything
  python tool/date_icons.py --check    redraw WED 28 and compare it with
                                       assets/icon/fg.png (no files written)
"""
import os
import re
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, 'assets', 'icon', 'InterVariable.ttf')
MAIN = os.path.join(ROOT, 'android', 'app', 'src', 'main')
RES = os.path.join(MAIN, 'res')

RED = '#F23E32'
INK = '#222222'
WEEKDAYS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']
DAYS = range(1, 32)

# The original drawing (page_icon.py, kept here as numbers): a 1024 canvas
# drawn 3x supersampled, the tile 0.667 of it, each word's ink stretched into
# (w, h) = fractions of the tile, centred at cy of the tile.
SS = 3
N = 1024 * SS
T = int(1024 * 0.667) * SS
TOP = (N - T) / 2
WORDS = {
    # role: (reference text, weight, box w, box h, centre y, colour)
    'wd': ('WED', 800, T * 0.385, T * 0.11, 0.205, RED),
    'day': ('28', 560, T * 0.67, T * 0.42, 0.58, INK),
}
PIL_SIZE = 400  # the size the original laid the word out at
FLAG_HANG = 0.5  # how much of a leading 1's flag hangs outside (Face.middle)


class Face:
    """One weight of Inter Display: outlines from fontTools, and PIL's layout
    of the reference word, which is what the original stretched."""

    def __init__(self, weight):
        f = TTFont(FONT)
        self.font = instantiateVariableFont(f, {'opsz': 32, 'wght': weight})
        self.upm = self.font['head'].unitsPerEm
        self.cmap = self.font.getBestCmap()
        self.glyphs = self.font.getGlyphSet()
        self.hmtx = self.font['hmtx']
        self.pil = ImageFont.truetype(FONT, PIL_SIZE)
        self.pil.set_variation_by_axes([32, weight])

    def layout(self, text):
        """[(glyph name, x offset in font units)], advancing by the font's
        widths with no kerning, as PIL's basic layout (no raqm) does."""
        x, out = 0, []
        for ch in text:
            g = self.cmap[ord(ch)]
            out.append((g, x))
            x += self.hmtx[g][0]
        return out

    def middle(self, text):
        """The word's horizontal centre as the eye reads it, in font units.

        The ink box's centre, except that HALF of a leading 1's flag hangs
        outside the box. The eye reads a 1 mostly as its stem, and the flag
        sticks out a long way left of it: centring the whole ink box put 1,
        11 and 17 visibly right of centre, and hanging the whole flag put
        them (and 18, 19) visibly left. Half was picked by eye from a third,
        a half and two thirds (owner's call, 2026-11-23). Every other word,
        WED and 28 among them, is its plain ink box."""
        xmin, _, xmax, _ = self.ink(text)
        if text.startswith('1'):
            xmin += FLAG_HANG * (self.stem_left('1') - xmin)
        return (xmin + xmax) / 2

    def stem_left(self, ch):
        """Left edge of the glyph's tallest column run: a 1's stem."""
        from fontTools.pens.recordingPen import RecordingPen
        g = self.cmap[ord(ch)]
        rec = RecordingPen()
        self.glyphs[g].draw(rec)
        xmin, ymin, xmax, ymax = self.ink(ch)
        k = 1000 / max(xmax - xmin, ymax - ymin)
        flat = RecordingPen()
        rec.replay(TransformPen(flat, (k, 0, 0, -k, 10 - xmin * k, 10 + ymax * k)))
        m = rasterize([flat], 1024, 1)
        cols = m.sum(0)
        stem = (cols > 0.9 * cols.max()).nonzero()[0]
        return xmin + (stem.min() - 10) / k

    def ink(self, text):
        """Exact ink box in font units (y up): xmin, ymin, xmax, ymax."""
        from fontTools.pens.boundsPen import BoundsPen
        bp = BoundsPen(self.glyphs)
        for g, x in self.layout(text):
            self.glyphs[g].draw(TransformPen(bp, (1, 0, 0, 1, x, 0)))
        return bp.bounds


def transforms():
    """Font units -> 1024 canvas, per role, read off the reference words."""
    out = {}
    for role, (ref, weight, w, h, cy, colour) in WORDS.items():
        face = Face(weight)
        probe = ImageDraw.Draw(Image.new('L', (1, 1)))
        b = probe.textbbox((0, 0), ref, font=face.pil)
        lw, lh = b[2] - b[0] + 4, b[3] - b[1] + 4
        gw, gh = max(1, int(w)), max(1, int(h))
        y0 = int(TOP + T * cy - gh / 2) + 2 * gh / lh
        px = PIL_SIZE / face.upm
        kx = px * gw / lw / SS
        ky = px * gh / lh / SS
        xmin, _, xmax, ymax = face.ink(ref)
        # PIL's box starts at the pen, not at the ink: a figure's side
        # bearing sits inside it. So the pen (x = 0) lands at x0 less b[0].
        origin = (int(N / 2 - gw / 2) + (2 - b[0]) * gw / lw) / SS
        # Where the reference's visual centre (see Face.middle) landed: every
        # other word puts its own there, so WED 28 stays exactly as drawn.
        centre = origin + face.middle(ref) * kx
        base = y0 / SS + ymax * ky
        out[role] = (face, kx, ky, base, centre, colour)
    return out


def path(face, kx, ky, base, centre, text):
    """The word as SVG path data on the 1024 canvas: same stretch and
    baseline as the reference, visual centre where the reference's was."""
    tx = centre - face.middle(text) * kx
    rec = RecordingPen()
    for g, x in face.layout(text):
        face.glyphs[g].draw(TransformPen(rec, (kx, 0, 0, -ky, tx + x * kx, base)))
    pen = SVGPathPen(None, ntos=lambda v: ('%.2f' % v).rstrip('0').rstrip('.'))
    rec.replay(pen)
    return pen.getCommands(), rec


def vector(d, colour):
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Generated by tool/date_icons.py. Do not edit. -->\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp"\n    android:height="108dp"\n'
            '    android:viewportWidth="1024"\n    android:viewportHeight="1024">\n'
            '    <path\n        android:fillColor="%s"\n'
            '        android:pathData="%s" />\n</vector>\n' % (colour, d))


# The margin around the words, on every icon (the date icons and the static
# one alike, so a switch never changes the size). The original drawing ran
# the words to 65% of the visible circle and sat them high (12% clear above,
# 21% below): beside Chrome and the other apps, themed icons above all, it
# read as crowded (owner, 2026-11-23). PAD_SCALE shrinks the two words as
# one block and the insets centre that block in the circle; both are
# Android's own <inset>, so the glyphs are untouched.
PAD_SCALE = 0.86
# Above true centre by this much of the icon: the heavy date at the bottom
# makes a block centred by its ink look low (owner, 2026-11-23), so it sits
# at the optical centre instead.
OPTICAL_LIFT = 0.02


def padding(tr):
    """(left, top, right, bottom) insets in percent of the 108 dp icon:
    scale the words by PAD_SCALE and centre the tallest pair (the highest
    weekday over the lowest date) on the icon's centre."""
    from fontTools.pens.boundsPen import BoundsPen

    def bounds(role, text):
        face, kx, ky, base, centre, _ = tr[role]
        bp = BoundsPen(None)
        path(face, kx, ky, base, centre, text)[1].replay(bp)
        return bp.bounds

    top = min(bounds('wd', w)[1] for w in WEEKDAYS)
    bottom = max(bounds('day', str(d))[3] for d in DAYS)
    side = (1 - PAD_SCALE) / 2
    inset_top = (512 - (top + bottom) / 2 * PAD_SCALE) / 1024 - OPTICAL_LIFT
    inset_bottom = 1 - PAD_SCALE - inset_top
    return tuple(round(v * 100, 1) for v in (side, inset_top, side, inset_bottom))


def inset_attrs(pad, indent):
    names = ('insetLeft', 'insetTop', 'insetRight', 'insetBottom')
    return ''.join('\n%sandroid:%s="%s%%"' % (indent, n, ('%.1f' % v).rstrip('0').rstrip('.'))
                   for n, v in zip(names, pad))


def adaptive(wd, day, pad):
    layers = ('        <inset%s>\n'
              '            <layer-list>\n'
              '                <item android:drawable="@drawable/date_wd_%s" />\n'
              '                <item android:drawable="@drawable/date_day_%d" />\n'
              '            </layer-list>\n'
              '        </inset>\n') % (inset_attrs(pad, '            '), wd, day)
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Generated by tool/date_icons.py. Do not edit. -->\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background" />\n'
            '    <foreground>\n%s    </foreground>\n'
            '    <monochrome>\n%s    </monochrome>\n'
            '</adaptive-icon>\n') % (layers, layers)


def alias_name(wd, day):
    """Must match DateIcon.aliasFor."""
    return 'Date%s%d' % (wd.capitalize(), day)


def task_alias_name(wd, day):
    """Must match DateIcon.taskAliasFor."""
    return 'Task%s%d' % (wd.capitalize(), day)


def manifest_block():
    lines = ['        <!-- DATE ICONS: generated by tool/date_icons.py, do not edit.',
             '             One launcher entry per weekday and date; DateIcon.kt',
             '             enables today\'s and disables the rest. -->']
    for wd in WEEKDAYS:
        for day in DAYS:
            lines += [
                '        <activity-alias',
                '            android:name=".%s"' % alias_name(wd, day),
                # Not DatesActivity itself: see DateEntryActivity.kt (a
                # task named after an entry later switched off is dropped
                # from Recents).
                '            android:targetActivity=".DateEntryActivity"',
                '            android:icon="@mipmap/ic_date_%s_%d"' % (wd.lower(), day),
                '            android:enabled="false"',
                '            android:exported="true">',
                '            <intent-filter>',
                '                <action android:name="android.intent.action.MAIN"/>',
                '                <category android:name="android.intent.category.LAUNCHER"/>',
                '            </intent-filter>',
                '        </activity-alias>',
            ]
    # One hidden entry per date for the app's task (DateEntryActivity opens
    # the app through today's). Recents draws a task's icon from the entry
    # it was opened by, in the phone's own icon style; these are never
    # switched off, so the task is never dropped. No intent filter and not
    # exported: they appear nowhere else.
    for wd in WEEKDAYS:
        for day in DAYS:
            lines += [
                '        <activity-alias',
                '            android:name=".%s"' % task_alias_name(wd, day),
                '            android:targetActivity=".DatesActivity"',
                '            android:icon="@mipmap/ic_date_%s_%d"' % (wd.lower(), day),
                '            android:exported="false" />',
            ]
    lines.append('        <!-- /DATE ICONS -->')
    return '\n'.join(lines) + '\n'


def write(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write(s)


def rasterize(recs, size=1024, ss=4):
    """Nonzero-winding fill of the recorded outlines, for --check."""
    import numpy as np
    from fontTools.pens.basePen import BasePen

    class Flat(BasePen):
        def __init__(self):
            super().__init__(None)
            self.edges, self.cur, self.start = [], None, None

        def _moveTo(self, p):
            self.cur = self.start = p

        def _lineTo(self, p):
            self.edges.append((self.cur, p)); self.cur = p

        def _curveToOne(self, a, b, c):
            p0 = self.cur
            for i in range(1, 17):
                t = i / 16
                u = 1 - t
                self._lineTo((u**3*p0[0]+3*u*u*t*a[0]+3*u*t*t*b[0]+t**3*c[0],
                              u**3*p0[1]+3*u*u*t*a[1]+3*u*t*t*b[1]+t**3*c[1]))

        def _qCurveToOne(self, a, b):
            p0 = self.cur
            for i in range(1, 17):
                t = i / 16
                u = 1 - t
                self._lineTo((u*u*p0[0]+2*u*t*a[0]+t*t*b[0], u*u*p0[1]+2*u*t*a[1]+t*t*b[1]))

        def _closePath(self):
            if self.cur != self.start:
                self._lineTo(self.start)

    fl = Flat()
    for r in recs:
        r.replay(fl)
    e = np.array([(a[0], a[1], b[0], b[1]) for a, b in fl.edges]) * ss
    H = size * ss
    out = np.zeros((H, H), bool)
    ys = np.arange(H) + 0.5
    y0, y1 = e[:, 1], e[:, 3]
    for row, y in enumerate(ys):
        hit = ((y0 <= y) & (y1 > y)) | ((y1 <= y) & (y0 > y))
        if not hit.any():
            continue
        ee = e[hit]
        x = ee[:, 0] + (y - ee[:, 1]) * (ee[:, 2] - ee[:, 0]) / (ee[:, 3] - ee[:, 1])
        w = np.where(ee[:, 3] > ee[:, 1], 1, -1)
        o = np.argsort(x)
        x, w = x[o], w[o]
        acc = np.cumsum(w)
        for i in range(len(x) - 1):
            if acc[i] != 0:
                a, b = int(np.ceil(x[i] - 0.5)), int(np.ceil(x[i + 1] - 0.5))
                out[row, max(a, 0):max(b, 0)] = True
    return out.reshape(size, ss, size, ss).mean((1, 3))


def check(tf):
    import numpy as np
    recs = [path(*tf['wd'][:5], 'WED')[1], path(*tf['day'][:5], '28')[1]]
    mine = rasterize(recs)
    ref = np.array(Image.open(os.path.join(ROOT, 'assets', 'icon', 'fg.png')))[..., 3] / 255.0
    a, b = ref > 0.5, mine > 0.5
    iou = (a & b).sum() / (a | b).sum()
    diff = np.abs(ref - mine).sum() / ref.sum()
    print('WED 28 vs assets/icon/fg.png: IoU %.4f, coverage difference %.2f%%' % (iou, diff * 100))
    Image.fromarray((mine * 255).astype('uint8')).save(os.path.join(ROOT, 'build', 'date_icon_check.png'))
    return iou


def main():
    tf = transforms()
    if '--check' in sys.argv:
        os.makedirs(os.path.join(ROOT, 'build'), exist_ok=True)
        sys.exit(0 if check(tf) > 0.98 else 1)
    for wd in WEEKDAYS:
        write(os.path.join(RES, 'drawable', 'date_wd_%s.xml' % wd.lower()),
              vector(path(*tf['wd'][:5], wd)[0], tf['wd'][5]))
    for day in DAYS:
        write(os.path.join(RES, 'drawable', 'date_day_%d.xml' % day),
              vector(path(*tf['day'][:5], str(day))[0], tf['day'][5]))
    pad = padding(tf)
    aliases = []
    for wd in WEEKDAYS:
        for day in DAYS:
            name = 'ic_date_%s_%d' % (wd.lower(), day)
            write(os.path.join(RES, 'mipmap-anydpi-v26', name + '.xml'), adaptive(wd.lower(), day, pad))
            aliases.append('    <item name="%s" type="mipmap">@mipmap/ic_launcher</item>' % name)
    write(os.path.join(RES, 'values', 'date_icons.xml'),
          '<?xml version="1.0" encoding="utf-8"?>\n'
          '<!-- Generated by tool/date_icons.py. Do not edit. Below Android 8\n'
          '     there are no adaptive icons; the date aliases are never enabled\n'
          '     there, but each name still needs an icon. -->\n'
          '<resources>\n%s\n</resources>\n' % '\n'.join(aliases))
    mp = os.path.join(MAIN, 'AndroidManifest.xml')
    s = open(mp, encoding='utf-8').read()
    block = manifest_block()
    pat = re.compile(r'        <!-- DATE ICONS:.*?<!-- /DATE ICONS -->\n', re.S)
    if pat.search(s):
        s = pat.sub(lambda _: block, s)
    else:
        s = s.replace('    </application>', block + '    </application>', 1)
    write(mp, s)
    # The static icon (flutter_launcher_icons writes it, from the same WED 28
    # drawing as a picture) gets the same margin, so the icon keeps its size
    # when the first switch replaces it. flutter_launcher_icons can only
    # write one even inset, so rerun this script after it.
    sp = os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml')
    st = open(sp, encoding='utf-8').read()
    st, n = re.subn(r'android:inset(?:Left|Top|Right|Bottom)?="[^"]*"(?:\s*android:inset(?:Left|Top|Right|Bottom)="[^"]*")*',
                    inset_attrs(pad, '          ').lstrip(), st)
    if n != 2:
        sys.exit('ic_launcher.xml: expected 2 insets (foreground, monochrome), found %d' % n)
    write(sp, st)
    print('wrote %d weekdays, %d dates, %d icons and aliases; margin %s'
          % (len(WEEKDAYS), len(DAYS), len(WEEKDAYS) * len(DAYS), pad))


if __name__ == '__main__':
    main()
