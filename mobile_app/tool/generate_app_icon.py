import math
import os
from PIL import Image, ImageDraw, ImageFilter

def create_app_icon(output_path="assets/icon/app_icon.png"):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    size = 1024
    
    # 1. Base: Modern charcoal backdrop (#1A1D24)
    img = Image.new("RGBA", (size, size), (26, 29, 36, 255))
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2

    # 2. Subtle radial glow behind the emblem
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    for r in range(420, 40, -12):
        alpha = int(28 * (1.0 - (r / 420.0)))
        glow_draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(0, 242, 254, alpha)
        )
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)

    # 3. Outer Protective Shield / Hexagon
    def get_hex_points(center_x, center_y, radius):
        points = []
        for i in range(6):
            angle = math.radians(60 * i - 30)
            px = center_x + radius * math.cos(angle)
            py = center_y + radius * math.sin(angle)
            points.append((px, py))
        return points

    outer_hex = get_hex_points(cx, cy, 440)
    inner_hex = get_hex_points(cx, cy, 410)

    # Shield body (rich carbon)
    draw.polygon(outer_hex, fill=(32, 36, 46, 255))
    # Border: Crisp cyber cyan
    draw.polygon(outer_hex, outline=(0, 242, 254, 255), width=10)
    draw.polygon(inner_hex, outline=(48, 54, 69, 255), width=4)

    # 4. Crisp Perspective Roadway Gradient
    vx, vy = cx, cy - 80
    road_poly = [
        (vx - 50, vy),
        (vx + 50, vy),
        (cx + 280, cy + 340),
        (cx - 280, cy + 340),
    ]
    draw.polygon(road_poly, fill=(18, 21, 28, 255))

    # Flanking high-visibility Hazard Warning Yellow (#FFC107) edge curbs
    draw.line([(vx - 50, vy), (cx - 280, cy + 340)], fill=(255, 193, 7, 255), width=12)
    draw.line([(vx + 50, vy), (cx + 280, cy + 340)], fill=(255, 193, 7, 255), width=12)

    # Center lane divider dashes (Perspective road markings)
    lane_dashes = [
        (vy + 20, vy + 55, 6),
        (vy + 90, vy + 145, 12),
        (vy + 185, vy + 260, 18),
        (vy + 300, vy + 340, 24),
    ]
    for top_y, bot_y, w in lane_dashes:
        draw.line([(cx, top_y), (cx, bot_y)], fill=(255, 255, 255, 240), width=w)

    # 5. Cyber Cyan Scan Reticle & Radar Arcs
    scan_arc_1 = [cx - 310, cy - 310, cx + 310, cy + 310]
    draw.arc(scan_arc_1, start=205, end=335, fill=(0, 242, 254, 220), width=6)
    scan_arc_2 = [cx - 360, cy - 360, cx + 360, cy + 360]
    draw.arc(scan_arc_2, start=215, end=325, fill=(0, 242, 254, 120), width=4)

    # 6. Prominent Road Damage Target Reticle (Hazard Warning Yellow + Cyber Cyan)
    tx, ty = cx, cy + 150
    tw, th = 220, 110
    bx1, by1 = tx - tw // 2, ty - th // 2
    bx2, by2 = tx + tw // 2, ty + th // 2

    # High-vis corner brackets (#FFC107 Yellow)
    bracket_color = (255, 193, 7, 255)
    b_len = 40
    b_width = 10

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

    # Cyan Target Crosshair
    draw.line([(tx - 30, ty), (tx + 30, ty)], fill=(0, 242, 254, 255), width=5)
    draw.line([(tx, ty - 30), (tx, ty + 30)], fill=(0, 242, 254, 255), width=5)
    draw.ellipse([tx - 12, ty - 12, tx + 12, ty + 12], outline=(0, 242, 254, 255), width=4)

    # Semi-transparent red warning target fill
    target_fill = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    target_draw = ImageDraw.Draw(target_fill)
    target_draw.rectangle([bx1, by1, bx2, by2], fill=(239, 68, 68, 55))
    img = Image.alpha_composite(img, target_fill)

    img.save(output_path, "PNG")
    print(f"Professional high-contrast ADAS app icon saved to: {output_path}")

if __name__ == "__main__":
    create_app_icon()
