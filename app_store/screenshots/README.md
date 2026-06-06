# døPi App Store screenshots

This folder uses the `ios-screenshots` skill overlay flow.

Files:

- `mockup.png`: iPhone frame copied from the skill.
- `raw/`: the four extracted screenshots from the chat, in app order.
- `index.html`: browser overlay/export page with per-slide controls, URL-hash persistence, screenshot zoom, and Apple iPhone export sizes.
- `exports/iphone-6.9/`: generated 1320x2868 App Store PNGs using the raw images and the iPhone overlay.

Raw screenshot mapping:

- `raw/01-home-menu.png`
- `raw/02-cover-flow.png`
- `raw/03-apple-music.png`
- `raw/04-genres.png`

The overlay follows the skill rule: `mockup.png` is behind the screen content and the screenshot layer sits above the mockup screen area so the opaque black mockup screen cannot hide it.
