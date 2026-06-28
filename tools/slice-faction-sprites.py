#!/usr/bin/env python3
from pathlib import Path
from shutil import copyfile

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
GENERATED_DIR = ROOT / "assets" / "generated" / "avw_reskin"
OUT_DIR = ROOT / "assets" / "units"
PORTRAIT_DIR = ROOT / "assets" / "portraits"
UI_DIR = ROOT / "assets" / "ui"
CELL = 48
SHEET = CELL * 4
UNIT_KINDS = ("villager", "swordsman", "archer", "lancer", "siege")

SOURCES_BY_FACTION = {
    "ansem": {
        "portrait": GENERATED_DIR / "portrait_ansem.png",
        **{kind: GENERATED_DIR / f"ansem_{kind}.png" for kind in UNIT_KINDS},
    },
    "wynn": {
        "portrait": GENERATED_DIR / "portrait_wynn.png",
        **{kind: GENERATED_DIR / f"wynn_{kind}.png" for kind in UNIT_KINDS},
    },
}


def require_png(path: Path, size: tuple[int, int]) -> None:
    if not path.exists():
        raise FileNotFoundError(path)
    with Image.open(path) as img:
        if img.size != size:
            raise RuntimeError(f"{path} should be {size[0]}x{size[1]}, got {img.size}")
        if "A" not in img.convert("RGBA").getbands():
            raise RuntimeError(f"{path} should include alpha")
        if img.convert("RGBA").getchannel("A").getbbox() is None:
            raise RuntimeError(f"{path} has no visible pixels")


def normalize_sheet(source: Path) -> Image.Image:
    src = Image.open(source).convert("RGBA")
    sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
    for row in range(4):
        for col in range(4):
            x0 = col * CELL
            y0 = row * CELL
            cell = src.crop((x0, y0, x0 + CELL, y0 + CELL))
            bbox = cell.getchannel("A").getbbox()
            if bbox is None:
                continue
            pose = cell.crop(bbox)
            scale = min(44 / pose.width, 46 / pose.height)
            size = (
                max(1, round(pose.width * scale)),
                max(1, round(pose.height * scale)),
            )
            pose = pose.resize(size, Image.Resampling.NEAREST)
            px = x0 + (CELL - pose.width) // 2
            py = y0 + CELL - pose.height - 1
            sheet.alpha_composite(pose, (px, py))
    return sheet


def install_assets() -> list[Path]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PORTRAIT_DIR.mkdir(parents=True, exist_ok=True)
    UI_DIR.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []

    for faction, sources in SOURCES_BY_FACTION.items():
        portrait = sources["portrait"]
        require_png(portrait, (256, 256))
        portrait_out = PORTRAIT_DIR / f"faction_portrait_{faction}.png"
        icon_out = UI_DIR / f"faction_icon_{faction}.png"
        copyfile(portrait, portrait_out)
        copyfile(portrait, icon_out)
        written.extend([portrait_out, icon_out])

        for kind in UNIT_KINDS:
            source = sources[kind]
            require_png(source, (SHEET, SHEET))
            out = OUT_DIR / f"{faction}_{kind}_walk.png"
            normalize_sheet(source).save(out)
            written.append(out)

    return written


def main() -> int:
    for path in install_assets():
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
