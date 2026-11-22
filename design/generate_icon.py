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
SURFACE = (21, 21, 28)      # #15151C
BODY = (242, 242, 247)      # #F2F2F7
PILL = (199, 199, 207)      # #C7C7CF


def draw_remote(canvas_size, body_w_ratio=0.46, vertical_center=0.5):
    """Draw the stylized Siri-remote glyph centered on a TRANSPARENT canvas."""
    W = canvas_size
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    body_w = int(W * body_w_ratio)
    body_h = int(body_w * 2.15)
    radius = body_w // 2
    x0 = (W - body_w) // 2
    y0 = int(W * vertical_center - body_h / 2)
    x1 = x0 + body_w
    y1 = y0 + body_h

    # soft accent glow behind the remote
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    pad = int(body_w * 0.55)
    gd.ellipse(
        [x0 - pad, y0 - pad // 2, x1 + pad, y1 + pad // 2],
        fill=ACCENT + (60,),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.09))
    img.alpha_composite(glow)

    # remote body
    d.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=BODY + (255,))

    # touch surface: dark circle with accent ring, upper third of the body
    ring_d = int(body_w * 0.72)
    ring_r = ring_d // 2
    cx = W // 2
    cy = y0 + int(body_h * 0.30)
    ring_w = max(2, int(W * 0.012))
    d.ellipse(
        [cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r],
        fill=SURFACE + (255,),
        outline=ACCENT + (255,),
        width=ring_w,
    )

    # two pill buttons under the touch surface
    pill_w = int(body_w * 0.42)
    pill_h = max(2, int(pill_w * 0.30))
    py = y0 + int(body_h * 0.62)
    gap = int(pill_h * 1.1)
    for i in range(2):
        oy = py + i * (pill_h + gap)
        d.rounded_rectangle(
            [cx - pill_w // 2, oy, cx + pill_w // 2, oy + pill_h],
            radius=pill_h // 2,
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
    glyph = draw_remote(S, body_w_ratio=0.40, vertical_center=0.52)
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
    fg = draw_remote(432, body_w_ratio=0.30, vertical_center=0.5)
    fg_path = os.path.join(res, "drawable-nodpi", "ic_launcher_foreground.png")
    os.makedirs(os.path.dirname(fg_path), exist_ok=True)
    fg.save(fg_path)
    print("wrote", fg_path)


if __name__ == "__main__":
    main()
