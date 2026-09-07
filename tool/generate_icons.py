#!/usr/bin/env python3
"""Generate every raster asset for Sablekey from a single vector description.

The Sablekey mark is a faceted obsidian hexagon lit by an ember gradient, with
the keyhole knocked out as negative space. The facet seam running across the
upper-left is what makes it read as cut obsidian rather than a generic shield.

Run:  python3 tool/generate_icons.py
Deps: pillow
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------
# Brand palette. Keep in sync with lib/ui/theme/tokens.dart.
# ---------------------------------------------------------------------------
OBSIDIAN_TOP = (16, 15, 22)
OBSIDIAN_BOTTOM = (7, 7, 11)
EMBER_TOP = (255, 199, 122)
EMBER_MID = (242, 128, 60)
EMBER_BOTTOM = (216, 74, 95)
FACET_LIFT = 34  # how much lighter the upper-left facet is

WORK = 2048  # supersampled working canvas


def vertical_gradient(size: int, stops: list[tuple[float, tuple[int, int, int]]]) -> Image.Image:
    """Build a vertical gradient from (position, rgb) stops."""
    grad = Image.new("RGB", (1, size))
    px = grad.load()
    stops = sorted(stops, key=lambda s: s[0])
    for y in range(size):
        t = y / max(size - 1, 1)
        lo, hi = stops[0], stops[-1]
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                lo, hi = stops[i], stops[i + 1]
                break
        span = max(hi[0] - lo[0], 1e-6)
        k = min(max((t - lo[0]) / span, 0.0), 1.0)
        px[0, y] = tuple(round(lo[1][c] + (hi[1][c] - lo[1][c]) * k) for c in range(3))
    return grad.resize((size, size), Image.NEAREST)


def hexagon(cx: float, cy: float, r: float) -> list[tuple[float, float]]:
    """Pointy-top hexagon."""
    return [
        (cx + r * math.sin(math.radians(60 * i)), cy - r * math.cos(math.radians(60 * i)))
        for i in range(6)
    ]


def keyhole_mask(size: int, cx: float, cy: float, scale: float) -> Image.Image:
    """The keyhole: a bore circle over a tapered ward slot."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    bore = 0.118 * scale
    top = cy - 0.090 * scale
    d.ellipse([cx - bore, top - bore, cx + bore, top + bore], fill=255)
    # Long, narrow ward slot. Kept slim so the mark never reads as a figure.
    half_top = bore * 0.38
    half_foot = bore * 0.66
    foot = cy + 0.300 * scale
    d.polygon(
        [
            (cx - half_top, top),
            (cx + half_top, top),
            (cx + half_foot, foot),
            (cx - half_foot, foot),
        ],
        fill=255,
    )
    return mask


def build_mark(size: int, with_background: bool, bleed: float = 1.0) -> Image.Image:
    """Render the Sablekey mark.

    bleed < 1 shrinks the mark inside the canvas, which is what Android
    adaptive icons need (the launcher masks and animates the outer 33%).
    """
    s = WORK
    cx = cy = s / 2
    scale = s * 0.56 * bleed
    r = scale * 0.5

    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    if with_background:
        bg = vertical_gradient(s, [(0.0, OBSIDIAN_TOP), (1.0, OBSIDIAN_BOTTOM)]).convert("RGBA")
        # Faint ember bloom behind the mark so the tile is not flat black.
        bloom = Image.new("L", (s, s), 0)
        ImageDraw.Draw(bloom).ellipse(
            [cx - s * 0.42, cy - s * 0.30, cx + s * 0.42, cy + s * 0.54], fill=46
        )
        bloom = bloom.filter(ImageFilter.GaussianBlur(s * 0.11))
        bg = Image.composite(Image.new("RGBA", (s, s), (232, 118, 62, 255)), bg, bloom)
        canvas.alpha_composite(bg)

    # --- hexagon body -------------------------------------------------------
    hex_pts = hexagon(cx, cy, r)
    body = Image.new("L", (s, s), 0)
    ImageDraw.Draw(body).polygon(hex_pts, fill=255)

    ember = vertical_gradient(
        s, [(0.18, EMBER_TOP), (0.55, EMBER_MID), (1.0, EMBER_BOTTOM)]
    ).convert("RGBA")

    # --- facet: lift the upper-left half, separated by a thin obsidian seam --
    facet = Image.new("L", (s, s), 0)
    seam_dx, seam_dy = r * 1.35, r * 0.78
    ImageDraw.Draw(facet).polygon(
        [
            (cx - seam_dx, cy - seam_dy),
            (cx + seam_dx * 0.30, cy - seam_dy * 1.9),
            (cx + seam_dx, cy - seam_dy * 0.20),
            (cx - seam_dx, cy + seam_dy * 0.9),
        ],
        fill=255,
    )
    lifted = ember.point(lambda v: min(255, v + FACET_LIFT))
    ember = Image.composite(lifted, ember, facet)

    # The seam itself: a hairline of background showing through the plate.
    seam = Image.new("L", (s, s), 0)
    ImageDraw.Draw(seam).line(
        [(cx - seam_dx, cy + seam_dy * 0.9), (cx + seam_dx, cy - seam_dy * 0.20)],
        fill=255,
        width=max(2, int(s * 0.008)),
    )
    body = Image.composite(Image.new("L", (s, s), 0), body, seam)

    # --- knock the keyhole out of the plate ---------------------------------
    hole = keyhole_mask(s, cx, cy, scale)
    body = Image.composite(Image.new("L", (s, s), 0), body, hole)

    plate = ember.copy()
    plate.putalpha(body)
    canvas.alpha_composite(plate)

    return canvas.resize((size, size), Image.LANCZOS)


def build_monochrome(size: int) -> Image.Image:
    """Android 13+ themed icon: opaque silhouette, system tints it."""
    img = build_mark(size, with_background=False)
    white = Image.new("RGBA", img.size, (255, 255, 255, 255))
    white.putalpha(img.getchannel("A"))
    return white


def write(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)
    print(f"  {path.relative_to(ROOT)}  {img.size[0]}x{img.size[1]}")


def main() -> None:
    print("Sablekey asset generation")

    # Master artwork -------------------------------------------------------
    write(build_mark(1024, with_background=True), ROOT / "assets/brand/sablekey_icon_1024.png")
    write(build_mark(512, with_background=False), ROOT / "assets/brand/sablekey_mark_512.png")

    # Android legacy + round mipmaps ---------------------------------------
    android = ROOT / "android/app/src/main/res"
    for folder, px in [
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ]:
        tile = build_mark(px, with_background=True)
        write(tile, android / folder / "ic_launcher.png")
        write(tile, android / folder / "ic_launcher_round.png")

    # Android adaptive foreground + monochrome (108dp canvas) --------------
    for folder, px in [
        ("mipmap-mdpi", 108),
        ("mipmap-hdpi", 162),
        ("mipmap-xhdpi", 216),
        ("mipmap-xxhdpi", 324),
        ("mipmap-xxxhdpi", 432),
    ]:
        write(build_mark(px, with_background=False, bleed=0.62), android / folder / "ic_launcher_foreground.png")
        write(build_monochrome(px), android / folder / "ic_launcher_monochrome.png")

    # iOS app icon set -----------------------------------------------------
    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    ios_sizes = [
        (20, 1), (20, 2), (20, 3), (29, 1), (29, 2), (29, 3),
        (40, 1), (40, 2), (40, 3), (60, 2), (60, 3),
        (76, 1), (76, 2), (83.5, 2), (1024, 1),
    ]
    images = []
    for pt, sc in ios_sizes:
        px = int(round(pt * sc))
        name = f"Icon-App-{pt:g}x{pt:g}@{sc}x.png"
        write(build_mark(px, with_background=True), ios / name)
        entry = {"size": f"{pt:g}x{pt:g}", "idiom": "ios-marketing" if pt == 1024 else "iphone",
                 "filename": name, "scale": f"{sc}x"}
        if pt in (76, 83.5) or (pt in (20, 29, 40) and sc in (1, 2)):
            entry["idiom"] = "ipad" if pt in (76, 83.5) else entry["idiom"]
        images.append(entry)
    (ios / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"version": 1, "author": "sablekey"}}, indent=2) + "\n"
    )
    print(f"  {(ios / 'Contents.json').relative_to(ROOT)}")

    print("done.")


if __name__ == "__main__":
    main()
