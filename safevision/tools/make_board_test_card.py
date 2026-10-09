"""Create deterministic 640x480, 24-bit BI_RGB BMPs; never format a card."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

W, H = 640, 480


def colour(image, x, y):
    if image == 0:
        bars = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255),
                (255, 255, 0), (0, 255, 255), (255, 0, 255), (0, 0, 0)]
        return bars[x // 80]
    if image == 1:
        return (x * 255 // (W - 1), y * 255 // (H - 1), ((x // 32 + y // 32) % 2) * 255)
    if image == 2:
        border = x < 8 or y < 8 or x >= W - 8 or y >= H - 8
        return (255, 128, 0) if border else ((0, 255, 255) if x == W // 2 or y == H // 2 else (16, 16, 64))
    return ((x ^ y) & 255, (x + y) & 255,
            ((x * 3) ^ (y * 5) ^ ((x >> 8) << 6) ^ ((y >> 8) << 5)) & 255)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', type=Path, required=True)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rowsize = (W * 3 + 3) & ~3
    size = 54 + rowsize * H
    header = struct.pack('<2sIHHI', b'BM', size, 0, 0, 54)
    header += struct.pack('<IiiHHIIiiII', 40, W, H, 1, 24, 0, rowsize * H, 0, 0, 0, 0)
    records = []
    for image in range(4):
        data = bytearray(header)
        for y in range(H - 1, -1, -1):
            for x in range(W):
                r, g, b = colour(image, x, y)
                data.extend((b, g, r))
            data.extend(b'\0' * (rowsize - W * 3))
        path = args.out / f'SV{image + 1:04d}.BMP'
        path.write_bytes(data)
        readback = path.read_bytes()
        if len(readback) != size or readback != data:
            raise RuntimeError(f'BMP readback failed: {path}')
        records.append({'name': path.name, 'bytes': size, 'sha256': hashlib.sha256(readback).hexdigest(),
                        'width': W, 'height': H, 'bpp': 24, 'compression': 'BI_RGB', 'rows': 'bottom-up'})
    (args.out / 'manifest.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
    print(f'Created and read back 4 uncompressed BMP files in {args.out}. Copy SV0001.BMP..SV0004.BMP to a FAT32 card root.')


if __name__ == '__main__':
    main()
