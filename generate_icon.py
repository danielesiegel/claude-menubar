#!/usr/bin/env python3
"""Generate ClaudeMenuBar app icon with Claude orange theme"""

from PIL import Image, ImageDraw
import os
import subprocess

# Claude orange color
CLAUDE_ORANGE = (217, 119, 87)  # #D97757
WHITE = (255, 255, 255)

# Icon sizes needed for macOS app icon
SIZES = [16, 32, 64, 128, 256, 512, 1024]

def draw_brain_icon(draw, size, color):
    """Draw a simplified brain icon"""
    # Scale factor
    s = size / 100.0
    cx, cy = size / 2, size / 2

    # Brain outline - simplified stylized brain
    # Main brain mass (two hemispheres)
    padding = int(20 * s)
    brain_width = size - (padding * 2)
    brain_height = int(brain_width * 0.85)
    top_y = cy - brain_height // 2 + int(5 * s)

    # Left hemisphere
    left_x = padding
    draw.ellipse([
        left_x, top_y,
        cx + int(5 * s), top_y + brain_height
    ], fill=color)

    # Right hemisphere
    draw.ellipse([
        cx - int(5 * s), top_y,
        size - padding, top_y + brain_height
    ], fill=color)

    # Brain stem
    stem_width = int(12 * s)
    stem_height = int(15 * s)
    draw.ellipse([
        cx - stem_width // 2, top_y + brain_height - int(10 * s),
        cx + stem_width // 2, top_y + brain_height + stem_height
    ], fill=color)

    # Brain folds/sulci (decorative lines) - draw as gaps
    line_color = CLAUDE_ORANGE
    line_width = max(1, int(2 * s))

    # Central fissure
    draw.line([
        (cx, top_y + int(10 * s)),
        (cx, top_y + brain_height - int(15 * s))
    ], fill=line_color, width=line_width)

    # Left hemisphere curves
    for i, offset in enumerate([0.25, 0.5, 0.7]):
        y_pos = top_y + int(brain_height * offset)
        draw.arc([
            left_x + int(5 * s), y_pos - int(10 * s),
            cx - int(5 * s), y_pos + int(10 * s)
        ], start=0, end=180, fill=line_color, width=line_width)

    # Right hemisphere curves
    for i, offset in enumerate([0.25, 0.5, 0.7]):
        y_pos = top_y + int(brain_height * offset)
        draw.arc([
            cx + int(5 * s), y_pos - int(10 * s),
            size - padding - int(5 * s), y_pos + int(10 * s)
        ], fill=line_color, width=line_width, start=0, end=180)

def create_icon(size, output_path):
    """Create a single icon at the specified size"""
    # Create image with orange background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Draw rounded rectangle background (orange)
    corner_radius = int(size * 0.22)  # macOS style rounded corners

    # Draw rounded rectangle
    draw.rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=corner_radius,
        fill=CLAUDE_ORANGE
    )

    # Draw brain icon in white
    draw_brain_icon(draw, size, WHITE)

    img.save(output_path, 'PNG')
    print(f"Created {size}x{size} icon: {output_path}")

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    iconset_dir = os.path.join(script_dir, 'ClaudeMenuBar', 'ClaudeMenuBar',
                               'Assets.xcassets', 'AppIcon.appiconset')

    os.makedirs(iconset_dir, exist_ok=True)

    # Generate icons at all required sizes
    for size in SIZES:
        # 1x
        output_path = os.path.join(iconset_dir, f'icon_{size}x{size}.png')
        create_icon(size, output_path)

        # 2x (for retina) - only for sizes up to 512
        if size <= 512:
            output_path_2x = os.path.join(iconset_dir, f'icon_{size}x{size}@2x.png')
            create_icon(size * 2, output_path_2x)

    # Update Contents.json
    contents = {
        "images": [
            {"filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
            {"filename": "icon_16x16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
            {"filename": "icon_32x32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
            {"filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
            {"filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
            {"filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
            {"filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512"}
        ],
        "info": {"author": "xcode", "version": 1}
    }

    import json
    contents_path = os.path.join(iconset_dir, 'Contents.json')
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    print(f"Updated {contents_path}")

    # Also create icns for the app bundle
    print("\nCreating .icns file...")
    iconset_tmp = '/tmp/ClaudeMenuBar.iconset'
    os.makedirs(iconset_tmp, exist_ok=True)

    # Copy with correct names for iconutil
    icon_mappings = [
        (16, 'icon_16x16.png'),
        (32, 'icon_16x16@2x.png'),
        (32, 'icon_32x32.png'),
        (64, 'icon_32x32@2x.png'),
        (128, 'icon_128x128.png'),
        (256, 'icon_128x128@2x.png'),
        (256, 'icon_256x256.png'),
        (512, 'icon_256x256@2x.png'),
        (512, 'icon_512x512.png'),
        (1024, 'icon_512x512@2x.png'),
    ]

    for size, name in icon_mappings:
        src = os.path.join(iconset_dir, f'icon_{size}x{size}.png')
        if size > 512:
            src = os.path.join(iconset_dir, f'icon_512x512@2x.png')
        dst = os.path.join(iconset_tmp, name)
        if os.path.exists(src):
            import shutil
            shutil.copy(src, dst)

    # Generate icns
    icns_path = os.path.join(script_dir, 'ClaudeMenuBar.icns')
    result = subprocess.run(['iconutil', '-c', 'icns', iconset_tmp, '-o', icns_path],
                          capture_output=True, text=True)
    if result.returncode == 0:
        print(f"Created {icns_path}")
    else:
        print(f"iconutil error: {result.stderr}")

    # Clean up
    import shutil
    shutil.rmtree(iconset_tmp, ignore_errors=True)

if __name__ == '__main__':
    main()
