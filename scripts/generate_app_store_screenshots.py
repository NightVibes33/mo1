#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'app_store' / 'screenshots'
FASTLANE = ROOT / 'ios' / 'fastlane' / 'screenshots' / 'en-US'
FONT_DIR = ROOT / 'assets' / 'fonts'
BOLD = str(FONT_DIR / 'Helvetica-Bold.ttf')
REG = str(FONT_DIR / 'Helvetica.ttf')
W, H = 1320, 2868
SIZES = {
    'iphone_6_9': (1320, 2868),
    'iphone_6_5': (1284, 2778),
    'iphone_6_3': (1206, 2622),
    'iphone_6_1': (1125, 2436),
}
SLIDES = ['01_home_menu', '02_cover_flow', '03_apple_music', '04_genres']


def f(size, bold=True):
    return ImageFont.truetype(BOLD if bold else REG, size)


def txt(d, xy, s, size, fill=(0, 0, 0), anchor=None):
    d.text(xy, s, font=f(size), fill=fill, anchor=anchor)


def fit(d, xy, s, size, width, fill=(0, 0, 0)):
    while size > 20 and d.textbbox((0, 0), s, font=f(size))[2] > width:
        size -= 2
    txt(d, xy, s, size, fill)


def chevron(d, x, y, size=30, fill=(255, 255, 255)):
    d.line((x, y, x + size, y + size), fill=fill, width=8)
    d.line((x + size, y + size, x, y + size * 2), fill=fill, width=8)


def battery(d, x, y):
    d.rectangle((x, y, x + 62, y + 34), outline=(80, 80, 80), width=3, fill=(230, 235, 224))
    d.rectangle((x + 62, y + 10, x + 72, y + 24), fill=(80, 80, 80))
    d.rectangle((x + 7, y + 7, x + 42, y + 27), fill=(124, 184, 62))


def pause(d, x, y):
    d.rounded_rectangle((x, y, x + 18, y + 52), 3, fill=(116, 190, 232))
    d.rounded_rectangle((x + 30, y, x + 48, y + 52), 3, fill=(68, 145, 207))


def base():
    img = Image.new('RGB', (W, H), (204, 208, 208))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, H), fill=(205, 209, 209))
    d.rectangle((0, 0, W, 92), fill=(225, 227, 227))
    d.rectangle((22, 0, 28, H), fill=(235, 237, 237))
    d.rectangle((W - 28, 0, W - 22, H), fill=(164, 168, 168))
    return img


def screen(img, title):
    d = ImageDraw.Draw(img)
    sx, sy, sw, sh = 72, 218, 1176, 814
    d.rounded_rectangle((sx, sy, sx + sw, sy + sh), 22, fill=(255, 255, 255), outline=(0, 0, 0), width=10)
    d.rectangle((sx + 8, sy + 8, sx + sw - 8, sy + 92), fill=(248, 248, 248))
    d.line((sx + 8, sy + 92, sx + sw - 8, sy + 92), fill=(125, 125, 125), width=2)
    d.line((sx + 8, sy + 108, sx + sw - 8, sy + 108), fill=(205, 205, 205), width=2)
    txt(d, (sx + 34, sy + 22), title, 62)
    pause(d, sx + sw - 174, sy + 20)
    battery(d, sx + sw - 100, sy + 27)
    return sx, sy, sw, sh


def select(d, x, y, w, h):
    d.rounded_rectangle((x, y, x + w, y + h), 18, fill=(100, 210, 225), outline=(155, 208, 238), width=3)
    d.rectangle((x + w // 2, y + 3, x + w - 3, y + h - 3), fill=(68, 126, 208))


def wheel(d):
    cx, cy, r = W // 2, 2212, 390
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255), outline=(245, 245, 245), width=4)
    d.ellipse((cx - 138, cy - 138, cx + 138, cy + 138), fill=(212, 214, 214), outline=(165, 168, 168), width=4)
    c = (128, 141, 148)
    txt(d, (cx, cy - 310), 'MENU', 60, c, 'mm')
    txt(d, (cx - 254, cy), '|◀◀', 44, c, 'mm')
    txt(d, (cx + 254, cy), '▶▶|', 44, c, 'mm')
    txt(d, (cx, cy + 300), '▶Ⅱ', 52, c, 'mm')


def home():
    img = base(); d = ImageDraw.Draw(img); sx, sy, sw, sh = screen(img, 'døPi')
    body = sy + 108; left = 588
    d.rectangle((sx + 8, body, sx + left, sy + sh - 8), fill=(255, 255, 255))
    d.rectangle((sx + left, body, sx + sw - 8, sy + sh - 8), fill=(99, 107, 112))
    select(d, sx + 28, body + 26, left - 52, 82)
    for i, item in enumerate(['Music', 'Settings', 'Shuffle So...', 'Now Playing']):
        txt(d, (sx + 58, body + 32 + i * 106), item, 62, (255, 255, 255) if i == 0 else (0, 0, 0))
    chevron(d, sx + left - 82, body + 42)
    d.rounded_rectangle((sx + left + 170, body + 220, sx + left + 470, body + 520), 34, fill=(235, 108, 164), outline=(220, 220, 220), width=4)
    txt(d, (sx + left + 320, body + 366), '♪', 150, (255, 255, 255), 'mm')
    wheel(d); return img


def cover():
    img = base(); d = ImageDraw.Draw(img); sx, sy, sw, sh = screen(img, 'Cover Flow')
    body = sy + 118
    d.rectangle((sx + 8, body, sx + sw - 8, sy + sh - 8), fill=(255, 255, 255))
    covers = [((112, body + 70, 392, body + 350), (60, 112, 220), 'MOON'), ((410, body + 36, 820, body + 446), (220, 40, 88), 'NEON'), ((842, body + 70, 1122, body + 350), (30, 176, 190), 'WAVE')]
    for box, color, label in covers:
        d.rectangle(box, fill=color)
        txt(d, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2), label, 54, (255, 255, 255), 'mm')
        d.rectangle((box[0], box[3] + 8, box[2], box[3] + 80), fill=(232, 232, 232))
    txt(d, (sx + sw // 2, sy + sh - 140), 'Neon City - Single', 64, anchor='mm')
    txt(d, (sx + sw // 2, sy + sh - 64), 'døPi Library', 58, anchor='mm')
    wheel(d); return img


def apple():
    img = base(); d = ImageDraw.Draw(img); sx, sy, sw, sh = screen(img, 'Apple Music')
    body = sy + 108
    d.rectangle((sx + 8, body, sx + sw - 8, sy + sh - 8), fill=(255, 255, 255))
    rows = [('Search Apple Music', 'Catalog search', True), ('Import Music Library', 'Saved songs + playlists', False), ('Play in døPi', 'Artwork, tracks, metadata', False)]
    for i, (a, b, sel) in enumerate(rows):
        y = body + i * 154
        d.rectangle((sx + 8, y, sx + 178, y + 154), fill=(238, 238, 238))
        txt(d, (sx + 92, y + 78), '♪', 98, (190, 190, 190), 'mm')
        if sel:
            d.rectangle((sx + 178, y, sx + sw - 8, y + 154), fill=(78, 133, 211))
            txt(d, (sx + 214, y + 20), a, 62, (255, 255, 255))
            txt(d, (sx + 214, y + 88), b, 52, (255, 255, 255))
            chevron(d, sx + sw - 88, y + 46)
        else:
            txt(d, (sx + 214, y + 18), a, 60)
            txt(d, (sx + 214, y + 88), b, 48, (68, 68, 68))
        d.line((sx + 8, y + 154, sx + sw - 8, y + 154), fill=(226, 226, 226), width=2)
    wheel(d); return img


def genres():
    img = base(); d = ImageDraw.Draw(img); sx, sy, sw, sh = screen(img, 'Genres')
    body = sy + 108
    d.rectangle((sx + 8, body, sx + sw - 8, sy + sh - 8), fill=(255, 255, 255))
    items = ['Alternative', 'Alternative Rap', 'Anime', 'Contemporary R&B', 'Country', 'Dance', 'Dubstep', 'Electronic', 'Hip-Hop']
    for i, item in enumerate(items):
        y = body + 34 + i * 88
        if item == 'Anime':
            select(d, sx + 28, y - 12, sw - 56, 76)
            txt(d, (sx + 58, y - 4), item, 58, (255, 255, 255))
            chevron(d, sx + sw - 84, y + 2, 24)
        else:
            fit(d, (sx + 58, y - 4), item, 58, sw - 110)
    wheel(d); return img


def main():
    OUT.mkdir(parents=True, exist_ok=True); FASTLANE.mkdir(parents=True, exist_ok=True)
    renders = {'01_home_menu': home(), '02_cover_flow': cover(), '03_apple_music': apple(), '04_genres': genres()}
    for folder, size in SIZES.items():
        dest = OUT / folder; dest.mkdir(parents=True, exist_ok=True)
        for i, name in enumerate(SLIDES, 1):
            im = renders[name] if size == (W, H) else renders[name].resize(size)
            im.save(dest / f'{name}.png')
            if folder == 'iphone_6_9': im.save(FASTLANE / f'{i:02d}_{name}.png')
    (OUT / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>døPi screenshots</title><style>body{background:#111;color:white;font-family:Arial;padding:24px}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:16px}img{width:100%;border-radius:12px}</style><h1>døPi App Store screenshots</h1><div class="grid">' + ''.join(f'<a href="iphone_6_9/{n}.png"><img src="iphone_6_9/{n}.png"></a>' for n in SLIDES) + '</div>', encoding='utf-8')
    (OUT / 'README.md').write_text('# døPi App Store screenshots\n\nRun `python3 scripts/generate_app_store_screenshots.py` to regenerate the silver paid-app screenshots.\n', encoding='utf-8')

if __name__ == '__main__':
    main()
