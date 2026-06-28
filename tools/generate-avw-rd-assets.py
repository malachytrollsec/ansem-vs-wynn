#!/usr/bin/env python3
import base64
import json
import sys
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


API_URL = "https://api.retrodiffusion.ai/v1/inferences"
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "generated" / "avw_reskin"

NEGATIVE = (
    "photorealistic, text, letters, logo, watermark, UI frame, huge portrait, "
    "cropped body, white background, black background, blurry, anti-aliased smear, "
    "single large character only, empty cells"
)

JOBS = [
    {
        "name": "portrait_ansem",
        "w": 256,
        "h": 256,
        "style": "rd_plus__default",
        "remove_bg": True,
        "prompt": (
            "Crisp high quality RTS pixel art faction portrait bust, transparent "
            "background, no text, no watermark. ANSEM as a black biomechanical "
            "alien market warlord, elongated xeno head, glossy obsidian armor, "
            "cyan and acid green trading-screen glow, sinister meme coin trench-war "
            "energy, readable silhouette, centered."
        ),
    },
    {
        "name": "portrait_wynn",
        "w": 256,
        "h": 256,
        "style": "rd_plus__default",
        "remove_bg": True,
        "prompt": (
            "Crisp high quality RTS pixel art faction portrait bust, transparent "
            "background, no text, no watermark. WYNN as a silver masked predator "
            "hunter trader, trophy hunter armor, gold and green accents, plasma "
            "visor glow, aggressive high-stakes whale bidder energy, readable "
            "silhouette, centered."
        ),
    },
]

UNIT_SPECS = {
    "ansem_villager": (
        "small alien scout worker drone, lean black xeno body, cyan satchel, "
        "carrying glowing market data crystal"
    ),
    "ansem_swordsman": (
        "alien claw infantry, black biomechanical armor, long talons, cyan "
        "highlights, melee attacker"
    ),
    "ansem_archer": (
        "alien acid-spit ranged unit, black xeno body, green acid glands, "
        "projectile pose"
    ),
    "ansem_lancer": (
        "fast alien stalker lancer, long tail spear silhouette, cyan claws, "
        "charging pose"
    ),
    "ansem_siege": (
        "large alien hive siege beast, bulky biomechanical crawler, acid cannon "
        "sacs, black and green glow"
    ),
    "wynn_villager": (
        "masked hunter trader scout worker, green gold armor, small coin satchel "
        "and tools, trophy hunter vibe"
    ),
    "wynn_swordsman": (
        "masked hunter blade infantry, silver face mask, gold green armor, wrist "
        "blade sword, melee attacker"
    ),
    "wynn_archer": (
        "masked hunter plasma ranged unit, shoulder cannon, green gold armor, "
        "silver visor, ranged pose"
    ),
    "wynn_lancer": (
        "masked hunter spear lancer, silver mask, long spear, green gold armor, "
        "charging pose"
    ),
    "wynn_siege": (
        "large masked hunter war pack siege unit, armored heavy hunter with cannon "
        "gear, green gold silver armor"
    ),
}

for name, subject in UNIT_SPECS.items():
    JOBS.append(
        {
            "name": name,
            "w": 192,
            "h": 192,
            "style": "rd_plus__default",
            "remove_bg": True,
            "prompt": (
                "Crisp cohesive RTS pixel art 4x4 walking sprite sheet, transparent "
                "background, no text, no watermark, no UI frame. Exactly sixteen "
                "tiny frames in a 4 by 4 grid, each frame centered in a 48 by 48 "
                "cell, readable top-down isometric game unit. "
                f"{subject}. Consistent character design across all frames, "
                "idle/walk facings, full body visible."
            ),
        }
    )


def request_image(token: str, job: dict) -> Path:
    payload = {
        "width": job["w"],
        "height": job["h"],
        "prompt": job["prompt"],
        "prompt_style": job["style"],
        "num_images": 1,
        "negative_prompt": NEGATIVE,
    }
    if job.get("remove_bg"):
        payload["remove_bg"] = True

    req = Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json", "X-RD-Token": token},
    )
    try:
        with urlopen(req, timeout=180) as res:
            data = json.loads(res.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"{job['name']}: Retro Diffusion HTTP {exc.code}: {detail[:500]}"
        ) from exc

    images = data.get("base64_images") or []
    if not images:
        raise RuntimeError(f"{job['name']}: no base64_images, keys={list(data.keys())}")

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{job['name']}.png"
    path.write_bytes(base64.b64decode(images[0]))
    return path


def main() -> int:
    token = sys.stdin.readline().strip()
    if not token:
        raise SystemExit("missing Retro Diffusion token on stdin")

    for i, job in enumerate(JOBS, 1):
        print(f"[{i}/{len(JOBS)}] {job['name']}", flush=True)
        print(request_image(token, job), flush=True)
        time.sleep(0.25)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
