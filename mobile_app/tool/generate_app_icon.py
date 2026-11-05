import math
import os
from PIL import Image, ImageDraw, ImageFilter

def create_app_icon(output_path="assets/icon/app_icon.png"):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    size = 1024
    img = Image.new("RGBA", (size, size), (10, 15, 29, 255)) # Dark slate base
    draw = ImageDraw.Draw(img)

    # 1. Subtle radial glow in background
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    cx, cy = size // 2, size // 2
    for r in range(400, 50, -10):
        alpha = int(25 * (1.0 - (r / 400.0)))
        glow_draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(0, 242, 254, alpha)
        )
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    # 2. Protective Hexagonal Outer Shield
    def get_hex_points(center_x, center_y, radius):
        points = []
        for i in range(6):
            angle = math.radians(60 * i - 30)
            px = center_x + radius * math.cos(angle)
            py = center_y + radius * math.sin(angle)
            points.append((px, py))
        return points

    outer_hex = get_hex_points(cx, cy, 420)
    inner_hex = get_hex_points(cx, cy, 390)

    # Shield fill
    draw.polygon(outer_hex, fill=(15, 23, 42, 240))
    # Shield border neon cyan
    draw.polygon(outer_hex, outline=(0, 242, 254, 255), width=8)
    draw.polygon(inner_hex, outline=(30, 41, 59, 255), width=4)

    # 3. High-Tech Perspective Roadway
    # Vanishing point
    vx, vy = cx, cy - 60
    # Road edges expanding downwards
    road_poly = [
        (vx - 40, vy),
        (vx + 40, vy),
        (cx + 260, cy + 320),
        (cx - 260, cy + 320),
    ]
    draw.polygon(road_poly, fill=(24, 32, 47, 255))
    draw.line([(vx - 40, vy), (cx - 260, cy + 320)], fill=(0, 242, 254, 180), width=6)
    draw.line([(vx + 40, vy), (cx + 260, cy + 320)], fill=(0, 242, 254, 180), width=6)

    # Dashed center lane markings in road perspective
    lane_segments = [
        (vy + 20, vy + 50, 4),
        (vy + 80, vy + 130, 8),
        (vy + 170, vy + 240, 14),
        (vy + 280, vy + 320, 20),
    ]
    for top_y, bot_y, w in lane_segments:
        draw.line([(cx, top_y), (cx, bot_y)], fill=(245, 158, 11, 255), width=w)

    # 4. Neon AI Damage Detection Target (Corner Brackets & Reticle)
    # Target Box on road
    tx, ty = cx, cy + 140
    tw, th = 200, 100
    bx1, by1 = tx - tw // 2, ty - th // 2
    bx2, by2 = tx + tw // 2, ty + th // 2

    # Corner brackets (Neon Amber / Orange)
    bracket_color = (245, 158, 11, 255)
    b_len = 35
    b_width = 8

    # Top-Left
    draw.line([(bx1, by1 + b_len), (bx1, by1)], fill=bracket_color, width=b_width)
    draw.line([(bx1, by1), (bx1 + b_len, by1)], fill=bracket_color, width=b_width)
    # Top-Right
    draw.line([(bx2 - b_len, by1), (bx2, by1)], fill=bracket_color, width=b_width)
    draw.line([(bx2, by1), (bx2, by1 + b_len)], fill=bracket_color, width=b_width)
    # Bottom-Left
    draw.line([(bx1, by2 - b_len), (bx1, by2)], fill=bracket_color, width=b_width)
    draw.line([(bx1, by2), (bx1 + b_len, by2)], fill=bracket_color, width=b_width)
    # Bottom-Right
    draw.line([(bx2 - b_len, by2), (bx2, by2)], fill=bracket_color, width=b_width)
    draw.line([(bx2, by2), (bx2, by2 - b_len)], fill=bracket_color, width=b_width)

    # Crosshair in target center
    draw.line([(tx - 25, ty), (tx + 25, ty)], fill=(239, 68, 68, 240), width=4)
    draw.line([(tx, ty - 25), (tx, ty + 25)], fill=(239, 68, 68, 240), width=4)
    draw.ellipse([tx - 10, ty - 10, tx + 10, ty + 10], outline=(239, 68, 68, 240), width=3)

    # 5. Glowing AI Radar Arc / Scan Waves
    scan_arc_box = [cx - 280, cy - 280, cx + 280, cy + 280]
    draw.arc(scan_arc_box, start=200, end=340, fill=(0, 242, 254, 200), width=5)
    scan_arc_box2 = [cx - 320, cy - 320, cx + 320, cy + 320]
    draw.arc(scan_arc_box2, start=210, end=330, fill=(0, 242, 254, 100), width=3)

    img.save(output_path, "PNG")
    print(f"Generated app icon saved to: {output_path}")

if __name__ == "__main__":
    create_app_icon()
