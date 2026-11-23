"""Play Store art, step 2 of 2: frames the captured screens.

Run after the capture test (see test/store_art_test.dart):

    flutter test test/store_art_test.dart --dart-define=STORE_ART=true
    python tool/store_art.py

Reads build/store_art/raw/<device>_<shot>.png and writes every image under
store/ at its fixed size: a caption (headline, the accent on its second
half, a subline), a device frame holding the real screen with only the
thin gesture handle at its foot (gesture navigation, never 3-button), and
the warm background, light or dark to match the shot.
"""

from __future__ import annotations

import json
import os
import shutil

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "build", "store_art", "raw")
STORE = os.path.join(ROOT, "store")
FONTS = os.path.join(ROOT, "assets", "fonts")
# Where the images go: store/ itself, or a staging folder to check first.
OUT = os.environ.get("STORE_ART_OUT", STORE)

# Logical widths of the captures (test/store_art_test.dart), for dp maths.
LOGICAL_W = {"phone": 412, "tablet": 1280, "square": 840, "desktop": 1280}

ACCENT = (242, 140, 40)
LIGHT = dict(
    top=(250, 245, 237), mid=(242, 233, 221), bottom=(229, 213, 195),
    ink=(24, 22, 20), sub=(112, 102, 92), frame=(21, 19, 21),
    handle=(0, 0, 0, 217),
)
DARK = dict(
    top=(16, 14, 15), mid=(30, 22, 17), bottom=(38, 27, 18),
    ink=(248, 244, 238), sub=(172, 162, 152), frame=(44, 43, 48),
    handle=(255, 255, 255, 217),
)

# stem -> (line 1, accent line, subline, long subline)
SHOTS = {
    "01_today": ("Your day,", "at a glance",
                 "Week, day of year and what's coming up",
                 "Week, day of year and what's coming up"),
    "02_tools": ("Six tools,", "one tap",
                 "Count, find and check any date",
                 "Count, find and check any date"),
    "03_between": ("Time between,", "exactly",
                   "Years, months and days, to the second",
                   "Years, months and days, down to the second"),
    "04_age": ("Your age,", "to the day",
               "With a countdown to your next birthday",
               "With a countdown to your next birthday"),
    "05_work": ("Count your", "working days",
                "Pick your week, skip the days off",
                "Pick your week, skip the days off"),
    "06_settings": ("Make it", "yours",
                    "Seven colours, light or dark, your format",
                    "Seven colours, light or dark, your date format"),
}
ORDER = list(SHOTS)


def font(weight: str, size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(os.path.join(FONTS, f"Inter-{weight}.ttf"), round(size))


def palette(stem: str) -> dict:
    return DARK if int(stem[:2]) % 2 == 0 else LIGHT


def background(w: int, h: int, pal: dict) -> Image.Image:
    """A soft vertical wash: top, a warmer middle, the warmest foot."""
    col = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        a, b, u = (pal["top"], pal["mid"], t / 0.55) if t < 0.55 else (
            pal["mid"], pal["bottom"], (t - 0.55) / 0.45)
        col.putpixel((0, y), tuple(round(a[i] + (b[i] - a[i]) * u) for i in range(3)))
    return col.resize((w, h))


def text_w(f, s):
    return f.getlength(s)


def draw_center(d, cx, y, s, f, fill):
    d.text((cx - text_w(f, s) / 2, y), s, font=f, fill=fill)


def wrap(s: str, f, width: float) -> list[str]:
    words, lines, cur = s.split(), [], ""
    for w in words:
        nxt = f"{cur} {w}".strip()
        if cur and text_w(f, nxt) > width:
            lines.append(cur)
            cur = w
        else:
            cur = nxt
    return lines + [cur]


def device(screen: Image.Image, height: int, pal: dict, device_kind: str,
           radius_frac: float = 0.06, stem: str | None = None) -> Image.Image:
    """The screen, scaled to [height] including the bezel, in a dark frame,
    with only the gesture handle drawn at its foot (gesture navigation,
    never 3-button; a desktop window has none). With [stem], the shot's
    hero card is cut out to be lifted over the frame by [place]."""
    bezel = max(8, round(height * 0.0105))
    inner_h = height - 2 * bezel
    inner_w = round(screen.width * inner_h / screen.height)
    shot = screen.convert("RGB").resize((inner_w, inner_h), Image.LANCZOS)
    shot = shot.convert("RGBA")
    dp = inner_w / LOGICAL_W[device_kind]
    hero = None
    if stem:
        meta = json.load(open(os.path.join(RAW, f"{device_kind}_{stem}.json")))
        # A card that reaches down to the screen's own bottom bar is not
        # lifted: enlarged, it would cover the bar's buttons.
        if "hero" in meta and meta["hero"][3] < meta["height"] * 0.82:
            k = inner_w / meta["width"]
            l, t, r, b = (round(v * k) for v in meta["hero"])
            card = shot.crop((l, t, r, b))
            m = Image.new("L", card.size, 0)
            rad = (18 if stem == "02_tools" else 26) * k * scale_of(meta)
            ImageDraw.Draw(m).rounded_rectangle((0, 0, card.width - 1, card.height - 1), rad, fill=255)
            card.putalpha(m)
            hero = (card, l + bezel, t + bezel)
    if device_kind != "desktop":
        # The gesture handle: 108 x 4 dp, 8 dp above the bottom edge.
        over = Image.new("RGBA", shot.size, (0, 0, 0, 0))
        od = ImageDraw.Draw(over)
        hw, hh = 108 * dp, max(2, 4 * dp)
        hy = inner_h - 8 * dp - hh
        od.rounded_rectangle(
            (inner_w / 2 - hw / 2, hy, inner_w / 2 + hw / 2, hy + hh),
            radius=hh / 2, fill=pal["handle"])
        shot = Image.alpha_composite(shot, over)

    w, h = inner_w + 2 * bezel, height
    r_out = round(min(w, h) * radius_frac) + bezel
    r_in = r_out - bezel
    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, w - 1, h - 1), r_out, fill=pal["frame"] + (255,))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner_w - 1, inner_h - 1), r_in, fill=255)
    frame.paste(shot, (bezel, bezel), mask)
    frame.info["hero"] = hero
    return frame


def scale_of(meta: dict) -> float:
    """The app's own ScaleToWidth factor at the capture's size."""
    w, h = meta["width"], meta["height"]
    f = min(min(w, h) / 418, max(w, h) / 860)
    return max(0.8, min(f, max(1.15, min(2.0, max(w, h) / 1200))))


def place(canvas: Image.Image, dev: Image.Image, x: int, y: int, dark: bool):
    """Pastes [dev] with one soft shadow under it."""
    pad = 80
    sh = Image.new("RGBA", (dev.width + 2 * pad, dev.height + 2 * pad), (0, 0, 0, 0))
    a = dev.split()[3].point(lambda v: round(v * (0.55 if dark else 0.28)))
    sh.paste((0, 0, 0, 255), (pad, pad), a)
    sh = sh.filter(ImageFilter.GaussianBlur(36))
    canvas.alpha_composite(sh, (x - pad, y - pad + 24))
    canvas.alpha_composite(dev, (x, y))
    hero = dev.info.get("hero")
    if hero:
        # The hero card, lifted: 6% larger, on its own deeper shadow, so it
        # stands out of the screen as the old set's did.
        card, hx, hy = hero
        big = card.resize((round(card.width * 1.06), round(card.height * 1.06)), Image.LANCZOS)
        cx, cy = x + hx + card.width / 2, y + hy + card.height / 2
        bx, by = round(cx - big.width / 2), round(cy - big.height / 2)
        pad = 60
        sh = Image.new("RGBA", (big.width + 2 * pad, big.height + 2 * pad), (0, 0, 0, 0))
        a = big.split()[3].point(lambda v: round(v * (0.6 if dark else 0.3)))
        sh.paste((0, 0, 0, 255), (pad, pad), a)
        sh = sh.filter(ImageFilter.GaussianBlur(28))
        canvas.alpha_composite(sh, (bx - pad, by - pad + 18))
        canvas.alpha_composite(big, (bx, by))


def raw(kind: str, stem: str) -> Image.Image:
    return Image.open(os.path.join(RAW, f"{kind}_{stem}.png"))


def save(img: Image.Image, *path: str):
    out = os.path.join(OUT, *path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.convert("RGB").save(out, optimize=True)
    print(out, img.size)


# ───────────────────────────── layouts

def portrait(W: int, H: int, stem: str, kind: str, long_sub=False) -> Image.Image:
    """Phone-like: two-line headline centred, device below."""
    pal = palette(stem)
    l1, l2, sub, sub_long = SHOTS[stem]
    s = W / 1080
    img = background(W, H, pal).convert("RGBA")
    d = ImageDraw.Draw(img)
    hf, sf = font("ExtraBold", 96 * s), font("Regular", 38 * s)
    draw_center(d, W / 2, 106 * s, l1, hf, pal["ink"])
    draw_center(d, W / 2, 204 * s, l2, hf, ACCENT)
    draw_center(d, W / 2, 342 * s, sub_long if long_sub else sub, sf, pal["sub"])
    top = round(444 * s)
    dev = device(raw(kind, stem), H - top - round(48 * s), pal, kind, 0.075, stem)
    place(img, dev, (W - dev.width) // 2, top, pal is DARK)
    return img


def landscape(W: int, H: int, stem: str, kind: str = "tablet") -> Image.Image:
    """Tablet / desktop: one-line headline, tablet below."""
    pal = palette(stem)
    l1, l2, sub, _ = SHOTS[stem]
    img = background(W, H, pal).convert("RGBA")
    d = ImageDraw.Draw(img)
    hf, sf = font("ExtraBold", 80), font("Regular", 38)
    total = text_w(hf, l1 + " ") + text_w(hf, l2)
    x = W / 2 - total / 2
    d.text((x, 104), l1 + " ", font=hf, fill=pal["ink"])
    d.text((x + text_w(hf, l1 + " "), 104), l2, font=hf, fill=ACCENT)
    draw_center(d, W / 2, 218, sub, sf, pal["sub"])
    top = 298
    dev = device(raw(kind, stem), H - top - 34, pal, kind, 0.045 if kind == "tablet" else 0.02, stem)
    place(img, dev, (W - dev.width) // 2, top, pal is DARK)
    return img


def side(W: int, H: int, stem: str, frac: float = 0.82) -> Image.Image:
    """Wide foldable / 7in tablet: caption on the left, device on the right."""
    pal = palette(stem)
    l1, l2, _, sub = SHOTS[stem]
    s = min(H / 1080, W / 1920)
    img = background(W, H, pal).convert("RGBA")
    d = ImageDraw.Draw(img)
    dev = device(raw("square", stem), round(H * frac), pal, "square", 0.05, stem)
    dx = W - dev.width - round(96 * s)
    x = round(110 * s)
    # The headline never reaches the device: it shrinks to the room left.
    size = 80 * s
    while max(text_w(font("ExtraBold", size), l) for l in (l1, l2)) > dx - x - 48 * s:
        size -= 2
    s = min(s, size / 80)
    hf, sf = font("ExtraBold", 80 * s), font("Regular", 36 * s)
    lines = wrap(sub, sf, min(dx - x - 60 * s, 600 * s))
    block = 96 * s * 2 + 24 * s + len(lines) * 50 * s
    y = H / 2 - block / 2
    d.text((x, y), l1, font=hf, fill=pal["ink"])
    d.text((x, y + 96 * s), l2, font=hf, fill=ACCENT)
    for i, line in enumerate(lines):
        d.text((x, y + 2 * 96 * s + 24 * s + i * 50 * s), line, font=sf, fill=pal["sub"])
    place(img, dev, dx, (H - dev.height) // 2, pal is DARK)
    return img


def square(W: int, H: int, stem: str) -> Image.Image:
    """Unfolded 1:1: two-line headline, near-square device below."""
    pal = palette(stem)
    l1, l2, _, sub = SHOTS[stem]
    s = W / 2048
    img = background(W, H, pal).convert("RGBA")
    d = ImageDraw.Draw(img)
    hf, sf = font("ExtraBold", 150 * s), font("Regular", 66 * s)
    draw_center(d, W / 2, 190 * s, l1, hf, pal["ink"])
    draw_center(d, W / 2, 345 * s, l2, hf, ACCENT)
    draw_center(d, W / 2, 568 * s, sub, sf, pal["sub"])
    top = round(724 * s)
    dev = device(raw("square", stem), H - top - round(60 * s), pal, "square", 0.05, stem)
    place(img, dev, (W - dev.width) // 2, top, pal is DARK)
    return img


def feature_graphic():
    W, H = 1024, 500
    pal = dict(DARK, top=(40, 27, 18), mid=(44, 30, 19), bottom=(56, 38, 21))
    img = background(W, H, pal).convert("RGBA")
    d = ImageDraw.Draw(img)
    icon = Image.open(os.path.join(STORE, "icon_512.png")).convert("RGBA").resize((112, 112), Image.LANCZOS)
    m = Image.new("L", icon.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, 111, 111), 26, fill=255)
    img.paste(icon, (64, 100), m)
    d.text((62, 238), "Dates", font=font("Bold", 74), fill=(248, 244, 238))
    bf = font("Bold", 34)
    d.text((64, 332), "Every date, ", font=bf, fill=(248, 244, 238))
    d.text((64 + text_w(bf, "Every date, "), 332), "counted.", font=bf, fill=ACCENT)
    d.text((64, 381), "Countdowns, age, working days and more",
           font=font("Regular", 21), fill=(172, 162, 152))
    # A light phone showing Today, running off the foot.
    shot = raw("phone", "01_today")
    dev = device(shot, 760, dict(LIGHT, frame=(58, 54, 56)), "phone", 0.075)
    place(img, dev, 545, 48, True)
    save(img, "feature_graphic.png")


def main():
    for stem in ORDER:
        save(portrait(1080, 1920, stem, "phone"), "phone", f"{stem}.png")
        save(landscape(1920, 1080, stem), "tablet_10in", f"{stem}.png")
        save(landscape(1920, 1080, stem, "desktop"), "desktop", f"{stem}.png")
        t7 = {"05_work": "05_working", "06_settings": "06_yours"}.get(stem, stem)
        save(side(1920, 1080, stem), "tablet_7in", f"{t7}.png")
        n = stem[:2]
        save(portrait(1000, 1600, stem, "phone"), "foldable", "folded_10x16", f"{n}.png")
        save(square(2048, 2048, stem), "foldable", "unfolded_1x1", f"{n}.png")
        save(side(2048, 1536, stem, 0.78), "foldable", "unfolded_4x3", f"{n}.png")
    # The upload set: one of each shape, by the names Play was given.
    for name, src in [
        ("1_today_1x1.png", ("unfolded_1x1", "01.png")),
        ("2_tools_4x3.png", ("unfolded_4x3", "02.png")),
        ("3_between_10x16.png", ("folded_10x16", "03.png")),
        ("4_age_1x1.png", ("unfolded_1x1", "04.png")),
        ("5_working_4x3.png", ("unfolded_4x3", "05.png")),
        ("6_settings_10x16.png", ("folded_10x16", "06.png")),
    ]:
        out = os.path.join(OUT, "fold_upload", name)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        shutil.copyfile(os.path.join(OUT, "foldable", *src), out)
        print(out, Image.open(out).size)
    feature_graphic()


if __name__ == "__main__":
    main()
