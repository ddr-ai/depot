#!/usr/bin/env python3
"""1024 app icon: cream D on charcoal. Python stdlib only."""
import struct
import zlib
from pathlib import Path

W = 1024
BG = (11, 12, 14)
FG = (232, 226, 214)


def pixel(x: int, y: int) -> tuple[int, int, int]:
    # Stem of a D, plus a right-hand bowl.
    if 338 <= x <= 418 and 292 <= y <= 732:
        return FG
    dx = x - 418
    dy = y - 512
    dist = (dx * dx + dy * dy) ** 0.5
    if dx >= -6 and 168 <= dist <= 252:
        return FG
    return BG


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def main() -> None:
    raw = bytearray()
    for y in range(W):
        raw.append(0)
        for x in range(W):
            raw.extend(pixel(x, y))
    ihdr = struct.pack(">IIBBBBB", W, W, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    out = Path(__file__).resolve().parents[1] / "Depot" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)
    print(f"wrote {out} ({len(png)} bytes)")


if __name__ == "__main__":
    main()
