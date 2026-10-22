"""Read-only independent verification of all BMP542 pixels and bounds551 inputs.

Python standard library only. No RTL, testbench, fixture generator, simulator or
reference.json claim is used as the numerical oracle. The eight complete cases
and all38 malformed/valid headers are fixed below. This checks fixture truth;
simulation, routed timing and the actual display remain separate gates.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
CASES = (
    (1080, 1920, 0, 24, 54), (1080, 1920, 1, 24, 138),
    (3840, 2160, 0, 32, 54), (641, 479, 1, 32, 54),
    (16384, 1, 0, 24, 54), (1, 16384, 1, 32, 54),
    (1, 1, 1, 24, 54), (17, 13, 0, 32, 54),
)
WIDTH, HEIGHT = 640, 480
PIXELS = len(CASES) * WIDTH * HEIGHT
# name,w,signed_height,bpp,planes,compression,pixel_offset,DIB,signature,
# supplied_header_bytes,bfSize,directory_size,expected_first_diagnostic.
# Full input values are fixed, including the intentionally wrapped bfSize in
# the INT_MIN-height case. Parsed signed geometry must reject it before size.
BOUNDS = (
    ('minimum_24', 1, 1, 24, 1, 0, 54, 40, 'BM', 54, 58, 58, 0),
    ('minimum_32', 1, 1, 32, 1, 0, 54, 40, 'BM', 54, 58, 58, 0),
    ('maximum_24', 16384, 16384, 24, 1, 0, 54, 40, 'BM', 54, 805306422, 805306422, 0),
    ('maximum_32', 16384, 16384, 32, 1, 0, 54, 40, 'BM', 54, 1073741878, 1073741878, 0),
    ('maximum_top_down', 16384, -16384, 32, 1, 0, 54, 40, 'BM', 54, 1073741878, 1073741878, 0),
    ('valid_v5_header', 1, 1, 24, 1, 0, 138, 124, 'BM', 54, 142, 142, 0),
    ('valid_large_header_gap', 1, 1, 24, 1, 0, 65536, 108, 'BM', 54, 65540, 65540, 0),
    ('zero_width', 0, 1, 24, 1, 0, 54, 40, 'BM', 54, 54, 54, 57),
    ('zero_height', 1, 0, 24, 1, 0, 54, 40, 'BM', 54, 54, 54, 57),
    ('over_width', 16385, 1, 24, 1, 0, 54, 40, 'BM', 54, 49210, 49210, 57),
    ('over_height', 1, 16385, 24, 1, 0, 54, 40, 'BM', 54, 65594, 65594, 57),
    ('over_negative_height', 1, -16385, 24, 1, 0, 54, 40, 'BM', 54, 65594, 65594, 57),
    ('nonzero_width_high_word', 65536, 1, 24, 1, 0, 54, 40, 'BM', 54, 196662, 196662, 57),
    ('negative_width', -1, 1, 24, 1, 0, 54, 40, 'BM', 54, 54, 54, 57),
    ('minimum_signed_height', 1, -2147483648, 24, 1, 0, 54, 40, 'BM', 54, 54, 54, 57),
    ('planes_zero', 1, 1, 24, 0, 0, 54, 40, 'BM', 54, 58, 58, 58),
    ('planes_two', 1, 1, 24, 2, 0, 54, 40, 'BM', 54, 58, 58, 58),
    ('bpp_8', 1, 1, 8, 1, 0, 54, 40, 'BM', 54, 58, 58, 58),
    ('bpp_16', 1, 1, 16, 1, 0, 54, 40, 'BM', 54, 58, 58, 58),
    ('bpp_48', 1, 1, 48, 1, 0, 54, 40, 'BM', 54, 62, 62, 58),
    ('bpp_high_word', 1, 1, 280, 1, 0, 54, 40, 'BM', 54, 90, 90, 58),
    ('compressed_rle', 1, 1, 24, 1, 1, 54, 40, 'BM', 54, 58, 58, 58),
    ('compressed_bitfields', 1, 1, 24, 1, 3, 54, 40, 'BM', 54, 58, 58, 58),
    ('bad_signature', 1, 1, 24, 1, 0, 54, 40, 'BX', 54, 58, 58, 55),
    ('small_dib', 1, 1, 24, 1, 0, 54, 39, 'BM', 54, 58, 58, 56),
    ('overlapping_v5_header', 1, 1, 24, 1, 0, 54, 124, 'BM', 54, 58, 58, 56),
    ('overflowing_dib', 1, 1, 24, 1, 0, 54, 4294967295, 'BM', 54, 58, 58, 56),
    ('pixel_offset_inside_file_header', 1, 1, 24, 1, 0, 13, 40, 'BM', 54, 17, 17, 59),
    ('pixel_offset_short', 1, 1, 24, 1, 0, 53, 40, 'BM', 54, 57, 57, 56),
    ('short_declared_extent', 1, 1, 24, 1, 0, 54, 40, 'BM', 54, 57, 58, 59),
    ('directory_shorter_than_bf', 1, 1, 24, 1, 0, 54, 40, 'BM', 54, 58, 57, 59),
    ('directory_extent_overflow', 1, 1, 24, 1, 0, 4294967294, 40, 'BM', 54, 4294967295, 4294967295, 59),
    ('huge_offset_short_file', 1, 1, 24, 1, 0, 4294967280, 40, 'BM', 54, 4294967295, 58, 59),
    ('zero_directory', 1, 1, 24, 1, 0, 54, 40, 'BM', 54, 58, 0, 59),
    ('truncated_header_1', 1, 1, 24, 1, 0, 54, 40, 'BM', 1, 58, 58, 59),
    ('truncated_header_13', 1, 1, 24, 1, 0, 54, 40, 'BM', 13, 58, 58, 59),
    ('truncated_header_26', 1, 1, 24, 1, 0, 54, 40, 'BM', 26, 58, 58, 59),
    ('truncated_header_53', 1, 1, 24, 1, 0, 54, 40, 'BM', 53, 58, 58, 59),
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def words(path, digits):
    """Strict width/count is checked by the caller; newline style is portable."""
    with path.open('r', encoding='ascii') as stream:
        for line_number, line in enumerate(stream, 1):
            token = line.strip()
            require(re.fullmatch(r'[0-9A-Fa-f]{' + str(digits) + '}', token) is not None,
                    f'{path.name}:{line_number}: invalid {digits * 4}-bit hex word')
            yield int(token, 16)


def check_pixels(root):
    folder = root / 'safevision/verification/assets/bmp542'
    metadata = json.loads((folder / 'reference.json').read_text(encoding='utf-8-sig'))
    expected_metadata = {
        'cases': [list(case) for case in CASES],
        'oracle': 'Independent NumPy direct source-coordinate floor mapping and integer RGB565 conversion; full640x480 comparisons per case',
        'pixels': PIXELS,
        'includes': 'full4K BGRX32, full1080x1920 portrait both orientations,16384-axis boundaries, odd width, header gap, ignored nonopaque alpha, upscaling',
    }
    require(metadata == expected_metadata, 'BMP542 metadata differs from the fixed eight-case contract')
    expected_case_words = [(w << 48) | (h << 32) | (top << 24) | (bpp << 16) | offset
                           for w, h, top, bpp, offset in CASES]
    require(list(words(folder / 'bmp542_cases.mem', 16)) == expected_case_words,
            'BMP542 case input words differ from the fixed complete geometry/format contract')
    iterator = iter(words(folder / 'bmp542_expected.mem', 4))
    compared, black, case_results = 0, 0, []
    for case_index, (width, height, top, bpp, offset) in enumerate(CASES):
        # Unbounded Python integers and direct division, independent of the
        # hardware's iterative subtraction/DDA and its register bit widths.
        if width * HEIGHT >= height * WIDTH:
            draw_width, draw_height = WIDTH, max(1, height * WIDTH // width)
        else:
            draw_width, draw_height = max(1, width * HEIGHT // height), HEIGHT
        left, upper = (WIDTH - draw_width) // 2, (HEIGHT - draw_height) // 2
        source_columns = [x * width // draw_width for x in range(draw_width)]
        for y in range(HEIGHT):
            source_y = (y - upper) * height // draw_height
            active_row = upper <= y < upper + draw_height
            for x in range(WIDTH):
                expected = 0
                if active_row and left <= x < left + draw_width:
                    source_x = source_columns[x - left]
                    red = (17 * source_x + 3 * source_y) % 256
                    green = (7 * source_x + 11 * source_y + 23) % 256
                    blue = (13 * source_x + 5 * source_y + 101) % 256
                    expected = (red // 8) * 2048 + (green // 4) * 32 + blue // 8
                else:
                    black += 1
                actual = next(iterator, None)
                require(actual is not None, f'BMP542 missing pixel case{case_index} ({x},{y})')
                require(actual == expected,
                        f'BMP542 pixel mismatch case{case_index} ({x},{y}): expected {expected:04x}, got {actual:04x}')
                compared += 1
        case_results.append({'case': case_index, 'source': [width, height],
                             'top_down': bool(top), 'bpp': bpp, 'pixel_offset': offset,
                             'fit': [left, upper, draw_width, draw_height], 'pixels_compared': WIDTH * HEIGHT})
    require(next(iterator, None) is None, 'BMP542 contains unexpected pixels after its eight complete frames')
    require(compared == PIXELS, 'BMP542 incomplete comparison count')
    return {'cases': case_results, 'pixels_compared': compared, 'black_border_pixels_compared': black}


def canonical_header(row):
    _, width, height, bpp, planes, compression, offset, dib, signature, _, bfsize, _, _ = row
    header = bytearray(54)
    header[:2] = signature.encode('ascii')
    struct.pack_into('<I', header, 2, bfsize)
    struct.pack_into('<IIiiHHI', header, 10, offset, dib, width, height, planes, bpp, compression)
    return bytes(header)


def classify_header(header, supplied, directory_size):
    """Parse file bytes independently; preserve documented first-error priority."""
    if supplied < 54:
        return 0x3b
    if header[:2] != b'BM':
        return 0x37
    bfsize = struct.unpack_from('<I', header, 2)[0]
    offset, dib, width, height, planes, bpp, compression = struct.unpack_from('<IIiiHHI', header, 10)
    if dib < 40 or (offset >= 14 and dib > offset - 14):
        return 0x38
    if not (1 <= width <= 16384 and 1 <= abs(height) <= 16384):
        return 0x39
    if planes != 1 or bpp not in (24, 32) or compression != 0:
        return 0x3a
    stride = ((width * (bpp // 8) + 3) // 4) * 4
    extent = offset + stride * abs(height)  # No32-bit overflow/wrap permitted.
    if offset < 54 or bfsize > directory_size or extent > directory_size or extent > bfsize:
        return 0x3b
    return 0


def check_bounds(root):
    folder = root / 'safevision/verification/assets/bmp_bounds551'
    raw = bytes(words(folder / 'headers.mem', 2))
    require(len(raw) == len(BOUNDS) * 54, 'BOUNDS551 must contain exactly38 complete54-byte header fixtures')
    inputs = list(words(folder / 'cases.mem', 12))
    require(len(inputs) == len(BOUNDS), 'BOUNDS551 input count differs from fixed38 cases')
    expected_rows, classifications = [], []
    fields = ('name', 'w', 'h', 'bpp', 'planes', 'comp', 'off', 'dib', 'signature',
              'length', 'bf', 'directory', 'expected_detail')
    for index, row in enumerate(BOUNDS):
        header = raw[index * 54:(index + 1) * 54]
        require(header == canonical_header(row), f'BOUNDS551 header{index} {row[0]} differs from complete fixed input bytes')
        expected_input = (row[11] << 16) | (row[9] << 8) | row[12]
        require(inputs[index] == expected_input, f'BOUNDS551 input{index} {row[0]} directory/stream-length/diagnostic mismatch')
        result = classify_header(header, row[9], row[11])
        require(result == row[12], f'BOUNDS551 independent parsed classification{index} {row[0]} differs from fixed diagnostic')
        record = dict(zip(fields, row))
        record['header_hex'] = header.hex()
        expected_rows.append(record)
        classifications.append({'case': index, 'name': row[0], 'diagnostic': result})
    metadata = json.loads((folder / 'reference.json').read_text(encoding='utf-8-sig'))
    require(metadata == {
        'cases': expected_rows, 'count': len(BOUNDS),
        'oracle': 'Python arbitrary-precision signed geometry and BMP extent validation; explicit malformed headers, no DUT-derived arithmetic',
    }, 'BOUNDS551 metadata differs from the complete fixed and independently parsed input contract')
    return {'headers_compared': len(BOUNDS), 'header_bytes_compared': len(raw), 'classifications': classifications}


def check(root=None):
    root = Path(root if root is not None else ROOT).resolve()
    paths = ['safevision/verification/assets/bmp542/' + name
             for name in ('bmp542_cases.mem', 'bmp542_expected.mem', 'reference.json')]
    paths += ['safevision/verification/assets/bmp_bounds551/' + name
              for name in ('headers.mem', 'cases.mem', 'reference.json')]
    def snapshot():
        return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in paths}
    before = snapshot()
    pixels = check_pixels(root)
    bounds = check_bounds(root)
    require(snapshot() == before, 'BMP oracle inputs changed during the read-only check')
    return {'schema': 1, 'accepted': True, 'implementation': 'Independent Python standard-library exact integer oracle',
            'repository': str(root), 'pixels': pixels, 'bounds': bounds,
            'inputs_sha256': before, 'input_files_unchanged': True,
            'hardware_verified': False, 'rtl_simulation_verified': False, 'timing_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        result = check(args.repo)
    except Exception as error:
        print(json.dumps({'accepted': False, 'error': str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
