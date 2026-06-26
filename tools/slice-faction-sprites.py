#!/usr/bin/env python3
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "units"
CELL = 48
SHEET = CELL * 4

SOURCES_BY_FACTION = {
    "israel": {
        "swordsman": Path("/Users/binkyfishai/Downloads/idf swordsman.png"),
        "villager": Path("/Users/binkyfishai/Downloads/idf villager.png"),
        "archer": Path("/Users/binkyfishai/Downloads/idf archer.png"),
        "siege": Path("/Users/binkyfishai/Downloads/idf siegecrawler.png"),
    },
    "palestine": {
        "swordsman": Path("/Users/binkyfishai/Downloads/pal swordsman.png"),
        "villager": Path("/Users/binkyfishai/Downloads/palestinian villlager.png"),
    },
}

DERIVED_ROLES = {
    ("israel", "lancer"): {"base": "swordsman", "overlay": "lance"},
    ("palestine", "archer"): {"base": "swordsman", "overlay": "bow"},
    ("palestine", "lancer"): {"base": "swordsman", "overlay": "lance"},
    ("palestine", "siege"): {"base": "", "overlay": "siege_cart"},
}

# Source sheets are 4 columns x 2 rows. Build a 4x4 Godot sheet where each row
# is a useful facing band and each column is a tiny walk cycle.
ROW_POSES = [
    [0, 7, 0, 7],  # facing down / camera
    [1, 2, 1, 2],  # side / forward diagonal
    [4, 5, 4, 5],  # facing up / away
    [3, 6, 3, 6],  # back diagonal / alternate side
]


def bg_candidate(pixel):
    r, g, b = pixel[:3]
    low = min(r, g, b)
    high = max(r, g, b)
    spread = high - low
    return (low >= 218 and spread <= 58) or (high >= 145 and spread <= 28)


def zero_transparent_rgb(rgba):
    pix = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = pix[x, y]
            if a <= 2:
                pix[x, y] = (0, 0, 0, 0)
    return rgba


def touches_transparent(pix, x, y, w, h):
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if nx < 0 or ny < 0 or nx >= w or ny >= h:
            return True
        if pix[nx, ny][3] <= 2:
            return True
    return False


def strip_background_fringe(rgba):
    pix = rgba.load()
    w, h = rgba.size
    for _ in range(3):
        clear = []
        for y in range(h):
            for x in range(w):
                r, g, b, a = pix[x, y]
                if a <= 2 or not touches_transparent(pix, x, y, w, h):
                    continue
                if bg_candidate((r, g, b, a)):
                    clear.append((x, y))
        if not clear:
            break
        for x, y in clear:
            pix[x, y] = (0, 0, 0, 0)
    return zero_transparent_rgb(rgba)


def resize_rgba(src, size):
    premul = src.convert("RGBA")
    pix = premul.load()
    for y in range(premul.height):
        for x in range(premul.width):
            r, g, b, a = pix[x, y]
            pix[x, y] = (r * a // 255, g * a // 255, b * a // 255, a)
    resized = premul.resize(size, Image.Resampling.LANCZOS)
    pix = resized.load()
    for y in range(resized.height):
        for x in range(resized.width):
            r, g, b, a = pix[x, y]
            if a <= 2:
                pix[x, y] = (0, 0, 0, 0)
            else:
                pix[x, y] = (
                    min(255, round(r * 255 / a)),
                    min(255, round(g * 255 / a)),
                    min(255, round(b * 255 / a)),
                    a,
                )
    return resized


def remove_small_components(rgba, min_area=8):
    pix = rgba.load()
    w, h = rgba.size
    seen = set()
    for sy in range(h):
        for sx in range(w):
            if (sx, sy) in seen or pix[sx, sy][3] <= 8:
                continue
            q = deque([(sx, sy)])
            component = []
            seen.add((sx, sy))
            while q:
                x, y = q.popleft()
                component.append((x, y))
                for ny in range(y - 1, y + 2):
                    for nx in range(x - 1, x + 2):
                        if nx < 0 or ny < 0 or nx >= w or ny >= h or (nx, ny) in seen:
                            continue
                        if pix[nx, ny][3] <= 8:
                            continue
                        seen.add((nx, ny))
                        q.append((nx, ny))
            if len(component) < min_area:
                for x, y in component:
                    pix[x, y] = (0, 0, 0, 0)
    return rgba


def transparent_cell(cell):
    rgba = cell.convert("RGBA")
    pix = rgba.load()
    w, h = rgba.size
    seen = set()
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or (x, y) in seen:
            continue
        seen.add((x, y))
        if pix[x, y][3] <= 2:
            continue
        if not bg_candidate(pix[x, y]):
            continue
        pix[x, y] = (255, 255, 255, 0)
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))

    return strip_background_fringe(rgba)


def crop_pose(src, index):
    sw, sh = src.size
    col = index % 4
    row = index // 4
    x0 = round(col * sw / 4)
    x1 = round((col + 1) * sw / 4)
    y0 = round(row * sh / 2)
    y1 = round((row + 1) * sh / 2)
    cell = transparent_cell(src.crop((x0, y0, x1, y1)))
    bbox = cell.getchannel("A").getbbox()
    if not bbox:
        raise RuntimeError(f"pose {index} has no visible pixels")
    return cell.crop(bbox)


def fit_pose(pose):
    max_w = 44
    max_h = 46
    scale = min(max_w / pose.width, max_h / pose.height)
    nw = max(1, round(pose.width * scale))
    nh = max(1, round(pose.height * scale))
    scaled = resize_rgba(pose, (nw, nh))
    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    scaled = remove_small_components(scaled)
    out.alpha_composite(scaled, ((CELL - nw) // 2, CELL - nh - 1))
    return out


def build_sheet(faction, kind, path):
    src = Image.open(path).convert("RGBA")
    poses = [fit_pose(crop_pose(src, i)) for i in range(8)]
    sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
    for row, indices in enumerate(ROW_POSES):
        for col, pose_idx in enumerate(indices):
            sheet.alpha_composite(poses[pose_idx], (col * CELL, row * CELL))
    out = OUT_DIR / f"{faction}_{kind}_walk.png"
    sheet.save(out)
    return out


def draw_overlay(sheet, overlay):
    out = sheet.copy()
    draw = ImageDraw.Draw(out, "RGBA")
    for row in range(4):
        for col in range(4):
            x = col * CELL
            y = row * CELL
            if overlay == "lance":
                draw.line((x + 14, y + 34, x + 39, y + 8), fill=(92, 56, 28, 255), width=3)
                draw.polygon([(x + 37, y + 5), (x + 45, y + 2), (x + 42, y + 13)], fill=(220, 222, 216, 255))
                draw.line((x + 37, y + 5, x + 45, y + 2), fill=(55, 50, 46, 255), width=1)
            elif overlay == "bow":
                draw.arc((x + 24, y + 11, x + 45, y + 42), 265, 95, fill=(116, 72, 34, 255), width=3)
                draw.line((x + 38, y + 13, x + 38, y + 39), fill=(224, 224, 210, 230), width=1)
            elif overlay == "siege":
                draw.rounded_rectangle((x + 5, y + 27, x + 43, y + 43), radius=3, fill=(94, 67, 38, 255), outline=(42, 31, 22, 255), width=2)
                draw.ellipse((x + 10, y + 38, x + 20, y + 48), fill=(36, 34, 33, 255), outline=(178, 165, 128, 255))
                draw.ellipse((x + 30, y + 38, x + 40, y + 48), fill=(36, 34, 33, 255), outline=(178, 165, 128, 255))
                draw.rectangle((x + 19, y + 23, x + 29, y + 31), fill=(141, 107, 52, 255), outline=(42, 31, 22, 255))
    return out


def draw_siege_cart_cell(draw, x, y, row, col):
    shade = 8 if (row + col) % 2 else 0
    wood = (98 + shade, 67 + shade, 36, 255)
    dark = (38, 31, 24, 255)
    canvas = (58, 82, 48, 255)
    red = (144, 33, 30, 255)
    white = (232, 224, 202, 255)
    draw.rounded_rectangle((x + 6, y + 23, x + 42, y + 39), radius=3, fill=wood, outline=dark, width=2)
    draw.polygon([(x + 11, y + 22), (x + 25, y + 10), (x + 38, y + 22)], fill=canvas, outline=dark)
    draw.rectangle((x + 17, y + 24, x + 34, y + 32), fill=(117, 83, 42, 255), outline=dark)
    draw.rectangle((x + 13, y + 27, x + 17, y + 34), fill=red)
    draw.rectangle((x + 17, y + 27, x + 21, y + 34), fill=white)
    draw.rectangle((x + 21, y + 27, x + 25, y + 34), fill=(30, 124, 61, 255))
    draw.line((x + 5, y + 21, x + 0, y + 18), fill=dark, width=2)
    draw.line((x + 42, y + 24, x + 48, y + 21), fill=dark, width=2)
    for wx in (12, 31):
        draw.ellipse((x + wx, y + 35, x + wx + 10, y + 45), fill=(25, 25, 24, 255), outline=(180, 165, 116, 255))
        draw.ellipse((x + wx + 3, y + 38, x + wx + 7, y + 42), fill=(86, 80, 68, 255))


def build_siege_cart_sheet():
    sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
    draw = ImageDraw.Draw(sheet, "RGBA")
    for row in range(4):
        for col in range(4):
            draw_siege_cart_cell(draw, col * CELL, row * CELL, row, col)
    return sheet


def derive_sheet(faction, kind, spec):
    out = OUT_DIR / f"{faction}_{kind}_walk.png"
    if spec["overlay"] == "siege_cart":
        build_siege_cart_sheet().save(out)
        return out

    base_path = OUT_DIR / f"{faction}_{spec['base']}_walk.png"
    if not base_path.exists():
        raise FileNotFoundError(base_path)
    sheet = Image.open(base_path).convert("RGBA")
    draw_overlay(sheet, spec["overlay"]).save(out)
    return out


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for faction, sources in SOURCES_BY_FACTION.items():
        for kind, path in sources.items():
            if not path.exists():
                raise FileNotFoundError(path)
            out = build_sheet(faction, kind, path)
            print(out.relative_to(ROOT))

    for (faction, kind), spec in DERIVED_ROLES.items():
        out = derive_sheet(faction, kind, spec)
        print(out.relative_to(ROOT))


if __name__ == "__main__":
    main()
