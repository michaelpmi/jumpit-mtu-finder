#!/usr/bin/env python3
"""Turn a full-bleed square source PNG into a native macOS app-icon master:
trim the artwork to its colored body, round the corners (Big Sur squircle),
add transparent margins + a soft shadow, and emit a 1024 master PNG."""
import sys
from PIL import Image, ImageDraw, ImageFilter

src_path = sys.argv[1] if len(sys.argv) > 1 else "higgsfield_icon.png"
out_path = sys.argv[2] if len(sys.argv) > 2 else "icon_master_1024.png"

im = Image.open(src_path).convert("RGBA")
W, H = im.size
px = im.load()

# 1) bounding box of the non-background body (exclude white + light-gray shadow)
def is_bg(r, g, b):
    return r > 225 and g > 225 and b > 225

minx, miny, maxx, maxy = W, H, 0, 0
step = 4
for y in range(0, H, step):
    for x in range(0, W, step):
        r, g, b, a = px[x, y]
        if a > 10 and not is_bg(r, g, b):
            if x < minx: minx = x
            if y < miny: miny = y
            if x > maxx: maxx = x
            if y > maxy: maxy = y

# square it up around the detected body
cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
side = max(maxx - minx, maxy - miny)
half = side / 2
l, t = int(cx - half), int(cy - half)
body = im.crop((l, t, int(cx + half), int(cy + half)))

S = 824                      # icon body size on a 1024 canvas (Big Sur proportion)
body = body.resize((S, S), Image.LANCZOS)

# 2) rounded-corner (squircle-ish) alpha mask to make the corners transparent
SS = 4                        # supersample for clean antialiasing
mask = Image.new("L", (S * SS, S * SS), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    [0, 0, S * SS - 1, S * SS - 1], radius=int(0.2237 * S * SS), fill=255)
mask = mask.resize((S, S), Image.LANCZOS)
body.putalpha(mask)

# 3) compose onto a 1024 transparent canvas with a soft drop shadow
C = 1024
canvas = Image.new("RGBA", (C, C), (0, 0, 0, 0))
off = (C - S) // 2

shadow = Image.new("RGBA", (C, C), (0, 0, 0, 0))
sh_mask = Image.new("L", (C, C), 0)
ImageDraw.Draw(sh_mask).rounded_rectangle(
    [off, off + 16, off + S, off + S + 16], radius=int(0.2237 * S), fill=90)
shadow.putalpha(sh_mask.filter(ImageFilter.GaussianBlur(22)))
canvas = Image.alpha_composite(canvas, shadow)

canvas.alpha_composite(body, (off, off))
canvas.save(out_path)
print(f"wrote {out_path} ({C}x{C}) from body {side}px @ ({l},{t})")
