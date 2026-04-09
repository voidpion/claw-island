#!/usr/bin/env python3
"""Generate macOS app icon from the MascotCanvas pixel data."""
from PIL import Image, ImageDraw

# Frame 0 pixel data (same as MascotCanvas.frames[0] in NotchContentView.swift)
# 18 cols × 6 rows, bit17 = leftmost column
FRAMES = [
    [0x7FF8, 0x6FD8, 0x1FFFE, 0x7FF8, 0x2850, 0x0000],
]
COLS = 18
ROWS = 6

def render_frame(frame_idx=0, img_size=512):
    """Render pixel art at given size on transparent background."""
    data = FRAMES[frame_idx]

    # Calculate pixel block size with padding
    margin = img_size * 0.15
    draw_area = img_size - margin * 2
    pw = draw_area / COLS
    ph = draw_area / ROWS

    img = Image.new("RGBA", (img_size, img_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Center the sprite
    sprite_w = COLS * pw
    sprite_h = ROWS * ph
    ox = (img_size - sprite_w) / 2
    oy = (img_size - sprite_h) / 2

    for row, mask in enumerate(data):
        for col in range(COLS):
            if (mask >> (17 - col)) & 1:
                x0 = ox + col * pw
                y0 = oy + row * ph
                draw.rectangle([x0, y0, x0 + pw, y0 + ph], fill=(255, 255, 255, 255))

    return img

def make_icon(size=512):
    """Create a macOS-style rounded rect icon with the mascot."""
    radius = size * 0.2237  # macOS icon corner radius

    # Background: dark rounded rectangle
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)

    bg_draw = ImageDraw.Draw(bg)
    bg_draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=(24, 24, 28, 255))

    # Render mascot and composite
    mascot = render_frame(0, size)
    bg.paste(mascot, mask=mascot)

    # Apply rounded corners mask
    final = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    final.paste(bg, mask=mask)

    return final

# Generate all required sizes
import os
base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(base, "ClawIsland", "Resources", "Assets.xcassets", "AppIcon.appiconset")

sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes:
    icon = make_icon(s)
    # 1024 is for App Store, others are standard
    if s == 1024:
        icon.save(os.path.join(out, f"icon_{s}.png"))
        print(f"  icon_{s}.png")
    else:
        icon.save(os.path.join(out, f"icon_{s}.png"))
        print(f"  icon_{s}.png")

# Update Contents.json
import json
contents = {
    "images": [
        {"filename": "icon_16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
        {"filename": "icon_32.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
        {"filename": "icon_32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
        {"filename": "icon_64.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
        {"filename": "icon_128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
        {"filename": "icon_256.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
        {"filename": "icon_256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
        {"filename": "icon_512.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
        {"filename": "icon_512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
        {"filename": "icon_1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
    ],
    "info": {"author": "xcode", "version": 1}
}

with open(os.path.join(out, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)

print("\nDone. All icons generated.")
