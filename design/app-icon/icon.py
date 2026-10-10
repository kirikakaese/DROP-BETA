"""DROP's app icon: a droplet with an arrow cut out of it, on a rounded tile, in every style.

Same geometry and colors as Packages/DROPKit/Sources/DROPUI/AppIconArtwork.swift, which draws the
icons in the app; change both together. The styles and their palette are the same as SMP's: three
colors and nine pride flags, plus DROP's teal, which is the bundle's icon.

Canvas 1024 x 1024, on Apple's macOS icon grid (the tile is 824 x 824 with a 185 corner radius and
room for its shadow). The droplet is a circle with a point on top; the arrow points down through it.

Usage:
  python3 design/app-icon/icon.py OUT_DIR    writes OUT_DIR/<style>.svg for every style
  python3 design/app-icon/icon.py --bundle   writes the teal PNGs into the app's AppIcon.appiconset
                                             (needs Pillow and NumPy)
"""
import math
import pathlib
import sys

TILE = (100, 100, 824, 824, 185)  # x, y, width, height, corner radius
CENTER = (512, 600)
RADIUS = 230
APEX = (512, 190)
SHAFT = (472, 410, 552, 600)  # left, top, right, bottom
HEAD = [(388, 580), (636, 580), (512, 724)]

GRADIENTS = {  # top, bottom
    "teal": ("#f4fbfa", "#d3ece9"),
    "graphite": ("#5b616b", "#24282e"),
    "blue": ("#4f9bff", "#0b4fd0"),
    "silver": ("#fbfbfd", "#c7ccd4"),
}
FLAGS = {  # (color, weight), top to bottom
    "rainbow": [("#E40303", 1), ("#FF8C00", 1), ("#FFED00", 1), ("#008026", 1), ("#004DFF", 1), ("#750787", 1)],
    "progress": [("#E40303", 1), ("#FF8C00", 1), ("#FFED00", 1), ("#008026", 1), ("#004DFF", 1), ("#750787", 1)],
    "transgender": [("#5BCEFA", 1), ("#F5A9B8", 1), ("#FFFFFF", 1), ("#F5A9B8", 1), ("#5BCEFA", 1)],
    "nonbinary": [("#FCF434", 1), ("#FFFFFF", 1), ("#9C59D1", 1), ("#2C2C2C", 1)],
    "bisexual": [("#D60270", 2), ("#9B4F96", 1), ("#0038A8", 2)],
    "pansexual": [("#FF218C", 1), ("#FFD800", 1), ("#21B1FF", 1)],
    "lesbian": [("#D52D00", 1), ("#EF7627", 1), ("#FF9A56", 1), ("#FFFFFF", 1), ("#D162A4", 1),
                ("#B55690", 1), ("#A30262", 1)],
    "asexual": [("#000000", 1), ("#A3A3A3", 1), ("#FFFFFF", 1), ("#800080", 1)],
    "aromantic": [("#3DA542", 1), ("#A7D379", 1), ("#FFFFFF", 1), ("#A9A9A9", 1), ("#000000", 1)],
}
PROGRESS_CHEVRON = ["#000000", "#784F17", "#5BCEFA", "#F5A9B8", "#FFFFFF"]  # outermost first
TEAL = ("#2cc4b5", "#179a8e", "#0a6f68")
GOLD = ("#ffe9a8", "#e6b43a", "#b8840f")
WHITE = ("#ffffff", "#eef2f8", "#c8d1de")

# (filename, pixels) for every image the asset catalog lists.
PNGS = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
ICONSET = pathlib.Path(__file__).resolve().parents[2] / "App/Resources/Assets.xcassets/AppIcon.appiconset"


def glyph_colors(style):
    """Teal on DROP's tile, gold on graphite and silver, white on blue and on every flag."""
    if style == "teal":
        return TEAL
    return GOLD if style in ("graphite", "silver") else WHITE


def tangent_points():
    """Where the straight sides of the droplet touch the circle."""
    beta = math.pi / 2 - math.asin(RADIUS / (CENTER[1] - APEX[1]))
    dx, dy = RADIUS * math.sin(beta), RADIUS * math.cos(beta)
    return (CENTER[0] + dx, CENTER[1] - dy), (CENTER[0] - dx, CENTER[1] - dy)


def glyph_path():
    right, left = tangent_points()
    l, t, r, b = SHAFT
    drop = (f"M{APEX[0]},{APEX[1]} L{right[0]:.1f},{right[1]:.1f} "
            f"A{RADIUS},{RADIUS} 0 1,1 {left[0]:.1f},{left[1]:.1f} Z")
    arrow = (f"M{l},{t} H{r} V{HEAD[0][1]} H{HEAD[1][0]} L{HEAD[2][0]},{HEAD[2][1]} "
             f"L{HEAD[0][0]},{HEAD[0][1]} H{l} Z")
    return f"{drop} {arrow}"


def svg(style):
    x, y, w, h, r = TILE
    if style in GRADIENTS:
        a, b = GRADIENTS[style]
        bg = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#bg)"/>'
        bgdef = (f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{a}"/>'
                 f'<stop offset="1" stop-color="{b}"/></linearGradient>')
    else:
        stripes = FLAGS[style]
        total = sum(weight for _, weight in stripes)
        top, parts = y, []
        for color, weight in stripes:
            height = h * weight / total
            parts.append(f'<rect x="{x}" y="{top:.2f}" width="{w}" height="{height + 0.5:.2f}" fill="{color}"/>')
            top += height
        if style == "progress":
            for i, color in enumerate(PROGRESS_CHEVRON):
                tip = x + w * (0.46 - 0.075 * i)
                left = x - w * 0.075 * i - 1
                parts.append(f'<polygon points="{left},{y} {tip},{y + h / 2} {left},{y + h}" fill="{color}"/>')
        bg, bgdef = "".join(parts), ""
    on_flag = style not in GRADIENTS
    k0, k1, k2 = glyph_colors(style)
    path = glyph_path()
    outline = (f'<path d="{path}" fill-rule="evenodd" fill="none" stroke="#000" stroke-opacity="0.35" '
               f'stroke-width="20"/>') if on_flag else ""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>{bgdef}
<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.20"/><stop offset="0.5" stop-color="#fff" stop-opacity="0"/></linearGradient>
<linearGradient id="glyph" gradientUnits="userSpaceOnUse" x1="230" y1="230" x2="800" y2="800"><stop offset="0" stop-color="{k0}"/><stop offset="0.5" stop-color="{k1}"/><stop offset="1" stop-color="{k2}"/></linearGradient>
<clipPath id="tile"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/></clipPath>
<filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.30"/></filter>
<filter id="glyphShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="16" stdDeviation="16" flood-color="#000" flood-opacity="{0.55 if on_flag else 0.40}"/></filter>
</defs>
<g filter="url(#tileShadow)"><g clip-path="url(#tile)">{bg}<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#gloss)"/></g>
<rect x="{x + 1}" y="{y + 1}" width="{w - 2}" height="{h - 2}" rx="{r - 1}" fill="none" stroke="#fff" stroke-opacity="0.16" stroke-width="2"/></g>
<g filter="url(#glyphShadow)">{outline}<path d="{path}" fill-rule="evenodd" fill="url(#glyph)"/></g>
</svg>
"""


def render(style, scale=4):
    """The icon in `style` as a 1024-point RGBA image drawn `scale` times larger (Pillow and NumPy)."""
    import numpy as np
    from PIL import Image, ImageChops, ImageDraw, ImageFilter

    size = 1024 * scale

    def rgba(hex_color, alpha=255):
        value = int(hex_color.lstrip("#"), 16)
        return (value >> 16 & 255, value >> 8 & 255, value & 255, alpha)

    def gradient(colors, t):
        """An RGBA image filled by interpolating `colors` along `t` (0...1 per pixel)."""
        stops = np.array([rgba(color) for color in colors], dtype=float)
        positions = np.linspace(0, 1, len(colors))
        channels = [np.interp(t, positions, stops[:, channel]) for channel in range(4)]
        return Image.fromarray(np.dstack(channels).astype(np.uint8), "RGBA")

    def shadow(mask, blur, offset, opacity):
        alpha = mask.filter(ImageFilter.GaussianBlur(blur * scale)).point(lambda v: int(v * opacity))
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        layer.putalpha(ImageChops.offset(alpha, 0, offset * scale))
        return layer

    def points(pairs):
        return [(px * scale, py * scale) for px, py in pairs]

    ys, xs = np.mgrid[0:size, 0:size] / scale
    x, y, w, h, r = TILE
    tile_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(tile_mask).rounded_rectangle(
        [x * scale, y * scale, (x + w) * scale, (y + h) * scale], radius=r * scale, fill=255
    )
    if style in GRADIENTS:
        tile = gradient(GRADIENTS[style], np.clip((ys - y) / h, 0, 1))
    else:
        tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(tile)
        total = sum(weight for _, weight in FLAGS[style])
        top = y
        for color, weight in FLAGS[style]:
            height = h * weight / total
            draw.rectangle([x * scale, top * scale, (x + w) * scale, (top + height + 0.5) * scale], fill=rgba(color))
            top += height
        if style == "progress":
            for i, color in enumerate(PROGRESS_CHEVRON):
                tip, left = x + w * (0.46 - 0.075 * i), x - w * 0.075 * i - 1
                draw.polygon(points([(left, y), (tip, y + h / 2), (left, y + h)]), fill=rgba(color))
    gloss = gradient(("#ffffff", "#ffffff"), np.zeros_like(ys))
    gloss.putalpha(Image.fromarray((np.clip(1 - (ys - y) / (h / 2), 0, 1) * 0.2 * 255).astype(np.uint8)))
    tile.alpha_composite(gloss)
    tile.putalpha(tile_mask)
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(
        [(x + 1) * scale, (y + 1) * scale, (x + w - 1) * scale, (y + h - 1) * scale],
        radius=(r - 1) * scale, outline=rgba("#ffffff", int(0.16 * 255)), width=2 * scale,
    )

    right, left = tangent_points()
    glyph_mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(glyph_mask)
    draw.polygon(points([APEX, right, CENTER, left]), fill=255)
    cx, cy = CENTER
    draw.ellipse([(cx - RADIUS) * scale, (cy - RADIUS) * scale, (cx + RADIUS) * scale, (cy + RADIUS) * scale],
                 fill=255)
    arrow = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(arrow)
    left_edge, top_edge, right_edge, bottom_edge = SHAFT
    draw.rectangle([left_edge * scale, top_edge * scale, right_edge * scale, bottom_edge * scale], fill=255)
    draw.polygon(points(HEAD), fill=255)
    glyph_mask = ImageChops.subtract(glyph_mask, arrow)
    glyph = gradient(glyph_colors(style), np.clip(((xs - 230) + (ys - 230)) / (2 * 570), 0, 1))
    glyph.putalpha(glyph_mask)

    on_flag = style not in GRADIENTS
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.alpha_composite(shadow(tile_mask, 12, 10, 0.30))
    icon.alpha_composite(tile)
    icon.alpha_composite(rim)
    icon.alpha_composite(shadow(glyph_mask, 16, 16, 0.55 if on_flag else 0.40))
    if on_flag:
        # A dark rim (a 20-point stroke, so 10 points outside) keeps the white droplet visible.
        grown = glyph_mask.filter(ImageFilter.MaxFilter(20 * scale + 1))
        outline = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        outline.putalpha(grown.point(lambda v: int(v * 0.35)))
        icon.alpha_composite(outline)
    icon.alpha_composite(glyph)
    return icon


def bundle_pngs():
    """The teal icon, as the asset catalog's PNGs: drawn 4x larger and scaled down."""
    from PIL import Image

    icon = render("teal")
    for name, pixels in PNGS:
        icon.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / name)
    print(f"wrote {len(PNGS)} PNGs to {ICONSET}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--bundle":
        bundle_pngs()
        return
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for style in list(GRADIENTS) + list(FLAGS):
        (out / f"{style}.svg").write_text(svg(style))
    print(f"wrote {len(GRADIENTS) + len(FLAGS)} SVGs to {out}")


if __name__ == "__main__":
    main()
