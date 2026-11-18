"""Capture four unchanged Build 16 screens on a dedicated, account-free AVD.

Never run against tester AVDs: the fixture replaces this capture app's local state.
ADB UI control was explicitly authorized for this Android workflow.
"""
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ADB = '/opt/homebrew/share/android-commandlinetools/platform-tools/adb'
SERIAL = 'emulator-5574'
APP = 'com.FAE.ScepTRONIC'
PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT / 'play-store-assets/build16-refresh-20261118/android'


def adb(*args):
    return subprocess.check_output([ADB, '-s', SERIAL, *args])


def nodes():
    adb('shell', 'uiautomator', 'dump', '/sdcard/sceptronic-capture.xml')
    return list(ET.fromstring(adb('exec-out', 'cat',
                                '/sdcard/sceptronic-capture.xml')).iter('node'))


def wait_label(label, timeout=30):
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        current = nodes()
        matches = [n for n in current if n.get('content-desc') == label
                   or n.get('text') == label]
        if matches:
            return matches
        time.sleep(.4)
    raise RuntimeError(f'UI label not found: {label}')


def tap(node):
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
    adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))


def capture(folder, name, expected):
    path = folder / name
    path.write_bytes(adb('exec-out', 'screencap', '-p'))
    with Image.open(path) as image:
        assert image.size == expected, (path, image.size)
        rgb = image.convert('RGB')
        rgb.save(path)
    print(f'CAPTURED {path.relative_to(ROOT)}', flush=True)


assert b'ScepTRONIC_Build16_Capture_20261118' in adb('emu', 'avd', 'name')
adb('shell', 'am', 'force-stop', APP)
adb('push', str(PROJECT / 'tool/build16_capture_fixture.json'),
    '/data/local/tmp/sceptronic-capture-fixture.json')
adb('shell', 'run-as', APP, 'cp',
    '/data/local/tmp/sceptronic-capture-fixture.json', 'app_flutter/app_state.json')
adb('shell', 'am', 'broadcast', '-a', 'com.android.systemui.demo',
    '-e', 'command', 'exit')
adb('shell', 'settings', 'put', 'global', 'sysui_demo_allowed', '0')
adb('shell', 'dumpsys', 'battery', 'set', 'level', '100')
adb('shell', 'cmd', 'statusbar', 'send-disable-flag', 'notification-icons')

for name, width, height, density in [
    ('phone-1080x1920', 1080, 1920, 320),
    ('tablet-7-inch-1080x1920', 1080, 1920, 240),
    ('tablet-10-inch-1440x2560', 1440, 2560, 240),
]:
    if len(sys.argv) > 1 and name != sys.argv[1]:
        continue
    folder = ROOT / name
    folder.mkdir(parents=True, exist_ok=True)
    adb('shell', 'am', 'force-stop', APP)
    adb('shell', 'wm', 'size', f'{width}x{height}')
    adb('shell', 'wm', 'density', str(density))
    adb('shell', 'am', 'start', '-n',
        f'{APP}/com.masacookie.septronics.MainActivity')
    time.sleep(4)
    capture(folder, '04-splash.png', (width, height))
    buttons = wait_label('OPEN')
    capture(folder, '01-stock-select.png', (width, height))
    tap(buttons[0])
    wait_label('STOCK A SETTING')
    time.sleep(.4)
    capture(folder, '02-color-setting.png', (width, height))
    adb('shell', 'input', 'keyevent', '4')
    bluetooth = wait_label('Bluetooth Setting')
    tap(bluetooth[0])
    wait_label('BLUETOOTH SETTING')
    wait_label('Noxel-1')
    time.sleep(.5)
    capture(folder, '03-bluetooth-setting.png', (width, height))
print('ANDROID CAPTURE COMPLETE', flush=True)
