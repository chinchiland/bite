"""Draws Bite's app icon: a cream cookie with a bite out of it on ink, three crumbs in the macro colors.

Usage: python tools/make_icon.py Bite/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 1024
SCALE = 4  # draw big, then downsample for smooth edges
INK = (28, 21, 18)
CREAM = (246, 244, 241)
PROTEIN = (42, 120, 214)
CARBS = (237, 161, 0)
FAT = (27, 175, 122)


def circle(draw, cx, cy, r, fill):
    draw.ellipse([(cx - r) * SCALE, (cy - r) * SCALE, (cx + r) * SCALE, (cy + r) * SCALE], fill=fill)


def main(out: str) -> None:
    big = Image.new("RGB", (S * SCALE, S * SCALE), INK)

    # The cookie, a little left of center so the bite has room on the right.
    cookie = Image.new("L", big.size, 0)
    d = ImageDraw.Draw(cookie)
    cx, cy, r = 488, 530, 318
    circle(d, cx, cy, r, 255)
    # Three overlapping circles take the bite out of the upper right.
    for bx, by, br in [(784, 366, 112), (712, 250, 104), (826, 494, 98)]:
        circle(d, bx, by, br, 0)
    big.paste(CREAM, (0, 0), cookie)

    # Crumbs falling from the bite.
    d = ImageDraw.Draw(big)
    circle(d, 868, 650, 40, PROTEIN)
    circle(d, 918, 768, 31, CARBS)
    circle(d, 852, 858, 24, FAT)

    icon = big.resize((S, S), Image.LANCZOS)
    icon.save(out, "PNG")
    print(f"wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1])
