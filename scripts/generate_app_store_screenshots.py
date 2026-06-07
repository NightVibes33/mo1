#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "screenshots" / "combined.jpg"
SCREENSHOT_DIR = ROOT / "app_store" / "screenshots"
RAW_DIR = SCREENSHOT_DIR / "raw"
CROPS_DIR = SCREENSHOT_DIR / "crops"
EXPORT_DIR = SCREENSHOT_DIR / "exports"

CELL_COLUMNS = 4
CELL_ROWS = 2

SELECTED = [
    ("01-home-menu", "11"),
    ("02-cover-flow", "13"),
    ("03-apple-music", "21"),
    ("04-genres", "23"),
]

IPHONE_SIZES = [
    ("iphone-6.9", 1320, 2868),
    ("iphone-6.5", 1284, 2778),
    ("iphone-6.3", 1206, 2622),
    ("iphone-6.1", 1125, 2436),
]

IPAD_SIZES = [
    ("ipad-13", 2064, 2752),
]


def crop_to_aspect(image: Image.Image, width: int, height: int) -> Image.Image:
    target = width / height
    current = image.width / image.height
    if current > target:
        next_w = round(image.height * target)
        left = (image.width - next_w) // 2
        return image.crop((left, 0, left + next_w, image.height))

    next_h = round(image.width / target)
    top = (image.height - next_h) // 2
    return image.crop((0, top, image.width, top + next_h))


def main() -> None:
    sheet = Image.open(SOURCE).convert("RGB")
    cell_w = sheet.width // CELL_COLUMNS
    cell_h = sheet.height // CELL_ROWS

    CROPS_DIR.mkdir(parents=True, exist_ok=True)
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    cells: dict[str, Path] = {}
    for row in range(CELL_ROWS):
        for col in range(CELL_COLUMNS):
            key = f"{row + 1}{col + 1}"
            left = col * cell_w
            top = row * cell_h
            right = (col + 1) * cell_w if col < CELL_COLUMNS - 1 else sheet.width
            bottom = (row + 1) * cell_h if row < CELL_ROWS - 1 else sheet.height
            crop = sheet.crop((left, top, right, bottom))
            path = CROPS_DIR / f"{key}.png"
            crop.save(path, optimize=True)
            cells[key] = path

    for name, key in SELECTED:
        image = Image.open(cells[key]).convert("RGB")
        image.save(RAW_DIR / f"{name}.png", optimize=True)

    for folder, width, height in [*IPHONE_SIZES, *IPAD_SIZES]:
        out_dir = EXPORT_DIR / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        for name, _ in SELECTED:
            image = Image.open(RAW_DIR / f"{name}.png").convert("RGB")
            export = crop_to_aspect(image, width, height).resize(
                (width, height),
                Image.Resampling.LANCZOS,
            )
            export.save(out_dir / f"{name}.png", optimize=True)


if __name__ == "__main__":
    main()
