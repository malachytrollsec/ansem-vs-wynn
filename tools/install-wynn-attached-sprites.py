#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
WYNN_SOURCE_DIR = Path(
    "/tmp/codex-remote-attachments/019ee8b3-1df6-7373-a50d-5223ab08a280/"
    "46230104-e048-4d4a-92a8-429def7fb3fd"
)
NEW_SOURCE_DIR = Path(
    "/tmp/codex-remote-attachments/019ee8b3-1df6-7373-a50d-5223ab08a280/"
    "dd5d82e5-d3ec-4b66-adec-f9c982ab418a"
)
LATEST_SOURCE_DIR = Path(
    "/tmp/codex-remote-attachments/019ee8b3-1df6-7373-a50d-5223ab08a280/"
    "cf69723b-2395-42cd-9dab-1ad2d1e50c21"
)
GENERATED_DIR = ROOT / "assets" / "generated" / "avw_reskin"
UNIT_DIR = ROOT / "assets" / "units"
CELL = 48
SHEET = CELL * 4

SPRITE_SOURCES = {
    ("wynn", "villager"): WYNN_SOURCE_DIR / "4-Photo-4.jpg",
    ("wynn", "swordsman"): WYNN_SOURCE_DIR / "5-Photo-5.jpg",
    ("wynn", "lancer"): LATEST_SOURCE_DIR / "1-Photo-1.jpg",
    ("wynn", "siege"): WYNN_SOURCE_DIR / "2-Photo-2.jpg",
    ("wynn", "archer"): NEW_SOURCE_DIR / "1-Photo-1.jpg",
    ("ansem", "villager"): NEW_SOURCE_DIR / "2-Photo-2.jpg",
    ("ansem", "swordsman"): NEW_SOURCE_DIR / "5-Photo-5.jpg",
    ("ansem", "archer"): LATEST_SOURCE_DIR / "2-Photo-2.jpg",
    ("ansem", "lancer"): NEW_SOURCE_DIR / "3-Photo-3.jpg",
    ("ansem", "siege"): NEW_SOURCE_DIR / "4-Photo-4.jpg",
}
ALT_SOURCES = {
    ("wynn", "siege_banner_alt"): WYNN_SOURCE_DIR / "1-Photo-1.jpg",
}

# Source grids are eight directional poses: four across, two down.
# Game sheets are four facing rows by four animation columns.
POSE_ROWS = {
    "front": [(0, 0), (0, 1), (1, 3), (0, 0)],
    "side": [(0, 2), (1, 2), (0, 2), (1, 2)],
    "back": [(1, 0), (0, 3), (1, 1), (1, 0)],
    "back_diag": [(0, 3), (1, 1), (0, 3), (1, 1)],
}
ROW_ORDER = ("front", "side", "back", "back_diag")


def foreground_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    rgba = img.convert("RGBA")
    pix = rgba.load()
    w, h = rgba.size
    x0 = w
    y0 = h
    x1 = -1
    y1 = -1
    for y in range(h):
        for x in range(w):
            r, g, b, _ = pix[x, y]
            # JPG sheets have a white paper background. Keep bright green glows
            # and black armor, but drop paper and compression fuzz.
            if r > 236 and g > 236 and b > 236:
                continue
            x0 = min(x0, x)
            y0 = min(y0, y)
            x1 = max(x1, x + 1)
            y1 = max(y1, y + 1)
    if x1 < 0:
        return None
    pad = 3
    return (
        max(0, x0 - pad),
        max(0, y0 - pad),
        min(w, x1 + pad),
        min(h, y1 + pad),
    )


def remove_white_background(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    pix = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if r > 236 and g > 236 and b > 236:
                pix[x, y] = (r, g, b, 0)
            elif r > 224 and g > 224 and b > 224:
                pix[x, y] = (r, g, b, min(a, 96))
    return rgba


def extract_pose(source: Image.Image, grid_pos: tuple[int, int]) -> Image.Image:
    row, col = grid_pos
    cell_w = source.width // 4
    cell_h = source.height // 2
    crop = source.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
    bbox = foreground_bbox(crop)
    if bbox is None:
        raise RuntimeError(f"empty pose at row {row}, col {col}")
    return remove_white_background(crop.crop(bbox))


def fit_pose(pose: Image.Image, kind: str) -> Image.Image:
    bbox = pose.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("pose lost all alpha")
    pose = pose.crop(bbox)
    max_w = 47 if kind in {"siege", "lancer"} else 45
    max_h = 47 if kind in {"siege", "lancer"} else 46
    scale = min(max_w / pose.width, max_h / pose.height)
    size = (max(1, round(pose.width * scale)), max(1, round(pose.height * scale)))
    return pose.resize(size, Image.Resampling.LANCZOS)


def build_sheet(source_path: Path, kind: str) -> Image.Image:
    source = Image.open(source_path).convert("RGBA")
    sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
    for row_index, row_name in enumerate(ROW_ORDER):
        for col_index, grid_pos in enumerate(POSE_ROWS[row_name]):
            pose = fit_pose(extract_pose(source, grid_pos), kind)
            x = col_index * CELL + (CELL - pose.width) // 2
            y = row_index * CELL + CELL - pose.height - 1
            sheet.alpha_composite(pose, (x, y))
    return sheet


def make_contact_sheet(paths: list[Path], out: Path) -> None:
    scale = 3
    tile = SHEET * scale
    contact = Image.new("RGBA", (tile * len(paths), tile + 24), (10, 14, 16, 255))
    draw = ImageDraw.Draw(contact)
    for i, path in enumerate(paths):
        img = Image.open(path).convert("RGBA").resize((tile, tile), Image.Resampling.NEAREST)
        x = i * tile
        contact.alpha_composite(img, (x, 0))
        draw.text((x + 8, tile + 6), path.stem.replace("_", " "), fill=(198, 255, 95, 255))
    contact.save(out)


def install() -> list[Path]:
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    UNIT_DIR.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    for (faction, kind), source in SPRITE_SOURCES.items():
        if not source.exists():
            raise FileNotFoundError(source)
        sheet = build_sheet(source, kind)
        generated_out = GENERATED_DIR / f"{faction}_{kind}.png"
        unit_out = UNIT_DIR / f"{faction}_{kind}_walk.png"
        sheet.save(generated_out)
        sheet.save(unit_out)
        written.extend([generated_out, unit_out])

    for (faction, label), source in ALT_SOURCES.items():
        if source.exists():
            alt = build_sheet(source, "siege")
            alt_out = GENERATED_DIR / f"{faction}_{label}.png"
            alt.save(alt_out)
            written.append(alt_out)

    live_units = [
        UNIT_DIR / f"{faction}_{kind}_walk.png"
        for faction, kinds in {
            "ansem": ("villager", "swordsman", "archer", "lancer", "siege"),
            "wynn": ("villager", "swordsman", "archer", "lancer", "siege"),
        }.items()
        for kind in kinds
        if (UNIT_DIR / f"{faction}_{kind}_walk.png").exists()
    ]
    contact = GENERATED_DIR / "attached_units_contact_sheet.png"
    make_contact_sheet(live_units, contact)
    written.append(contact)
    return written


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.parse_args()
    for path in install():
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
