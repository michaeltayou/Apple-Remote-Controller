"""Generate the Apple TV Remote launcher icons.

Renders:
  - design/app_icon_1024.png             master icon (rounded dark tile + remote glyph)
  - android/app/src/main/res/mipmap-*/ic_launcher.png   legacy launcher icons
  - android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png
  - (adaptive icon XML + background color are static files in res/)

Run:  python design/generate_icon.py
"""

from PIL import Image, ImageDraw, ImageFilter

BG_TOP = (27, 27, 36)       # #1B1B24
BG_BOTTOM = (16, 16, 22)    # #101016
ACCENT = (10, 132, 255)     # #0A84FF (app accent)
AMBER = (255, 214, 10)      # #FFD60A (lamp glow)
SURFACE = (21, 21, 28)      # #15151C
BODY = (242, 242, 247)      # #F2F2F7
PILL = (199, 199, 207)      # #C7C7CF


def draw_tv_and_bulb(canvas_size, scale=1.0, vertical_center=0.5):
    """TV + glowing lamp bulb — the app's two controls — on a TRANSPARENT canvas."""
    W = int(canvas_size * scale)
    S = canvas_size
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    off = int(S * vertical_center - W / 2)

    def sx(v):
        return int(off + v * W / 1000)

    # warm glow behind the bulb
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse(
        [sx(500), sx(480), sx(940), sx(920)],
        fill=AMBER + (70,),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.07))
    img.alpha_composite(glow)

    # TV: white frame, dark screen, small stand
    d.rounded_rectangle(
        [sx(90), sx(170), sx(640), sx(560)],
        radius=int(W * 0.045),
        fill=BODY + (255,),
    )
    d.rounded_rectangle(
        [sx(140), sx(220), sx(590), sx(510)],
        radius=int(W * 0.025),
        fill=SURFACE + (255,),
    )
    # subtle accent line inside the screen (a "playing" bar)
    d.rounded_rectangle(
        [sx(200), sx(420), sx(420), sx(455)],
        radius=int(W * 0.012),
        fill=ACCENT + (255,),
    )
    d.rounded_rectangle(
        [sx(350), sx(560), sx(380), sx(630)],
        radius=int(W * 0.012),
        fill=BODY + (255,),
    )
    d.rounded_rectangle(
        [sx(270), sx(630), sx(460), sx(660)],
        radius=int(W * 0.015),
        fill=BODY + (255,),
    )

    # lightbulb: amber globe + grey screw base
    bulb_r = int(W * 0.155)
    bx, by = sx(715), sx(640)
    d.ellipse(
        [bx - bulb_r, by - bulb_r, bx + bulb_r, by + bulb_r],
        fill=AMBER + (255,),
    )
    base_w = int(bulb_r * 0.85)
    d.rounded_rectangle(
        [bx - base_w // 2, by + int(bulb_r * 0.85), bx + base_w // 2, by + int(bulb_r * 1.35)],
        radius=int(W * 0.018),
        fill=PILL + (255,),
    )
    return img


def vertical_gradient(size, top, bottom):
    grad = Image.linear_gradient("L").resize((1, size))  # 0 top -> 255 bottom
    out = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        out.putpixel(
            (0, y),
            tuple(int(top[c] + (bottom[c] - top[c]) * t) for c in range(3)),
        )
    return out.resize((size, size))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255
    )
    return m


def build_master(size=1024):
    S = size * 4  # supersample for crisp edges
    bg = vertical_gradient(S, BG_TOP, BG_BOTTOM).convert("RGBA")
    glyph = draw_tv_and_bulb(S, scale=0.86, vertical_center=0.52)
    bg.alpha_composite(glyph)
    corner = int(S * 0.22)
    bg.putalpha(rounded_mask(S, corner))
    return bg.resize((size, size), Image.LANCZOS)


def main():
    import os

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    res = os.path.join(root, "android", "app", "src", "main", "res")

    # 1) master + legacy mipmaps
    master = build_master(1024)
    master_path = os.path.join(root, "design", "app_icon_1024.png")
    master.save(master_path)
    print("wrote", master_path)

    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in densities.items():
        out = os.path.join(res, folder, "ic_launcher.png")
        master.resize((px, px), Image.LANCZOS).save(out)
        print("wrote", out)

    # 2) adaptive-icon foreground (transparent, glyph in the safe zone)
    fg = draw_tv_and_bulb(432, scale=0.62, vertical_center=0.5)
    fg_path = os.path.join(res, "drawable-nodpi", "ic_launcher_foreground.png")
    os.makedirs(os.path.dirname(fg_path), exist_ok=True)
    fg.save(fg_path)
    print("wrote", fg_path)


if __name__ == "__main__":
    main()
