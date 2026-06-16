# døPe App Store screenshots

These screenshots are direct crops from `screenshots/combined.jpg`. The source sheet is split into 4 columns by 2 rows, producing eight portrait crops in `crops/`.

Selected App Store screenshots:

- `crops/11.png` -> `raw/01-home-menu.png`
- `crops/13.png` -> `raw/02-cover-flow.png`
- `crops/21.png` -> `raw/03-apple-music.png`
- `crops/23.png` -> `raw/04-genres.png`

Generated exports are exact Apple screenshot sizes:

- `exports/iphone-6.9/` -> 1320x2868
- `exports/iphone-6.5/` -> 1284x2778
- `exports/iphone-6.3/` -> 1206x2622
- `exports/iphone-6.1/` -> 1125x2436

Run `python3 scripts/generate_app_store_screenshots.py` after changing `screenshots/combined.jpg`. The generator only center-crops to the target App Store aspect ratio and resizes; it does not add a fake phone frame or marketing layout.
