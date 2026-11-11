import os
from PIL import Image, ImageDraw

def generate_icon():
    size = (1024, 1024)
    # Deep Obsidian Background
    img = Image.new("RGBA", size, (11, 15, 23, 255))
    draw = ImageDraw.Draw(img)

    # 1. Subtle Outer Glow Ring / Border
    draw.rounded_rectangle([32, 32, 992, 992], radius=220, outline=(0, 240, 255, 60), width=6)
    draw.rounded_rectangle([48, 48, 976, 976], radius=210, outline=(38, 51, 69, 180), width=4)

    # 2. Road Perspective (Trapezoid converging towards vanishing point)
    # Vanishing point around (512, 380)
    vp_x, vp_y = 512, 380
    road_pts = [
        (450, vp_y),
        (574, vp_y),
        (880, 920),
        (144, 920)
    ]
    # Dark asphalt road surface
    draw.polygon(road_pts, fill=(21, 28, 40, 255), outline=(0, 240, 255, 120))

    # Road shoulder lines (Cyan pulse)
    draw.line([(450, vp_y), (144, 920)], fill=(0, 240, 255, 220), width=8)
    draw.line([(574, vp_y), (880, 920)], fill=(0, 240, 255, 220), width=8)

    # Dashed center line
    segments = [
        ((512, 430), (512, 470), 4),
        ((512, 510), (512, 570), 6),
        ((512, 620), (512, 700), 10),
        ((512, 760), (512, 870), 14),
    ]
    for p1, p2, w in segments:
        draw.line([p1, p2], fill=(255, 184, 0, 240), width=w) # Amber pulse

    # 3. AI Reticle / Scanning Target at the Horizon
    # Concentric cyan rings
    draw.ellipse([vp_x - 120, vp_y - 120, vp_x + 120, vp_y + 120], outline=(0, 240, 255, 100), width=4)
    draw.ellipse([vp_x - 80, vp_y - 80, vp_x + 80, vp_y + 80], outline=(0, 240, 255, 220), width=6)
    draw.ellipse([vp_x - 30, vp_y - 30, vp_x + 30, vp_y + 30], fill=(0, 240, 255, 255))

    # Crosshair ticks
    draw.line([(vp_x - 140, vp_y), (vp_x - 90, vp_y)], fill=(0, 240, 255, 240), width=6)
    draw.line([(vp_x + 90, vp_y), (vp_x + 140, vp_y)], fill=(0, 240, 255, 240), width=6)
    draw.line([(vp_x, vp_y - 140), (vp_x, vp_y - 90)], fill=(0, 240, 255, 240), width=6)
    draw.line([(vp_x, vp_y + 90), (vp_x, vp_y + 140)], fill=(0, 240, 255, 240), width=6)

    # 4. Save to target paths
    target_dirs = [
        "mobile_app/assets/icons",
        "mobile_app/assets/icon"
    ]
    for d in target_dirs:
        os.makedirs(d, exist_ok=True)
    
    img.save("mobile_app/assets/icons/velopath_icon.png")
    img.save("mobile_app/assets/icon/app_icon.png")
    print(f"[Icon Generated] Successfully saved 1024x1024 icons to mobile_app/assets/icons/velopath_icon.png and mobile_app/assets/icon/app_icon.png")

if __name__ == "__main__":
    generate_icon()
