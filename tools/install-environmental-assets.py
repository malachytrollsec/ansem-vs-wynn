#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = Path(
    "/tmp/codex-remote-attachments/019ee8b3-1df6-7373-a50d-5223ab08a280/"
    "14159fd2-4502-4e09-b9a8-96d11fb81a8d"
)
GENERATED_DIR = ROOT / "assets" / "generated" / "avw_reskin" / "environment"
STRUCTURE_DIR = ROOT / "assets" / "structures"
TERRAIN_DIR = ROOT / "assets" / "terrain"

MAPPINGS = {
    "forest_stand": {
        "source": "1-Photo-1.jpg",
        "size": 96,
        "outputs": [
            TERRAIN_DIR / "resource_oak_stand.png",
            TERRAIN_DIR / "resource_pine_stand.png",
        ],
    },
    "crypto_hut": {
        "source": "2-Photo-2.jpg",
        "size": 96,
        "outputs": [STRUCTURE_DIR / "house_asset.png"],
    },
    "watch_tower": {
        "source": "3-Photo-3.jpg",
        "size": 96,
        "outputs": [STRUCTURE_DIR / "tower_asset.png"],
    },
    "forge": {
        "source": "4-Photo-4.jpg",
        "size": 96,
        "outputs": [STRUCTURE_DIR / "forge_asset.png"],
    },
    "market_coins": {
        "source": "5-Photo-5.jpg",
        "size": 96,
        "outputs": [STRUCTURE_DIR / "market_asset.png"],
    },
}


def remove_white_background(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    pix = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pix[x, y]
            if r > 238 and g > 238 and b > 238:
                pix[x, y] = (r, g, b, 0)
            elif r > 228 and g > 228 and b > 228:
                pix[x, y] = (r, g, b, min(a, 96))
    return rgba


def subject_bbox(img: Image.Image) -> tuple[int, int, int, int]:
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
            if r > 238 and g > 238 and b > 238:
                continue
            x0 = min(x0, x)
            y0 = min(y0, y)
            x1 = max(x1, x + 1)
            y1 = max(y1, y + 1)
    if x1 < 0:
        raise RuntimeError("source image contains no foreground")
    pad = 8
    return (
        max(0, x0 - pad),
        max(0, y0 - pad),
        min(w, x1 + pad),
        min(h, y1 + pad),
    )


def build_asset(source: Path, size: int) -> Image.Image:
    src = Image.open(source).convert("RGBA")
    crop = remove_white_background(src.crop(subject_bbox(src)))
    bbox = crop.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError(f"{source} lost alpha foreground")
    crop = crop.crop(bbox)
    max_w = size - 2
    max_h = size - 2
    scale = min(max_w / crop.width, max_h / crop.height)
    resized = crop.resize(
        (max(1, round(crop.width * scale)), max(1, round(crop.height * scale))),
        Image.Resampling.NEAREST,
    )
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - resized.width) // 2
    y = size - resized.height - 1
    canvas.alpha_composite(resized, (x, y))
    return canvas


def make_contact_sheet(paths: list[Path], out: Path) -> None:
    scale = 4
    tile = 96 * scale
    contact = Image.new("RGBA", (tile * len(paths), tile + 24), (10, 14, 16, 255))
    draw = ImageDraw.Draw(contact)
    for i, path in enumerate(paths):
        img = Image.open(path).convert("RGBA").resize((tile, tile), Image.Resampling.NEAREST)
        x = i * tile
        contact.alpha_composite(img, (x, 0))
        draw.text((x + 8, tile + 6), path.stem, fill=(198, 255, 95, 255))
    contact.save(out)


def install() -> list[Path]:
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    STRUCTURE_DIR.mkdir(parents=True, exist_ok=True)
    TERRAIN_DIR.mkdir(parents=True, exist_ok=True)

    written: list[Path] = []
    previews: list[Path] = []
    for name, mapping in MAPPINGS.items():
        source = SOURCE_DIR / str(mapping["source"])
        if not source.exists():
            raise FileNotFoundError(source)
        asset = build_asset(source, int(mapping["size"]))
        generated_out = GENERATED_DIR / f"{name}.png"
        asset.save(generated_out)
        written.append(generated_out)
        previews.append(generated_out)
        for out in mapping["outputs"]:
            asset.save(out)
            written.append(out)

    contact = GENERATED_DIR / "environment_contact_sheet.png"
    make_contact_sheet(previews, contact)
    written.append(contact)
    return written


def main() -> int:
    for path in install():
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
