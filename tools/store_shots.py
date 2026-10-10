"""Composes the Play Store screenshots from raw game captures.

Capture first (720x1280 windows), e.g.:
  godot --path . --resolution 720x1280 -- --shot shots/s_board_1.png --shot-after 1
  godot --path . --resolution 720x1280 -- --menu-shot shots/s_home.png
  godot --path . --resolution 720x1280 -- --page-shot spin:shots/s_spin.png
then: python tools/store_shots.py  ->  docs/store/screen_N.png (1080x1920)
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, 'shots')
OUT = os.path.join(ROOT, 'docs', 'store')
FONT = os.path.join(ROOT, 'art', 'fonts', 'Fredoka.ttf')
ITEMS = [
    ('board_1', 'Pick your path', 'Every roll is a choice'),
    ('board_13', 'Build a sky city', 'Grow streets into landmarks'),
    ('results', 'Win the table', 'Fast 4-player matches online'),
    ('home', 'Climb the tables', 'From Karachi to the top'),
    ('spin', 'Daily spin & rewards', 'Something new every day'),
    ('shop', 'Make it yours', 'Golden pawns, neon dice'),
]
W, H = 1080, 1920
TOP, BOTTOM = (124, 92, 255), (255, 140, 170)


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([weight, 100])
    return f


def gradient():
    col = Image.new('RGB', (1, H))
    for y in range(H):
        t = y / H
        col.putpixel((0, y), tuple(int(TOP[i] * (1 - t) + BOTTOM[i] * t) for i in range(3)))
    return col.resize((W, H)).convert('RGBA')


def compose(name, title, sub):
    bg = gradient()
    shot = Image.open(os.path.join(SHOTS, 's_%s.png' % name)).convert('RGBA')
    sw = 820
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, H - sh - 40
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 6, y + 24, x + sw + 6, y + sh + 24), radius=60, fill=(40, 10, 80, 120))
    bg = Image.alpha_composite(bg, shadow.filter(ImageFilter.GaussianBlur(24)))
    frame = Image.new('RGBA', (sw + 24, sh + 24), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, sw + 23, sh + 23), radius=66, fill=(255, 255, 255, 255))
    bg.alpha_composite(frame, (x - 12, y - 12))
    mask = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=56, fill=255)
    bg.paste(shot, (x, y), mask)
    d = ImageDraw.Draw(bg)
    for text, f, top, fill, stroke in [(title, font(96, 700), 64, (255, 255, 255), 7),
                                       (sub, font(52, 600), 186, (255, 236, 190), 4)]:
        d.text(((W - d.textlength(text, font=f)) / 2, top), text, font=f, fill=fill,
               stroke_width=stroke, stroke_fill=(70, 40, 140))
    return bg.convert('RGB')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for i, (name, title, sub) in enumerate(ITEMS):
        compose(name, title, sub).save(os.path.join(OUT, 'screen_%d.png' % (i + 1)))
    sheet = Image.new('RGB', (len(ITEMS) * 280, 480), (255, 255, 255))
    for i in range(len(ITEMS)):
        sheet.paste(Image.open(os.path.join(OUT, 'screen_%d.png' % (i + 1))).resize((270, 480)), (i * 280, 0))
    sheet.save(os.path.join(SHOTS, 'store_sheet.png'))
    print('wrote', len(ITEMS), 'screenshots')
