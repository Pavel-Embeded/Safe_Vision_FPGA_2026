
import argparse
from pathlib import Path
import re


def tables(bits):
    maximum = (1 << bits) - 1
    width = 4 * (1 << bits)


    results = [(foreground * 224 + background * 31 + 127) // 255
               for foreground in (0, maximum, maximum // 2, maximum // 2)
               for background in range(1 << bits)]
    return width, [sum(((value >> bit) & 1) << index for index, value in enumerate(results))
                   for bit in range(bits)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--output', type=Path, help='optional generated function-block snippet')
    args = parser.parse_args()
    path = Path(__file__).resolve().parents[1] / 'rtl/video/v3_constant224_blend.v'
    source = path.read_text()
    blocks = []
    for bits in (5, 6):
        width, planes = tables(bits)
        block = [f' function[{bits-1}:0] map{bits};input[{bits-1}:0] background;input[1:0] kind;reg[{width-1}:0] plane;begin']
        for bit, plane in enumerate(planes):
            block.append(f"  plane={width}'h{plane:0{width//4}x};map{bits}[{bit}]=plane[{{kind,background}}];")
        block.append(' end endfunction')
        blocks.extend(block)
        if args.check:
            actual = re.findall(r"plane=(\d+)'h([0-9a-fA-F]+);map" + str(bits) + r'\[(\d+)\]', source)
            observed = {int(bit): (int(size), int(value, 16)) for size, value, bit in actual}
            if len(actual) != bits or observed != {bit: (width, plane) for bit, plane in enumerate(planes)}:
                raise SystemExit(f'FAIL: map{bits} does not match exact rounded fixed-alpha formula')
    text = '\n'.join(blocks) + '\n'
    if args.output:
        args.output.write_text(text, encoding='ascii')
    if args.check:
        print('PASS: eleven bitplanes reproduce every 5/6-bit palette blend at alpha224 exactly')
    elif not args.output:
        print(text, end='')


if __name__ == '__main__':
    main()
