#!/usr/bin/env python3
"""Convert an image into a 240x240 RGB565 binary for GC9A01 panels."""

from __future__ import annotations

import argparse
import pathlib
import struct
from typing import Tuple

from PIL import Image


def _center_crop(image: Image.Image) -> Image.Image:
    size = min(image.width, image.height)
    left = (image.width - size) // 2
    top = (image.height - size) // 2
    return image.crop((left, top, left + size, top + size))


def convert(
    src_path: pathlib.Path,
    dst_path: pathlib.Path,
    size: int,
    rotate: int | None,
    center_crop: bool,
    endian: str,
) -> None:
    image = Image.open(src_path)
    if center_crop:
        image = _center_crop(image)
    image = image.convert("RGB")
    image = image.resize((size, size), Image.LANCZOS)
    if rotate:
        image = image.rotate(rotate, expand=False)

    data = bytearray()
    for r, g, b in image.getdata():
        rgb565 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
        if endian == "big":
            data += struct.pack(">H", rgb565)
        else:
            data += struct.pack("<H", rgb565)

    dst_path.parent.mkdir(parents=True, exist_ok=True)
    dst_path.write_bytes(data)
    print(f"Saved {dst_path} ({len(data)} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert an input image to RGB565 binary for GC9A01."
    )
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--size", type=int, default=240, help="output width/height")
    parser.add_argument(
        "--rotate", type=int, default=None, help="rotation angle in degrees"
    )
    parser.add_argument(
        "--center-crop",
        action="store_true",
        help="crop the longest side to make the image square before resizing",
    )
    parser.add_argument(
        "--endian",
        choices=("big", "little"),
        default="big",
        help="byte order expected by the firmware",
    )
    args = parser.parse_args()

    convert(
        src_path=args.input,
        dst_path=args.output,
        size=args.size,
        rotate=args.rotate,
        center_crop=args.center_crop,
        endian=args.endian,
    )


if __name__ == "__main__":
    main()
