#!/usr/bin/env python3

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
BRANDING_DIR = ROOT / "assets" / "branding"
IOS_ICON_DIR = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
ANDROID_RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"

MASTER_SOURCE = BRANDING_DIR / "android_app_icon.png"
WORK_SIZE = 4096
BACKGROUND = (36, 36, 36, 255)
FOREGROUND = (255, 255, 255, 255)


IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

ANDROID_SIZES = {
    "mipmap-mdpi/ic_launcher.png": 48,
    "mipmap-hdpi/ic_launcher.png": 72,
    "mipmap-xhdpi/ic_launcher.png": 96,
    "mipmap-xxhdpi/ic_launcher.png": 144,
    "mipmap-xxxhdpi/ic_launcher.png": 192,
}


def _sparkle_points(samples: int = 2048) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    center = WORK_SIZE / 2
    radius_x = WORK_SIZE * 0.39
    radius_y = WORK_SIZE * 0.43
    exponent = 0.56

    for index in range(samples):
        theta = 2.0 * math.pi * index / samples
        cos_v = math.cos(theta)
        sin_v = math.sin(theta)
        x = math.copysign(abs(cos_v) ** (2.0 / exponent), cos_v)
        y = math.copysign(abs(sin_v) ** (2.0 / exponent), sin_v)
        points.append((center + x * radius_x, center + y * radius_y))

    return points


def _render_master() -> Image.Image:
    image = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.polygon(_sparkle_points(), fill=FOREGROUND)
    return image


def _save_resized(image: Image.Image, destination: Path, size: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")
    resized.save(destination)


def main() -> None:
    master = _render_master()
    _save_resized(master, MASTER_SOURCE, 2134)

    for filename, size in IOS_SIZES.items():
        _save_resized(master, IOS_ICON_DIR / filename, size)

    for relative_path, size in ANDROID_SIZES.items():
        _save_resized(master, ANDROID_RES_DIR / relative_path, size)

    print(f"Updated icon assets from {MASTER_SOURCE}")


if __name__ == "__main__":
    main()
