#!/usr/bin/env python3
"""Generate original geometric icons and a deterministic local noise sample."""
import json
import random
import shutil
import struct
import wave
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / 'Resources'
assets = root / 'Assets.xcassets'
presets = {'IconGreen': ('#163A29', '#99D39A'), 'IconNight': ('#091924', '#F0E8D9'), 'IconPaper': ('#EEE7D8', '#354A39')}
for name, (bg, fg) in presets.items():
    image = Image.new('RGB', (1024, 1024), bg)
    draw = ImageDraw.Draw(image)
    draw.ellipse((236, 236, 788, 788), fill=fg)
    draw.ellipse((400, 164, 888, 652), fill=bg)
    draw.rectangle((262, 802, 762, 828), fill=fg)
    for x, y, r in [(688, 264, 16), (798, 396, 11), (700, 442, 9)]: draw.ellipse((x-r, y-r, x+r, y+r), fill=fg)
    directory = assets / f'{name}.appiconset'; directory.mkdir(parents=True, exist_ok=True)
    image.save(directory / f'{name}.png')
    (directory / 'Contents.json').write_text(json.dumps({'images': [{'filename': f'{name}.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2))
for name in ['AppIcon'] + list(presets):
    directory = assets / f'Preview{name}.imageset'; directory.mkdir(parents=True, exist_ok=True)
    image = Image.open(assets / f'{name}.appiconset' / f'{name}.png').convert('RGB').resize((120, 120))
    image.save(directory / 'preview.png')
    (directory / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'preview.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2))
rng = random.Random(404)
with wave.open(str(root / 'WhiteNoise.wav'), 'wb') as audio:
    audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(22050)
    audio.writeframes(b''.join(struct.pack('<h', rng.randint(-12000, 12000)) for _ in range(22050)))
print('Generated three alternate icons, four previews and local white noise.')
