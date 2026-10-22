"""Reproduce the two V3 video ROMs; --check performs a read-only audit.

Compression is accepted only when expansion exactly reproduces all 4,096 bytes
of the checked-in source font. A different font must therefore either satisfy
the same lossless format or cause this command to fail before writing assets.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


LINES = (
    "SAFEVISION BASE SLOT 1 GEN 000 FPS 00",
    "SD READY CACHE F STATE PLAY LAT 21 PX",
    "VIDEO UF 00000000 AUDIO UF 00000000 ERR 00",
    "CONFIG  NEXT:+ AUTO:- LONG NEXT:FIELD",
    "BRIGHTNESS  +000",
    "CONTRAST    000",
    "SCALER      NEAREST",
    "SCALE       FIT",
    "FADE        ON  32 FRAMES",
    "VOLUME      000",
    "PERIOD      00 SECONDS",
    "OSD ALPHA   000",
    "WARNING CODE 00 | PRESS NEXT TO RECOVER",
    "SAFEVISION | EMERGENCY EXIT SYSTEM",
    "LEVEL",
)


def read_mem(path: Path) -> bytes:
    words = " ".join(line.split("//", 1)[0] for line in path.read_text().splitlines())
    return bytes(int(word, 16) for word in words.split())


def assets(font: bytes) -> dict[str, bytes]:
    if len(font) != 4096:
        raise ValueError("source font must contain 256 characters x 16 rows")
    compact = bytes(
        font[character * 16 + row * 2 + 1] if row < 7 else 0
        for character in range(128) for row in range(8)
    )
    expanded = bytes(
        0 if character >= 128 or row in (0, 15)
        else compact[character * 8 + (row - 1) // 2]
        for character in range(256) for row in range(16)
    )
    if expanded != font:
        raise ValueError("source font is incompatible with lossless V3 compression")
    text = b"".join(line.ljust(64).encode("ascii") for line in LINES)
    text += b"EMERGENCY".ljust(16) + b"EXIT".ljust(8)
    text += b"SAFE MODE - NEXT TO RECOVER".ljust(40)
    if len(compact) != 1024 or len(text) != 1024:
        raise ValueError("V3 ROM must fit exactly 1,024 bytes")
    return {"font8x16_compact.mem": compact, "v3_status_text.mem": text}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    directory = Path(__file__).resolve().parents[1] / "assets" / "fonts"
    font = read_mem(directory / "font8x16.mem")
    for filename, data in assets(font).items():
        path = directory / filename
        if arguments.check:
            actual = read_mem(path)
            if actual != data:
                raise ValueError(f"stale or corrupt generated asset: {path}")
        else:
            path.write_text("".join(f"{byte:02x}\n" for byte in data), encoding="ascii")
        print(f"PASS {filename}: {len(data)} bytes sha256={hashlib.sha256(data).hexdigest()}")
    print("PASS lossless expansion: all 4096 source-font bytes")


if __name__ == "__main__":
    main()
