"""DROP's app icon: a teal droplet with an arrow cut out of it, on a light rounded tile.

Canvas 1024 x 1024, on Apple's macOS icon grid (the tile is 824 x 824 with a 185 corner radius).
The droplet is a circle with a point on top; the arrow points down, through the drop.

Usage:
  python3 design/app-icon/icon.py              writes design/app-icon/drop-icon.svg
  python3 design/app-icon/icon.py ICONSET      also writes the PNGs into ICONSET (needs Pillow)

Rebuild the bundle's icon with
  python3 design/app-icon/icon.py App/Resources/Assets.xcassets/AppIcon.appiconset
"""
import math
import pathlib
import sys

SIZE = 1024
TILE = (100, 100, 824, 824, 185)  # x, y, width, height, corner radius
TILE_COLORS = ("#f4fbfa", "#d3ece9")  # top, bottom
DROP_COLORS = ("#2cc4b5", "#0a6f68")  # top, bottom

CENTER = (512, 600)
RADIUS = 230
APEX = (512, 190)
SHAFT = (472, 410, 552, 600)  # left, top, right, bottom
HEAD = [(388, 580), (636, 580), (512, 724)]

# (filename, pixels) for every image the asset catalog lists.
PNGS = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]


def tangent_points():
    """Where the straight sides of the droplet touch the circle."""
    distance = CENTER[1] - APEX[1]
    angle = math.asin(RADIUS / distance)  # between the axis and each side, at the apex
    beta = math.pi / 2 - angle  # between the axis and the radius to the tangent point
    dx, dy = RADIUS * math.sin(beta), RADIUS * math.cos(beta)
    return (CENTER[0] + dx, CENTER[1] - dy), (CENTER[0] - dx, CENTER[1] - dy)


def svg():
    right, left = tangent_points()
    x, y, w, h, r = TILE
    left_edge, top, right_edge, bottom = SHAFT
    arrow = (f"M{left_edge},{top} H{right_edge} V{HEAD[0][1]} H{HEAD[1][0]} L{HEAD[2][0]},{HEAD[2][1]} "
             f"L{HEAD[0][0]},{HEAD[0][1]} H{left_edge} Z")
    drop = (f"M{APEX[0]},{APEX[1]} L{right[0]:.1f},{right[1]:.1f} "
            f"A{RADIUS},{RADIUS} 0 1,1 {left[0]:.1f},{left[1]:.1f} Z")
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{TILE_COLORS[0]}"/><stop offset="1" stop-color="{TILE_COLORS[1]}"/>
    </linearGradient>
    <linearGradient id="drop" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{DROP_COLORS[0]}"/><stop offset="1" stop-color="{DROP_COLORS[1]}"/>
    </linearGradient>
  </defs>
  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="url(#tile)"/>
  <path d="{drop} {arrow}" fill="url(#drop)" fill-rule="evenodd"/>
</svg>
"""


def pngs(out_dir):
    from PIL import Image, ImageChops, ImageDraw

    scale = 4
    big = SIZE * scale

    def gradient(colors, mask):
        top = Image.new("RGBA", (big, big), colors[0])
        bottom = Image.new("RGBA", (big, big), colors[1])
        ramp = Image.linear_gradient("L").resize((big, big))
        layer = Image.composite(bottom, top, ramp)
        layer.putalpha(mask)
        return layer

    def scaled(points):
        return [(px * scale, py * scale) for px, py in points]

    x, y, w, h, r = TILE
    tile_mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(tile_mask).rounded_rectangle(
        (x * scale, y * scale, (x + w) * scale, (y + h) * scale), radius=r * scale, fill=255
    )

    right, left = tangent_points()
    drop_mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(drop_mask)
    draw.polygon(scaled([APEX, right, CENTER, left]), fill=255)
    cx, cy = CENTER
    draw.ellipse(((cx - RADIUS) * scale, (cy - RADIUS) * scale, (cx + RADIUS) * scale, (cy + RADIUS) * scale),
                 fill=255)
    arrow_mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(arrow_mask)
    left_edge, top, right_edge, bottom = SHAFT
    draw.rectangle((left_edge * scale, top * scale, right_edge * scale, bottom * scale), fill=255)
    draw.polygon(scaled(HEAD), fill=255)
    drop_mask = ImageChops.subtract(drop_mask, arrow_mask)

    icon = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    icon.alpha_composite(gradient(TILE_COLORS, tile_mask))
    icon.alpha_composite(gradient(DROP_COLORS, drop_mask))
    for name, pixels in PNGS:
        icon.resize((pixels, pixels), Image.LANCZOS).save(out_dir / name)


def main():
    source = pathlib.Path(__file__).with_name("drop-icon.svg")
    source.write_text(svg())
    print(f"wrote {source}")
    if len(sys.argv) > 1:
        iconset = pathlib.Path(sys.argv[1])
        iconset.mkdir(parents=True, exist_ok=True)
        pngs(iconset)
        print(f"wrote {len(PNGS)} PNGs to {iconset}")


if __name__ == "__main__":
    main()
