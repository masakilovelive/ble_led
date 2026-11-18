"""Validate and package generated screenshots; never redraw their UI pixels."""
import csv
import hashlib
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1] / 'play-store-assets/build16-refresh-20261118'
SIZES = {
    'android/phone-1080x1920': (1080, 1920),
    'android/tablet-7-inch-1080x1920': (1080, 1920),
    'android/tablet-10-inch-1440x2560': (1440, 2560),
    'ios-ui-renders/6.9-inch': (1320, 2868),
    'ios-ui-renders/6.3-inch': (1206, 2622),
    'ios-ui-renders/6.1-inch': (1170, 2532),
    'ios-ui-renders/5.5-inch': (1242, 2208),
    'ios-ui-renders/ipad-13-inch': (2064, 2752),
    'ios-ui-renders/ipad-12.9-inch': (2048, 2732),
    'ios-ui-renders/ipad-11-inch': (1668, 2420),
}
NAMES = ['01-stock-select.png', '02-color-setting.png',
         '03-bluetooth-setting.png', '04-splash.png']
preview = ROOT / 'previews-not-for-upload'
preview.mkdir(exist_ok=True)
rows = []
for directory, size in SIZES.items():
    sheet = Image.new('RGB', (1120, 680), '#202020')
    draw = ImageDraw.Draw(sheet)
    draw.text((12, 8), f'{directory}  {size[0]}x{size[1]}', fill='white')
    for index, name in enumerate(NAMES):
        path = ROOT / directory / name
        with Image.open(path) as original:
            assert original.size == size, (path, original.size, size)
            before = original.convert('RGB')
            # Only remove the opaque alpha channel, not alter RGB pixel values.
            assert 'A' not in original.getbands() or original.getextrema()[-1] == (255, 255)
            before.save(path, optimize=True)
            with Image.open(path) as encoded:
                assert encoded.mode == 'RGB' and encoded.tobytes() == before.tobytes()
            thumb = ImageOps.contain(before, (266, 590))
            sheet.paste(thumb, (index * 280 + (280-thumb.width)//2, 55))
            draw.text((index * 280 + 8, 650), name, fill='white')
        rows.append((str(path.relative_to(ROOT)), *size, 'RGB',
                     hashlib.sha256(path.read_bytes()).hexdigest()))
    sheet.save(preview / f'{directory.replace("/", "-")}.jpg', quality=92)

with (ROOT / 'IMAGE_MANIFEST.csv').open('w', newline='') as handle:
    writer = csv.writer(handle)
    writer.writerow(['file', 'width', 'height', 'mode', 'sha256'])
    writer.writerows(rows)
assert len(rows) == 40

groups = {
    'ScepTRONIC-Build16-Android-12-images.zip': ['android/'],
    'ScepTRONIC-Build16-iPhone-16-UI-images.zip': [
        f'ios-ui-renders/{name}/' for name in ['6.9-inch', '6.3-inch', '6.1-inch', '5.5-inch']],
    'ScepTRONIC-Build16-iPad-12-reference-images.zip': ['ios-ui-renders/ipad-'],
    'ScepTRONIC-Build16-All-40-images.zip': ['android/', 'ios-ui-renders/'],
}
for name, prefixes in groups.items():
    with zipfile.ZipFile(ROOT / name, 'w', zipfile.ZIP_DEFLATED) as archive:
        for row in rows:
            if any(row[0].startswith(prefix) for prefix in prefixes):
                archive.write(ROOT / row[0], row[0])
        for metadata in ['README.txt', 'IMAGE_MANIFEST.csv', 'UPLOAD_STATUS.txt']:
            if (ROOT / metadata).exists():
                archive.write(ROOT / metadata, metadata)
    print(name, (ROOT / name).stat().st_size, flush=True)
print('Validated 40 RGB PNG images, exact dimensions and unchanged RGB values.')
