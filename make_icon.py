#!/usr/bin/env python3
"""Generate Masker macOS app icon using Pillow"""
import struct
import zlib
import os

OUT_DIR = os.path.join(os.path.dirname(__file__), "masker-icon")
os.makedirs(OUT_DIR, exist_ok=True)

# ── PNG writer ──

def write_png(width, height, pixels, path):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    raw = b""
    for y in range(height):
        raw += b"\x00"
        for x in range(width):
            p = pixels[y * width + x]
            if len(p) != 4:
                raise ValueError(f"Bad pixel at ({x},{y}): {p}")
            raw += struct.pack("BBBB", *p)

    idat = zlib.compress(raw)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", idat)
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)

def hex_color(h):
    h = h.lstrip("#")
    if len(h) == 6:
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16))

def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(4))

# ── Icon generation ──

def generate_icon(size):
    w, h = size, size
    cx, cy = w / 2, h / 2

    bg_top = hex_color("#1a1a2e")
    bg_bot = hex_color("#16213e")
    accent = hex_color("#0f9b8e")
    accent_light = hex_color("#34d399")
    shield_outer = hex_color("#1e3a5f")
    shield_inner = hex_color("#2563eb")
    white = (255, 255, 255, 255)
    transparent = (0, 0, 0, 0)

    pixels = []

    for py in range(h):
        t = py / h
        bg = lerp_color(bg_top, bg_bot, t)

        for px in range(w):
            dx = (px - cx) / (w / 2)
            dy = (py - cy) / (h / 2)

            # Background rounded rect
            rx, ry = 0.78, 0.78
            corner = max(abs(dx) - rx, abs(dy) - ry, 0.0)

            if corner < 0.05:
                # Inside the icon area
                color = list(bg[:3])  # RGB only
                # Shield
                sx, sy = dx, dy + 0.1
                shield_h = 0.55
                shield_w = 0.45

                in_shield = False
                top_curve = (sx*sx)/(shield_w*shield_w) + ((sy+0.05)**2)/(0.18**2)
                if top_curve <= 1.0 and sy < -0.05:
                    in_shield = True
                if abs(sx) < shield_w * 0.85 and -0.05 < sy < shield_h:
                    in_shield = True
                if abs(sx) < shield_w * 0.4 and shield_h <= sy < shield_h + 0.12:
                    tip_t = (sy - shield_h) / 0.12
                    if abs(sx) < shield_w * 0.85 * (1.0 - tip_t):
                        in_shield = True

                if in_shield:
                    sc = lerp_color(shield_inner, shield_outer, (sy+0.25)/(shield_h+0.25))
                    for i in range(3):
                        color[i] = sc[i]

                    # Lock hole
                    hd = ((sx)**2 + (sy+0.05)**2)**0.5
                    if hd < 0.12:
                        ac = lerp_color(accent_light, accent, hd/0.12)
                        for i in range(3):
                            color[i] = ac[i]

                    # Sparkles
                    for sx2, sy2 in [(0.3,-0.3), (-0.25,-0.35), (0.35,0.15), (-0.32,0.3)]:
                        sd = ((sx-sx2)**2 + (sy-sy2)**2)**0.5
                        if sd < 0.04:
                            b = 1.0 - sd/0.04
                            for i in range(3):
                                color[i] = int(lerp_color((color[i],color[i],color[i],255), (255,255,255,255), b*0.6)[0])

                # Text lines
                for li, ly in enumerate([-0.5, 0.1, 0.2, 0.35]):
                    if abs(sy - ly) < 0.015:
                        lw = 0.3 + li * 0.1
                        ls, le = -lw, lw
                        if li == 1: ls, le = -0.35, 0.25
                        elif li == 2: ls, le = -0.25, 0.35
                        elif li == 3: ls, le = -0.15, 0.2
                        if ls <= sx <= le:
                            for i in range(3):
                                color[i] = int(lerp_color((color[i],color[i],color[i],255), white, 0.3)[0])

                color.append(255)  # alpha
                pixels.append(tuple(color))

            elif corner < 0.15:
                # Anti-alias edge
                aa = int(lerp_color(bg, transparent, (corner-0.05)/0.1)[3])
                pixels.append((bg[0], bg[1], bg[2], aa))

            else:
                # Outside - fully transparent
                pixels.append(transparent)

    return pixels


def main():
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    print("Generating 1024x1024 master icon...")
    master_pixels = generate_icon(1024)
    print(f"Done. Pixel count: {len(master_pixels)}")

    # Verify pixels
    bad = [(i, p) for i, p in enumerate(master_pixels) if len(p) != 4]
    if bad:
        print(f"ERROR: {len(bad)} bad pixels found")
        for i, p in bad[:5]:
            y, x = divmod(i, 1024)
            print(f"  Pixel ({x},{y}): {p}")
        return

    print("Writing icon files...")
    for name, size in sizes.items():
        if size == 1024:
            pixels = master_pixels
        else:
            scale = 1024 / size
            pixels = []
            for py in range(size):
                for px in range(size):
                    sx = int(px * scale)
                    sy = int(py * scale)
                    pixels.append(master_pixels[sy * 1024 + sx])

        path = os.path.join(OUT_DIR, name)
        write_png(size, size, pixels, path)
        print(f"  {name} ({size}x{size})")

    print(f"\nAll icons in {OUT_DIR}/")


if __name__ == "__main__":
    main()
